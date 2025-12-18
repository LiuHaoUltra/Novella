import 'package:logging/logging.dart';
import 'package:novella/core/network/signalr_service.dart';

class ChapterContent {
  final int id;
  final String title;
  final String content;
  final String? fontUrl;
  final int sortNum;

  ChapterContent({
    required this.id,
    required this.title,
    required this.content,
    this.fontUrl,
    required this.sortNum,
  });

  factory ChapterContent.fromJson(Map<dynamic, dynamic> json) {
    return ChapterContent(
      id: json['Id'] as int? ?? 0,
      title: json['Title'] as String? ?? 'Unknown Chapter',
      content: json['Content'] as String? ?? '',
      fontUrl: json['Font'] as String?,
      sortNum: json['SortNum'] as int? ?? 0,
    );
  }
}

class ChapterService {
  static final Logger _logger = Logger('ChapterService');
  final SignalRService _signalRService = SignalRService();

  /// Get chapter content
  /// Reference: getNovelContent in services/chapter/index.ts
  /// Convert: 't2s' | 's2t' | null
  Future<ChapterContent> getNovelContent(
    int bid,
    int sortNum, {
    String? convert,
  }) async {
    try {
      // Web reference always passes options with UseGzip: true as second arg
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetNovelContent',
        args: [
          {
            'Bid': bid,
            'SortNum': sortNum,
            if (convert != null) 'Convert': convert,
          },
          // Options (like reference's defaultRequestOptions)
          {'UseGzip': true},
        ],
      );

      // Debug: Print raw chapter data to see structure
      print('[CHAPTER] Raw result keys: ${result.keys.toList()}');
      if (result['Chapter'] != null) {
        final chapter = result['Chapter'];
        print('[CHAPTER] Chapter keys: ${chapter.keys.toList()}');
        print('[CHAPTER] Font value: ${chapter['Font']}');
        return ChapterContent.fromJson(result['Chapter']);
      }
      throw Exception('Chapter not found in response');
    } catch (e) {
      _logger.severe('Failed to get novel content: $e');
      rethrow;
    }
  }
}
