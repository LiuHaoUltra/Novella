import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/network/signalr_service.dart';
import 'package:novella/data/models/book.dart';

class UserService extends ChangeNotifier {
  static final Logger _logger = Logger('UserService');

  // Singleton pattern
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final SignalRService _signalRService = SignalRService();

  // Local cache of shelf items
  List<Map<String, dynamic>> _shelfCache = [];
  bool _initialized = false;

  /// Ensure shelf data is loaded from server
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await getShelf();
  }

  Future<List<ShelfItem>> getShelf({bool forceRefresh = true}) async {
    try {
      if (!forceRefresh && _initialized && _shelfCache.isNotEmpty) {
        return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
      }

      // Reference sends [params, options]. Params is null, options has UseGzip.
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetBookShelf',
        args: <Object>[
          {}, // Params
          {'UseGzip': true}, // Options
        ],
      );

      // Handle empty result (server error returned empty map)
      if (result.isEmpty) {
        _logger.warning('Empty shelf response from server');
        if (_initialized)
          return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
        return [];
      }

      // Response format: { data: ShelfItem[], ver?: number }
      final data = result['data'];
      if (data == null || data is! List) {
        _logger.warning('Unexpected shelf data type: ${data?.runtimeType}');
        if (_initialized)
          return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
        return [];
      }

      // Cache the raw shelf data for modification
      _shelfCache =
          data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _initialized = true;

      _logger.info('Parsed ${data.length} shelf items');

      notifyListeners();

      // Return all items (Books and Folders)
      return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
    } catch (e) {
      _logger.severe('Failed to get shelf: $e');
      if (_initialized)
        return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
      return [];
    }
  }

  /// Get all shelf items (books only, sorted by index)
  List<ShelfItem> getShelfItems() {
    if (!_initialized) return [];

    final rawItems = _shelfCache.toList();

    // Sort by index
    rawItems.sort((a, b) {
      final indexA = a['index'] as int? ?? 0;
      final indexB = b['index'] as int? ?? 0;
      return indexA.compareTo(indexB);
    });

    return rawItems.map((e) => ShelfItem.fromJson(e)).toList();
  }

  /// Re-index all items to make room at index 0 for new items
  void _reIndexItems() {
    // Sort by current index
    final items = _shelfCache.toList();
    items.sort((a, b) {
      final indexA = a['index'] as int? ?? 0;
      final indexB = b['index'] as int? ?? 0;
      return indexA.compareTo(indexB);
    });

    // Reassign indices starting from 1 (leave 0 for new item)
    for (var i = 0; i < items.length; i++) {
      items[i]['index'] = i + 1;
    }
  }

  /// Add a book to the shelf
  /// Reference: addToShelf in stores/shelf.ts
  Future<bool> addToShelf(int bookId) async {
    try {
      await ensureInitialized();

      // Check if already in shelf
      final exists = _shelfCache.any(
        (e) => e['id'] == bookId && e['type'] == 'BOOK',
      );
      if (exists) {
        _logger.info('Book $bookId already in shelf');
        return true;
      }

      // Re-index existing items to make room at index 0
      _reIndexItems();

      // Create new shelf item at the top (index 0)
      final newItem = {
        'type': 'BOOK',
        'id': bookId,
        'index': 0, // Insert at top
        'parents': <String>[],
        'updateAt': DateTime.now().toIso8601String(),
      };

      _shelfCache.add(newItem);

      // Sync to server (Optimistic - no await)
      notifyListeners();
      _saveShelfToServer();

      _logger.info('Added book $bookId to shelf');
      return true;
    } catch (e) {
      _logger.severe('Failed to add to shelf: $e');
      return false;
    }
  }

  /// Remove a book from the shelf
  /// Reference: removeFromShelf in stores/shelf.ts
  Future<bool> removeFromShelf(int bookId) async {
    try {
      await ensureInitialized();

      final initialLength = _shelfCache.length;
      _shelfCache.removeWhere((e) => e['id'] == bookId && e['type'] == 'BOOK');

      if (_shelfCache.length == initialLength) {
        _logger.info('Book $bookId was not in shelf');
        return true;
      }

      // Sync to server (Optimistic - no await)
      notifyListeners();
      _saveShelfToServer();

      _logger.info('Removed book $bookId from shelf');
      return true;
    } catch (e) {
      _logger.severe('Failed to remove from shelf: $e');
      return false;
    }
  }

  /// Check if a book is in the shelf
  bool isInShelf(int bookId) {
    if (!_initialized) {
      // If not initialized, we can't be sure, but returning false is safer than true
      // ideally caller MUST ensureInitialized()
      _logger.warning('isInShelf called before initialization for $bookId');
    }
    return _shelfCache.any((e) => e['id'] == bookId && e['type'] == 'BOOK');
  }

  // ============= History API Methods =============

  /// Get user's reading history (list of book IDs)
  /// Reference: getReadHistory in services/user/index.ts
  /// Returns { Novel: number[], Comic: number[] }
  Future<List<int>> getReadHistory() async {
    try {
      // Web client always passes [params, options] - for no-param calls, params can be empty {}
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetReadHistory',
        args: <Object>[
          {}, // params (empty for this call)
          {'UseGzip': true}, // options
        ],
      );

      _logger.info('GetReadHistory raw result: $result');

      if (result.isEmpty) {
        _logger.info('Empty read history from server');
        return [];
      }

      // Extract Novel list (we only care about novels for now)
      final novelList = result['Novel'];
      if (novelList == null || novelList is! List) {
        _logger.warning(
          'Unexpected history data type: ${novelList?.runtimeType}',
        );
        return [];
      }

      final bookIds = novelList.cast<int>().toList();
      _logger.info('Got ${bookIds.length} books in read history');
      return bookIds;
    } catch (e) {
      _logger.severe('Failed to get read history: $e');
      return [];
    }
  }

  /// Clear user's reading history
  /// Reference: clearHistory in services/user/index.ts
  Future<bool> clearReadHistory() async {
    try {
      // Include options like other API calls
      await _signalRService.invoke(
        'ClearReadHistory',
        args: [
          {}, // Empty params
          {'UseGzip': true}, // Options
        ],
      );
      _logger.info('Read history cleared');
      notifyListeners();
      return true;
    } catch (e) {
      _logger.severe('Failed to clear read history: $e');
      return false;
    }
  }

  /// Save shelf to server (like reference's syncToRemote)
  Future<void> _saveShelfToServer() async {
    if (!_initialized) return;

    try {
      await _signalRService.invoke(
        'SaveBookShelf',
        args: <Object>[
          {
            'data': _shelfCache,
            'ver': '20220211', // SHELF_STRUCT_VER.LATEST
          },
          {'UseGzip': true}, // Options matching getBookShelf call style?
        ],
      );
      _logger.info('Shelf synced to server');
    } catch (e) {
      _logger.severe('Failed to sync shelf to server: $e');
      // In optimistic UI, silent failure is ... effectively the current state
      // We might want to retry or revert, but for now simple optimistic.
    }
  }
}
