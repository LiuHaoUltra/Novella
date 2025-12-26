import 'dart:developer' as developer;
import 'package:dio/dio.dart';

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

    // Add logging interceptor - use print() for terminal output
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
        logPrint: (log) => developer.log(log.toString(), name: 'DIO'),
      ),
    );

    // Configure proxy for Windows (optional, comment out if not needed)
    // Uncomment if your network requires proxy
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
