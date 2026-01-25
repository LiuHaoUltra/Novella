import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 封面本地持久化服务
/// 针对首页“继续阅读”卡片，通过 Image.file 实现 0 闪烁同步加载
class LocalCoverService {
  static final Logger _logger = Logger('LocalCoverService');
  static final LocalCoverService _instance = LocalCoverService._internal();

  factory LocalCoverService() => _instance;
  LocalCoverService._internal();

  Directory? _coverDir;
  final Dio _dio = Dio();

  /// 初始化目录
  Future<void> _init() async {
    if (_coverDir != null) return;
    final appDir = await getApplicationSupportDirectory();
    _coverDir = Directory(p.join(appDir.path, 'covers'));
    if (!await _coverDir!.exists()) {
      await _coverDir!.create(recursive: true);
    }
  }

  /// 获取本地封面文件
  Future<File?> getLocalCover(int bid) async {
    await _init();
    final file = File(p.join(_coverDir!.path, 'book_$bid.jpg'));
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// 同步网络封面到本地物理存储
  Future<void> saveCover(int bid, String url) async {
    if (url.isEmpty) return;

    try {
      await _init();
      final filePath = p.join(_coverDir!.path, 'book_$bid.jpg');
      final file = File(filePath);

      // 如果文件已存在，不重复下载（减少负载）
      if (await file.exists()) {
        final length = await file.length();
        if (length > 1024) return; // 简单判断文件是否有效
      }

      await _dio.download(url, filePath);
      _logger.info('Successfully saved local cover for book $bid');
    } catch (e) {
      _logger.warning('Failed to save local cover for book $bid: $e');
    }
  }

  /// 安全获取封面文件路径（同步版本用于 Image.file）
  String getLocalCoverPathSync(int bid) {
    if (_coverDir == null) return '';
    return p.join(_coverDir!.path, 'book_$bid.jpg');
  }
}
