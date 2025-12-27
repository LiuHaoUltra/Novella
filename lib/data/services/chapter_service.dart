import 'dart:developer' as developer;
import 'package:logging/logging.dart';
import 'package:novella/core/network/signalr_service.dart';

class ChapterContent {
  final int id;
  final String title;
  final String content;
  final String? fontUrl;
  final int sortNum;
  // 服务端提供的阅读位置
  final String? serverPosition;

  ChapterContent({
    required this.id,
    required this.title,
    required this.content,
    this.fontUrl,
    required this.sortNum,
    this.serverPosition,
  });

  factory ChapterContent.fromJson(
    Map<dynamic, dynamic> json, {
    String? position,
  }) {
    return ChapterContent(
      id: json['Id'] as int? ?? 0,
      title: json['Title'] as String? ?? 'Unknown Chapter',
      content: json['Content'] as String? ?? '',
      fontUrl: json['Font'] as String?,
      sortNum: json['SortNum'] as int? ?? 0,
      serverPosition: position,
    );
  }
}

class ChapterService {
  static final Logger _logger = Logger('ChapterService');
  final SignalRService _signalRService = SignalRService();

  /// 获取章节内容
  /// 参考 services/chapter/index.ts
  /// Convert: 't2s' | 's2t' | null
  Future<ChapterContent> getNovelContent(
    int bid,
    int sortNum, {
    String? convert,
  }) async {
    try {
      // Web 参考包含 UseGzip
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetNovelContent',
        args: [
          {
            'Bid': bid,
            'SortNum': sortNum,
            if (convert != null) 'Convert': convert,
          },
          // 选项
          {'UseGzip': true},
        ],
      );

      // 调试：打印原始章节数据
      developer.log(
        'Raw result keys: ${result.keys.toList()}',
        name: 'CHAPTER',
      );
      if (result['Chapter'] != null) {
        final chapter = result['Chapter'];
        developer.log(
          'Chapter keys: ${chapter.keys.toList()}',
          name: 'CHAPTER',
        );
        developer.log('Font value: ${chapter['Font']}', name: 'CHAPTER');

        // 提取阅读位置
        String? position;
        final readPos = result['ReadPosition'];
        if (readPos != null && readPos is Map) {
          position = readPos['Position'] as String?;
          developer.log(
            'ReadPosition: ChapterId=${readPos['ChapterId']}, Position=$position',
            name: 'CHAPTER',
          );
        }

        return ChapterContent.fromJson(result['Chapter'], position: position);
      }
      throw Exception('Chapter not found in response');
    } catch (e) {
      _logger.severe('Failed to get novel content: $e');
      rethrow;
    }
  }
}
