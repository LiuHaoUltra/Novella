import 'dart:developer' as developer;
import 'package:logging/logging.dart';
import 'package:novella/core/network/signalr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地阅读位置数据
class ReadPosition {
  final int bookId;
  final int chapterId;
  final int sortNum;
  final double scrollPosition; // 0.0-1.0 滚动百分比

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
    // 简单字符串存储
    await prefs.setString(key, data);

    developer.log('SAVED: key=$key, data=$data', name: 'POSITION');
    developer.log(
      'SAVED: chapterId=$chapterId, sortNum=$sortNum, scroll=${(scrollPosition * 100).toStringAsFixed(1)}%',
      name: 'POSITION',
    );
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
        );
        developer.log(
          'LOAD: chapterId=${pos.chapterId}, sortNum=${pos.sortNum}, scroll=${(pos.scrollPosition * 100).toStringAsFixed(1)}%',
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
