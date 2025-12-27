import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:palette_generator/palette_generator.dart';

/// 书籍封面颜色提取与动态配色方案生成服务
class BookColorService {
  static final _logger = Logger('BookColorService');

  // Singleton instance
  static final BookColorService _instance = BookColorService._internal();
  factory BookColorService() => _instance;
  BookColorService._internal();

  // 缓存：ColorScheme
  final Map<String, ColorScheme> _schemeCache = {};

  // 缓存：渐变色
  final Map<String, List<Color>> _gradientCache = {};

  /// 基于封面获取动态 ColorScheme
  /// 提取失败返回 null
  Future<ColorScheme?> getColorScheme({
    required int bookId,
    required String coverUrl,
    required Brightness brightness,
  }) async {
    if (coverUrl.isEmpty) return null;

    final cacheKey = '${bookId}_${brightness.name}';

    // 优先检查缓存
    if (_schemeCache.containsKey(cacheKey)) {
      return _schemeCache[cacheKey];
    }

    try {
      final seedColor = await _extractDominantColor(coverUrl);
      if (seedColor == null) return null;

      // 生成 ColorScheme
      final colorScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );

      // 缓存结果
      _schemeCache[cacheKey] = colorScheme;
      _logger.info(
        'Generated ColorScheme for book $bookId (${brightness.name}): seed=${seedColor.toARGB32().toRadixString(16)}',
      );

      return colorScheme;
    } catch (e) {
      _logger.warning('Failed to generate ColorScheme for book $bookId: $e');
      return null;
    }
  }

  /// 获取背景渐变色
  Future<List<Color>?> getGradientColors({
    required int bookId,
    required String coverUrl,
    required bool isDark,
  }) async {
    if (coverUrl.isEmpty) return null;

    final cacheKey = '${bookId}_${isDark ? 'dark' : 'light'}';

    // Check cache first
    if (_gradientCache.containsKey(cacheKey)) {
      return _gradientCache[cacheKey];
    }

    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(coverUrl),
        size: const Size(24, 24), // 小尺寸以加速提取
        maximumColorCount: 3,
      );

      // 获取渐变色
      final rawColors = <Color>[];

      // 主色：主导或活力
      final primary =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      // 次色：柔和或深柔和
      final secondary =
          paletteGenerator.mutedColor?.color ??
          paletteGenerator.darkMutedColor?.color;

      // 第三色：深活力或浅柔和
      final tertiary =
          paletteGenerator.darkVibrantColor?.color ??
          paletteGenerator.lightMutedColor?.color;

      if (primary != null) rawColors.add(primary);
      if (secondary != null) rawColors.add(secondary);
      if (tertiary != null) rawColors.add(tertiary);

      // 确保至少2种颜色
      if (rawColors.length < 2) {
        if (rawColors.isNotEmpty) {
          rawColors.add(
            Color.lerp(
              rawColors.first,
              isDark ? Colors.black : Colors.white,
              0.4,
            )!,
          );
        } else {
          return null;
        }
      }

      // 调整颜色以适应主题
      final adjustedColors =
          rawColors.map((c) => _adjustColorForTheme(c, isDark)).toList();

      // Cache the result
      _gradientCache[cacheKey] = adjustedColors;

      return adjustedColors;
    } catch (e) {
      _logger.warning('Failed to extract gradient colors for book $bookId: $e');
      return null;
    }
  }

  /// 提取封面主色
  Future<Color?> _extractDominantColor(String coverUrl) async {
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(coverUrl),
        size: const Size(24, 24),
        maximumColorCount: 3,
      );

      // 优先活力色，回退主色
      return paletteGenerator.vibrantColor?.color ??
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.mutedColor?.color;
    } catch (e) {
      _logger.warning('Failed to extract dominant color: $e');
      return null;
    }
  }

  /// 根据亮度调整颜色
  Color _adjustColorForTheme(Color color, bool isDark) {
    final hsl = HSLColor.fromColor(color);
    if (isDark) {
      // 深色模式：降低亮度，微增饱和度
      return hsl
          .withLightness((hsl.lightness * 0.6).clamp(0.1, 0.4))
          .withSaturation((hsl.saturation * 1.1).clamp(0.0, 1.0))
          .toColor();
    } else {
      // 浅色模式：增加亮度，柔化饱和
      return hsl
          .withLightness((hsl.lightness * 0.8 + 0.3).clamp(0.5, 0.85))
          .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.8))
          .toColor();
    }
  }

  /// 清除所有缓存
  void clearCache() {
    _schemeCache.clear();
    _gradientCache.clear();
  }

  /// 清除特定书籍缓存
  void clearBookCache(int bookId) {
    _schemeCache.removeWhere((key, _) => key.startsWith('${bookId}_'));
    _gradientCache.removeWhere((key, _) => key.startsWith('${bookId}_'));
  }
}
