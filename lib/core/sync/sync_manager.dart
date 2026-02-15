import 'dart:async';
import 'dart:convert';
import 'dart:math'; // for Random
import 'package:flutter/foundation.dart'; // for compute
import 'package:flutter/widgets.dart'; // for WidgetsBindingObserver
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/sync/gist_sync_service.dart';
import 'package:novella/core/sync/sync_crypto.dart';
import 'package:novella/core/sync/sync_data_model.dart';
import 'package:novella/data/services/book_mark_service.dart';
import 'package:novella/data/services/reading_progress_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步状态
enum SyncStatus {
  disconnected, // 未连接
  idle, // 空闲
  syncing, // 同步中
  error, // 出错
}

/// 同步管理器 (核心协调逻辑)
/// 整合 GistSyncService, SyncCrypto, DataServices
class SyncManager with ChangeNotifier, WidgetsBindingObserver {
  static final Logger _logger = Logger('SyncManager');
  static final SyncManager _instance = SyncManager._internal();

  factory SyncManager() => _instance;
  SyncManager._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  final GistSyncService _gistService = GistSyncService();
  final BookMarkService _bookMarkService = BookMarkService();
  final ReadingProgressService _progressService = ReadingProgressService();

  static const _storage = FlutterSecureStorage();
  static const _keyGithubToken = 'github_access_token';
  static const _keyGistId = 'sync_gist_id';
  static const _keySyncPassword = 'sync_password';
  static const _keyLastSyncTime = 'last_sync_time';
  static const _keyLastSyncId = 'last_sync_id';

  SyncStatus _status = SyncStatus.disconnected;
  DateTime? _lastSyncTime;
  String? _errorMessage;
  bool _isSyncing = false; // 防止循环同步

  // 缓存 Key (避免重复计算)
  Uint8List? _cachedKey;
  Uint8List? _cachedSalt;
  String? _lastKnownSyncId;

  // 20s 防抖
  Timer? _syncDebounceTimer;
  static const _syncDebounceDelay = Duration(seconds: 20);

  // 自动重试机制
  int _retryCount = 0;
  static const _maxRetries = 3;
  DateTime? _lastFailureTime;

