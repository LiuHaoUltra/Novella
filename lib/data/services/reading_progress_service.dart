import 'package:logging/logging.dart';
import 'package:novella/core/network/signalr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local reading position data
class ReadPosition {
  final int bookId;
  final int chapterId;
  final int sortNum;
  final double scrollPosition; // 0.0 to 1.0 representing scroll percentage

  ReadPosition({
    required this.bookId,
    required this.chapterId,
    required this.sortNum,
    required this.scrollPosition,
  });

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'chapterId': chapterId,
    'sortNum': sortNum,
    'scrollPosition': scrollPosition,
  };

  factory ReadPosition.fromJson(Map<String, dynamic> json) {
    return ReadPosition(
      bookId: json['bookId'] as int? ?? 0,
      chapterId: json['chapterId'] as int? ?? 0,
      sortNum: json['sortNum'] as int? ?? 1,
      scrollPosition: (json['scrollPosition'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Service for managing reading progress
/// Syncs with server and caches locally
class ReadingProgressService {
  static final Logger _logger = Logger('ReadingProgressService');
  static final ReadingProgressService _instance =
      ReadingProgressService._internal();
  final SignalRService _signalRService = SignalRService();

  factory ReadingProgressService() => _instance;
  ReadingProgressService._internal();

  /// Save reading position to server
  /// Reference: saveReadPosition in services/book/index.ts
  Future<void> saveReadPosition({
    required int bookId,
    required int chapterId,
    required String xPath, // XPath position for precise scroll restoration
  }) async {
    try {
      // Web client calls: invoke('SaveReadPosition', params, {UseGzip: true})
      // MUST include options as second arg!
      await _signalRService.invoke(
        'SaveReadPosition',
        args: [
          {'Bid': bookId, 'Cid': chapterId, 'XPath': xPath},
          {'UseGzip': true}, // Options - REQUIRED!
        ],
      );
      _logger.info(
        'Saved reading position: book=$bookId, chapter=$chapterId, xPath=$xPath',
      );
    } catch (e) {
      _logger.warning('Failed to save position to server: $e');
      // Still save locally even if server fails
    }

    // Save locally as backup
    await _saveLocalPosition(bookId, chapterId, xPath);
  }

  /// Get reading position - LOCAL ONLY
  /// Note: GetReadPosition RPC does not exist on the server.
  /// Server position is embedded in GetBookInfo response as ReadPosition.
  /// This method only returns locally cached position.
  Future<Map<String, dynamic>?> getReadPosition(int bookId) async {
    // Just return local cache - server position comes from GetBookInfo
    return await _getLocalPosition(bookId);
  }

  /// Save scroll percentage locally (simpler than XPath for Flutter)
  Future<void> saveLocalScrollPosition({
    required int bookId,
    required int chapterId,
    required int sortNum,
    required double scrollPosition,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_pos_$bookId';

    final position = ReadPosition(
      bookId: bookId,
      chapterId: chapterId,
      sortNum: sortNum,
      scrollPosition: scrollPosition,
    );

    final data =
        '${position.chapterId}|${position.sortNum}|${position.scrollPosition}';
    // Store as simple string for SharedPreferences
    await prefs.setString(key, data);

    print('[POSITION] SAVED: key=$key, data=$data');
    print(
      '[POSITION] SAVED: chapterId=$chapterId, sortNum=$sortNum, scroll=${(scrollPosition * 100).toStringAsFixed(1)}%',
    );
  }

  /// Get local scroll position
  Future<ReadPosition?> getLocalScrollPosition(int bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_pos_$bookId';
    final data = prefs.getString(key);

    print('[POSITION] LOAD: key=$key, data=$data');

    if (data == null) {
      print('[POSITION] LOAD: no saved position found');
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
        );
        print(
          '[POSITION] LOAD: chapterId=${pos.chapterId}, sortNum=${pos.sortNum}, scroll=${(pos.scrollPosition * 100).toStringAsFixed(1)}%',
        );
        return pos;
      }
    } catch (e) {
      print('[POSITION] LOAD ERROR: $e');
      _logger.warning('Failed to parse local position: $e');
    }
    return null;
  }

  /// Private: Save XPath-based position locally
  Future<void> _saveLocalPosition(
    int bookId,
    int chapterId,
    String xPath,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_xpath_$bookId';
    await prefs.setString(key, '$chapterId|$xPath');
  }

  /// Private: Get XPath-based position from local cache
  Future<Map<String, dynamic>?> _getLocalPosition(int bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'read_xpath_$bookId';
    final data = prefs.getString(key);

    if (data == null) return null;

    final parts = data.split('|');
    if (parts.length >= 2) {
      return {
        'chapterId': int.tryParse(parts[0]) ?? 0,
        'xPath': parts.sublist(1).join('|'), // XPath may contain |
      };
    }
    return null;
  }
}
