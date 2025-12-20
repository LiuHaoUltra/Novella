import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/utils/font_manager.dart';
import 'package:novella/data/services/chapter_service.dart';
import 'package:novella/data/services/reading_progress_service.dart';
import 'package:novella/data/services/reading_time_service.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:palette_generator/palette_generator.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final int bid;
  final int sortNum;
  final int totalChapters;
  final String? coverUrl; // Optional cover URL for dynamic color

  const ReaderPage({
    super.key,
    required this.bid,
    required this.sortNum,
    required this.totalChapters,
    this.coverUrl,
  });

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  final _logger = Logger('ReaderPage');
  final _chapterService = ChapterService();
  final _fontManager = FontManager();
  final _progressService = ReadingProgressService();
  final _readingTimeService = ReadingTimeService();
  final ScrollController _scrollController = ScrollController();

  ChapterContent? _chapter;
  String? _fontFamily;
  bool _loading = true;
  String? _error;
  bool _initialScrollDone = false;
  bool _barsVisible = true;

  // Dynamic ColorScheme based on cover image
  ColorScheme? _dynamicColorScheme;

  // Debounce timer for scroll position saving
  Timer? _savePositionTimer;
  // Cache last position for synchronous save on dispose
  double _lastScrollPercent = 0.0;

  // Static cache for ColorScheme (shared across all reader instances)
  static final Map<String, ColorScheme> _schemeCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadChapter(widget.bid, widget.sortNum);
    // Start reading time tracking
    _readingTimeService.startSession();
    // Extract colors from cover for dynamic theme
    _extractColors();
  }

  /// Extract colors from cover image and generate dynamic ColorScheme
  Future<void> _extractColors() async {
    if (widget.coverUrl == null || widget.coverUrl!.isEmpty) return;

    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final isDark = brightness == Brightness.dark;
    final cacheKey = '${widget.bid}_${isDark ? 'dark' : 'light'}';

    // Check cache first
    if (_schemeCache.containsKey(cacheKey)) {
      if (mounted) {
        setState(() {
          _dynamicColorScheme = _schemeCache[cacheKey]!;
        });
      }
      return;
    }

    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(widget.coverUrl!),
        size: const Size(24, 24),
        maximumColorCount: 3,
      );

      // Use DOMINANT color first (by area coverage) for better cover representation
      final seedColor =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color ??
          paletteGenerator.mutedColor?.color;

      if (seedColor != null && mounted) {
        final scheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: isDark ? Brightness.dark : Brightness.light,
        );
        // Cache the result
        _schemeCache[cacheKey] = scheme;
        setState(() {
          _dynamicColorScheme = scheme;
        });
      }
    } catch (e) {
      _logger.warning('Failed to extract colors for reader: $e');
    }
  }

  @override
  void dispose() {
    _savePositionTimer?.cancel();
    // End reading time tracking
    _readingTimeService.endSession();
    // Save cached position synchronously before dispose
    if (_chapter != null && _lastScrollPercent > 0) {
      print('[POSITION] DISPOSE: Saving cached position $_lastScrollPercent');
      _progressService.saveLocalScrollPosition(
        bookId: widget.bid,
        chapterId: _chapter!.id,
        sortNum: _chapter!.sortNum,
        scrollPosition: _lastScrollPercent,
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save position and reading time when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveCurrentPosition();
      _readingTimeService.endSession();
    }
    // Restart reading time tracking when returning to foreground
    if (state == AppLifecycleState.resumed) {
      _readingTimeService.startSession();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Cache current scroll position for dispose
    if (maxScroll > 0) {
      _lastScrollPercent = offset / maxScroll;
    }

    // Auto show bars at top or bottom boundaries
    if ((offset <= 0 || offset >= maxScroll) && !_barsVisible) {
      setState(() {
        _barsVisible = true;
      });
    }

    // Debounced position save (every 2 seconds of idle)
    _savePositionTimer?.cancel();
    _savePositionTimer = Timer(const Duration(seconds: 2), () {
      _saveCurrentPosition();
    });
  }

  void _toggleBars() {
    setState(() {
      _barsVisible = !_barsVisible;
    });
  }

  /// Save current scroll position (local + server sync)
  Future<void> _saveCurrentPosition() async {
    if (_chapter == null || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final scrollPercent = maxScroll > 0 ? currentScroll / maxScroll : 0.0;

    // Save locally for fast restore
    await _progressService.saveLocalScrollPosition(
      bookId: widget.bid,
      chapterId: _chapter!.id,
      sortNum: _chapter!.sortNum,
      scrollPosition: scrollPercent,
    );

    // Sync to server - use scroll percentage encoded in XPath format
    // This allows backend to record which chapter user was reading
    // Format: "scroll:{percentage}" so we can parse it back later
    await _progressService.saveReadPosition(
      bookId: widget.bid,
      chapterId: _chapter!.id,
      xPath: 'scroll:${scrollPercent.toStringAsFixed(4)}',
    );

    _logger.info(
      'Saved position: ch${_chapter!.sortNum} @ ${(scrollPercent * 100).toStringAsFixed(1)}%',
    );
  }

  /// Restore scroll position after content loads
  Future<void> _restoreScrollPosition() async {
    if (_initialScrollDone) return;
    _initialScrollDone = true;

    final position = await _progressService.getLocalScrollPosition(widget.bid);

    _logger.info(
      'Restoring position check: saved=${position?.sortNum}, current=${_chapter?.sortNum}, '
      'scrollPos=${position?.scrollPosition.toStringAsFixed(3)}, hasClients=${_scrollController.hasClients}',
    );

    if (position != null &&
        position.sortNum == _chapter?.sortNum &&
        _scrollController.hasClients) {
      // Wait for layout to complete
      await Future.delayed(const Duration(milliseconds: 100));

      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final targetScroll = position.scrollPosition * maxScroll;

        _logger.info(
          'Jumping to: target=$targetScroll, max=$maxScroll, percent=${(position.scrollPosition * 100).toStringAsFixed(1)}%',
        );

        _scrollController.jumpTo(targetScroll);
      }
    } else if (position != null) {
      _logger.info(
        'Position NOT restored: sortNum mismatch or no scroll clients. '
        'Saved chapter=${position.sortNum}, Current chapter=${_chapter?.sortNum}',
      );
    }
  }

  Future<void> _loadChapter(int bid, int sortNum) async {
    _logger.info('Requesting chapter with SortNum: $sortNum...');

    // Save current position before loading new chapter
    if (_chapter != null) {
      await _saveCurrentPosition();
    }

    setState(() {
      _loading = true;
      _error = null;
      _initialScrollDone = false;
    });

    try {
      final settings = ref.read(settingsProvider);

      // 1. Fetch Content
      final chapter = await _chapterService.getNovelContent(
        bid,
        sortNum,
        convert: settings.convertType == 'none' ? null : settings.convertType,
      );
      _logger.info('Chapter loaded: ${chapter.title}');

      // 2. Load obfuscation font with cache settings
      String? family;
      if (chapter.fontUrl != null) {
        final settings = ref.read(settingsProvider);
        family = await _fontManager.loadFont(
          chapter.fontUrl,
          cacheEnabled: settings.fontCacheEnabled,
          cacheLimit: settings.fontCacheLimit,
        );
        _logger.info(
          'Font loaded: $family (cache: ${settings.fontCacheEnabled}, limit: ${settings.fontCacheLimit})',
        );
      }

      if (mounted) {
        setState(() {
          _chapter = chapter;
          _fontFamily = family;
          _loading = false;
        });

        // Restore scroll position after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _restoreScrollPosition();

          // Match Web behavior: save position shortly after chapter loads
          // Web uses IntersectionObserver with 300ms debounce
          // We use 500ms to ensure scroll restore completes first
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _chapter != null) {
              _saveCurrentPosition();
            }
          });
        });
      }
    } catch (e) {
      _logger.severe('Error loading chapter: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _onPrev() {
    if (_chapter != null && _chapter!.sortNum > 1) {
      _loadChapter(widget.bid, _chapter!.sortNum - 1);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已是第一章')));
    }
  }

  void _onNext() {
    if (_chapter != null && _chapter!.sortNum < widget.totalChapters) {
      _loadChapter(widget.bid, _chapter!.sortNum + 1);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已是最后一章')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    Widget content = Scaffold(
      body: Stack(
        children: [
          // 1. Main Content Layer
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleBars,
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? _buildErrorView()
                      : _buildWebContent(context, settings),
            ),
          ),

          // 2. Top Bar (AppBar replacement)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            top:
                _barsVisible
                    ? 0
                    : -kToolbarHeight - MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: _buildTopBar(context),
          ),

          // 3. Bottom Bar (Navigation)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            bottom:
                _barsVisible ? 0 : -100 - MediaQuery.of(context).padding.bottom,
            left: 0,
            right: 0,
            child: _buildBottomBar(context, settings),
          ),

          // 4. Gradient Blur Overlay
          _buildBlurOverlay(context),
        ],
      ),
    );

    // Use AnimatedTheme for smooth color transitions
    return AnimatedTheme(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      data: Theme.of(context).copyWith(
        colorScheme: _dynamicColorScheme ?? Theme.of(context).colorScheme,
      ),
      child: content,
    );
  }

  Widget _buildWebContent(BuildContext context, AppSettings settings) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        16.0,
        MediaQuery.of(context).padding.top +
            20, // Initial padding for status bar + breathing room
        16.0,
        // Add extra padding at bottom for navigation bar
        80.0 + MediaQuery.of(context).padding.bottom,
      ),
      child: HtmlWidget(
        _chapter!.content,
        textStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: settings.fontSize,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: kToolbarHeight + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withAlpha(240),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withAlpha(20),
            width: 0.5,
          ),
        ),
      ),
      child: NavigationToolbar(
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        middle: Text(
          _chapter?.title ?? '',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, AppSettings settings) {
    // Safety check for safe area to prevent glitches
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withAlpha(240),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Prev Button
          Expanded(
            child: TextButton.icon(
              onPressed:
                  (_chapter != null && _chapter!.sortNum > 1) ? _onPrev : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一章'),
            ),
          ),

          if (settings.showChapterNumber)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _chapter != null
                    ? '${_chapter!.sortNum} / ${widget.totalChapters}'
                    : '--',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          // Next Button
          Expanded(
            child: TextButton.icon(
              onPressed:
                  (_chapter != null && _chapter!.sortNum < widget.totalChapters)
                      ? _onNext
                      : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一章'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurOverlay(BuildContext context) {
    // Height: Status bar + a bit more (e.g., 20)
    // Masked with gradient to fade out
    final double height = MediaQuery.of(context).padding.top + 30;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        // Allow touches to pass through
        child: ShaderMask(
          shaderCallback: (rect) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [
                0.0,
                0.6,
                1.0,
              ], // Fade out starts at 60% of height (just below status bar)
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color:
                  Colors
                      .transparent, // Needed for BackdropFilter to catch something
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(_error ?? '未知错误', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadChapter(widget.bid, widget.sortNum),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
