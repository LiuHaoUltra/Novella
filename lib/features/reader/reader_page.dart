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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChapter(widget.bid, widget.sortNum);
  }

  @override
  void dispose() {
    _saveCurrentPosition(); // Save position when leaving
    WidgetsBinding.instance.removeObserver(this);
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

        _scrollController.animateTo(
          targetScroll,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );

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
      // 1. Fetch Content
      final chapter = await _chapterService.getNovelContent(bid, sortNum);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_chapter?.title ?? '加载中'),
        actions: [
          // Chapter progress indicator
          if (_chapter != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  '第 ${_chapter!.sortNum} 章',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text('内容加载失败', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _loadChapter(widget.bid, widget.sortNum),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              )
              : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        16.0,
                        16.0,
                        16.0,
                        // Add extra padding at bottom equal to nav bar height + safe area
                        // to ensure last line is visible
                        80.0 + MediaQuery.of(context).padding.bottom,
                      ),
                      child: HtmlWidget(
                        _chapter!.content,
                        textStyle: TextStyle(
                          fontFamily: _fontFamily,
                          fontSize: 18,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                  // Navigation bar
                  Container(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 4,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Previous Chapter Button
                            if (_chapter != null && _chapter!.sortNum > 1)
                              TextButton.icon(
                                onPressed: _onPrev,
                                icon: const Icon(Icons.chevron_left),
                                label: const Text('上一章'),
                              )
                            else
                              const SizedBox(
                                width: 80,
                              ), // Placeholder for alignment

                            Text(
                              '${_chapter!.sortNum}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),

                            // Next Chapter Button
                            if (_chapter != null &&
                                _chapter!.sortNum < widget.totalChapters)
                              TextButton.icon(
                                onPressed: _onNext,
                                icon: const Icon(Icons.chevron_right),
                                label: const Text('下一章'),
                              )
                            else
                              const SizedBox(
                                width: 80,
                              ), // Placeholder for alignment
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}
