import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地书签状态枚举
/// 仅本地，不同步至服务器
enum BookMarkStatus {
  none, // 0 - 无
  toRead, // 1 - 待读
  reading, // 2 - 在读
  finished, // 3 - 已读
}

/// 状态枚举扩展（显示文本/图标）
extension BookMarkStatusExtension on BookMarkStatus {
  String get displayName {
    switch (this) {
      case BookMarkStatus.none:
        return '';
      case BookMarkStatus.toRead:
        return '待读';
      case BookMarkStatus.reading:
        return '在读';
      case BookMarkStatus.finished:
        return '已读';
    }
  }

  /// 图标名称
  String get iconName {
    switch (this) {
      case BookMarkStatus.none:
        return '';
      case BookMarkStatus.toRead:
        return 'schedule';
      case BookMarkStatus.reading:
        return 'auto_stories';
      case BookMarkStatus.finished:
        return 'check_circle';
    }
  }
}

/// 本地书签管理服务
/// 使用 SharedPreferences 存储阅读状态
/// 纯本地功能，不影响服务端数据
class BookMarkService {
  static final Logger _logger = Logger('BookMarkService');
  static final BookMarkService _instance = BookMarkService._internal();

  factory BookMarkService() => _instance;
  BookMarkService._internal();

  // 存储键前缀
  static const _markPrefix = 'book_mark_';

  /// 设置标记状态
  /// 传入 [none] 移除标记
  Future<void> setBookMark(int bookId, BookMarkStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_markPrefix$bookId';

    if (status == BookMarkStatus.none) {
      await prefs.remove(key);
      _logger.info('Removed mark for book $bookId');
    } else {
      await prefs.setInt(key, status.index);
      _logger.info('Set mark for book $bookId: ${status.displayName}');
    }
  }

  /// Get the mark status for a book.
  /// Returns [BookMarkStatus.none] if no mark is set.
  Future<BookMarkStatus> getBookMark(int bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_markPrefix$bookId';
    final value = prefs.getInt(key);

    if (value == null || value < 0 || value >= BookMarkStatus.values.length) {
      return BookMarkStatus.none;
    }

    return BookMarkStatus.values[value];
  }

  /// Get all book IDs with a specific mark status.
  /// Returns an empty set if no books have the specified status.
  Future<Set<int>> getBooksWithStatus(BookMarkStatus status) async {
    if (status == BookMarkStatus.none) {
      return {};
    }

    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    final result = <int>{};

    for (final key in allKeys) {
      if (!key.startsWith(_markPrefix)) continue;

      final value = prefs.getInt(key);
      if (value == status.index) {
        // Extract book ID from key
        final bookIdStr = key.substring(_markPrefix.length);
        final bookId = int.tryParse(bookIdStr);
        if (bookId != null) {
          result.add(bookId);
        }
      }
    }

    _logger.info(
      'Found ${result.length} books with status: ${status.displayName}',
    );
    return result;
  }

  /// Remove the mark for a book.
  Future<void> removeBookMark(int bookId) async {
    await setBookMark(bookId, BookMarkStatus.none);
  }

  /// Get all marked books with their status.
  /// Returns a map of bookId -> status.
  Future<Map<int, BookMarkStatus>> getAllMarkedBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    final result = <int, BookMarkStatus>{};

    for (final key in allKeys) {
      if (!key.startsWith(_markPrefix)) continue;

      final value = prefs.getInt(key);
      if (value != null && value > 0 && value < BookMarkStatus.values.length) {
        final bookIdStr = key.substring(_markPrefix.length);
        final bookId = int.tryParse(bookIdStr);
        if (bookId != null) {
          result[bookId] = BookMarkStatus.values[value];
        }
      }
    }

    _logger.info('Found ${result.length} marked books total');
    return result;
  }
}