  /// 当前状态
  SyncStatus get status => _status;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _gistService.isConnected;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退后台/关闭时立即同步
    // 500ms 延时确保 SharedPreferences 写入完成 (优化自1秒)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _logger.info('App state $state, waiting for data flush before sync...');
      Future.delayed(const Duration(milliseconds: 500), () {
        _logger.info('Triggering immediate sync after flush...');
        triggerSync(immediate: true);
      });
    }
  }

  /// 初始化 (恢复状态)
  Future<void> init() async {
    // 恢复已保存的连接状态
    final token = await _storage.read(key: _keyGithubToken);
    final gistId = await _storage.read(key: _keyGistId);
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString(_keyLastSyncTime);
    _lastKnownSyncId = prefs.getString(_keyLastSyncId);

    if (token != null) {
      _gistService.setAccessToken(token, gistId: gistId);
      _status = SyncStatus.idle;
      notifyListeners();

      if (lastSyncStr != null) {
        _lastSyncTime = DateTime.tryParse(lastSyncStr);
      }

      _logger.info('Sync manager initialized, connected to GitHub');

      // 预热密钥 (可选，如果能读取到密码)
      final password = await getSyncPassword();
      if (password != null) {
        // 注：这里没有 salt，因为 salt 存储在 Gist 的加密文件中
        // 不能凭空生成 key。必须等到第一次下载文件或上传文件时才能确定 key。
      }
    } else {
      _status = SyncStatus.disconnected;
      notifyListeners();
      _logger.info('Sync manager initialized, not connected');
    }
  }

  /// 连接 GitHub (Device Flow)
  Future<DeviceFlowResponse> startDeviceFlow() async {
    return await _gistService.requestDeviceCode();
  }

  /// 完成授权
  Future<bool> completeDeviceFlow(
    DeviceFlowResponse flowData, {
    void Function(int remainingSeconds)? onTick,
  }) async {
    final token = await _gistService.pollForToken(flowData, onTick: onTick);
    if (token == null) return false;

    // 保存 token
    await _storage.write(key: _keyGithubToken, value: token);
    _status = SyncStatus.idle;
    notifyListeners();

    _logger.info('Device flow completed, connected to GitHub');
    return true;
  }

  /// 设置密码 (首次)
  Future<void> setSyncPassword(String password) async {
    if (!SyncCrypto.isValidPassword(password)) {
      throw Exception('密码需包含大小写字母和数字，8-32位');
    }
    await _storage.write(key: _keySyncPassword, value: password);
    // 清空缓存
    _cachedKey = null;
    _cachedSalt = null;
    _logger.info('Sync password set');
  }

  /// 获取密码
  Future<String?> getSyncPassword() async {
    return await _storage.read(key: _keySyncPassword);
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _storage.delete(key: _keyGithubToken);
    await _storage.delete(key: _keyGistId);
    // 保留密码
    _gistService.disconnect();
    _status = SyncStatus.disconnected;
    _cachedKey = null;
    _cachedSalt = null;
    notifyListeners();
    _logger.info('Disconnected from GitHub');
  }

  /// 手动同步
  Future<void> sync() async {
    final password = await getSyncPassword();
    if (password == null) {
      throw Exception('请先设置同步密码');
    }
    // 手动同步时重置重试计数器
    _retryCount = 0;
    _lastFailureTime = null;
    await _performSync(password);
  }

  int _pendingSyncCount = 0; // 挂起的同步请求计数
  static const _maxPendingBeforeDrop = 2; // 超过此值仅执行最后一次

  /// 触发同步 (可选立即)
  /// [immediate] 退后台时为 true
  void triggerSync({bool immediate = false}) {
    // 仅在已连接状态下触发
    if (!_gistService.isConnected) return;

    // 检查是否应该重置重试计数器 (5分钟冷却期)
    if (_shouldResetRetryCount()) {
      _retryCount = 0;
      _lastFailureTime = null;
    }

    _syncDebounceTimer?.cancel();

    // 如果正在同步，累加挂起请求计数
    if (_isSyncing) {
      _pendingSyncCount++;
      if (_pendingSyncCount > _maxPendingBeforeDrop) {
        _logger.info(
          'Sync in progress, pending count: $_pendingSyncCount '
          '(will merge into final sync)',
        );
      } else {
        _logger.info('Sync in progress, queuing pending sync request...');
      }
      return;
    }

    if (immediate) {
      _runSyncTask();
      return;
    }

    _syncDebounceTimer = Timer(_syncDebounceDelay, () {
      _runSyncTask();
    });
  }

  /// 检查是否应该重置重试计数器
  bool _shouldResetRetryCount() {
    if (_lastFailureTime == null) return true;
    final elapsed = DateTime.now().difference(_lastFailureTime!);
    return elapsed.inMinutes >= 5; // 5 分钟冷却期
  }

  Future<void> _runSyncTask() async {
    final password = await getSyncPassword();
    if (password != null &&
        _status == SyncStatus.idle &&
        _gistService.isConnected &&
        !_isSyncing) {
      try {
        await _performSync(password);
      } catch (e) {
        _logger.warning('Background sync failed: $e');
      }
    }
  }

  /// 执行同步核心逻辑
  Future<void> _performSync(String password) async {
    if (!_gistService.isConnected) {
      throw Exception('未连接 GitHub');
    }

    // 同步运行 ID：用于将一次同步链路串起来（可观测性）
    final syncRunId = DateTime.now().millisecondsSinceEpoch.toString();
    String stage = 'sync_start';

    _isSyncing = true;
    _status = SyncStatus.syncing;
    _errorMessage = null;
    notifyListeners();

    try {
      _logger.info(
        'SYNC run=$syncRunId stage=$stage status_before=$_status lastKnownSyncId=${_lastKnownSyncId ?? 'null'} gistId=${_gistService.gistId ?? 'null'}',
      );

      // 1. 收集本地
      stage = 'collect_local';
      final localData = await _collectLocalData();
      _logger.info(
        'SYNC run=$syncRunId stage=$stage modules=${localData.modules.keys.join(',')}',
      );

      // 2. 下载远程
      stage = 'download';
      final remoteEncrypted = await _gistService.downloadFromGist(
        syncRunId: syncRunId,
      );
      SyncData? remoteData;

      // 解密 & 缓存 Key
      if (remoteEncrypted != null) {
        stage = 'decrypt_parse';
        try {
          final decrypted = await compute(_decryptInIsolate, {
            'json': remoteEncrypted,
            'pass': password,
          });
          remoteData = SyncData.fromJson(
            (await _parseJson(decrypted)) as Map<String, dynamic>,
          );

          _logger.info(
            'SYNC run=$syncRunId stage=$stage remoteSyncId=${remoteData.syncId ?? 'null'} remoteModules=${remoteData.modules.keys.join(',')}',
          );

          // 更新缓存
          final encryptedJson =
              jsonDecode(remoteEncrypted) as Map<String, dynamic>;
          final salt = base64Decode(encryptedJson['salt']);
          final iter = encryptedJson['iter'] as int? ?? 100000;

          if (_cachedKey == null ||
              _cachedSalt == null ||
              !listEquals(_cachedSalt, salt)) {
            _logger.info('Deriving key in background isolate...');
            _cachedKey = await compute(deriveKeyCompute, {
              'pass': password,
              'salt': salt,
              'iter': iter,
            });
            _cachedSalt = salt;
          }
        } catch (e) {
          _logger.warning('Failed to decrypt remote data: $e');
          rethrow;
        }
      } else {
        _logger.info('SYNC run=$syncRunId stage=download_remote_empty');
        // 首次初始化 Key
        if (_cachedKey == null) {
          final random = Random.secure();
          final newSalt = Uint8List.fromList(
            List.generate(16, (_) => random.nextInt(256)),
          );
          _cachedKey = await compute(deriveKeyCompute, {
            'pass': password,
            'salt': newSalt,
            'iter': 100000, // 回退到 100,000
          });
          _cachedSalt = newSalt;
        }
      }

      // 3. 合并与冲突检测
      stage = 'merge';
      if (remoteData != null && _lastKnownSyncId != null) {
        if (remoteData.syncId != _lastKnownSyncId) {
          _logger.warning(
            'Sync conflict detected! Remote SyncID (${remoteData.syncId}) '
            'does not match last known ($_lastKnownSyncId). '
            'Merging data instead of simple overwrite.',
          );
          _logger.warning(
            'SYNC run=$syncRunId stage=$stage conflictDetected=true lastKnownSyncId=$_lastKnownSyncId remoteSyncId=${remoteData.syncId}',
          );
        } else {
          _logger.info('No conflict detected, SyncID matches.');
          _logger.info(
            'SYNC run=$syncRunId stage=$stage conflictDetected=false',
          );
        }
      }

      final mergedData =
          remoteData != null ? localData.mergeWith(remoteData) : localData;

      // 4. 加密上传 (复用 CachedKey)
      stage = 'encrypt_upload';
      if (_cachedKey == null || _cachedSalt == null) {
        throw Exception("Key cache missing");
      }

      final encrypted = SyncCrypto.encryptWithKey(
        mergedData.toJsonString(),
        _cachedKey!,
        _cachedSalt!,
      );

      // 尝试上传
      await _gistService.uploadToGist(encrypted, syncRunId: syncRunId);

      // 上传成功后更新持久化存储中的凭据
      final currentGistId = _gistService.gistId;
      if (currentGistId != null) {
        await _storage.write(key: _keyGistId, value: currentGistId);
      }

      // 5. 应用合并后的数据 (Update Local)
      // 关键修正：必须应用 mergedData，否则本地的新更改会被远程旧数据覆盖
      stage = 'apply_remote';
      await _applyRemoteData(mergedData);

      // 7. 更新时间
      _lastSyncTime = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSyncTime, _lastSyncTime!.toIso8601String());
      if (mergedData.syncId != null) {
        _lastKnownSyncId = mergedData.syncId;
        await prefs.setString(_keyLastSyncId, _lastKnownSyncId!);
      }

      _status = SyncStatus.idle;
      _retryCount = 0; // 成功后重置重试计数
      _lastFailureTime = null;
      _logger.info('Sync completed successfully');
      _logger.info(
        'SYNC run=$syncRunId stage=done lastKnownSyncId=${_lastKnownSyncId ?? 'null'} gistId=${_gistService.gistId ?? 'null'}',
      );
      notifyListeners();
    } catch (e) {
      _status = SyncStatus.error;
      _errorMessage = e.toString();
      _lastFailureTime = DateTime.now();

      _logger.severe(
        'SYNC run=$syncRunId stage=$stage status=error error=${e.toString()}',
      );

      // 判断是否应该重试
      final shouldRetry = _shouldRetryError(e);

      if (shouldRetry && _retryCount < _maxRetries) {
        _retryCount++;
        final delay = Duration(seconds: 5 * _retryCount);
        _logger.warning(
          'Sync failed ($_retryCount/$_maxRetries), '
          'retrying in ${delay.inSeconds}s: $e',
        );
        notifyListeners();
        Future.delayed(delay, () => _runSyncTask());
      } else if (!shouldRetry) {
        _logger.severe('Sync failed with non-retryable error: $e');
        notifyListeners();
        rethrow;
      } else {
        _logger.severe('Sync failed after $_maxRetries retries: $e');
        notifyListeners();
        rethrow;
      }
    } finally {
      _isSyncing = false;
      // 如果有挂起的同步请求，执行最后一次同步
      if (_pendingSyncCount > 0) {
        final count = _pendingSyncCount;
        _pendingSyncCount = 0;
        _logger.info(
          'Processing $count pending sync requests as one final sync',
        );
        // 使用 microtask 避免栈溢出
        Future.microtask(() => _runSyncTask());
      }
    }
  }

  /// 判断错误是否应该自动重试
  bool _shouldRetryError(dynamic error) {
    final errorMsg = error.toString().toLowerCase();

    // 不重试：密码/认证错误
    if (errorMsg.contains('密码') ||
        errorMsg.contains('解密失败') ||
        errorMsg.contains('unauthorized') ||
        errorMsg.contains('token')) {
      return false;
    }

    // 重试：网络、超时、冲突等其他错误
    return true;
  }

  /// 从 GitHub 恢复数据
  Future<bool> restoreFromGist(String password) async {
    if (!_gistService.isConnected) {
      throw Exception('未连接 GitHub');
    }

    _isSyncing = true;
    _status = SyncStatus.syncing;

    try {
      final syncRunId = DateTime.now().millisecondsSinceEpoch.toString();
      _logger.info('SYNC run=$syncRunId stage=restore_start');
      final remoteEncrypted = await _gistService.downloadFromGist(
        syncRunId: syncRunId,
      );
      if (remoteEncrypted == null) {
        _status = SyncStatus.idle;
        _logger.info('SYNC run=$syncRunId stage=restore_no_remote');
        return false;
      }

      final decrypted = await compute(_decryptInIsolate, {
        'json': remoteEncrypted,
        'pass': password,
      });

      final remoteData = SyncData.fromJson(
        (await _parseJson(decrypted)) as Map<String, dynamic>,
      );

      // 应用所有远程数据
      await _applyRemoteData(remoteData);

      // 保存密码
      await _storage.write(key: _keySyncPassword, value: password);

      // 更新缓存
      final encryptedJson = jsonDecode(remoteEncrypted) as Map<String, dynamic>;
      final salt = base64Decode(encryptedJson['salt']);
      final iter = encryptedJson['iter'] as int? ?? 100000;

      _cachedKey = await compute(deriveKeyCompute, {
        'pass': password,
        'salt': salt,
        'iter': iter,
      });
      _cachedSalt = salt;

      // 更新同步 ID
      if (remoteData.syncId != null) {
        _lastKnownSyncId = remoteData.syncId;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastSyncId, _lastKnownSyncId!);
      }

      _status = SyncStatus.idle;
      _logger.info('Restore from Gist completed');
      _logger.info('SYNC run=$syncRunId stage=restore_done');
      return true;
    } catch (e) {
      _logger.severe('Gist sync failed: $e');
      _status = SyncStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// 收集本地数据
  Future<SyncData> _collectLocalData() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

    final modules = <String, SyncModule>{};

    // 收集书签数据
    final bookmarks = await _bookMarkService.getAllMarkedBooks();
    if (bookmarks.isNotEmpty) {
      final bookmarkData = <String, dynamic>{};
      for (final entry in bookmarks.entries) {
        bookmarkData[entry.key.toString()] = {
          'status': entry.value.index,
          'updatedAt': DateTime.now().toIso8601String(),
        };
      }
      modules[SyncModuleNames.bookmarks] = SyncModule(
        version: 1,
        updatedAt: DateTime.now(),
        data: bookmarkData,
      );
    }

    // 收集阅读时长
    final prefs = await SharedPreferences.getInstance();
    final readingTimeData = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('reading_time_')) {
        final dateStr = key.substring('reading_time_'.length);
        final minutes = prefs.getInt(key);
        if (minutes != null && minutes > 0) {
          readingTimeData[dateStr] = minutes;
        }
      }
    }
    if (readingTimeData.isNotEmpty) {
      modules[SyncModuleNames.readingTime] = SyncModule(
        version: 1,
        updatedAt: DateTime.now(),
        data: readingTimeData,
      );
    }

    // 收集阅读进度
    final progressData = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('read_pos_')) {
        final bookIdStr = key.substring('read_pos_'.length);
        final data = prefs.getString(key);
        if (data != null) {
          final parts = data.split('|');
          if (parts.length >= 3) {
            progressData[bookIdStr] = {
              'chapterId': int.tryParse(parts[0]) ?? 0,
              'sortNum': int.tryParse(parts[1]) ?? 1,
              'scrollPosition': double.tryParse(parts[2]) ?? 0.0,
              'updatedAt':
                  parts.length >= 4
                      ? parts[3]
                      : DateTime.now().toIso8601String(), // 兼容旧数据
              'title':
                  parts.length >= 5
                      ? (parts[4].isEmpty ? null : parts[4])
                      : null,
              'cover':
                  parts.length >= 6
                      ? (parts[5].isEmpty ? null : parts[5])
                      : null,
              'chapterTitle':
                  parts.length >= 7
                      ? (parts[6].isEmpty ? null : parts[6])
                      : null,
            };
          }
        }
      }
    }
    if (progressData.isNotEmpty) {
      modules[SyncModuleNames.readingProgress] = SyncModule(
        version: 1,
        updatedAt: DateTime.now(),
        data: progressData,
      );
    }

    // 收集 RefreshToken
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken != null) {
      modules[SyncModuleNames.auth] = SyncModule(
        version: 1,
        updatedAt: DateTime.now(),
        data: {'refreshToken': refreshToken},
      );
    }

    return SyncData.create(appVersion: appVersion, modules: modules);
  }

  /// 应用远程数据到本地
  Future<void> _applyRemoteData(SyncData remoteData) async {
    final prefs = await SharedPreferences.getInstance();

    // 应用书签
    final bookmarksModule = remoteData.modules[SyncModuleNames.bookmarks];
    if (bookmarksModule != null) {
      for (final entry in bookmarksModule.data.entries) {
        final bookId = int.tryParse(entry.key);
        final data = entry.value as Map<String, dynamic>?;
        if (bookId != null && data != null) {
          final status = data['status'] as int?;
          if (status != null &&
              status >= 0 &&
              status < BookMarkStatus.values.length) {
            await _bookMarkService.setBookMark(
              bookId,
              BookMarkStatus.values[status],
              skipSync: true, // 避免从云端恢复数据时循环触发同步
            );
          }
        }
      }
    }

    // 应用阅读时长 (取每日最大值)
    final readingTimeModule = remoteData.modules[SyncModuleNames.readingTime];
    if (readingTimeModule != null) {
      for (final entry in readingTimeModule.data.entries) {
        final key = 'reading_time_${entry.key}';
        final remoteMinutes = entry.value as int?;
        if (remoteMinutes != null) {
          final localMinutes = prefs.getInt(key) ?? 0;
          if (remoteMinutes > localMinutes) {
            await prefs.setInt(key, remoteMinutes);
          }
        }
      }
    }

    // 应用阅读进度
    final progressModule = remoteData.modules[SyncModuleNames.readingProgress];
    if (progressModule != null) {
      for (final entry in progressModule.data.entries) {
        final bookId = int.tryParse(entry.key);
        final data = entry.value as Map<String, dynamic>?;
        if (bookId != null && data != null) {
          final updatedAt = DateTime.tryParse(
            data['updatedAt'] as String? ?? '',
          );
          await _progressService.saveLocalScrollPosition(
            bookId: bookId,
            chapterId: data['chapterId'] as int? ?? 0,
            sortNum: data['sortNum'] as int? ?? 1,
            scrollPosition: (data['scrollPosition'] as num?)?.toDouble() ?? 0.0,
            title: data['title'] as String?,
            cover: data['cover'] as String?,
            chapterTitle: data['chapterTitle'] as String?,
            updatedAt: updatedAt, // 传递远程时间戳
            skipIndexUpdate: true, // 同步过程中不更新“最后阅读”索引，防止中间乱序覆盖
          );
        }
      }
      // 所有进度同步完成后，根据时间戳统一刷新一次“最后阅读”索引
      await _progressService.refreshLastReadIndex();
    }

    // 应用 RefreshToken
    final authModule = remoteData.modules[SyncModuleNames.auth];
    if (authModule != null) {
      final refreshToken = authModule.data['refreshToken'] as String?;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString('refresh_token', refreshToken);
      }
    }

    _logger.info('Applied remote data to local storage');
  }

  Future<dynamic> _parseJson(String json) async {
    return Future.value(__parseJsonSync(json));
  }

  dynamic __parseJsonSync(String json) {
    return json.isEmpty
        ? {}
        : (json.startsWith('{') || json.startsWith('['))
        ? _decodeJson(json)
        : {};
  }

  dynamic _decodeJson(String json) {
    try {
      return const JsonDecoder().convert(json);
    } catch (e) {
      return {};
    }
  }
}

/// Isolate 专用：后台解密
/// 参数: { 'json': String, 'pass': String }
Future<String> _decryptInIsolate(Map<String, dynamic> params) async {
  final String encrypted = params['json'];
  final String password = params['pass'];
  return SyncCrypto.decrypt(encrypted, password);
}
