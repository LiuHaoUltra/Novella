import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/reading_progress_service.dart';
import 'package:novella/data/services/user_service.dart';
import 'package:novella/features/reader/reader_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:palette_generator/palette_generator.dart';

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

  const BookDetailPage({
    super.key,
    required this.bookId,
    this.initialCoverUrl,
    this.initialTitle,
  });

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  final _logger = Logger('BookDetailPage');
  final _bookService = BookService();
  final _progressService = ReadingProgressService();
  final _userService = UserService();

  // Static cache for extracted colors (shared across all instances)
  // Key format: "bookId_dark" or "bookId_light"
  static final Map<String, List<Color>> _colorCache = {};

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

  @override
  void initState() {
    super.initState();
    _loadBookInfo();
    // Delay color extraction to avoid lag during page transition
    // Start after transition animation (~300ms) to ensure smooth navigation
    if (widget.initialCoverUrl != null && widget.initialCoverUrl!.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && !_colorsExtracted) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          _extractColors(widget.initialCoverUrl!, isDark);
        }
      });
    }
  }

  /// Adjust color based on theme brightness for premium feel
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

  /// Extract dominant colors from cover image for gradient background
  Future<void> _extractColors(String coverUrl, bool isDark) async {
    if (coverUrl.isEmpty) {
      setState(() => _coverLoadFailed = true);
      return;
    }

    // Check cache first - use theme-specific cache key
    final cacheKey = '${widget.bookId}_${isDark ? 'dark' : 'light'}';
    if (_colorCache.containsKey(cacheKey)) {
      // Use cached adjusted colors directly
      _gradientColors = _colorCache[cacheKey]!;
      _colorsExtracted = true;
      if (mounted) setState(() {});
      return;
    }

    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(coverUrl),
        size: const Size(24, 24), // Very small for fast extraction
        maximumColorCount: 3,
      );

      if (!mounted) return;

      // Get colors for Apple Music-style gradient
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

      // Ensure we have at least 2 colors for gradient
      if (rawColors.length < 2) {
        if (rawColors.isNotEmpty) {
          // Add a darkened/lightened version
          rawColors.add(
            Color.lerp(
              rawColors.first,
              isDark ? Colors.black : Colors.white,
              0.4,
            )!,
          );
        } else {
          setState(() => _coverLoadFailed = true);
          return;
        }
      }

      // Adjust colors based on theme
      final adjustedColors =
          rawColors.map((c) => _adjustColorForTheme(c, isDark)).toList();

      // Cache the adjusted colors with theme-specific key
      _colorCache[cacheKey] = List.from(adjustedColors);

      if (mounted) setState(() => _gradientColors = adjustedColors);
      _colorsExtracted = true;
    } catch (e) {
      _logger.warning('Failed to extract colors: $e');
      if (mounted) setState(() => _coverLoadFailed = true);
    }
  }

  Future<void> _loadBookInfo() async {
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
        setState(() {
          _bookInfo = info;
          _readPosition = position;
          _isInShelf = _userService.isInShelf(widget.bookId);
          _loading = false;
        });
        // Only extract colors if not already done from initial cover
        if (!_colorsExtracted && _gradientColors == null) {
          _extractColors(info.cover, isDark);
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

  void _startReading({int sortNum = 1}) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (_) => ReaderPage(
                  bid: widget.bookId,
                  sortNum: sortNum,
                  totalChapters: _bookInfo!.chapters.length,
                ),
          ),
        )
        .then((_) {
          // Refresh reading position when returning from reader
          if (mounted) {
            _loadBookInfo();
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Show preview with initial data while loading
    if (_loading &&
        (widget.initialCoverUrl != null || widget.initialTitle != null)) {
      return Scaffold(body: _buildLoadingPreview(colorScheme));
    }

    return Scaffold(
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildErrorView()
              : _buildContent(colorScheme),
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
                        tag: 'cover_${widget.bookId}',
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
                            // Loading indicator for details
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
        // Loading placeholder for content
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
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
                        tag: 'cover_${book.id}',
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
                if (book.lastUpdatedChapter != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(128),
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
                            '最新: ${book.lastUpdatedChapter}',
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
