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

  // 书架项目本地缓存
  List<Map<String, dynamic>> _shelfCache = [];
  bool _initialized = false;

  /// 确保从服务器加载书架数据
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await getShelf();
  }

  Future<List<ShelfItem>> getShelf({bool forceRefresh = true}) async {
    try {
      if (!forceRefresh && _initialized && _shelfCache.isNotEmpty) {
        return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
      }

      // 参考实现：发送 [params, options]
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetBookShelf',
        args: <Object>[
          {}, // Params
          {'UseGzip': true}, // Options
        ],
      );

      // 处理空结果（服务端返回空 Map）
      if (result.isEmpty) {
        _logger.warning('Empty shelf response from server');
        if (_initialized) {
          return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
        }
        return [];
      }

      // 响应格式：{ data: ShelfItem[], ver?: number }
      final data = result['data'];
      if (data == null || data is! List) {
        _logger.warning('Unexpected shelf data type: ${data?.runtimeType}');
        if (_initialized) {
          return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
        }
        return [];
      }

      // 缓存原始数据以便修改
      _shelfCache =
          data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _initialized = true;

      _logger.info('Parsed ${data.length} shelf items');

      notifyListeners();

      // 返回所有项目（书和文件夹）
      return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
    } catch (e) {
      _logger.severe('Failed to get shelf: $e');
      if (_initialized) {
        return _shelfCache.map((e) => ShelfItem.fromJson(e)).toList();
      }
      return [];
    }
  }

  /// 获取所有书架项目（仅书籍，按索引排序）
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

  /// 重新索引，为新项目腾出位置 0
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

  /// 添加书籍到书架
  /// 参考 stores/shelf.ts
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

      // 重新索引以腾出位置 0
      _reIndexItems();

      // 在顶部（索引 0）创建新项目
      final newItem = {
        'type': 'BOOK',
        'id': bookId,
        'index': 0, // Insert at top
        'parents': <String>[],
        'updateAt': DateTime.now().toIso8601String(),
      };

      _shelfCache.add(newItem);

      // 同步到服务器（乐观更新，不等待）
      notifyListeners();
      _saveShelfToServer();

      _logger.info('Added book $bookId to shelf');
      return true;
    } catch (e) {
      _logger.severe('Failed to add to shelf: $e');
      return false;
    }
  }

  /// 从书架移除书籍
  /// 参考 stores/shelf.ts
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
      // 若未初始化，返回 false 以策安全
      // 调用者应确保已初始化
      _logger.warning('isInShelf called before initialization for $bookId');
    }
    return _shelfCache.any((e) => e['id'] == bookId && e['type'] == 'BOOK');
  }

  // ============= 历史记录 API =============

  /// 获取用户阅读历史（书籍 ID 列表）
  /// 参考 services/user/index.ts
  /// 返回 { Novel: number[], Comic: number[] }
  Future<List<int>> getReadHistory() async {
    try {
      // Web 端总是传递 [params, options]
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

      // 提取 Novel 列表（目前仅关注小说）
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

  /// 清除用户阅读历史
  /// 参考 services/user/index.ts
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

  /// 保存书架到服务器（参考 syncToRemote）
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
      // 乐观 UI 中允许无声失败，即维持当前状态
      // 暂时保持简单乐观更新
    }
  }
}
