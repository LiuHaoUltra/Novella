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

  // 前台恢复时的“门闩”：用于阻塞用户触发的网络操作，直到 token 刷新/重连完成。
  Completer<void>? _foregroundRecoveryGate;

  /// 令牌提供者委托，避免循环依赖
  static Future<String> Function()? tokenProvider;

  /// 强制刷新令牌（忽略内存 TTL），用于 unauthorized/NoToken 自动恢复
  ///
  /// 由 AuthService 注入，避免在本文件直接依赖 AuthService。
  static Future<String> Function()? forceRefreshTokenProvider;

  // 内存会话令牌，3秒有效期 (保留作为兜底)
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

  /// 标记进入前台恢复流程：在此期间 [`invoke()`](lib/core/network/signalr_service.dart:296) 会等待 gate 完成。
  void beginForegroundRecovery() {
    if (_foregroundRecoveryGate == null || _foregroundRecoveryGate!.isCompleted) {
      _foregroundRecoveryGate = Completer<void>();
      developer.log('Foreground recovery gate BEGIN', name: 'SIGNALR');
    }
  }

  /// 标记前台恢复流程结束：释放等待中的请求。
  void endForegroundRecovery() {
    final gate = _foregroundRecoveryGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
      developer.log('Foreground recovery gate END', name: 'SIGNALR');
    }
  }

  Future<void> _waitForForegroundRecovery() async {
    final gate = _foregroundRecoveryGate;
    if (gate != null && !gate.isCompleted) {
      developer.log('Waiting for foreground recovery gate...', name: 'SIGNALR');
      await gate.future;
    }
  }

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

  /// 获取有效会话令牌
  Future<String> _getValidToken({bool forceRefresh = false}) async {
    // 优先使用外部注入的提供者 (如 AuthService)
    if (tokenProvider != null) {
      final provided =
          forceRefresh && forceRefreshTokenProvider != null
              ? await forceRefreshTokenProvider!()
              : await tokenProvider!();

      if (provided.isNotEmpty) return provided;

      // provider 返回空：尝试从本地读取旧 session token 兜底
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString('auth_token');
      if (persisted != null && persisted.isNotEmpty) {
        developer.log(
          'tokenProvider returned empty, falling back to persisted auth_token',
          name: 'SIGNALR',
        );
        return persisted;
      }
      return '';
    }

    // 优先检查内存令牌（3秒有效期）
    String token = _sessionToken.get();
    if (token.isNotEmpty) {
      return token;
    }

    // 令牌过期或为空，使用 refresh_token 刷新（legacy path）
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');

    if (refreshToken == null || refreshToken.isEmpty) {
      developer.log('No refresh token available', name: 'SIGNALR');
      return '';
    }

    developer.log(
      'Refreshing session token (legacy path)... forceRefresh=$forceRefresh',
      name: 'SIGNALR',
    );

    // iOS resumed 后网络可能尚未完全恢复：做一次短重试，避免返回空 token 导致服务端直接 NoToken
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _dio.post(
          '/api/user/refresh_token',
          data: {'token': refreshToken},
        );

        if (response.statusCode == 200 && response.data is Map) {
          final newToken = response.data['Response'] ?? response.data['Token'];
          if (newToken != null && newToken is String && newToken.isNotEmpty) {
            _sessionToken.set(newToken);
            return newToken;
          }
        }
      } catch (e) {
        developer.log(
          'Failed to refresh token (attempt ${attempt + 1}/2): $e',
          name: 'SIGNALR',
        );
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    }

    // 最后兜底：尝试使用已持久化的 auth_token（可能已过期，但比空 token 更容易触发服务端走 unauthorized 分支）
    final persisted = prefs.getString('auth_token');
    if (persisted != null && persisted.isNotEmpty) {
      developer.log(
        'Refresh failed, falling back to persisted auth_token (may be expired)',
        name: 'SIGNALR',
      );
      return persisted;
    }

    return '';
  }

  bool _isAuthError(Object e) {
    final msg = e.toString().toLowerCase();
    // 服务器 Msg 可能包含 token / unauthorized / 权限不足
    return msg.contains('unauthorized') ||
        msg.contains('no token') ||
        msg.contains('notoken') ||
        msg.contains('token') && (msg.contains('401') || msg.contains('status')) ||
        msg.contains('权限') ||
        msg.contains('凭据');
  }

  Future<void> _recoverFromAuthError() async {
    developer.log('Attempting auth recovery...', name: 'SIGNALR');
    // 1) 强制刷新 token（如果注入了强刷提供者）
    try {
      final forced = await _getValidToken(forceRefresh: true);
      developer.log('Forced token ready: ${forced.isNotEmpty}', name: 'SIGNALR');
    } catch (e) {
      developer.log('Force refresh token failed: $e', name: 'SIGNALR');
    }

    // 2) 重建连接
    try {
      await stop();
    } catch (_) {}
    await init();
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
                accessTokenFactory:
                    () async => await _getValidToken(),
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
      return await _invokeWithAutoRecover<T>(methodName, args: args);
    });
  }

  Future<T> _invokeWithAutoRecover<T>(
    String methodName, {
    List<Object>? args,
    bool retrying = false,
  }) async {
    // 若 app 刚从后台回来且正在强制刷新 token，则阻塞用户触发的网络操作
    await _waitForForegroundRecovery();

    developer.log(
      'invoke($methodName) - state: ${_hubConnection?.state}',
      name: 'SIGNALR',
    );

    // 确保连接就绪（包含 _hubConnection==null 的场景）
    await ensureConnected();

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

    try {
      developer.log('Invoking: $methodName', name: 'SIGNALR');
      final result = await _hubConnection!.invoke(methodName, args: args);
      return _processResponse<T>(result);
    } catch (e) {
      developer.log('Invoke error: $e', name: 'SIGNALR');

      if (!retrying && _isAuthError(e)) {
        developer.log(
          'Auth-related error detected, recovering & retrying once...',
          name: 'SIGNALR',
        );
        await _recoverFromAuthError();
        return await _invokeWithAutoRecover<T>(
          methodName,
          args: args,
          retrying: true,
        );
      }

      rethrow;
    }
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
