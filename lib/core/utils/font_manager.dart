import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:convert/convert.dart';
import 'package:novella/src/rust/api/font_converter.dart' as rust_ffi;
import 'package:novella/main.dart' show rustLibInitialized, rustLibInitError;

/// Font cache information model
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

/// FontManager handles downloading and loading obfuscated fonts.
///
/// The lightnovel.life server uses custom fonts for content obfuscation.
/// Each book/chapter may have a unique font that maps garbled characters
/// to readable text. Fonts are delivered in WOFF2 format.
///
/// This implementation uses Rust FFI via flutter_rust_bridge to convert
/// WOFF2 to TTF format, which Flutter's FontLoader can then load.
class FontManager {
  static final FontManager _instance = FontManager._internal();
  final Dio _dio = Dio();
  final Set<String> _loadedFonts = {};

  factory FontManager() => _instance;
  FontManager._internal();

  /// Get the fonts cache directory
  Future<Directory> _getCacheDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final fontsDir = Directory(p.join(docDir.path, 'novella_fonts'));
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }
    return fontsDir;
  }

  /// Downloads a font from the given URL and loads it into Flutter.
  ///
  /// Returns the font family name to use with TextStyle, or null on failure.
  ///
  /// If [cacheEnabled] is true, the font will be cached and [cacheLimit]
  /// will be enforced after loading.
  Future<String?> loadFont(
    String? fontUrl, {
    bool cacheEnabled = true,
    int cacheLimit = 30,
  }) async {
    if (fontUrl == null || fontUrl.isEmpty) {
      print('[FONT] Font URL is null or empty');
      return null;
    }

    // Build absolute URL
    String url = fontUrl;
    if (!fontUrl.startsWith('http')) {
      url = 'https://api.lightnovel.life$fontUrl';
    }

    print('[FONT] Loading font from: $url');

    try {
      // 1. Generate unique font family name from URL hash
      final hash = md5.convert(Uint8List.fromList(url.codeUnits));
      final fontFamily = 'novella_${hex.encode(hash.bytes).substring(0, 16)}';

      // 2. Check if already loaded in Flutter engine
      if (_loadedFonts.contains(fontFamily)) {
        print('[FONT] Font already loaded: $fontFamily');
        return fontFamily;
      }

      // 3. Setup cache directory
      final fontsDir = await _getCacheDir();
      final ttfPath = p.join(fontsDir.path, '$fontFamily.ttf');
      final ttfFile = File(ttfPath);

      Uint8List ttfBytes;

      // 4. Check if TTF is cached
      if (await ttfFile.exists()) {
        ttfBytes = await ttfFile.readAsBytes();
        if (ttfBytes.length < 100) {
          print('[FONT] Cached TTF invalid, re-downloading');
          await ttfFile.delete();
        } else {
          print('[FONT] Using cached TTF: $ttfPath');
          // Update modification time to mark as recently used
          await ttfFile.setLastModified(DateTime.now());
        }
      }

      // 5. Download and convert if needed
      if (!await ttfFile.exists()) {
        // Download WOFF2 directly to memory (no disk caching)
        print('[FONT] Downloading WOFF2...');
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final woff2Bytes = Uint8List.fromList(response.data!);
        print('[FONT] WOFF2 size: ${woff2Bytes.length} bytes');

        // Convert WOFF2 to TTF using Rust FFI
        print('[FONT] Converting WOFF2 to TTF via Rust FFI...');
        print('[FONT] RustLib initialized: $rustLibInitialized');

        // Check if RustLib was successfully initialized in main.dart
        if (!rustLibInitialized) {
          print(
            '[FONT] *** ERROR: RustLib not initialized! Error: $rustLibInitError',
          );
          return null;
        }

        ttfBytes = await rust_ffi.convertWoff2ToTtf(woff2Data: woff2Bytes);
        print('[FONT] TTF size: ${ttfBytes.length} bytes');

        if (ttfBytes.isNotEmpty) {
          await ttfFile.writeAsBytes(ttfBytes);
          print('[FONT] Saved TTF: $ttfPath');
        } else {
          print('[FONT] Conversion returned empty!');
          return null;
        }
      }

      // 6. Load into Flutter
      ttfBytes = await ttfFile.readAsBytes();
      final fontLoader = FontLoader(fontFamily);
      fontLoader.addFont(Future.value(ByteData.view(ttfBytes.buffer)));
      await fontLoader.load();

      _loadedFonts.add(fontFamily);
      print('[FONT] Loaded: $fontFamily (${ttfBytes.length} bytes)');

      // 7. Enforce cache limit if enabled
      if (cacheEnabled) {
        await enforceCacheLimit(cacheLimit);
      }

      return fontFamily;
    } catch (e, stack) {
      print('[FONT] Error: $e');
      print('[FONT] Stack: $stack');
      return null;
    }
  }

  /// Clears all font caches (both WOFF2 and TTF files).
  /// Returns the number of files deleted.
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

      print('[FONT] Cleared $deletedCount cached files');
    } catch (e) {
      print('[FONT] Error clearing cache: $e');
    }
    return deletedCount;
  }

  /// Enforces the cache limit by keeping only the most recently used fonts.
  /// Uses file modification time to determine recency.
  Future<void> enforceCacheLimit(int limit) async {
    try {
      final fontsDir = await _getCacheDir();
      final files = fontsDir.listSync().whereType<File>().toList();

      // Only count TTF files for the limit (WOFF2 are intermediate)
      final ttfFiles = files.where((f) => f.path.endsWith('.ttf')).toList();

      if (ttfFiles.length <= limit) {
        return; // Within limit
      }

      // Sort by modification time (oldest first)
      ttfFiles.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return aStat.modified.compareTo(bStat.modified);
      });

      // Delete oldest files to meet limit
      final toDelete = ttfFiles.length - limit;
      for (int i = 0; i < toDelete; i++) {
        final ttfFile = ttfFiles[i];
        final baseName = p.basenameWithoutExtension(ttfFile.path);

        // Delete TTF
        await ttfFile.delete();

        // Remove from loaded set
        _loadedFonts.remove(baseName);

        print('[FONT] Removed old cache: $baseName');
      }

      print('[FONT] Enforced cache limit: $limit (removed $toDelete)');
    } catch (e) {
      print('[FONT] Error enforcing cache limit: $e');
    }
  }

  /// Gets information about the current font cache.
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
      print('[FONT] Error getting cache info: $e');
    }

    return FontCacheInfo(fileCount: fileCount, totalSizeBytes: totalSize);
  }
}
