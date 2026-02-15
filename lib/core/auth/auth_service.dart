import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:novella/core/network/api_client.dart';
import 'package:novella/core/network/signalr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

class AuthService {
  // Singleton：避免多处 new AuthService() 导致缓存/expireTime 判断不一致
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final ApiClient _apiClient = ApiClient();
  final SignalRService _signalRService = SignalRService();
  final Logger _logger = Logger('AuthService');

  AuthService._internal() {
    // 注入令牌提供者，实现全局单例刷新
    SignalRService.tokenProvider = getValidSessionToken;
    SignalRService.forceRefreshTokenProvider = forceRefreshSessionToken;
  }

  // 内存令牌缓存，避免冷启动及 SignalR 重复请求
  String? _sessionToken;
  DateTime? _lastRefreshTime;
  // Web 侧默认 session token validity 为 30s（见 VUE_SESSION_TOKEN_VALIDITY）
  // 这里必须与服务端/原实现接近，否则 iOS 后台较久回来会拿着“自以为有效”的旧 token 触发无Token/unauthorized。
  static const _tokenValidity = Duration(seconds: 30);

  // 预过期阈值：即将过期时（例如剩余 <= 5s）也视为需要刷新
  static const _preExpiryThreshold = Duration(seconds: 5);

  // 令牌刷新互斥锁
  Future<String?>? _refreshFuture;

