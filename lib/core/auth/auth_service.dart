import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:novella/core/network/api_client.dart';
import 'package:novella/core/network/signalr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();
  final SignalRService _signalRService = SignalRService();
  final Logger _logger = Logger('AuthService');

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
  }

  /// 保存刷新令牌并自动获取会话令牌
  Future<void> saveTokens(String token, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();

    // 若有会话令牌直接保存
    if (token.isNotEmpty) {
      await prefs.setString('auth_token', token);
    }

    // 保存刷新令牌
    if (refreshToken.isNotEmpty) {
      await prefs.setString('refresh_token', refreshToken);

      // 若无会话令牌，尝试刷新获取
      if (token.isEmpty) {
        _logger.info('No session token, attempting to refresh...');
        final success = await _refreshSessionToken(refreshToken);
        if (!success) {
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

  /// 使用刷新令牌获取新会话令牌
  Future<bool> _refreshSessionToken(String refreshToken) async {
    try {
      developer.log(
        'Calling refresh_token API with token: ${refreshToken.substring(0, 20)}...',
        name: 'AUTH',
      );
      developer.log(
        'API URL: ${_apiClient.dio.options.baseUrl}/api/user/refresh_token',
        name: 'AUTH',
      );

      final response = await _apiClient.dio.post(
        '/api/user/refresh_token',
        data: {'token': refreshToken},
      );

      developer.log(
        'Refresh API response status: ${response.statusCode}',
        name: 'AUTH',
      );
      developer.log(
        'Refresh API response data: ${response.data}',
        name: 'AUTH',
      );
      developer.log(
        'Response data type: ${response.data.runtimeType}',
        name: 'AUTH',
      );

      if (response.statusCode == 200) {
        // API 返回格式：{Response, Status, Success, Msg}
        String? newToken;
        if (response.data is String) {
          newToken = response.data;
        } else if (response.data is Map) {
          // 检查 Response 字段（实际 API 格式）
          if (response.data['Response'] != null) {
            newToken = response.data['Response'];
          } else if (response.data['Token'] != null) {
            newToken = response.data['Token'];
          }
        }

        if (newToken != null && newToken.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', newToken);
          developer.log(
            'Session token refreshed successfully: ${newToken.substring(0, 30)}...',
            name: 'AUTH',
          );
          return true;
        }
      }

      developer.log(
        'Refresh token API returned unexpected response',
        name: 'AUTH',
      );
      return false;
    } on DioException catch (e) {
      developer.log('DioException in refresh: ${e.type}', name: 'AUTH');
      developer.log('DioException message: ${e.message}', name: 'AUTH');
      developer.log('DioException response: ${e.response?.data}', name: 'AUTH');
      developer.log(
        'DioException status: ${e.response?.statusCode}',
        name: 'AUTH',
      );
      return false;
    } catch (e) {
      developer.log('Failed to refresh session token: $e', name: 'AUTH');
      return false;
    }
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
    final refreshSuccess = await _refreshSessionToken(refreshToken);
    if (!refreshSuccess) {
      _logger.warning('Failed to refresh session token, token may be invalid');
      return false;
    }

    // 初始化 SignalR
    try {
      await _signalRService.init();
      _logger.info('Auto-login successful');
      return true;
    } catch (e) {
      _logger.warning('Auto-login SignalR init failed: $e');
      // SignalR 失败但 token 有效，仍然返回 true
      return true;
    }
  }
}
