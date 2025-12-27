import 'dart:developer' as developer;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:convert/convert.dart';
import 'package:novella/src/rust/api/font_converter.dart' as rust_ffi;
import 'package:novella/main.dart' show rustLibInitialized, rustLibInitError;

/// 字体缓存信息模型
class FontCacheInfo {
  final int fileCount;
  final int totalSizeBytes;

  const FontCacheInfo({required this.fileCount, required this.totalSizeBytes});

  String get formattedSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 字体管理器：处理混淆字体的下载与加载。
///
/// 服务端使用自定义字体混淆内容。
/// 每本书/章节可能有唯一字体映射乱码。
/// 字体为 WOFF2 格式。
///
/// 使用 Rust FFI (flutter_rust_bridge) 将 WOFF2
/// 转为 Flutter 可加载的 TTF 格式。
class FontManager {
  static final FontManager _instance = FontManager._internal();
  final Dio _dio = Dio();
  final Set<String> _loadedFonts = {};

  factory FontManager() => _instance;
  FontManager._internal();

  /// 获取字体缓存目录
  Future<Directory> _getCacheDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final fontsDir = Directory(p.join(docDir.path, 'novella_fonts'));
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }
    return fontsDir;
  }

  /// 下载并加载字体。
  ///
  /// 返回 fontFamily，失败返回 null。
  ///
  /// 若 [cacheEnabled] 为 true，缓存并执行限制 [cacheLimit]。
  Future<String?> loadFont(
    String? fontUrl, {
    bool cacheEnabled = true,
    int cacheLimit = 30,
  }) async {
    if (fontUrl == null || fontUrl.isEmpty) {
      developer.log('Font URL is null or empty', name: 'FONT');
      return null;
    }

    // 构建绝对 URL
    String url = fontUrl;
    if (!fontUrl.startsWith('http')) {
      url = 'https://api.lightnovel.life$fontUrl';
    }

    developer.log('Loading font from: $url', name: 'FONT');

    try {
      // 1. 根据 URL 哈希生成唯一字体名
      final hash = md5.convert(Uint8List.fromList(url.codeUnits));
      final fontFamily = 'novella_${hex.encode(hash.bytes).substring(0, 16)}';

      // 2. 检查是否已加载
      if (_loadedFonts.contains(fontFamily)) {
        developer.log('Font already loaded: $fontFamily', name: 'FONT');
        return fontFamily;
      }

      // 3. 设置缓存目录
      final fontsDir = await _getCacheDir();
      final ttfPath = p.join(fontsDir.path, '$fontFamily.ttf');
      final ttfFile = File(ttfPath);

      Uint8List ttfBytes;

      // 4. 检查 TTF 缓存
      if (await ttfFile.exists()) {
        ttfBytes = await ttfFile.readAsBytes();
        if (ttfBytes.length < 100) {
          developer.log('Cached TTF invalid, re-downloading', name: 'FONT');
          await ttfFile.delete();
        } else {
          developer.log('Using cached TTF: $ttfPath', name: 'FONT');
          // 更新修改时间以标记为最近使用
          await ttfFile.setLastModified(DateTime.now());
        }
      }

      // 5. 下载并转换（如需）
      if (!await ttfFile.exists()) {
        // 下载 WOFF2 到内存（不缓存文件）
        developer.log('Downloading WOFF2...', name: 'FONT');
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final woff2Bytes = Uint8List.fromList(response.data!);
        developer.log('WOFF2 size: ${woff2Bytes.length} bytes', name: 'FONT');

        // 使用 Rust FFI 转为 TTF
        developer.log('Converting WOFF2 to TTF via Rust FFI...', name: 'FONT');
        developer.log('RustLib initialized: $rustLibInitialized', name: 'FONT');

        // 检查 RustLib 初始化状态
        if (!rustLibInitialized) {
          developer.log(
            '*** ERROR: RustLib not initialized! Error: $rustLibInitError',
            name: 'FONT',
          );
          return null;
        }

        ttfBytes = await rust_ffi.convertWoff2ToTtf(woff2Data: woff2Bytes);
        developer.log('TTF size: ${ttfBytes.length} bytes', name: 'FONT');

        if (ttfBytes.isNotEmpty) {
          await ttfFile.writeAsBytes(ttfBytes);
          developer.log('Saved TTF: $ttfPath', name: 'FONT');
        } else {
          developer.log('Conversion returned empty!', name: 'FONT');
          return null;
        }
      }

      // 6. 加载到 Flutter
      ttfBytes = await ttfFile.readAsBytes();
      final fontLoader = FontLoader(fontFamily);
      fontLoader.addFont(Future.value(ByteData.view(ttfBytes.buffer)));
      await fontLoader.load();

      _loadedFonts.add(fontFamily);
      developer.log(
        'Loaded: $fontFamily (${ttfBytes.length} bytes)',
        name: 'FONT',
      );

      // 7. 执行缓存限制
      if (cacheEnabled) {
        await enforceCacheLimit(cacheLimit);
      }

      return fontFamily;
    } catch (e, stack) {
      developer.log('Error: $e', name: 'FONT');
      developer.log('Stack: $stack', name: 'FONT');
      return null;
    }
  }

  /// 清除所有字体缓存。
  /// 返回删除文件数。
  Future<int> clearAllCaches() async {
    int deletedCount = 0;
    try {
      final fontsDir = await _getCacheDir();
      final files = fontsDir.listSync();

      for (final entity in files) {
        if (entity is File) {
          await entity.delete();
          deletedCount++;
        }
      }

      // Clear loaded fonts set since cache is gone
      _loadedFonts.clear();

      developer.log('Cleared $deletedCount cached files', name: 'FONT');
    } catch (e) {
      developer.log('Error clearing cache: $e', name: 'FONT');
    }
    return deletedCount;
  }

  /// 执行缓存限制，保留最近使用的字体。
  /// 基于文件修改时间。
  Future<void> enforceCacheLimit(int limit) async {
    try {
      final fontsDir = await _getCacheDir();
      final files = fontsDir.listSync().whereType<File>().toList();

      // 仅统计 TTF 文件
      final ttfFiles = files.where((f) => f.path.endsWith('.ttf')).toList();

      if (ttfFiles.length <= limit) {
        return; // Within limit
      }

      // 按修改时间排序（旧文件在前）
      ttfFiles.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return aStat.modified.compareTo(bStat.modified);
      });

      // 删除最旧文件以满足限制
      final toDelete = ttfFiles.length - limit;
      for (int i = 0; i < toDelete; i++) {
        final ttfFile = ttfFiles[i];
        final baseName = p.basenameWithoutExtension(ttfFile.path);

        // Delete TTF
        await ttfFile.delete();

        // 从已加载集合中移除
        _loadedFonts.remove(baseName);

        developer.log('Removed old cache: $baseName', name: 'FONT');
      }

      developer.log(
        'Enforced cache limit: $limit (removed $toDelete)',
        name: 'FONT',
      );
    } catch (e) {
      developer.log('Error enforcing cache limit: $e', name: 'FONT');
    }
  }

  /// 获取当前字体缓存信息
  Future<FontCacheInfo> getCacheInfo() async {
    int fileCount = 0;
    int totalSize = 0;

    try {
      final fontsDir = await _getCacheDir();
      final files = fontsDir.listSync().whereType<File>();

      for (final file in files) {
        fileCount++;
        totalSize += await file.length();
      }
    } catch (e) {
      developer.log('Error getting cache info: $e', name: 'FONT');
    }

    return FontCacheInfo(fileCount: fileCount, totalSizeBytes: totalSize);
  }
}
