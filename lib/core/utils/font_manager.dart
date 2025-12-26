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
      developer.log('Font URL is null or empty', name: 'FONT');
      return null;
    }

    // Build absolute URL
    String url = fontUrl;
    if (!fontUrl.startsWith('http')) {
      url = 'https://api.lightnovel.life$fontUrl';
    }

    developer.log('Loading font from: $url', name: 'FONT');

    try {
      // 1. Generate unique font family name from URL hash
      final hash = md5.convert(Uint8List.fromList(url.codeUnits));
      final fontFamily = 'novella_${hex.encode(hash.bytes).substring(0, 16)}';

      // 2. Check if already loaded in Flutter engine
      if (_loadedFonts.contains(fontFamily)) {
        developer.log('Font already loaded: $fontFamily', name: 'FONT');
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
          developer.log('Cached TTF invalid, re-downloading', name: 'FONT');
          await ttfFile.delete();
        } else {
          developer.log('Using cached TTF: $ttfPath', name: 'FONT');
          // Update modification time to mark as recently used
          await ttfFile.setLastModified(DateTime.now());
        }
      }

      // 5. Download and convert if needed
      if (!await ttfFile.exists()) {
        // Download WOFF2 directly to memory (no disk caching)
        developer.log('Downloading WOFF2...', name: 'FONT');
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final woff2Bytes = Uint8List.fromList(response.data!);
        developer.log('WOFF2 size: ${woff2Bytes.length} bytes', name: 'FONT');

        // Convert WOFF2 to TTF using Rust FFI
        developer.log('Converting WOFF2 to TTF via Rust FFI...', name: 'FONT');
        developer.log('RustLib initialized: $rustLibInitialized', name: 'FONT');

        // Check if RustLib was successfully initialized in main.dart
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

      // 6. Load into Flutter
      ttfBytes = await ttfFile.readAsBytes();
      final fontLoader = FontLoader(fontFamily);
      fontLoader.addFont(Future.value(ByteData.view(ttfBytes.buffer)));
      await fontLoader.load();

      _loadedFonts.add(fontFamily);
      developer.log(
        'Loaded: $fontFamily (${ttfBytes.length} bytes)',
        name: 'FONT',
      );

      // 7. Enforce cache limit if enabled
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

      developer.log('Cleared $deletedCount cached files', name: 'FONT');
    } catch (e) {
      developer.log('Error clearing cache: $e', name: 'FONT');
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
      developer.log('Error getting cache info: $e', name: 'FONT');
    }

    return FontCacheInfo(fileCount: fileCount, totalSizeBytes: totalSize);
  }
}
