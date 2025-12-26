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
          'token': '', // Captcha token (Turnstile)
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

  /// Save refresh token and automatically fetch session token
  Future<void> saveTokens(String token, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();

    // If we have a session token, save it directly
    if (token.isNotEmpty) {
      await prefs.setString('auth_token', token);
    }

    // Save refresh token
    if (refreshToken.isNotEmpty) {
      await prefs.setString('refresh_token', refreshToken);

      // If no session token provided, use refresh token to get one
      if (token.isEmpty) {
        _logger.info('No session token, attempting to refresh...');
        final success = await _refreshSessionToken(refreshToken);
        if (!success) {
          throw Exception('Failed to refresh session token');
        }
      }
    }

    _logger.info('Tokens saved. Initializing SignalR...');
    // Await SignalR connection to ensure it's ready (like reference's getMyInfo() pattern)
    try {
      await _signalRService.init();
      developer.log('SignalR initialized successfully', name: 'AUTH');
    } catch (e) {
      developer.log('SignalR init error: $e', name: 'AUTH');
      // Don't throw - user can still retry API calls which will reconnect
    }
  }

  /// Use refresh token to get a new session token
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
        // API returns: {Response: "JWT_TOKEN", Status: 200, Success: true, Msg: ""}
        String? newToken;
        if (response.data is String) {
          newToken = response.data;
        } else if (response.data is Map) {
          // Check 'Response' field (actual API format)
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

  /// Try to auto-login using stored refresh token
  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');

    if (refreshToken != null && refreshToken.isNotEmpty) {
      _logger.info('Found refresh token, attempting auto-login...');
      // Initialize SignalR in background (don't await if we want fast UI but better to await for connection)
      // Actually, let's await it to ensure we are connected before showing Home
      try {
        await _signalRService.init();
        return true;
      } catch (e) {
        _logger.warning('Auto-login SignalR init failed: $e');
        // Even if SignalR fails (e.g. network), we still have a token.
        // We might want to let user into app and retry connection there.
        return true;
      }
    }
    return false;
  }
}
