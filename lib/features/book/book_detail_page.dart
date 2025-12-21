import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/services/book_info_cache_service.dart';
import 'package:novella/data/services/book_mark_service.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/reading_progress_service.dart';
import 'package:novella/data/services/user_service.dart';
import 'package:novella/features/reader/reader_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:palette_generator/palette_generator.dart';

/// Shimmer loading effect widget
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 4,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Detailed book information response
class BookInfo {
  final int id;
  final String title;
  final String cover;
  final String author;
  final String introduction;
  final DateTime lastUpdatedAt;
  final String? lastUpdatedChapter;
  final int favorite;
  final int views;
  final bool canEdit;
  final List<ChapterInfo> chapters;
  final UserInfo? user;
  // Server-provided reading position (from GetBookInfo response)
  final ServerReadPosition? serverReadPosition;

  BookInfo({
    required this.id,
    required this.title,
    required this.cover,
    required this.author,
    required this.introduction,
    required this.lastUpdatedAt,
    this.lastUpdatedChapter,
    required this.favorite,
    required this.views,
    required this.canEdit,
    required this.chapters,
    this.user,
    this.serverReadPosition,
  });

  factory BookInfo.fromJson(Map<dynamic, dynamic> json) {
    final book = json['Book'] as Map<dynamic, dynamic>? ?? json;
    final chapterList =
        (book['Chapter'] as List?)
            ?.map((e) => ChapterInfo.fromJson(e as Map<dynamic, dynamic>))
            .toList() ??
        [];

    // Parse ReadPosition from server response
    ServerReadPosition? readPos;
    final posData = json['ReadPosition'];
    if (posData != null && posData is Map) {
      readPos = ServerReadPosition.fromJson(posData);
    }

    return BookInfo(
      id: book['Id'] as int? ?? 0,
      title: book['Title'] as String? ?? 'Unknown',
      cover: book['Cover'] as String? ?? '',
      author: book['Author'] as String? ?? 'Unknown',
      introduction: book['Introduction'] as String? ?? '',
      lastUpdatedAt:
          DateTime.tryParse(book['LastUpdatedAt']?.toString() ?? '') ??
          DateTime.now(),
      lastUpdatedChapter: book['LastUpdatedChapter'] as String?,
      favorite: book['Favorite'] as int? ?? 0,
      views: book['Views'] as int? ?? 0,
      canEdit: book['CanEdit'] as bool? ?? false,
      chapters: chapterList,
      user: book['User'] != null ? UserInfo.fromJson(book['User']) : null,
      serverReadPosition: readPos,
    );
  }
}

/// Server-provided reading position
class ServerReadPosition {
  final int? chapterId;
  final String? position; // XPath or scroll position string

  ServerReadPosition({this.chapterId, this.position});

  factory ServerReadPosition.fromJson(Map<dynamic, dynamic> json) {
    return ServerReadPosition(
      chapterId: json['ChapterId'] as int?,
      position: json['Position'] as String?,
    );
  }
}

class ChapterInfo {
  final int id;
  final String title;

  ChapterInfo({required this.id, required this.title});

  factory ChapterInfo.fromJson(Map<dynamic, dynamic> json) {
    return ChapterInfo(
      id: json['Id'] as int? ?? 0,
      title: json['Title'] as String? ?? '',
    );
  }
}

class UserInfo {
  final int id;
  final String userName;
  final String avatar;

  UserInfo({required this.id, required this.userName, required this.avatar});

  factory UserInfo.fromJson(Map<dynamic, dynamic> json) {
    return UserInfo(
      id: json['Id'] as int? ?? 0,
      userName: json['UserName'] as String? ?? '',
      avatar: json['Avatar'] as String? ?? '',
    );
  }
}

class BookDetailPage extends ConsumerStatefulWidget {
  final int bookId;
  final String? initialCoverUrl;
  final String? initialTitle;
  final String? heroTag;

  const BookDetailPage({
    super.key,
    required this.bookId,
    this.initialCoverUrl,
    this.initialTitle,
    this.heroTag,
  });

  @override
  ConsumerState<BookDetailPage> createState() => BookDetailPageState();
}

class BookDetailPageState extends ConsumerState<BookDetailPage> {
  final _logger = Logger('BookDetailPage');
  final _bookService = BookService();
  final _progressService = ReadingProgressService();
  final _userService = UserService();
  final _bookMarkService = BookMarkService();
  final _cacheService = BookInfoCacheService();

