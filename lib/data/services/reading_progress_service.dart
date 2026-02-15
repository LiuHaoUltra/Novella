import 'dart:developer' as developer;
import 'package:logging/logging.dart';
import 'package:novella/core/network/signalr_service.dart';
import 'package:novella/core/sync/sync_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地阅读位置数据
class ReadPosition {
  final int bookId;
  final int chapterId;
  final int sortNum;
  final double scrollPosition; // 0.0-1.0 滚动百分比
  final String? title; // 书籍标题
  final String? cover; // 封面 URL
  final String? chapterTitle; // 新增：章节标题

  ReadPosition({
    required this.bookId,
    required this.chapterId,
    required this.sortNum,
    required this.scrollPosition,
    this.title,
    this.cover,
    this.chapterTitle,
  });

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'chapterId': chapterId,
    'sortNum': sortNum,
    'scrollPosition': scrollPosition,
    'title': title,
    'cover': cover,
    'chapterTitle': chapterTitle,
  };

  factory ReadPosition.fromJson(Map<String, dynamic> json) {
    return ReadPosition(
      bookId: json['bookId'] as int? ?? 0,
      chapterId: json['chapterId'] as int? ?? 0,
      sortNum: json['sortNum'] as int? ?? 1,
      scrollPosition: (json['scrollPosition'] as num?)?.toDouble() ?? 0.0,
      title: json['title'] as String?,
      cover: json['cover'] as String?,
      chapterTitle: json['chapterTitle'] as String?,
    );
  }
}

/// 阅读进度管理服务
/// 同步服务端并本地缓存
class ReadingProgressService {
  static final Logger _logger = Logger('ReadingProgressService');
  static final ReadingProgressService _instance =
      ReadingProgressService._internal();
  final SignalRService _signalRService = SignalRService();

  factory ReadingProgressService() => _instance;
  ReadingProgressService._internal();

  /// 保存阅读位置到服务器
  /// 参考 services/book/index.ts
  Future<void> saveReadPosition({
    required int bookId,
    required int chapterId,
    required String xPath, // XPath 精确位置
  }) async {
    try {
      // Web 端调用包含选项，必须包含！
      await _signalRService.invoke(
        'SaveReadPosition',
        args: [
          {'Bid': bookId, 'Cid': chapterId, 'XPath': xPath},
          {'UseGzip': true}, // 选项（必须！）
        ],
      );
      _logger.info(
        'Saved reading position: book=$bookId, chapter=$chapterId, xPath=$xPath',
      );
    } catch (e) {
      _logger.warning('Failed to save position to server: $e');
      // 服务端失败仍保存本地
    }

    // 本地备份
    await _saveLocalPosition(bookId, chapterId, xPath);
  }

  /// 获取阅读位置（仅本地）
  /// 注：服务端无 GetReadPosition 接口。
  /// 服务端位置包含在 GetBookInfo 响应中。
  /// 此方法仅返回本地缓存。
  Future<Map<String, dynamic>?> getReadPosition(int bookId) async {
    // 仅返回本地缓存
    return await _getLocalPosition(bookId);
  }

