import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/utils/font_manager.dart';
import 'package:novella/data/services/chapter_service.dart';
import 'package:novella/data/services/reading_progress_service.dart';
import 'package:novella/data/services/reading_time_service.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final int bid;
  final int sortNum;
  final int totalChapters;
  final String? coverUrl; // 封面 URL（用于动态取色）

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
  final _bookService = BookService();
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

  // 基于封面的动态配色
  ColorScheme? _dynamicColorScheme;

  // 滚动保存防抖计时器
  Timer? _savePositionTimer;
  // 缓存位置用于销毁时同步保存
  double _lastScrollPercent = 0.0;

  // ColorScheme 静态缓存
  static final Map<String, ColorScheme> _schemeCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadChapter(widget.bid, widget.sortNum);
    // 开始记录阅读时长
    _readingTimeService.startSession();
    // 提取封面颜色用于动态主题
    _extractColors();
  }

  /// 提取封面颜色生成动态配色
  Future<void> _extractColors() async {
    if (widget.coverUrl == null || widget.coverUrl!.isEmpty) return;

    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final isDark = brightness == Brightness.dark;
    final cacheKey = '${widget.bid}_${isDark ? 'dark' : 'light'}';

    // 优先检查缓存
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

      // 优先使用主导色（覆盖面积大）
      final seedColor =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color ??
          paletteGenerator.mutedColor?.color;

      if (seedColor != null && mounted) {
        final scheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: isDark ? Brightness.dark : Brightness.light,
        );
        // 缓存结果
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
    // 结束阅读时长记录
    _readingTimeService.endSession();
    // 销毁前同步保存位置
    if (_chapter != null && _lastScrollPercent > 0) {
      developer.log(
        'DISPOSE: Saving cached position $_lastScrollPercent',
        name: 'POSITION',
      );
      _progressService.saveLocalScrollPosition(
        bookId: widget.bid,
        chapterId: _chapter!.id,
        sortNum: _chapter!.sortNum,
        scrollPosition: _lastScrollPercent,
        immediate: true, // 退出阅读器时立即同步
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台时保存位置和时长
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveCurrentPosition();
      _readingTimeService.endSession();
    }
    // 前台恢复记录时长
    if (state == AppLifecycleState.resumed) {
      _readingTimeService.startSession();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // 缓存当前位置用于销毁
    if (maxScroll > 0) {
      _lastScrollPercent = offset / maxScroll;
    }

    // 边界自动显示菜单栏
    if ((offset <= 0 || offset >= maxScroll) && !_barsVisible) {
      setState(() {
        _barsVisible = true;
      });
    }

    // 防抖保存（闲置 2 秒）
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

  /// 保存滚动进度（本地+服务端）
  Future<void> _saveCurrentPosition() async {
    if (_chapter == null || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final scrollPercent = maxScroll > 0 ? currentScroll / maxScroll : 0.0;

    // 本地保存以便快速恢复
    await _progressService.saveLocalScrollPosition(
      bookId: widget.bid,
      chapterId: _chapter!.id,
      sortNum: _chapter!.sortNum,
      scrollPosition: scrollPercent,
    );

    // 同步服务端（XPath 格式存储百分比）
    // 记录用户所在章节
    // 格式 "scroll:{percentage}"
    await _progressService.saveReadPosition(
      bookId: widget.bid,
      chapterId: _chapter!.id,
      xPath: 'scroll:${scrollPercent.toStringAsFixed(4)}',
    );

    _logger.info(
      'Saved position: ch${_chapter!.sortNum} @ ${(scrollPercent * 100).toStringAsFixed(1)}%',
    );
  }

  /// 内容加载后恢复进度
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
      // 使用帧回调递归等待布局完成
      await _waitForLayoutAndJump(position.scrollPosition);
    } else if (position != null) {
      _logger.info(
        'Position NOT restored: sortNum mismatch or no scroll clients. '
        'Saved chapter=${position.sortNum}, Current chapter=${_chapter?.sortNum}',
      );
    }
  }

  /// 等待布局完成后跳转到指定位置
  /// 使用帧回调递归，更符合 Flutter 响应式设计
  Future<void> _waitForLayoutAndJump(double scrollPercent) async {
    const maxFrames = 60; // 最多等待 60 帧 (约 1 秒 @ 60fps)
    int frameCount = 0;

    final completer = Completer<void>();

    void checkLayout(Duration _) {
      if (!mounted || !_scrollController.hasClients) {
        completer.complete();
        return;
      }

      final maxScroll = _scrollController.position.maxScrollExtent;

      // 布局完成：maxScrollExtent > 0
      // 或短内容：已经尝试了足够多帧，内容确实很短
      if (maxScroll > 0 || frameCount >= maxFrames) {
        if (maxScroll > 0 && scrollPercent > 0) {
          final targetScroll = scrollPercent * maxScroll;
          _logger.info(
            'Jumping to: target=$targetScroll, max=$maxScroll, '
            'percent=${(scrollPercent * 100).toStringAsFixed(1)}% (frame $frameCount)',
          );
          _scrollController.jumpTo(targetScroll);
        } else if (maxScroll == 0) {
          _logger.info(
            'Content too short for scrolling (maxScroll=0), position restore skipped',
          );
        }
        completer.complete();
        return;
      }

      // 继续等待下一帧
      frameCount++;
      WidgetsBinding.instance.addPostFrameCallback(checkLayout);
    }

    // 开始第一次检查
    WidgetsBinding.instance.addPostFrameCallback(checkLayout);

    return completer.future;
  }

  Future<void> _loadChapter(int bid, int sortNum) async {
    _logger.info('Requesting chapter with SortNum: $sortNum...');

    // 加载新章前保存当前进度
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

      // 1. 获取内容
      final chapter = await _chapterService.getNovelContent(
        bid,
        sortNum,
        convert: settings.convertType == 'none' ? null : settings.convertType,
      );
      _logger.info('Chapter loaded: ${chapter.title}');

      // 2. 加载混淆字体（带缓存控制）
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

        // 构建后恢复进度
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _restoreScrollPosition();

          // Bug修复：无论是否恢复进度，都保存当前章节到服务端
          // 确保点击章节进入后即使不滑动也能同步
          if (mounted && _chapter != null) {
            if (_scrollController.hasClients &&
                _scrollController.position.maxScrollExtent > 0) {
              // 布局完成，保存当前位置（包含章节信息）
              await _saveCurrentPosition();
              _logger.info(
                'Chapter loaded, saved position to sync with server',
              );
            } else {
              // 布局未完成但章节已加载，至少同步章节信息
              await _progressService.saveLocalScrollPosition(
                bookId: widget.bid,
                chapterId: _chapter!.id,
                sortNum: _chapter!.sortNum,
                scrollPosition: 0.0,
              );
              await _progressService.saveReadPosition(
                bookId: widget.bid,
                chapterId: _chapter!.id,
                xPath: 'scroll:0.0000',
              );
              _logger.info(
                'Chapter loaded (no scroll), saved ch${_chapter!.sortNum} to sync',
              );
            }
          }
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
    final useFloatingControls = settings.notchedDisplayMode;
    final double topPadding = MediaQuery.of(context).padding.top;

    // 动态计算模糊高度
    // 展开模式 (Floating & Visible)：增加高度以实现更长更柔和的渐变 (状态栏 + 240px)
    // 阅读模式 (Compact): 仅保护状态栏 (1.3倍)
    final double blurHeight =
        (useFloatingControls && _barsVisible)
            ? topPadding + 240.0
            : topPadding * 1.3;

    Widget content = Scaffold(
      body: Stack(
        children: [
          // 2. 主要内容层
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleBars,
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? _buildErrorView()
                      : SoftEdgeBlur(
                        edges: [
                          EdgeBlur(
                            type: EdgeType.topEdge,
                            size: blurHeight,

                            // 调整模糊度，配合增加的高度使用
                            sigma: 50,

                            // 降低不透明度，使过渡更自然，减少断层感
                            tintColor: Colors.black.withValues(alpha: 0.6),

                            controlPoints: [
                              // 起点
                              ControlPoint(
                                position: 0.0,
                                type: ControlPointType.visible,
                              ),

                              // 仅在非沉浸模式下保留中间过点以保护状态栏
                              // 展开时移除中间点，结合更大的高度实现丝滑的从顶到底渐变
                              if (!(useFloatingControls && _barsVisible))
                                ControlPoint(
                                  position: 0.6,
                                  type: ControlPointType.visible,
                                ),

                              // 终点
                              ControlPoint(
                                position: 1.0,
                                type: ControlPointType.transparent,
                              ),
                            ],
                          ),
                        ],
                        child: _buildWebContent(context, settings),
                      ),
            ),
          ),

          if (useFloatingControls) ...[
            // 悬浮模式：顶部毛玻璃功能区
            _buildFloatingTopBar(context),
            // 悬浮模式：右下角功能区
            _buildFloatingBottomControls(context),
          ] else ...[
            // 传统模式：顶部栏
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
            // 传统模式：底部导航栏
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              bottom:
                  _barsVisible
                      ? 0
                      : -100 - MediaQuery.of(context).padding.bottom,
              left: 0,
              right: 0,
              child: _buildBottomBar(context, settings),
            ),
          ],
        ],
      ),
    );

    // AnimatedTheme 平滑过渡颜色
    // AnimatedTheme 平滑过渡颜色
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // 顶部状态栏透明（由 SoftEdgeBlur 接管视觉）
        statusBarIconBrightness:
            Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
        // 底部导航条透明沉浸
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
      ),
      child: AnimatedTheme(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        data: Theme.of(context).copyWith(
          colorScheme: _dynamicColorScheme ?? Theme.of(context).colorScheme,
        ),
        child: content,
      ),
    );
  }

  Widget _buildWebContent(BuildContext context, AppSettings settings) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        // 滑动停止时强制刷新进度，确保百分比是最新的
        // 即使菜单不收起，也要能看到最新的 "已读 x%"
        if (mounted) setState(() {});
        return false;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          16.0,
          MediaQuery.of(context).padding.top + 20, // 状态栏边距+留白
          16.0,
          // 底部导航栏留白
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
    // 安全区域检查防止抖动
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
          // 上一章按钮
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

          // 下一章按钮
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

  // ==================== 悬浮控件模式（异形屏优化）====================

  /// MD3 风格圆形按钮（使用主题色或封面取色）
  /// MD3 风格圆形按钮（高斯模糊毛玻璃版）
  Widget _buildFloatingButton({required IconData icon, VoidCallback? onTap}) {
    // 优先使用封面取色，否则使用主题色
    final colorScheme = _dynamicColorScheme ?? Theme.of(context).colorScheme;
    final isDisabled = onTap == null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 淡淡的阴影提升层次感
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            // 半透明背景色：深色模式用深色，浅色模式用浅色，以保证对比度
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: isDark ? 0.3 : 0.5,
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 20,
                  color:
                      isDisabled
                          ? colorScheme.onSurface.withValues(alpha: 0.38)
                          : colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// MD3 风格卡片（使用主题色或封面取色）
  /// MD3 风格卡片（高斯模糊毛玻璃版）
  Widget _buildFloatingCard({required Widget child}) {
    // 优先使用封面取色，否则使用主题色
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        // 淡淡的阴影
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            // 半透明背景色
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: isDark ? 0.3 : 0.5,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: child,
          ),
        ),
      ),
    );
  }

  /// 悬浮顶部功能区
  Widget _buildFloatingTopBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: AnimatedOpacity(
        opacity: _barsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Row(
          children: [
            // 圆形返回按钮
            _buildFloatingButton(
              icon: Icons.arrow_back_ios_new,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 12),

            // 章节信息（毛玻璃卡片）
            Expanded(
              child: _buildFloatingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 章节标题
                    Text(
                      _chapter?.title ?? '',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // 书名 + 阅读进度
                    // 书名 + 阅读进度 -> 改为仅显示进度
                    Text(
                      '已读 ${(_lastScrollPercent * 100).toInt()}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 右侧更多按钮
            _buildFloatingButton(
              icon: Icons.more_horiz,
              onTap: () {
                // TODO: 更多操作
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 悬浮右下角功能区
  Widget _buildFloatingBottomControls(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Positioned(
      right: 16,
      bottom: bottomPadding + 16,
      child: AnimatedSlide(
        offset: _barsVisible ? Offset.zero : const Offset(1.5, 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: _barsVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 章节切换
              _buildFloatingButton(
                icon: Icons.list,
                onTap: () => _showChapterListSheet(context),
              ),
              const SizedBox(height: 8),

              // 阅读背景/主题
              _buildFloatingButton(
                icon: Icons.palette_outlined,
                onTap: () {
                  // TODO: 阅读主题切换
                },
              ),
              const SizedBox(height: 12),

              // 上下章节导航（横向）
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFloatingButton(
                    icon: Icons.chevron_left,
                    onTap:
                        _chapter != null && _chapter!.sortNum > 1
                            ? _onPrev
                            : null,
                  ),
                  const SizedBox(width: 8),
                  _buildFloatingButton(
                    icon: Icons.chevron_right,
                    onTap:
                        _chapter != null &&
                                _chapter!.sortNum < widget.totalChapters
                            ? _onNext
                            : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 章节列表底部弹窗
  Future<void> _showChapterListSheet(BuildContext context) async {
    var chapters = BookDetailPageState.cachedChapterList;

    // 如果没有缓存（直接进入阅读页的情况），尝试重新获取
    if (chapters == null || chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在加载章节列表...'),
          duration: Duration(seconds: 1),
        ),
      );

      try {
        final bookInfo = await _bookService.getBookInfo(widget.bid);
        if (bookInfo.chapters.isNotEmpty) {
          chapters = bookInfo.chapters;
          // 更新缓存，以便下次不用再加载
          BookDetailPageState.cachedChapterList = bookInfo.chapters;
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('加载章节列表失败: $e')));
        }
        return;
      }
    }

    if (chapters == null || chapters.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂无章节信息')));
      }
      return;
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        // 创建非空局部变量，避免 Dart 闭包中的 null 检查问题
        final chapterList = chapters!;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    '章节列表',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // 副标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '共 ${chapterList.length} 章 · 当前第 ${_chapter?.sortNum ?? 0} 章',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // 章节列表
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: chapterList.length,
                    itemBuilder: (context, index) {
                      final chapter = chapterList[index];
                      final sortNum = index + 1;
                      final isCurrentChapter = sortNum == _chapter?.sortNum;

                      return ListTile(
                        leading: Icon(
                          isCurrentChapter
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          color:
                              isCurrentChapter
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          chapter.title,
                          style: TextStyle(
                            color:
                                isCurrentChapter ? colorScheme.primary : null,
                            fontWeight:
                                isCurrentChapter ? FontWeight.bold : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing:
                            isCurrentChapter
                                ? Icon(
                                  Icons.play_arrow,
                                  color: colorScheme.primary,
                                )
                                : null,
                        onTap: () {
                          Navigator.pop(context);
                          if (sortNum != _chapter?.sortNum) {
                            _loadChapter(widget.bid, sortNum);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
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
