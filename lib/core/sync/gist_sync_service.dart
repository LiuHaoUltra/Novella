import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Device Flow 响应
class DeviceFlowResponse {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  DeviceFlowResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  factory DeviceFlowResponse.fromJson(Map<String, dynamic> json) {
    return DeviceFlowResponse(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      expiresIn: json['expires_in'] as int,
      interval: json['interval'] as int,
    );
  }
}

/// Gist 同步服务 (OAuth + CRUD)
class GistSyncService {
  static final Logger _logger = Logger('GistSyncService');
  static final GistSyncService _instance = GistSyncService._internal();

  factory GistSyncService() => _instance;
  GistSyncService._internal();

  // Config
  static const String _clientId = 'Ov23lio3OykhATf225lB';
  static const String _scope = 'gist';
  static const String _gistFileName = 'novella_sync.json';
  static const String _gistDescription = 'Novella App Sync Data (Encrypted)';

  // State
  String? _accessToken;
  String? _gistId;

  /// 是否连接
  bool get isConnected => _accessToken != null;

  /// 恢复 Token
  void setAccessToken(String token, {String? gistId}) {
    _accessToken = token;
    _gistId = gistId;
  }

  /// 断开
  void disconnect() {
    _accessToken = null;
    _gistId = null;
  }

  // ============================================================
  // OAuth 授权流程
  // ============================================================

  /// Step 1: 请求验证码
  Future<DeviceFlowResponse> requestDeviceCode() async {
    _logger.info('Requesting device code...');

    final response = await http
        .post(
          Uri.parse('https://github.com/login/device/code'),
          headers: {'Accept': 'application/json'},
          body: {'client_id': _clientId, 'scope': _scope},
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final flowResponse = DeviceFlowResponse.fromJson(data);
      _logger.info(
        'Device code received: ${flowResponse.userCode}, '
        'expires in ${flowResponse.expiresIn}s',
      );
      return flowResponse;
    } else {
      _logger.severe('Failed to request device code: ${response.body}');
      throw Exception('Failed to request device code: ${response.statusCode}');
    }
  }

