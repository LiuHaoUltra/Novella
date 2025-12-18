import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
// msgpack_dart no longer needed - gzip data is JSON, not MessagePack
import 'package:novella/core/network/request_queue.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novella/core/network/novel_hub_protocol.dart';

/// In-memory token storage with auto-expiry (like reference implementation)
class _TokenStorage {
  String _token = '';
  DateTime _lastUpdate = DateTime(1970);
  final Duration _validity;

  _TokenStorage(this._validity);

  String get() {
    if (_token.isEmpty) return '';
    if (DateTime.now().difference(_lastUpdate) > _validity) {
      return ''; // Token expired, return empty to trigger refresh
    }
    return _token;
  }

  void set(String newToken) {
    _token = newToken;
    _lastUpdate = DateTime.now();
  }

  void clear() {
    _token = '';
    _lastUpdate = DateTime(1970);
  }
}

class SignalRService {
  // Singleton
  static final SignalRService _instance = SignalRService._internal();
  factory SignalRService() => _instance;
  SignalRService._internal();

  HubConnection? _hubConnection;
  final String _baseUrl = 'https://api.lightnovel.life';
  final RequestQueue _requestQueue = RequestQueue();

  // Connection state tracking
  Completer<void>? _connectionCompleter;
  bool _isStarting = false;

  // In-memory session token with 3-second validity (like reference)
  static final _TokenStorage _sessionToken = _TokenStorage(
    const Duration(seconds: 3),
  );

  // Dio for token refresh
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.lightnovel.life',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  bool get isConnected => _hubConnection?.state == HubConnectionState.Connected;

  /// Stop the current connection
  Future<void> stop() async {
    if (_hubConnection != null) {
      await _hubConnection?.stop();
      _hubConnection = null;
      _isStarting = false;
      _connectionCompleter = null;
      print('[SIGNALR] Connection stopped');
    }
  }

  /// Get valid session token using in-memory storage with auto-expiry
  /// Mimics reference implementation's TokenStorage pattern
  Future<String> _getValidToken() async {
    // Check in-memory token first (3-second validity like reference)
    String token = _sessionToken.get();
    if (token.isNotEmpty) {
      return token;
    }

    // Token expired or empty, refresh using refresh_token
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');

    if (refreshToken == null || refreshToken.isEmpty) {
      print('[SIGNALR] No refresh token available');
      return '';
    }

    print('[SIGNALR] Refreshing session token...');
    try {
      final response = await _dio.post(
        '/api/user/refresh_token',
        data: {'token': refreshToken},
      );

      if (response.statusCode == 200 && response.data is Map) {
        final newToken = response.data['Response'];
        if (newToken != null && newToken is String && newToken.isNotEmpty) {
          // Store in memory only (like reference implementation)
          _sessionToken.set(newToken);
          print('[SIGNALR] Session token refreshed');
          return newToken;
        }
      }
    } catch (e) {
      print('[SIGNALR] Failed to refresh token: $e');
    }

    return '';
  }

  Future<void> init() async {
    print('[SIGNALR] init() - current state: ${_hubConnection?.state}');

    // If already connected, return immediately
    if (_hubConnection?.state == HubConnectionState.Connected) {
      print('[SIGNALR] Already connected');
      return;
    }

    // If already starting, wait for existing connection attempt
    if (_isStarting && _connectionCompleter != null) {
      print('[SIGNALR] Already connecting, waiting...');
      return _connectionCompleter!.future;
    }

    // Start new connection
    _isStarting = true;
    _connectionCompleter = Completer<void>();

    if (_hubConnection != null) {
      await _hubConnection?.stop();
      _hubConnection = null;
    }

    final hubUrl = '$_baseUrl/hub/api';
    print('[SIGNALR] Connecting to: $hubUrl');

    final token = await _getValidToken();
    print('[SIGNALR] Token ready: ${token.isNotEmpty}');

    _hubConnection =
        HubConnectionBuilder()
            .withUrl(
              hubUrl,
              options: HttpConnectionOptions(
                accessTokenFactory: () async => await _getValidToken(),
                requestTimeout: 30000, // 30 second request timeout
              ),
            )
            // Custom retry policy: 0s, 5s, 10s, 20s, 30s delays
            .withAutomaticReconnect(retryDelays: [0, 5000, 10000, 20000, 30000])
            .withHubProtocol(NovelHubProtocol())
            .build();

    // Configure server timeout - should be 2x the server's KeepAliveInterval
    // Default server KeepAliveInterval is 15s, so we set 30s
    _hubConnection?.serverTimeoutInMilliseconds = 30000;

    _hubConnection?.onclose(({Exception? error}) {
      print('[SIGNALR] Closed: $error');
      _isStarting = false;
    });

    _hubConnection?.onreconnecting(({Exception? error}) {
      print('[SIGNALR] Reconnecting: $error');
    });

    _hubConnection?.onreconnected(({String? connectionId}) {
      print('[SIGNALR] Reconnected: $connectionId');
    });

    try {
      await _hubConnection?.start();
      print('[SIGNALR] Connected successfully');
      _connectionCompleter?.complete();
    } catch (e) {
      print('[SIGNALR] Failed to connect: $e');
      _connectionCompleter?.completeError(e);
      _isStarting = false;
      rethrow;
    }
  }