  /// 本地保存滚动百分比
  Future<void> saveLocalScrollPosition({
    required int bookId,
    required int chapterId,
    required int sortNum,
    required double scrollPosition,
    String? title, // 新增：书籍标题
    String? cover, // 新增：封面 URL
    String? chapterTitle, // 新增：章节标题
    DateTime? updatedAt, // 新增：支持指定时间戳 (用于同步)
    bool immediate = false, // 新增：是否立即同步
    bool skipIndexUpdate = false, // 新增：是否跳过更新最后阅读索引 (用于同步批量写入)
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_pos_$bookId';

    final timestamp = updatedAt ?? DateTime.now();

    final position = ReadPosition(
      bookId: bookId,
      chapterId: chapterId,
      sortNum: sortNum,
      scrollPosition: scrollPosition,
      title: title,
      cover: cover,
      chapterTitle: chapterTitle,
    );

    // 格式: chapterId|sortNum|scrollPosition|updatedAt|title|cover|chapterTitle
    final data =
        '${position.chapterId}|${position.sortNum}|${position.scrollPosition}|${timestamp.toIso8601String()}|${title ?? ''}|${cover ?? ''}|${chapterTitle ?? ''}';

    await prefs.setString(key, data);
    // 更新最后阅读书籍索引，用于极速定位
    if (!skipIndexUpdate) {
      await prefs.setInt('last_read_book_id', bookId);
    }

    developer.log('SAVED: key=$key, data=$data', name: 'POSITION');

    // 如果是外部传入的时间戳 (说明是同步写入)，则不触发回传同步
    // 本地写入则触发同步
    if (updatedAt == null) {
      SyncManager().triggerSync(immediate: immediate);
    }
  }

  /// 仅回填阅读记录的展示元数据（不改变进度、不刷新 updatedAt、不更新 last_read_book_id、也不触发同步）
  ///
  /// 用途：首页“继续阅读”模块补全 title/cover/chapterTitle 时调用，避免污染基于 updatedAt 的多端合并。
  Future<void> backfillLocalReadMetadata({
    required int bookId,
    String? title,
    String? cover,
    String? chapterTitle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_pos_$bookId';
    final data = prefs.getString(key);

    if (data == null) return;

    final parts = data.split('|');

    // 需要至少包含 updatedAt 才能保证不污染时间戳
    if (parts.length < 4) {
      _logger.fine(
        'SYNC_META_BACKFILL skipped for book=$bookId: legacy record without updatedAt',
      );
      return;
    }

    final existingTitle = parts.length >= 5 ? parts[4] : '';
    final existingCover = parts.length >= 6 ? parts[5] : '';
    final existingChapterTitle = parts.length >= 7 ? parts[6] : '';

    // 仅在原字段为空时回填，避免覆盖用户已持久化的元数据
    final newTitle = existingTitle.isNotEmpty ? existingTitle : (title ?? '');
    final newCover = existingCover.isNotEmpty ? existingCover : (cover ?? '');
    final newChapterTitle =
        existingChapterTitle.isNotEmpty
            ? existingChapterTitle
            : (chapterTitle ?? '');

    final changed =
        (newTitle != existingTitle) ||
        (newCover != existingCover) ||
        (newChapterTitle != existingChapterTitle);

    if (!changed) return;

    // 保留进度与 updatedAt（parts[0..3]），仅更新元数据字段
    // 格式: chapterId|sortNum|scrollPosition|updatedAt|title|cover|chapterTitle
    final rebuilt =
        '${parts[0]}|${parts[1]}|${parts[2]}|${parts[3]}|$newTitle|$newCover|$newChapterTitle';

    await prefs.setString(key, rebuilt);
    developer.log('BACKFILL: key=$key, data=$rebuilt', name: 'POSITION');
  }

  /// 获取本地滚动位置
  Future<ReadPosition?> getLocalScrollPosition(int bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_pos_$bookId';
    final data = prefs.getString(key);

    developer.log('LOAD: key=$key, data=$data', name: 'POSITION');

    if (data == null) {
      developer.log('LOAD: no saved position found', name: 'POSITION');
      return null;
    }

    try {
      final parts = data.split('|');
      if (parts.length >= 3) {
        final pos = ReadPosition(
          bookId: bookId,
          chapterId: int.parse(parts[0]),
          sortNum: int.parse(parts[1]),
          scrollPosition: double.parse(parts[2]),
          title:
              parts.length >= 5 ? (parts[4].isEmpty ? null : parts[4]) : null,
          cover:
              parts.length >= 6 ? (parts[5].isEmpty ? null : parts[5]) : null,
          chapterTitle:
              parts.length >= 7 ? (parts[6].isEmpty ? null : parts[6]) : null,
        );
        developer.log(
          'LOAD: chapterId=${pos.chapterId}, sortNum=${pos.sortNum}, scroll=${(pos.scrollPosition * 100).toStringAsFixed(1)}%, title=${pos.title}, chTitle=${pos.chapterTitle}',
          name: 'POSITION',
        );
        return pos;
      }
    } catch (e) {
      developer.log('LOAD ERROR: $e', name: 'POSITION');
      _logger.warning('Failed to parse local position: $e');
    }
    return null;
  }

  /// 获取最后一次阅读的书籍信息（基于本地更新时间）
  Future<ReadPosition?> getLastReadBook() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. 优先尝试极速索引 (O(1))
    final lastReadId = prefs.getInt('last_read_book_id');
    if (lastReadId != null) {
      final pos = await getLocalScrollPosition(lastReadId);
      if (pos != null) return pos;
    }

    // 2. 回退到遍历模式 (仅针对老旧数据或异常情况)
    final keys = prefs.getKeys().where((k) => k.startsWith('read_pos_'));

    ReadPosition? lastPos;
    DateTime? lastTime;

    for (final key in keys) {
      final data = prefs.getString(key);
      if (data == null) continue;

      try {
        final parts = data.split('|');
        if (parts.length >= 4) {
          // chapterId|sortNum|scrollPosition|updatedAt
          final updatedAt = DateTime.parse(parts[3]);

          if (lastTime == null || updatedAt.isAfter(lastTime)) {
            lastTime = updatedAt;
            // 键格式：read_pos_{bookId}
            final bookId = int.tryParse(key.replaceFirst('read_pos_', ''));
            if (bookId != null) {
              lastPos = ReadPosition(
                bookId: bookId,
                chapterId: int.parse(parts[0]),
                sortNum: int.parse(parts[1]),
                scrollPosition: double.parse(parts[2]),
                title:
                    parts.length >= 5
                        ? (parts[4].isEmpty ? null : parts[4])
                        : null,
                cover:
                    parts.length >= 6
                        ? (parts[5].isEmpty ? null : parts[5])
                        : null,
                chapterTitle:
                    parts.length >= 7
                        ? (parts[6].isEmpty ? null : parts[6])
                        : null,
              );
            }
          }
        }
      } catch (e) {
        _logger.warning('Failed to parse read pos for key $key: $e');
      }
    }

    if (lastPos != null) {
      developer.log(
        'Found last read book (via traverse): ${lastPos.bookId} at ${lastTime?.toIso8601String()}',
        name: 'POSITION',
      );
    }

    return lastPos;
  }

  /// 刷新最后一次阅读的书籍索引
  /// 遍历所有记录，根据时间戳找到真正最后阅读的书籍并更新索引
  Future<void> refreshLastReadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('read_pos_'));