  /// Step 2: 轮询等待授权
  Future<String?> pollForToken(
    DeviceFlowResponse flowData, {
    void Function(int remainingSeconds)? onTick,
  }) async {
    _logger.info('Starting token polling...');

    final uri = Uri.parse('https://github.com/login/oauth/access_token');
    int currentInterval = flowData.interval;
    final expireTime = DateTime.now().add(
      Duration(seconds: flowData.expiresIn),
    );

    while (DateTime.now().isBefore(expireTime)) {
      // 回调倒计时
      final remaining = expireTime.difference(DateTime.now()).inSeconds;
      onTick?.call(remaining);

      // 等待
      await Future.delayed(Duration(seconds: currentInterval));

      // 查询 Token
      final response = await http
          .post(
            uri,
            headers: {'Accept': 'application/json'},
            body: {
              'client_id': _clientId,
              'device_code': flowData.deviceCode,
              'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            },
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // 成功
      if (data['access_token'] != null) {
        final token = data['access_token'] as String;
        _accessToken = token;
        _logger.info('Access token obtained successfully');
        return token;
      }

      // 处理错误状态
      final error = data['error'] as String?;

      if (error == 'authorization_pending') {
        // 用户尚未授权，继续轮询
        _logger.fine('Authorization pending, continuing poll...');
        continue;
      } else if (error == 'slow_down') {
        // 请求过于频繁，增加间隔 5 秒
        currentInterval += 5;
        _logger.warning('Slow down requested, interval now $currentInterval s');
        continue;
      } else if (error == 'expired_token') {
        // 验证码过期
        _logger.warning('Device code expired');
        return null;
      } else if (error == 'access_denied') {
        // 用户拒绝授权
        _logger.warning('User denied authorization');
        throw Exception('用户拒绝了授权');
      } else if (error != null) {
        // 其他错误
        _logger.severe('OAuth error: $error');
        throw Exception('OAuth 错误: $error');
      }
    }

    // 超时
    _logger.warning('Polling timed out');
    return null;
  }

  // ============================================================
  // Gist CRUD
  // ============================================================

  /// 上传 (Create/Update)
  Future<void> uploadToGist(
    String encryptedJsonContent, {
    String? syncRunId,
  }) async {
    if (_accessToken == null) {
      throw Exception('未连接 GitHub');
    }

    _logger.info(
      'SYNC run=$syncRunId stage=gist_upload_prepare gistId=${_gistId ?? 'null'} bytes=${encryptedJsonContent.length}',
    );

    final headers = {
      'Authorization': 'Bearer $_accessToken',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    };

    final body = jsonEncode({
      'description': _gistDescription,
      'public': false, // Secret Gist
      'files': {
        _gistFileName: {'content': encryptedJsonContent},
      },
    });

    if (_gistId == null) {
      // 创建新 Gist
      _logger.info('SYNC run=$syncRunId stage=gist_create_start');
      final response = await http
          .post(
            Uri.parse('https://api.github.com/gists'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      _logger.info(
        'SYNC run=$syncRunId stage=gist_create_done httpStatus=${response.statusCode}',
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _gistId = data['id'] as String;
        _logger.info(
          'SYNC run=$syncRunId stage=gist_create_ok gistId=$_gistId',
        );
      } else {
        _logger.severe('Failed to create Gist: ${response.body}');
        throw Exception('创建 Gist 失败: ${response.statusCode}');
      }
    } else {
      // 更新已有 Gist
      _logger.info(
        'SYNC run=$syncRunId stage=gist_update_start gistId=$_gistId',
      );
      final response = await http
          .patch(
            Uri.parse('https://api.github.com/gists/$_gistId'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      _logger.info(
        'SYNC run=$syncRunId stage=gist_update_done gistId=$_gistId httpStatus=${response.statusCode}',
      );

      if (response.statusCode == 200) {
        _logger.info(
          'SYNC run=$syncRunId stage=gist_update_ok gistId=$_gistId',
        );
      } else if (response.statusCode == 404) {
        // Gist 被删除或丢失
        _logger.warning('Gist not found (404), clearing local ID');
        _gistId = null;
        throw Exception('云端数据丢失，将在下次同步时重新创建');
      } else {
        _logger.severe('Failed to update Gist: ${response.body}');
        throw Exception('更新 Gist 失败: ${response.statusCode}');
      }
    }
  }

  /// 下载 (Read)
  /// 返回加密后的内容字符串，若无则返回 null
  Future<String?> downloadFromGist({String? syncRunId}) async {
    if (_accessToken == null) {
      throw Exception('未连接 GitHub');
    }

    final headers = {
      'Authorization': 'Bearer $_accessToken',
      'Accept': 'application/vnd.github+json',
    };

    // 如果没有已知的 Gist ID，需要先搜索
    if (_gistId == null) {
      _logger.info('SYNC run=$syncRunId stage=gist_find_start');
      _gistId = await _findExistingGist(syncRunId: syncRunId);
      if (_gistId == null) {
        _logger.info('SYNC run=$syncRunId stage=gist_find_none');
        return null;
      }
      _logger.info(
        'SYNC run=$syncRunId stage=gist_find_ok gistId=$_gistId',
      );
    }

    _logger.info(
      'SYNC run=$syncRunId stage=gist_download_start gistId=$_gistId',
    );
    final response = await http
        .get(
          Uri.parse('https://api.github.com/gists/$_gistId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));

    _logger.info(
      'SYNC run=$syncRunId stage=gist_download_done gistId=$_gistId httpStatus=${response.statusCode}',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final files = data['files'] as Map<String, dynamic>?;
      final syncFile = files?[_gistFileName] as Map<String, dynamic>?;
      final content = syncFile?['content'] as String?;
      if (content != null) {
        _logger.info(
          'SYNC run=$syncRunId stage=gist_download_ok gistId=$_gistId bytes=${content.length}',
        );
        return content;
      }
    } else if (response.statusCode == 404) {
      _logger.warning('Gist not found, resetting gistId');
      _gistId = null;
      return null;
    } else {
      _logger.severe('Failed to download Gist: ${response.body}');
      throw Exception('下载 Gist 失败: ${response.statusCode}');
    }

    return null;
  }

  /// 查找已有 Gist
  Future<String?> _findExistingGist({String? syncRunId}) async {
    _logger.info('SYNC run=$syncRunId stage=gist_list_start');

    final response = await http
        .get(
          Uri.parse('https://api.github.com/gists'),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Accept': 'application/vnd.github+json',
          },
        )
        .timeout(const Duration(seconds: 30));

    _logger.info(
      'SYNC run=$syncRunId stage=gist_list_done httpStatus=${response.statusCode}',
    );

    if (response.statusCode == 200) {
      final gists = jsonDecode(response.body) as List<dynamic>;
      for (final gist in gists) {
        final files =
            (gist as Map<String, dynamic>)['files'] as Map<String, dynamic>?;
        if (files?.containsKey(_gistFileName) == true) {
          final id = gist['id'] as String;
          _logger.info('SYNC run=$syncRunId stage=gist_list_match gistId=$id');
          return id;
        }
      }
    }

    return null;
  }

  /// 获取当前 Gist ID
  String? get gistId => _gistId;
}