  /// Ensure connection is ready before making calls
  Future<void> ensureConnected() async {
    if (_hubConnection?.state == HubConnectionState.Connected) {
      return;
    }
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      return _connectionCompleter!.future;
    }
    await init();
  }

  Future<T> invoke<T>(String methodName, {List<Object>? args}) async {
    return _requestQueue.enqueue(() async {
      print('[SIGNALR] invoke($methodName) - state: ${_hubConnection?.state}');

      // Wait for connection if connecting/reconnecting (max 15 seconds)
      if (_hubConnection?.state == HubConnectionState.Connecting ||
          _hubConnection?.state == HubConnectionState.Reconnecting) {
        print('[SIGNALR] Waiting for connection...');
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_hubConnection?.state == HubConnectionState.Connected) {
            break;
          }
        }
      }

      // If disconnected, try to restart once
      if (_hubConnection?.state == HubConnectionState.Disconnected) {
        print('[SIGNALR] Disconnected, attempting restart...');
        try {
          await _hubConnection?.start();
          print('[SIGNALR] Restart successful');
        } catch (e) {
          print('[SIGNALR] Restart failed: $e');
          throw Exception('SignalR connection failed: $e');
        }
      }

      // Final check
      if (_hubConnection?.state != HubConnectionState.Connected) {
        throw Exception(
          'SignalR not connected (state: ${_hubConnection?.state})',
        );
      }

      print('[SIGNALR] Invoking: $methodName');
      final result = await _hubConnection!.invoke(methodName, args: args);
      return _processResponse<T>(result);
    });
  }

  T _processResponse<T>(dynamic result) {
    dynamic processedResult = result;

    print('[SIGNALR] _processResponse input type: ${result.runtimeType}');

    // Handle completely null result (server error or invoke failure)
    if (result == null) {
      print('[SIGNALR] Result is null, returning empty container for type $T');
      if (T == Map || T.toString().contains('Map')) {
        return <dynamic, dynamic>{} as T;
      } else if (T == List || T.toString().contains('List')) {
        return <dynamic>[] as T;
      }
      throw Exception('Server returned null response');
    }

    if (result is Map) {
      final success = result['Success'] as bool? ?? false;
      final msg = result['Msg'] as String?;
      final status = result['Status'];
      var responseData = result['Response'];

      print(
        '[SIGNALR] Success=$success, ResponseType=${responseData.runtimeType}',
      );

      if (!success) {
        throw Exception('Server Error: $msg (Status: $status)');
      }

      if (responseData == null) {
        // Handle null response - return empty container based on expected type
        print('[SIGNALR] Response is null, returning empty container');
        if (T == Map || T.toString().contains('Map')) {
          return <dynamic, dynamic>{} as T;
        } else if (T == List || T.toString().contains('List')) {
          return <dynamic>[] as T;
        }
        return null as T;
      }

      if (responseData is Uint8List ||
          (responseData is List &&
              responseData.isNotEmpty &&
              responseData[0] is int)) {
        final List<int> bytes =
            result['Response'] is Uint8List
                ? result['Response']
                : List<int>.from(result['Response']);

        print('[SIGNALR] Decompressing: ${bytes.length} bytes');
        final decodedBytes = GZipDecoder().decodeBytes(bytes);
        // Web reference: Response = JSON.parse(ungzip(Response, { to: 'string' }))
        // The gzip-compressed data is JSON, not MessagePack
        final decodedData = jsonDecode(utf8.decode(decodedBytes));
        print('[SIGNALR] Decompressed type: ${decodedData.runtimeType}');
        processedResult = decodedData;
      } else {
        processedResult = responseData;
      }
    }

    print('[SIGNALR] Returning type: ${processedResult.runtimeType} as $T');
    return processedResult as T;
  }
}
