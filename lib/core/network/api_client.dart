import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:novella/core/auth/auth_service.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.lightnovel.life',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // 添加 Auth 拦截器
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = AuthService().sessionToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          // 统一处理 401 令牌过期
          if (e.response?.statusCode == 401) {
            developer.log(
              'API returned 401, attempting to refresh token...',
              name: 'AUTH',
            );
            final success = await AuthService().tryAutoLogin();
            if (success) {
              final newToken = AuthService().sessionToken;
              if (newToken != null && newToken.isNotEmpty) {
                // 更新 Header 并重试该请求
                final requestOptions = e.requestOptions;
                requestOptions.headers['Authorization'] = 'Bearer $newToken';

                // 必须通过一个新的 dio 实例或原始 dio 重新发出请求
                try {
                  final cloneReq = await _dio.fetch(requestOptions);
                  return handler.resolve(cloneReq);
                } on DioException catch (retryError) {
                  return handler.next(retryError);
                }
              }
            }
          }
          return handler.next(e);
        },
      ),
    );

    // 添加日志拦截器
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
        logPrint: (log) => developer.log(log.toString(), name: 'DIO'),
      ),
    );

    // 配置代理（可选）
    // 需要代理时取消注释
    /*
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY 127.0.0.1:7890';
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
    */
  }

  Dio get dio => _dio;
}