  Future<bool> login(String username, String password) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/user/login',
        data: {
          'email': username,
          'password': password,
          'token': '', // 验证码 token (Turnstile)
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        _logger.info('Login Response: $data');

        final accessToken = data['Token'];
        final refreshToken = data['RefreshToken'];

        if (accessToken != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', accessToken);
          if (refreshToken != null) {
            await prefs.setString('refresh_token', refreshToken);
          }

          // 写入内存缓存，避免刚登录就立刻再触发 refresh
          if (accessToken is String && accessToken.isNotEmpty) {
            _sessionToken = accessToken;
            _lastRefreshTime = DateTime.now();
          }

          await _signalRService.init();
          return true;
        }
      }
      return false;
    } catch (e) {
      _logger.severe('Login Failed: $e');
      if (e is DioException) {
        _logger.severe('DioError: ${e.response?.data}');
      }
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');

    // 同步清理内存缓存
    invalidateSessionTokenCache();
  }

  DateTime? _tryParseJwtExpiry(String token) {
    // 尝试解析 JWT 的 exp（秒级时间戳）。若不是 JWT 返回 null。
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = base64Url.normalize(parts[1]);
      final payloadBytes = base64Url.decode(payload);
      final payloadObj = jsonDecode(utf8.decode(payloadBytes));
      if (payloadObj is! Map) return null;
      final exp = payloadObj['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true)
            .toLocal();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 获取当前 session token 的“预计过期时间”
  ///
  /// 优先：若 token 可解析为 JWT，则使用其 exp。
  /// 否则：使用 lastRefreshTime + 内存 TTL 作为近似 expireTime。
  DateTime? get sessionTokenExpireTime {
    final token = _sessionToken;
    if (token != null && token.isNotEmpty) {
      final jwtExp = _tryParseJwtExpiry(token);
      if (jwtExp != null) return jwtExp;
    }
    final t = _lastRefreshTime;
    if (t == null) return null;
    return t.add(_tokenValidity);
  }

  /// 是否已过期或即将过期（<= threshold）
  bool isSessionTokenExpiredOrExpiringSoon({Duration? threshold}) {
    final th = threshold ?? _preExpiryThreshold;
    final expireAt = sessionTokenExpireTime;
    if (expireAt == null) return true; // 无法判断则视为需要刷新
    return expireAt.difference(DateTime.now()) <= th;
  }

  /// 确保 session token 在前台可用（用于 resumed 阻塞式刷新）
  ///
  /// - 若已过期/即将过期：强制刷新并等待完成。
  /// - 若仍充足：直接返回当前有效 token（若内存没有，会按正常路径 refresh）。
  Future<String> ensureFreshSessionToken({Duration? threshold}) async {
    // 没有 refresh_token 无法刷新
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return '';

    if (isSessionTokenExpiredOrExpiringSoon(threshold: threshold)) {
      return await forceRefreshSessionToken();
    }
    return await getValidSessionToken();
  }

  /// 保存刷新令牌并自动获取会话令牌
  Future<void> saveTokens(String token, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();

    // 若有会话令牌直接保存
    if (token.isNotEmpty) {
      await prefs.setString('auth_token', token);

      // 写入内存缓存
      _sessionToken = token;
      _lastRefreshTime = DateTime.now();
    }

    // 保存刷新令牌
    if (refreshToken.isNotEmpty) {
      await prefs.setString('refresh_token', refreshToken);

      // 若无会话令牌，尝试刷新获取
      if (token.isEmpty) {
        _logger.info('No session token, attempting to refresh...');
        final tokenCandidate = await _refreshSessionToken(refreshToken);
        if (tokenCandidate == null) {
          throw Exception('Failed to refresh session token');
        }
      }
    }

    _logger.info('Tokens saved. Initializing SignalR...');
    // 等待 SignalR 连接就绪（参考 getMyInfo 模式）
    try {
      await _signalRService.init();
      developer.log('SignalR initialized successfully', name: 'AUTH');
    } catch (e) {
      developer.log('SignalR init error: $e', name: 'AUTH');
      // 不抛出异常，允许用户重试
    }
  }

  /// 使用刷新令牌获取新会话令牌 (带并发锁)
  Future<String?> _refreshSessionToken(
    String refreshToken, {
    bool force = false,
  }) async {
    // 如果已经有正在进行的刷新请求，直接等待它
    if (_refreshFuture != null) {
      _logger.info('Refresh already in progress, waiting...');
      return _refreshFuture;
    }

    // 检查缓存是否有效
    if (!force) {
      if (_sessionToken != null && _lastRefreshTime != null) {
        if (DateTime.now().difference(_lastRefreshTime!) < _tokenValidity) {
          return _sessionToken;
        }
      }
    }

    final completer = Completer<String?>();
    _refreshFuture = completer.future;

    try {
      _logger.info('Performing network refresh for session token...');
      final response = await _apiClient.dio.post(
        '/api/user/refresh_token',
        data: {'token': refreshToken},
      );

      _logger.info('Refresh API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        String? newToken;
        if (response.data is String) {
          newToken = response.data;
        } else if (response.data is Map) {
          if (response.data['Response'] != null) {
            newToken = response.data['Response'];
          } else if (response.data['Token'] != null) {
            newToken = response.data['Token'];
          }
        }

        if (newToken != null && newToken.isNotEmpty) {
          _sessionToken = newToken;
          _lastRefreshTime = DateTime.now();

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', newToken);

          _logger.info('Session token refreshed successfully');
          completer.complete(newToken);
          return newToken;
        }
      }

      _logger.warning('Refresh token API returned unexpected response');
      completer.complete(null);
      return null;
    } on DioException catch (e) {
      _logger.severe('DioException in refresh: ${e.message}');
      completer.complete(null);
      return null;
    } catch (e) {
      _logger.severe('Failed to refresh session token: $e');
      completer.complete(null);
      return null;
    } finally {
      _refreshFuture = null;
    }
  }

  /// 强制刷新一次会话 token（忽略内存 TTL）
  ///
  /// 用于 iOS resumed 后的“预热”，避免用户第一次点击触发请求时才发现 token 过期。
  Future<String> forceRefreshSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return '';
    return await _refreshSessionToken(refreshToken, force: true) ?? '';
  }

  /// 使本地会话 token 缓存失效
  ///
  /// 不会清除持久化 refresh_token（用于触发后续重新 refresh）。
  void invalidateSessionTokenCache() {
    _sessionToken = null;
    _lastRefreshTime = null;
  }

  /// 获取有效的会话令牌 (供 SignalR 使用)
  Future<String> getValidSessionToken() async {
    // 1. 无需刷新直接返回
    if (_sessionToken != null && _lastRefreshTime != null) {
      if (DateTime.now().difference(_lastRefreshTime!) < _tokenValidity) {
        return _sessionToken!;
      }
    }

    // 2. 需要刷新或正在刷新
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return '';

    return await _refreshSessionToken(refreshToken) ?? '';
  }

  /// 尝试使用存储的刷新令牌自动登录
  /// 会实际调用 API 验证 refresh token 是否有效
  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');

    if (refreshToken == null || refreshToken.isEmpty) {
      _logger.info('No refresh token found');
      return false;
    }

    _logger.info('Found refresh token, attempting to refresh session...');

    // 尝试刷新 session token 来验证 refresh token 有效性
    final newToken = await _refreshSessionToken(refreshToken);
    if (newToken == null) {
      _logger.warning('Failed to refresh session token, token may be invalid');
      return false;
    }

    // 在后台启动 SignalR 初始化，不阻塞进入主页的过程
    // 具体的网络请求会通过 RequestQueue 自动等待连接就绪
    unawaited(
      _signalRService.init().catchError((e) {
        _logger.warning('Background SignalR init failed: $e');
      }),
    );

    _logger.info('Auto-login token validated, proceeding to main page');
    return true;
  }
}
