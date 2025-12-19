import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/utils/font_manager.dart';
import 'package:novella/data/services/chapter_service.dart';
import 'package:novella/data/services/reading_progress_service.dart';
import 'package:novella/features/settings/settings_page.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final int bid;
  final int sortNum;
  final int totalChapters;

  const ReaderPage({
    super.key,
    required this.bid,
    required this.sortNum,
    required this.totalChapters,
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
  final ScrollController _scrollController = ScrollController();

  ChapterContent? _chapter;
  String? _fontFamily;
  bool _loading = true;
  String? _error;
  bool _initialScrollDone = false;
  bool _barsVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadChapter(widget.bid, widget.sortNum);
  }

  @override
  void dispose() {
    _saveCurrentPosition(); // Save position when leaving
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save position when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveCurrentPosition();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Auto show bars at top or bottom boundaries
    if ((offset <= 0 || offset >= maxScroll) && !_barsVisible) {
      setState(() {
        _barsVisible = true;
      });
    }
  }

  void _toggleBars() {
    setState(() {
      _barsVisible = !_barsVisible;
    });
  }

  /// Save current scroll position
  Future<void> _saveCurrentPosition() async {
    if (_chapter == null || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final scrollPercent = maxScroll > 0 ? currentScroll / maxScroll : 0.0;

    await _progressService.saveLocalScrollPosition(
      bookId: widget.bid,
      chapterId: _chapter!.id,
      sortNum: _chapter!.sortNum,
      scrollPosition: scrollPercent,
    );

    _logger.info(
      'Saved position: ${(scrollPercent * 100).toStringAsFixed(1)}%',
    );
  }

  /// Restore scroll position after content loads
  Future<void> _restoreScrollPosition() async {
    if (_initialScrollDone) return;
    _initialScrollDone = true;

    final position = await _progressService.getLocalScrollPosition(widget.bid);

    if (position != null &&
        position.sortNum == _chapter?.sortNum &&
        _scrollController.hasClients) {
      // Wait for layout to complete
      await Future.delayed(const Duration(milliseconds: 100));

      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final targetScroll = position.scrollPosition * maxScroll;

        _scrollController.jumpTo(targetScroll);

        _logger.info(
          'Restored position: ${(position.scrollPosition * 100).toStringAsFixed(1)}%',
        );
      }
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

    return Scaffold(
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
