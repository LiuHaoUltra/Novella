import 'package:novella/features/book/book_detail_page.dart';

/// BookInfo 内存会话缓存
/// 应用重启时清除
class BookInfoCacheService {
  static final BookInfoCacheService _instance = BookInfoCacheService._();
  factory BookInfoCacheService() => _instance;
  BookInfoCacheService._();

  final Map<int, BookInfo> _cache = {};

  /// 获取缓存，无则返回 null
  BookInfo? get(int bookId) => _cache[bookId];

  /// 缓存 BookInfo
  void set(int bookId, BookInfo info) => _cache[bookId] = info;

  /// 使特定书籍缓存失效
  void invalidate(int bookId) => _cache.remove(bookId);

  /// 清除所有缓存
  void clear() => _cache.clear();

  /// 检查是否有缓存
  bool has(int bookId) => _cache.containsKey(bookId);
}
