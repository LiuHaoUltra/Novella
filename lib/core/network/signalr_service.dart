/*
 * Portions of this file are derived from the lightnovelshelf/web project.
 * Original Repository: https://github.com/LightNovelShelf/Web
 * Original License: AGPL-3.0
 * * Logic ported from:
 * - src/services/internal/request/signalr/index.ts (Connection flow & Gzip handling)
 * - src/utils/session.ts (TokenStorage mechanism)
 */

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
// gzip 数据为 JSON 格式，无需 msgpack
import 'package:novella/core/network/request_queue.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novella/core/network/novel_hub_protocol.dart';

/// 带自动过期的内存令牌存储（参考原实现）
class _TokenStorage {
  String _token = '';
  DateTime _lastUpdate = DateTime(1970);
  final Duration _validity;

  _TokenStorage(this._validity);

  String get() {
    if (_token.isEmpty) return '';
    if (DateTime.now().difference(_lastUpdate) > _validity) {
      return ''; // 令牌过期，返回空以触发刷新
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
  // 单例
  static final SignalRService _instance = SignalRService._internal();
  factory SignalRService() => _instance;
  SignalRService._internal();

  HubConnection? _hubConnection;
  final String _baseUrl = 'https://api.lightnovel.life';
  final RequestQueue _requestQueue = RequestQueue();

  // 连接状态追踪
  Completer<void>? _connectionCompleter;
  bool _isStarting = false;

  // 内存会话令牌，3秒有效期
  static final _TokenStorage _sessionToken = _TokenStorage(
    const Duration(seconds: 3),
  );

  // 用于令牌刷新的 Dio 实例
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.lightnovel.life',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  bool get isConnected => _hubConnection?.state == HubConnectionState.Connected;

  /// 停止当前连接
  Future<void> stop() async {
    if (_hubConnection != null) {
      await _hubConnection?.stop();
      _hubConnection = null;
      _isStarting = false;
      _connectionCompleter = null;
      developer.log('Connection stopped', name: 'SIGNALR');
    }
  }

  /// 获取有效会话令牌（内存存储/自动刷新）
  /// 仿照参考实现的 TokenStorage 模式
  Future<String> _getValidToken() async {
    // 优先检查内存令牌（3秒有效期）
    String token = _sessionToken.get();
    if (token.isNotEmpty) {
      return token;
    }

    // 令牌过期或为空，使用 refresh_token 刷新
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
          // 仅存储在内存中
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

    // 若已连接直接返回
    if (_hubConnection?.state == HubConnectionState.Connected) {
      developer.log('Already connected', name: 'SIGNALR');
      return;
    }

    // 若正在启动，等待现有尝试
    if (_isStarting && _connectionCompleter != null) {
      developer.log('Already connecting, waiting...', name: 'SIGNALR');
      return _connectionCompleter!.future;
    }

    // 启动新连接
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
                requestTimeout: 30000, // 30秒请求超时
              ),
            )
            // 自定义重试策略：0s, 5s, 10s, 20s, 30s
            .withAutomaticReconnect(retryDelays: [0, 5000, 10000, 20000, 30000])
            .withHubProtocol(NovelHubProtocol())
            .build();

    // 配置服务器超时 - 默认为 15s 故设为 30s
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

  /// 确保连接就绪
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

      // 若正在连接/重连，等待最多 15 秒
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

      // 若断开连接，尝试重启一次
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

      // 最终检查
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

    // 处理空结果（服务器错误或调用失败）
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
        // 响应为空，根据类型返回空容器
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
        // 参考 Web 实现：解压 gzip
        // gzip 解压后为 JSON 数据
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