    int? latestBookId;
    DateTime? latestTime;

    for (final key in keys) {
      final data = prefs.getString(key);
      if (data == null) continue;

      try {
        final parts = data.split('|');
        if (parts.length >= 4) {
          final updatedAt = DateTime.tryParse(parts[3]);
          if (updatedAt != null) {
            if (latestTime == null || updatedAt.isAfter(latestTime)) {
              latestTime = updatedAt;
              latestBookId = int.tryParse(key.replaceFirst('read_pos_', ''));
            }
          }
        }
      } catch (e) {
        _logger.warning('Error parsing key $key during index refresh: $e');
      }
    }

    if (latestBookId != null) {
      await prefs.setInt('last_read_book_id', latestBookId);
      developer.log(
        'REFRESHED: last_read_book_id=$latestBookId (time=${latestTime?.toIso8601String()})',
        name: 'POSITION',
      );
    }
  }

  /// 私有：本地保存 XPath 位置
  Future<void> _saveLocalPosition(
    int bookId,
    int chapterId,
    String xPath,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_xpath_$bookId';
    await prefs.setString(key, '$chapterId|$xPath');
  }

  /// 私有：获取本地 XPath 位置
  Future<Map<String, dynamic>?> _getLocalPosition(int bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_xpath_$bookId';
    final data = prefs.getString(key);

    if (data == null) return null;

    final parts = data.split('|');
    if (parts.length >= 2) {
      return {
        'chapterId': int.tryParse(parts[0]) ?? 0,
        'xPath': parts.sublist(1).join('|'), // XPath 可能包含 |
      };
    }
    return null;
  }
}
