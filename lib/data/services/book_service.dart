import 'package:logging/logging.dart';
import 'package:novella/core/network/signalr_service.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/features/book/book_detail_page.dart';

class BookService {
  static final Logger _logger = Logger('BookService');
  final SignalRService _signalRService = SignalRService();

  Future<List<Book>> getLatestBooks({
    int page = 1,
    int size = 20,
    bool ignoreJapanese = false,
    bool ignoreAI = false,
  }) async {
    try {
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetLatestBookList',
        args: [
          // Request params
          {
            'Page': page,
            'Size': size,
            'Order': 'latest',
            'IgnoreJapanese': ignoreJapanese,
            'IgnoreAI': ignoreAI,
          },
          // Options (like reference's defaultRequestOptions)
          {'UseGzip': true},
        ],
      );

      if (result['Data'] is List) {
        final List<dynamic> list = result['Data'];
        _logger.info('Parsed ${list.length} books from server');
        return list.map((e) => Book.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _logger.severe('Failed to get latest books: $e');
      rethrow;
    }
  }

  /// Get book list with pagination, sorting and filtering
  Future<SearchResult> getBookList({
    int page = 1,
    int size = 20,
    String order = 'latest',
    bool ignoreJapanese = false,
    bool ignoreAI = false,
  }) async {
    try {
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetBookList',
        args: [
          {
            'Page': page,
            'Size': size,
            'Order': order,
            'IgnoreJapanese': ignoreJapanese,
            'IgnoreAI': ignoreAI,
          },
          {'UseGzip': true},
        ],
      );

      final List<dynamic> data = result['Data'] ?? [];
      final int totalPages = result['TotalPages'] ?? 0;

      return SearchResult(
        books: data.map((e) => Book.fromJson(e)).toList(),
        totalPages: totalPages,
        currentPage: page,
      );
    } catch (e) {
      _logger.severe('Failed to get book list: $e');
      rethrow;
    }
  }

  Future<List<Book>> getBooksByIds(List<int> ids) async {
    if (ids.isEmpty) return [];

    // Chunking to 24 max as per PRD/Ref
    final List<Book> allBooks = [];
    final int chunkSize = 24;

    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
      final chunk = ids.sublist(i, end);

      try {
        final result = await _signalRService.invoke<List<dynamic>>(
          'GetBookListByIds',
          args: [
            // Request params
            {'Ids': chunk},
            // Options
            {'UseGzip': true},
          ],
        );

        allBooks.addAll(result.map((e) => Book.fromJson(e)).toList());
      } catch (e) {
        _logger.severe('Failed to get books chunk $i-$end: $e');
        rethrow;
      }
    }

    return allBooks;
  }

  /// Get detailed book information including chapters
  /// Reference: getBookInfo in services/book/index.ts
  Future<BookInfo> getBookInfo(int id) async {
    try {
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetBookInfo',
        args: [
          {'Id': id},
          {'UseGzip': true},
        ],
      );

      _logger.info('Got book info for id=$id');
      return BookInfo.fromJson(result);
    } catch (e) {
      _logger.severe('Failed to get book info: $e');
      rethrow;
    }
  }

  /// Get ranking list for specified period
  /// Reference: getRank in services/book/index.ts
  /// [days]: 1 = daily, 7 = weekly, 31 = monthly
  Future<List<Book>> getRank(int days) async {
    try {
      final result = await _signalRService.invoke<List<dynamic>>(
        'GetRank',
        args: [
          {'Days': days},
          {'UseGzip': true},
        ],
      );

      _logger.info('Got ${result.length} books from ranking (days=$days)');
      return result.map((e) => Book.fromJson(e)).toList();
    } catch (e) {
      _logger.severe('Failed to get ranking: $e');
      rethrow;
    }
  }

  /// Search books by keywords
  /// Reference: getBookList in services/book/index.ts
  Future<SearchResult> searchBooks(
    String keywords, {
    int page = 1,
    int size = 10,
    bool ignoreJapanese = false,
    bool ignoreAI = false,
  }) async {
    try {
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetBookList',
        args: [
          {
            'Page': page,
            'Size': size,
            'KeyWords': keywords,
            'IgnoreJapanese': ignoreJapanese,
            'IgnoreAI': ignoreAI,
          },
          {'UseGzip': true},
        ],
      );

      final List<dynamic> data = result['Data'] ?? [];
      final int totalPages = result['TotalPages'] ?? 0;

      _logger.info(
        'Search "$keywords" page $page: ${data.length} results, $totalPages pages',
      );

      return SearchResult(
        books: data.map((e) => Book.fromJson(e)).toList(),
        totalPages: totalPages,
        currentPage: page,
      );
    } catch (e) {
      _logger.severe('Failed to search books: $e');
      rethrow;
    }
  }
}

/// Search result with pagination info
class SearchResult {
  final List<Book> books;
  final int totalPages;
  final int currentPage;

  SearchResult({
    required this.books,
    required this.totalPages,
    required this.currentPage,
  });
}
