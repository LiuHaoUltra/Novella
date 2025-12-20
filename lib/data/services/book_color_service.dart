import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:palette_generator/palette_generator.dart';

/// Service for extracting colors from book covers and generating dynamic ColorSchemes
class BookColorService {
  static final _logger = Logger('BookColorService');

  // Singleton instance
  static final BookColorService _instance = BookColorService._internal();
  factory BookColorService() => _instance;
  BookColorService._internal();

  // Cache: "bookId_brightness" -> ColorScheme
  final Map<String, ColorScheme> _schemeCache = {};

  // Cache: "bookId_brightness" -> List<Color> (gradient colors)
  final Map<String, List<Color>> _gradientCache = {};

  /// Get a dynamic ColorScheme based on cover image
  /// Returns null if color extraction fails
  Future<ColorScheme?> getColorScheme({
    required int bookId,
    required String coverUrl,
    required Brightness brightness,
  }) async {
    if (coverUrl.isEmpty) return null;

    final cacheKey = '${bookId}_${brightness.name}';

    // Check cache first
    if (_schemeCache.containsKey(cacheKey)) {
      return _schemeCache[cacheKey];
    }

    try {
      final seedColor = await _extractDominantColor(coverUrl);
      if (seedColor == null) return null;

      // Generate ColorScheme from seed color
      final colorScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );

      // Cache the result
      _schemeCache[cacheKey] = colorScheme;
      _logger.info(
        'Generated ColorScheme for book $bookId (${brightness.name}): seed=${seedColor.value.toRadixString(16)}',
      );

      return colorScheme;
    } catch (e) {
      _logger.warning('Failed to generate ColorScheme for book $bookId: $e');
      return null;
    }
  }

  /// Get gradient colors for background (reusing existing logic)
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
        size: const Size(24, 24), // Small for fast extraction
        maximumColorCount: 3,
      );

      // Get colors for gradient
      final rawColors = <Color>[];

      // Primary: dominant or vibrant
      final primary =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      // Secondary: muted or dark muted
      final secondary =
          paletteGenerator.mutedColor?.color ??
          paletteGenerator.darkMutedColor?.color;

      // Tertiary: dark vibrant or light muted
      final tertiary =
          paletteGenerator.darkVibrantColor?.color ??
          paletteGenerator.lightMutedColor?.color;

      if (primary != null) rawColors.add(primary);
      if (secondary != null) rawColors.add(secondary);
      if (tertiary != null) rawColors.add(tertiary);

      // Ensure at least 2 colors
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

      // Adjust colors for theme
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

  /// Extract dominant color from cover image
  Future<Color?> _extractDominantColor(String coverUrl) async {
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(coverUrl),
        size: const Size(24, 24),
        maximumColorCount: 3,
      );

      // Prefer vibrant color for more saturated seed, fallback to dominant
      return paletteGenerator.vibrantColor?.color ??
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.mutedColor?.color;
    } catch (e) {
      _logger.warning('Failed to extract dominant color: $e');
      return null;
    }
  }

  /// Adjust color based on theme brightness
  Color _adjustColorForTheme(Color color, bool isDark) {
    final hsl = HSLColor.fromColor(color);
    if (isDark) {
      // Dark mode: reduce lightness, increase saturation slightly
      return hsl
          .withLightness((hsl.lightness * 0.6).clamp(0.1, 0.4))
          .withSaturation((hsl.saturation * 1.1).clamp(0.0, 1.0))
          .toColor();
    } else {
      // Light mode: increase lightness, soften saturation
      return hsl
          .withLightness((hsl.lightness * 0.8 + 0.3).clamp(0.5, 0.85))
          .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.8))
          .toColor();
    }
  }

  /// Clear all cached data
  void clearCache() {
    _schemeCache.clear();
    _gradientCache.clear();
  }

  /// Clear cache for a specific book
  void clearBookCache(int bookId) {
    _schemeCache.removeWhere((key, _) => key.startsWith('${bookId}_'));
    _gradientCache.removeWhere((key, _) => key.startsWith('${bookId}_'));
  }
}