  // Local book mark status
  BookMarkStatus _currentMark = BookMarkStatus.none;

  // Static cache for extracted colors (shared across all instances)
  // Key format: "bookId_dark" or "bookId_light"
  static final Map<String, List<Color>> _colorCache = {};
  // Static cache for ColorScheme (shared across all instances)
  static final Map<String, ColorScheme> _schemeCache = {};

  // Track current brightness to detect theme changes
  Brightness? _currentBrightness;

  /// Clear all color caches (call when theme changes)
  static void clearColorCache() {
    _colorCache.clear();
    _schemeCache.clear();
  }

  BookInfo? _bookInfo;
  ReadPosition? _readPosition;
  bool _loading = true;
  bool _isInShelf = false;
  bool _shelfLoading = false;
  String? _error;

  // Gradient colors extracted from cover
  List<Color>? _gradientColors;
  bool _coverLoadFailed = false;
  bool _colorsExtracted = false; // Track if we already extracted colors

  // Dynamic ColorScheme based on cover image
  ColorScheme? _dynamicColorScheme;

  /// Format DateTime to relative time string (dayjs-compatible thresholds)
  /// @see https://day.js.org/docs/en/display/from-now#list-of-breakdown-range
  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    final seconds = diff.inSeconds;
    final minutes = diff.inMinutes;
    final hours = diff.inHours;
    final days = diff.inDays;

