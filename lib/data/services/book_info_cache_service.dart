import 'package:novella/features/book/book_detail_page.dart';

/// In-memory session cache for BookInfo.
/// Cache is cleared when the app restarts.
class BookInfoCacheService {
  static final BookInfoCacheService _instance = BookInfoCacheService._();
  factory BookInfoCacheService() => _instance;
  BookInfoCacheService._();

  final Map<int, BookInfo> _cache = {};

  /// Get cached BookInfo by book ID, returns null if not cached.
  BookInfo? get(int bookId) => _cache[bookId];

  /// Cache BookInfo for a book ID.
  void set(int bookId, BookInfo info) => _cache[bookId] = info;

  /// Invalidate cache for a specific book.
  void invalidate(int bookId) => _cache.remove(bookId);

  /// Clear all cached BookInfo.
  void clear() => _cache.clear();

  /// Check if a book is cached.
  bool has(int bookId) => _cache.containsKey(bookId);
}
