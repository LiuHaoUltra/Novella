import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
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
      developer.log('Connection stopped', name: 'SIGNALR');
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
      developer.log('No refresh token available', name: 'SIGNALR');
      return '';
    }

    developer.log('Refreshing session token...', name: 'SIGNALR');
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
          developer.log('Session token refreshed', name: 'SIGNALR');
          return newToken;
        }
      }
    } catch (e) {
      developer.log('Failed to refresh token: $e', name: 'SIGNALR');
    }

    return '';
  }

  Future<void> init() async {
    developer.log(
      'init() - current state: ${_hubConnection?.state}',
      name: 'SIGNALR',
    );

    // If already connected, return immediately
    if (_hubConnection?.state == HubConnectionState.Connected) {
      developer.log('Already connected', name: 'SIGNALR');
      return;
    }

    // If already starting, wait for existing connection attempt
    if (_isStarting && _connectionCompleter != null) {
      developer.log('Already connecting, waiting...', name: 'SIGNALR');
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
    developer.log('Connecting to: $hubUrl', name: 'SIGNALR');

    final token = await _getValidToken();
    developer.log('Token ready: ${token.isNotEmpty}', name: 'SIGNALR');

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
      developer.log('Closed: $error', name: 'SIGNALR');
      _isStarting = false;
    });

    _hubConnection?.onreconnecting(({Exception? error}) {
      developer.log('Reconnecting: $error', name: 'SIGNALR');
    });

    _hubConnection?.onreconnected(({String? connectionId}) {
      developer.log('Reconnected: $connectionId', name: 'SIGNALR');
    });

    try {
      await _hubConnection?.start();
      developer.log('Connected successfully', name: 'SIGNALR');
      _connectionCompleter?.complete();
    } catch (e) {
      developer.log('Failed to connect: $e', name: 'SIGNALR');
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
      developer.log(
        'invoke($methodName) - state: ${_hubConnection?.state}',
        name: 'SIGNALR',
      );

      // Wait for connection if connecting/reconnecting (max 15 seconds)
      if (_hubConnection?.state == HubConnectionState.Connecting ||
          _hubConnection?.state == HubConnectionState.Reconnecting) {
        developer.log('Waiting for connection...', name: 'SIGNALR');
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_hubConnection?.state == HubConnectionState.Connected) {
            break;
          }
        }
      }

      // If disconnected, try to restart once
      if (_hubConnection?.state == HubConnectionState.Disconnected) {
        developer.log('Disconnected, attempting restart...', name: 'SIGNALR');
        try {
          await _hubConnection?.start();
          developer.log('Restart successful', name: 'SIGNALR');
        } catch (e) {
          developer.log('Restart failed: $e', name: 'SIGNALR');
          throw Exception('SignalR connection failed: $e');
        }
      }

      // Final check
      if (_hubConnection?.state != HubConnectionState.Connected) {
        throw Exception(
          'SignalR not connected (state: ${_hubConnection?.state})',
        );
      }

      developer.log('Invoking: $methodName', name: 'SIGNALR');
      final result = await _hubConnection!.invoke(methodName, args: args);
      return _processResponse<T>(result);
    });
  }

  T _processResponse<T>(dynamic result) {
    dynamic processedResult = result;

    developer.log(
      '_processResponse input type: ${result.runtimeType}',
      name: 'SIGNALR',
    );

    // Handle completely null result (server error or invoke failure)
    if (result == null) {
      developer.log(
        'Result is null, returning empty container for type $T',
        name: 'SIGNALR',
      );
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

      developer.log(
        'Success=$success, ResponseType=${responseData.runtimeType}',
        name: 'SIGNALR',
      );

      if (!success) {
        throw Exception('Server Error: $msg (Status: $status)');
      }

      if (responseData == null) {
        // Handle null response - return empty container based on expected type
        developer.log(
          'Response is null, returning empty container',
          name: 'SIGNALR',
        );
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

        developer.log('Decompressing: ${bytes.length} bytes', name: 'SIGNALR');
        final decodedBytes = GZipDecoder().decodeBytes(bytes);
        // Web reference: Response = JSON.parse(ungzip(Response, { to: 'string' }))
        // The gzip-compressed data is JSON, not MessagePack
        final decodedData = jsonDecode(utf8.decode(decodedBytes));
        developer.log(
          'Decompressed type: ${decodedData.runtimeType}',
          name: 'SIGNALR',
        );
        processedResult = decodedData;
      } else {
        processedResult = responseData;
      }
    }

    developer.log(
      'Returning type: ${processedResult.runtimeType} as $T',
      name: 'SIGNALR',
    );
    return processedResult as T;
  }
}