    if (seconds < 45) {
      return '刚刚';
    } else if (seconds < 90) {
      return '1分钟前';
    } else if (minutes < 45) {
      return '$minutes分钟前';
    } else if (minutes < 90) {
      return '1小时前';
    } else if (hours < 22) {
      return '$hours小时前';
    } else if (hours < 36) {
      return '1天前';
    } else if (days < 26) {
      final roundedDays = (hours / 24).round(); // Use rounding like dayjs
      return '$roundedDays天前';
    } else if (days < 46) {
      return '1个月前';
    } else if (days < 320) {
      final months = (days / 30.4).round(); // Average days per month
      return '$months个月前';
    } else if (days < 548) {
      return '1年前';
    } else {
      final years = (days / 365.25).round(); // Account for leap years
      return '$years年前';
    }
  }

  @override
  void initState() {
    super.initState();

    // Try to restore cached colors immediately to prevent flash
    _tryRestoreCachedColors();

    _loadBookInfo();
    // Delay color extraction to avoid lag during page transition
    // Use SchedulerBinding to ensure we wait for frame rendering
    if (widget.initialCoverUrl != null && widget.initialCoverUrl!.isNotEmpty) {
      // Wait for page transition to complete (reduced for faster feedback)
      // Then schedule after next frame to avoid jank
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_colorsExtracted) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_colorsExtracted) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              _extractColors(widget.initialCoverUrl!, isDark);
            }
          });
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    // Detect theme change and re-extract colors
    if (_currentBrightness != null && _currentBrightness != brightness) {
      _logger.info(
        'Theme changed from $_currentBrightness to $brightness, re-extracting colors',
      );
      // Reset color extraction state
      _gradientColors = null;
      _dynamicColorScheme = null;
      _colorsExtracted = false;
      // Re-extract colors for new theme
      final coverUrl = widget.initialCoverUrl ?? _bookInfo?.cover;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        _extractColors(coverUrl, brightness == Brightness.dark);
      }
    }
    _currentBrightness = brightness;
  }

  /// Try to restore cached colors immediately (synchronously) to prevent flash
  void _tryRestoreCachedColors() {
    // We need to check both light and dark theme cache keys
    // Since we don't have context here yet, try to get from platform brightness
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final isDark = brightness == Brightness.dark;
    final cacheKey = '${widget.bookId}_${isDark ? 'dark' : 'light'}';

    if (_colorCache.containsKey(cacheKey) &&
        _schemeCache.containsKey(cacheKey)) {
      _gradientColors = _colorCache[cacheKey]!;
      _dynamicColorScheme = _schemeCache[cacheKey]!;
      _colorsExtracted = true;
    }
  }

  /// Adjust color based on theme brightness for premium feel
  Color _adjustColorForTheme(Color color, bool isDark) {
    final hsl = HSLColor.fromColor(color);
    if (isDark) {
      // Dark mode: significantly reduce lightness for darker backgrounds
      // Range 0.05-0.25 ensures colors are dark but still distinguishable
      return hsl
          .withLightness((hsl.lightness * 0.4).clamp(0.05, 0.25))
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

  /// Extract dominant colors from cover image for gradient background
  Future<void> _extractColors(String coverUrl, bool isDark) async {
    if (coverUrl.isEmpty) {
      setState(() => _coverLoadFailed = true);
      return;
    }

    // Check cache first - use theme-specific cache key
    final cacheKey = '${widget.bookId}_${isDark ? 'dark' : 'light'}';
    if (_colorCache.containsKey(cacheKey) &&
        _schemeCache.containsKey(cacheKey)) {
      // Use cached adjusted colors and ColorScheme directly
      _gradientColors = _colorCache[cacheKey]!;
      _dynamicColorScheme = _schemeCache[cacheKey]!;
      _colorsExtracted = true;
      if (mounted) setState(() {});
      return;
    }

    try {
      // Extract colors from cover image
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(coverUrl),
        size: const Size(24, 24), // Small for fast extraction
        maximumColorCount: 2, // Only need top 2 colors
      );

      if (!mounted) return;

      // Get only top 2 colors for smoother gradient (avoids harsh lines)
      // Primary: dominant first (by area coverage), fallback to vibrant
      final primary =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      // Secondary: muted or dark muted (fallback to light muted)
      final secondary =
          paletteGenerator.mutedColor?.color ??
          paletteGenerator.darkMutedColor?.color ??
          paletteGenerator.lightMutedColor?.color;

      // Build gradient colors: primary -> middle (interpolated) -> secondary
      Color color1;
      Color color2;

      if (primary != null && secondary != null) {
        color1 = primary;
        color2 = secondary;
      } else if (primary != null) {
        color1 = primary;
        // Generate second color by darkening/lightening
        color2 =
            Color.lerp(primary, isDark ? Colors.black : Colors.white, 0.4)!;
      } else if (secondary != null) {
        color1 = secondary;
        color2 =
            Color.lerp(secondary, isDark ? Colors.black : Colors.white, 0.4)!;
      } else {
        setState(() => _coverLoadFailed = true);
        return;
      }

      // Adjust colors based on theme
      color1 = _adjustColorForTheme(color1, isDark);
      color2 = _adjustColorForTheme(color2, isDark);

      // Generate middle color by interpolation for smoother gradient
      final middleColor = Color.lerp(color1, color2, 0.5)!;

      // Final gradient: [color1, middle, color2] for smooth 3-stop gradient
      final adjustedColors = [color1, middleColor, color2];

      // Cache the adjusted colors with theme-specific key
      _colorCache[cacheKey] = List.from(adjustedColors);

      // Generate dynamic ColorScheme using the SAME primary color as gradient
      // Use color1 (already adjusted for theme) to ensure consistency
      // between background gradient and component colors
      final seedColor = color1;

      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
      );

      // Cache the ColorScheme
      _schemeCache[cacheKey] = dynamicScheme;

      if (mounted) {
        setState(() {
          _gradientColors = adjustedColors;
          _dynamicColorScheme = dynamicScheme;
        });
      }
      _colorsExtracted = true;
    } catch (e) {
      _logger.warning('Failed to extract colors: $e');
      if (mounted) setState(() => _coverLoadFailed = true);
    }
  }

  Future<void> _loadBookInfo({bool forceRefresh = false}) async {
    final settings = ref.read(settingsProvider);

    // Try to use cache if enabled and not forcing refresh
    if (!forceRefresh && settings.bookDetailCacheEnabled) {
      final cached = _cacheService.get(widget.bookId);
      if (cached != null) {
        // Use cached data and only refresh reading progress
        _bookInfo = cached;
        await _refreshReadingProgress();
        if (mounted && _loading) {
          setState(() => _loading = false);
        }
        // Extract colors if needed
        if (mounted && !_colorsExtracted && _gradientColors == null) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          _extractColors(cached.cover, isDark);
        }

        // Fetch fresh data from server in background to sync reading progress
        // This ensures multi-device sync works even when using cache
        _fetchServerDataInBackground();
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await _bookService.getBookInfo(widget.bookId);

      // Try to get position from both sources
      ReadPosition? position;

      // 1. Try server position from BookInfo response (embedded in GetBookInfo)
      if (info.serverReadPosition != null &&
          info.serverReadPosition!.chapterId != null) {
        final serverChapterId = info.serverReadPosition!.chapterId!;
        final positionStr = info.serverReadPosition!.position ?? '';

        // Find sortNum from chapter list (chapters are sorted by sortNum)
        int? sortNum;
        double scrollPosition = 0.0;

        for (int i = 0; i < info.chapters.length; i++) {
          if (info.chapters[i].id == serverChapterId) {
            sortNum = i + 1; // sortNum is 1-indexed
            break;
          }
        }

        // Parse scroll percentage from our custom format
        if (positionStr.startsWith('scroll:')) {
          scrollPosition = double.tryParse(positionStr.substring(7)) ?? 0.0;
        }

        if (sortNum != null) {
          position = ReadPosition(
            bookId: widget.bookId,
            chapterId: serverChapterId,
            sortNum: sortNum,
            scrollPosition: scrollPosition,
          );
          _logger.info(
            'Using server position: chapter $sortNum @ ${(scrollPosition * 100).toStringAsFixed(1)}%',
          );
        }
      }

      // 2. Fallback to local position
      if (position == null) {
        position = await _progressService.getLocalScrollPosition(widget.bookId);
        if (position != null) {
          _logger.info('Using local position: chapter ${position.sortNum}');
        }
      }

      // Ensure shelf is loaded for correct status
      await _userService.ensureInitialized();

      if (mounted) {
        // Check theme for color adjustment
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // Load local book mark status
        final mark = await _bookMarkService.getBookMark(widget.bookId);
        setState(() {
          _bookInfo = info;
          _readPosition = position;
          _isInShelf = _userService.isInShelf(widget.bookId);
          _currentMark = mark;
          _loading = false;
        });
        // Only extract colors if not already done from initial cover
        if (!_colorsExtracted && _gradientColors == null) {
          _extractColors(info.cover, isDark);
        }
        // Cache the book info if caching is enabled
        if (settings.bookDetailCacheEnabled) {
          _cacheService.set(widget.bookId, info);
        }
      }
    } catch (e) {
      _logger.severe('Failed to load book info: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Refresh only reading progress and related state (no network request for book info)
  Future<void> _refreshReadingProgress() async {
    try {
      // Get local reading position
      final position = await _progressService.getLocalScrollPosition(
        widget.bookId,
      );
      // Get local book mark status
      final mark = await _bookMarkService.getBookMark(widget.bookId);
      // Check shelf status
      await _userService.ensureInitialized();

      if (mounted) {
        setState(() {
          _readPosition = position;
          _isInShelf = _userService.isInShelf(widget.bookId);
          _currentMark = mark;
        });
      }
    } catch (e) {
      _logger.warning('Failed to refresh reading progress: $e');
    }
  }

  /// Fetch fresh data from server in background and selectively update changes
  /// Compares all book detail elements and only updates what has changed
  Future<void> _fetchServerDataInBackground() async {
    try {
      final info = await _bookService.getBookInfo(widget.bookId);

      if (!mounted || _bookInfo == null) return;

      final cached = _bookInfo!;
      bool needsUpdate = false;

      // Compare book info fields
      final bool infoChanged =
          cached.title != info.title ||
          cached.author != info.author ||
          cached.introduction != info.introduction ||
          cached.cover != info.cover ||
          cached.favorite != info.favorite ||
          cached.views != info.views ||
          cached.lastUpdatedAt != info.lastUpdatedAt ||
          cached.lastUpdatedChapter != info.lastUpdatedChapter ||
          cached.chapters.length != info.chapters.length;

      if (infoChanged) {
        _logger.info('Background sync: book info changed, updating UI');
        needsUpdate = true;
      }

      // Extract server reading position
      ReadPosition? serverPosition;
      if (info.serverReadPosition != null &&
          info.serverReadPosition!.chapterId != null) {
        final serverChapterId = info.serverReadPosition!.chapterId!;
        final positionStr = info.serverReadPosition!.position ?? '';

        int? sortNum;
        double scrollPosition = 0.0;

        for (int i = 0; i < info.chapters.length; i++) {
          if (info.chapters[i].id == serverChapterId) {
            sortNum = i + 1;
            break;
          }
        }

        if (positionStr.startsWith('scroll:')) {
          scrollPosition = double.tryParse(positionStr.substring(7)) ?? 0.0;
        }

        if (sortNum != null) {
          serverPosition = ReadPosition(
            bookId: widget.bookId,
            chapterId: serverChapterId,
            sortNum: sortNum,
            scrollPosition: scrollPosition,
          );
        }
      }

      // Compare reading position (only chapter number)
      bool positionChanged = false;
      if (serverPosition != null) {
        final currentPos = _readPosition;
        positionChanged =
            currentPos == null || serverPosition.sortNum > currentPos.sortNum;

        if (positionChanged) {
          _logger.info(
            'Background sync: reading position updated to ch${serverPosition.sortNum}',
          );
          // Save to local storage
          await _progressService.saveLocalScrollPosition(
            bookId: widget.bookId,
            chapterId: serverPosition.chapterId,
            sortNum: serverPosition.sortNum,
            scrollPosition: serverPosition.scrollPosition,
          );
        }
      }

      // Apply updates if anything changed
      if (mounted && (needsUpdate || positionChanged)) {
        setState(() {
          if (needsUpdate) {
            _bookInfo = info;
          }
          if (positionChanged && serverPosition != null) {
            _readPosition = serverPosition;
          }
        });
      }

      // Update cache with fresh data
      final settings = ref.read(settingsProvider);
      if (settings.bookDetailCacheEnabled) {
        _cacheService.set(widget.bookId, info);
      }
    } catch (e) {
      _logger.warning('Background sync failed: $e');
      // Silently ignore errors - we already have cached data
    }
  }

  void _startReading({int sortNum = 1}) {
    // Get cover URL for dynamic color in reader
    final coverUrl =
        widget.initialCoverUrl?.isNotEmpty == true
            ? widget.initialCoverUrl!
            : (_bookInfo?.cover ?? '');

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (_) => ReaderPage(
                  bid: widget.bookId,
                  sortNum: sortNum,
                  totalChapters: _bookInfo!.chapters.length,
                  coverUrl: coverUrl,
                ),
          ),
        )
        .then((_) {
          // Only refresh reading position when returning from reader (not full reload)
          if (mounted) {
            _refreshReadingProgress();
          }
        });
  }

  void _continueReading() {
    final sortNum = _readPosition?.sortNum ?? 1;
    _startReading(sortNum: sortNum);
  }

  Future<void> _toggleShelf() async {
    setState(() => _shelfLoading = true);

    try {
      bool success;
      if (_isInShelf) {
        success = await _userService.removeFromShelf(widget.bookId);
      } else {
        success = await _userService.addToShelf(widget.bookId);
      }

      if (mounted && success) {
        setState(() {
          _isInShelf = !_isInShelf;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isInShelf ? '已加入书架' : '已移出书架'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _logger.severe('Failed to toggle shelf: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _shelfLoading = false);
      }
    }
  }

  /// Get the icon for a mark status
  IconData _getMarkIcon(BookMarkStatus status) {
    switch (status) {
      case BookMarkStatus.none:
        return Icons.bookmark_border;
      case BookMarkStatus.toRead:
        return Icons.schedule;
      case BookMarkStatus.reading:
        return Icons.auto_stories;
      case BookMarkStatus.finished:
        return Icons.check_circle_outline;
    }
  }

  /// Show bottom sheet to mark book status
  void _showMarkBookSheet() {
    // Check if book is in shelf first
    if (!_isInShelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先将书籍加入书架'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '标记此书籍',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '选择当前状态',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Options
                  _buildMarkOption(
                    context,
                    BookMarkStatus.toRead,
                    Icons.schedule,
                    '待读',
                    colorScheme,
                  ),
                  _buildMarkOption(
                    context,
                    BookMarkStatus.reading,
                    Icons.auto_stories,
                    '在读',
                    colorScheme,
                  ),
                  _buildMarkOption(
                    context,
                    BookMarkStatus.finished,
                    Icons.check_circle_outline,
                    '已读',
                    colorScheme,
                  ),
                  // Clear mark option if already marked
                  if (_currentMark != BookMarkStatus.none)
                    _buildMarkOption(
                      context,
                      BookMarkStatus.none,
                      Icons.clear,
                      '清除标记',
                      colorScheme,
                    ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildMarkOption(
    BuildContext context,
    BookMarkStatus status,
    IconData icon,
    String label,
    ColorScheme colorScheme,
  ) {
    final isSelected = _currentMark == status;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(
        icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? colorScheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      trailing:
          isSelected ? Icon(Icons.check, color: colorScheme.primary) : null,
      onTap: () async {
        Navigator.pop(context);
        await _bookMarkService.setBookMark(widget.bookId, status);
        if (mounted) {
          setState(() {
            _currentMark = status;
          });
          if (status != BookMarkStatus.none) {
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text('已标记为${status.displayName}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check OLED black mode setting
    final settings = ref.watch(settingsProvider);
    final isOled = settings.oledBlack;

    // Use dynamic ColorScheme if available AND not in OLED mode
    // OLED mode uses system default colors for pure black experience
    final baseColorScheme = Theme.of(context).colorScheme;
    final colorScheme =
        (isOled || _dynamicColorScheme == null)
            ? baseColorScheme
            : _dynamicColorScheme!;

    // Show preview with initial data while loading
    if (_loading &&
        (widget.initialCoverUrl != null || widget.initialTitle != null)) {
      return _buildThemedScaffold(
        context,
        colorScheme,
        _buildLoadingPreview(colorScheme),
        isOled: isOled,
      );
    }

    return _buildThemedScaffold(
      context,
      colorScheme,
      _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorView()
          : _buildContent(colorScheme),
      isOled: isOled,
    );
  }

  /// Wrap content with animated Theme override when dynamic ColorScheme is available
  /// Uses AnimatedTheme for smooth color transitions (only when extracting colors)
  /// Skips animation if colors were restored from cache to prevent flash
  /// Skips dynamic ColorScheme entirely when OLED mode is enabled
  Widget _buildThemedScaffold(
    BuildContext context,
    ColorScheme colorScheme,
    Widget body, {
    bool isOled = false,
  }) {
    // Skip animation if colors were already extracted (from cache)
    // This prevents the flash when navigating to a cached book
    final shouldAnimate = !_colorsExtracted || _dynamicColorScheme == null;

    // In OLED mode, always use system theme (no dynamic colors)
    final effectiveColorScheme =
        isOled
            ? Theme.of(context).colorScheme
            : (_dynamicColorScheme ?? Theme.of(context).colorScheme);

    return AnimatedTheme(
      // Use longer duration (600ms) for smoother, more elegant fade-in
      duration:
          shouldAnimate ? const Duration(milliseconds: 600) : Duration.zero,
      curve: Curves.easeInOutCubic,
      data: Theme.of(context).copyWith(colorScheme: effectiveColorScheme),
      child: Scaffold(body: body),
    );
  }

  Widget _buildLoadingPreview(ColorScheme colorScheme) {
    final settings = ref.watch(settingsProvider);
    final isOled = settings.oledBlack;
    final coverUrl = widget.initialCoverUrl ?? '';
    final title = widget.initialTitle ?? '';

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Gradient background from extracted colors or loading placeholder
                if (!isOled && _gradientColors != null)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _gradientColors!,
                      ),
                    ),
                  )
                else
                  Container(
                    color:
                        colorScheme.brightness == Brightness.dark
                            ? (isOled ? Colors.black : const Color(0xFF1E1E1E))
                            : const Color(0xFFF0F0F0),
                  ),
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(40),
                        Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withAlpha(120),
                        Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withAlpha(200),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                      stops: const [0.0, 0.3, 0.5, 0.7, 0.9, 1.0],
                    ),
                  ),
                ),
                // Cover and title preview
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Cover
                      Hero(
                        tag: widget.heroTag ?? 'cover_${widget.bookId}',
                        child: Container(
                          width: 100,
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(60),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child:
                                coverUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      fit: BoxFit.cover,
                                      placeholder:
                                          (_, __) => Container(
                                            color:
                                                colorScheme
                                                    .surfaceContainerHighest,
                                          ),
                                      errorWidget:
                                          (_, __, ___) => Container(
                                            color: const Color(0xFF3A3A3A),
                                            child: const Center(
                                              child: Icon(
                                                Icons.menu_book_rounded,
                                                size: 40,
                                                color: Color(0xFF888888),
                                              ),
                                            ),
                                          ),
                                    )
                                    : Container(
                                      color:
                                          colorScheme.surfaceContainerHighest,
                                      child: const Center(
                                        child: Icon(
                                          Icons.menu_book_rounded,
                                          size: 40,
                                          color: Color(0xFF888888),
                                        ),
                                      ),
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (title.isNotEmpty)
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 8),
                            // Shimmer skeleton for loading author
                            ShimmerBox(width: 80, height: 16, borderRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Shimmer skeleton for content - simplified layout
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Meta chips skeleton: height=26, borderRadius=8
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShimmerBox(width: 55, height: 26, borderRadius: 8),
                  ShimmerBox(width: 70, height: 26, borderRadius: 8),
                  ShimmerBox(width: 55, height: 26, borderRadius: 8),
                ],
              ),
              const SizedBox(height: 20),
              // Action buttons: bookmark 56x56, read button height=56
              Row(
                children: [
                  ShimmerBox(width: 56, height: 56, borderRadius: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShimmerBox(
                      width: double.infinity,
                      height: 56,
                      borderRadius: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Introduction: single block for entire section
              ShimmerBox(width: double.infinity, height: 80, borderRadius: 16),
              const SizedBox(height: 24),
              // Unified block for Update Info + Chapter Header + Chapter List
              // Matches the visual weight of the lower section
              ShimmerBox(width: double.infinity, height: 300, borderRadius: 16),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('加载失败', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadBookInfo,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    final settings = ref.watch(settingsProvider);
    final isOled = settings.oledBlack;
    final book = _bookInfo!;
    // Use initial cover URL if same domain to leverage cache
    final coverUrl =
        widget.initialCoverUrl?.isNotEmpty == true
            ? widget.initialCoverUrl!
            : book.cover;

    return CustomScrollView(
      slivers: [
        // Modern header with blurred background and floating cover
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          stretch: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Gradient background from extracted colors or fallback
                if (!isOled && _gradientColors != null && !_coverLoadFailed)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors:
                            _gradientColors!.length >= 3
                                ? [
                                  _gradientColors![0],
                                  Color.lerp(
                                    _gradientColors![0],
                                    _gradientColors![1],
                                    0.5,
                                  )!,
                                  _gradientColors![1],
                                  Color.lerp(
                                    _gradientColors![1],
                                    _gradientColors![2],
                                    0.5,
                                  )!,
                                  _gradientColors![2],
                                ]
                                : [
                                  _gradientColors!.first,
                                  Color.lerp(
                                    _gradientColors!.first,
                                    _gradientColors!.last,
                                    0.3,
                                  )!,
                                  Color.lerp(
                                    _gradientColors!.first,
                                    _gradientColors!.last,
                                    0.7,
                                  )!,
                                  _gradientColors!.last,
                                ],
                        stops:
                            _gradientColors!.length >= 3
                                ? const [0.0, 0.25, 0.5, 0.75, 1.0]
                                : const [0.0, 0.35, 0.65, 1.0],
                      ),
                    ),
                  )
                else if (!isOled && (_coverLoadFailed || book.cover.isEmpty))
                  // Fallback: solid gray based on theme
                  Container(
                    color:
                        colorScheme.brightness == Brightness.dark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFE8E8E8),
                  )
                else
                  // Loading state: neutral placeholder (no cover image flash)
                  Container(
                    color:
                        colorScheme.brightness == Brightness.dark
                            ? (isOled ? Colors.black : const Color(0xFF1E1E1E))
                            : const Color(0xFFF0F0F0),
                  ),
                // Gradient overlay for smooth transition to content
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(40),
                        Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withAlpha(120),
                        Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withAlpha(200),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                      stops: const [0.0, 0.3, 0.5, 0.7, 0.9, 1.0],
                    ),
                  ),
                ),

                // Removed fade overlay to ensure sharp contrast for rounded content card
                // Cover and title overlay
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Floating cover card
                      Hero(
                        tag: widget.heroTag ?? 'cover_${book.id}',
                        child: Container(
                          width: 100,
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(60),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child:
                                _coverLoadFailed || coverUrl.isEmpty
                                    ? Container(
                                      color: const Color(0xFF3A3A3A),
                                      child: const Center(
                                        child: Icon(
                                          Icons.menu_book_rounded,
                                          size: 40,
                                          color: Color(0xFF888888),
                                        ),
                                      ),
                                    )
                                    : CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      fit: BoxFit.cover,
                                      placeholder:
                                          (_, __) => Container(
                                            color:
                                                colorScheme
                                                    .surfaceContainerHighest,
                                          ),
                                      errorWidget:
                                          (_, __, ___) => Container(
                                            color: const Color(0xFF3A3A3A),
                                            child: const Center(
                                              child: Icon(
                                                Icons.menu_book_rounded,
                                                size: 40,
                                                color: Color(0xFF888888),
                                              ),
                                            ),
                                          ),
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Title and author
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              book.title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              book.author,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Content
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats row - minimalist chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildMetaChip(
                      Icons.favorite_outline,
                      '${book.favorite}',
                      colorScheme,
                    ),
                    _buildMetaChip(
                      Icons.visibility_outlined,
                      '${book.views}',
                      colorScheme,
                    ),
                    _buildMetaChip(
                      Icons.library_books_outlined,
                      '${book.chapters.length} 章',
                      colorScheme,
                    ),
                    // Show mark status chip if marked
                    if (_currentMark != BookMarkStatus.none)
                      _buildMetaChip(
                        _getMarkIcon(_currentMark),
                        _currentMark.displayName,
                        colorScheme,
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // Action buttons - full width, modern style
                Row(
                  children: [
                    // Bookmark toggle
                    _shelfLoading
                        ? Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                        : Material(
                          color:
                              _isInShelf
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: _toggleShelf,
                            onLongPress: _showMarkBookSheet,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              child: Icon(
                                _isInShelf
                                    ? Icons.bookmark
                                    : Icons.bookmark_outline,
                                color:
                                    _isInShelf
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    const SizedBox(width: 12),
                    // Read button
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _continueReading,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow_rounded, size: 22),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _readPosition != null
                                      ? (() {
                                        // Find chapter title by chapterId
                                        final chapter = book.chapters
                                            .cast<ChapterInfo?>()
                                            .firstWhere(
                                              (c) =>
                                                  c?.id ==
                                                  _readPosition!.chapterId,
                                              orElse: () => null,
                                            );
                                        if (chapter != null &&
                                            chapter.title.isNotEmpty) {
                                          String title = chapter.title;

                                          // Apply cleaning if enabled in settings
                                          final settings = ref.read(
                                            settingsProvider,
                                          );
                                          if (settings.cleanChapterTitle) {
                                            // Smart hybrid regex:
                                            // Handles 【第一话】... or non-English leading identifier
                                            // Also handles 『「〈 as delimiters
                                            // Leaves pure English titles unchanged
                                            final regex = RegExp(
                                              r'^\s*(?:【([^】]*)】.*|(?![a-zA-Z]+\s)([^\s『「〈]+)[\s『「〈].*)$',
                                            );
                                            final match = regex.firstMatch(
                                              title,
                                            );
                                            if (match != null) {
                                              // Combine group 1 and group 2 (one will be non-null)
                                              final extracted =
                                                  (match.group(1) ?? '') +
                                                  (match.group(2) ?? '');
                                              if (extracted.isNotEmpty) {
                                                title = extracted;
                                              }
                                            }
                                          }

                                          // Truncate long titles
                                          if (title.length > 15) {
                                            title =
                                                '${title.substring(0, 15)}...';
                                          }
                                          return '续读 · $title';
                                        }
                                        return '续读';
                                      })()
                                      : '开始阅读',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Introduction - expandable
                if (book.introduction.isNotEmpty) ...[
                  _buildSectionTitle('简介'),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _showFullIntro(context, book.introduction),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _stripHtml(book.introduction),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.6,
                          fontSize: 14,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Update info - subtle
                ...[
                  Builder(
                    builder: (context) {
                      final relativeTime = _formatRelativeTime(
                        book.lastUpdatedAt,
                      );
                      // Use last chapter from chapters list for accuracy
                      final lastChapterTitle =
                          book.chapters.isNotEmpty
                              ? book.chapters.last.title
                              : null;
                      final hasChapter =
                          lastChapterTitle != null &&
                          lastChapterTitle.isNotEmpty;
                      final displayText =
                          hasChapter
                              ? '最新: $relativeTime - $lastChapterTitle'
                              : '最新: $relativeTime';

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withAlpha(
                            128,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.update_outlined,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                displayText,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                // Chapter list header
                _buildSectionTitle('章节'),
              ],
            ),
          ),
        ),

        // Chapter list - clean and minimal
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final chapter = book.chapters[index];
              final sortNum = index + 1;
              final isCurrentChapter = _readPosition?.sortNum == sortNum;

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                leading: Container(
                  width: 32,
                  alignment: Alignment.center,
                  child: Text(
                    '$sortNum',
                    style: TextStyle(
                      color:
                          isCurrentChapter
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                      fontWeight:
                          isCurrentChapter ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                title: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrentChapter ? colorScheme.primary : null,
                    fontWeight: isCurrentChapter ? FontWeight.w600 : null,
                    fontSize: 14,
                  ),
                ),
                trailing:
                    isCurrentChapter
                        ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '当前',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                        : null,
                onTap: () => _startReading(sortNum: sortNum),
              );
            }, childCount: book.chapters.length),
          ),
        ),

        // Bottom safe area
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: 40 + MediaQuery.of(context).padding.bottom,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String value, ColorScheme colorScheme) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showFullIntro(BuildContext context, String intro) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder:
                (context, scrollController) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '简介',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        children: [
                          Text(
                            _stripHtml(intro),
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.8,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  /// Simple HTML tag stripper
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
  }
}
