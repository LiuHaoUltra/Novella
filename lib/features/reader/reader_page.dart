import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
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
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:novella/features/reader/reader_background_page.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:novella/core/widgets/universal_glass_panel.dart';

enum _ReaderLayoutMode { standard, immersive, center }

class _ReaderLayoutInfo {
  final _ReaderLayoutMode mode;
  final bool endsWithImage;

  const _ReaderLayoutInfo(this.mode, {this.endsWithImage = false});
}

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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _logger = Logger('ReaderPage');
  final _chapterService = ChapterService();
  final _bookService = BookService();
  final _fontManager = FontManager();
  final _progressService = ReadingProgressService();
  final _readingTimeService = ReadingTimeService();
  final ScrollController _scrollController = ScrollController();

  late AnimationController _barsAnimController;

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

  // 顶部信息栏状态
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  String _timeString = '';
  Timer? _infoTimer;

  // 章节加载版本号（用于打断旧请求）
  int _loadVersion = 0;
  // 目标章节号（用于连续点击时追踪最终目标）
  late int _targetSortNum;

  /// 获取当前阅读背景色
  Color _getReaderBackgroundColor(AppSettings settings) {
    if (settings.readerUseThemeBackground) {
      // 使用主题色
      return (_dynamicColorScheme ?? Theme.of(context).colorScheme).surface;
    }
    if (settings.readerUseCustomColor) {
      // 自定义颜色
      return Color(settings.readerBackgroundColor);
    }
    // 预设颜色
    return kReaderPresets[settings.readerPresetIndex.clamp(
          0,
          kReaderPresets.length - 1,
        )]
        .backgroundColor;
  }

  /// 获取当前阅读文字色
  Color _getReaderTextColor(AppSettings settings) {
    if (settings.readerUseThemeBackground) {
      // 使用主题色
      return (_dynamicColorScheme ?? Theme.of(context).colorScheme).onSurface;
    }
    if (settings.readerUseCustomColor) {
      // 自定义颜色
      return Color(settings.readerTextColor);
    }
    // 预设颜色
    return kReaderPresets[settings.readerPresetIndex.clamp(
          0,
          kReaderPresets.length - 1,
        )]
        .textColor;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 初始化动画控制器，默认展开状态 (value: 1.0)
    _barsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );

    _scrollController.addListener(_onScroll);
    _targetSortNum = widget.sortNum; // 初始化目标章节号
    _loadChapter(widget.bid, widget.sortNum);
    // 开始记录阅读时长
    _readingTimeService.startSession();
    // 提取封面颜色用于动态主题
    _extractColors();

    // 初始化全屏和信息栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initInfoBar();
  }

  void _initInfoBar() {
    _updateTime();
    _updateBattery();
    // 每分钟更新一次时间 (和电量)
    _infoTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateTime();
      if (timer.tick % 2 == 0) _updateBattery(); // 每分钟检查一次电量
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? '上午' : '下午';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

    if (mounted) {
      setState(() {
        _timeString = '$period $displayHour:$minute';
      });
    }
  }

  Future<void> _updateBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() {
          _batteryLevel = level;
        });
      }
    } catch (e) {
      _logger.warning('Failed to get battery level: $e');
    }
  }

  /// 提取封面颜色生成动态配色
  Future<void> _extractColors() async {
    if (widget.coverUrl == null || widget.coverUrl!.isEmpty) return;

    // 检查是否开启了封面取色功能
    final settings = ref.read(settingsProvider);
    if (!settings.coverColorExtraction) return;

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
    _barsAnimController.dispose();
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
    _infoTimer?.cancel();
    // 退出阅读页时恢复系统栏显示
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

    // 缓存当前位置用于销毁，clamp 确保不超过 0-100%
    if (maxScroll > 0) {
      _lastScrollPercent = (offset / maxScroll).clamp(0.0, 1.0);
    }

    // 边界自动显示菜单栏
    if ((offset <= 0 || offset >= maxScroll) && !_barsVisible) {
      _toggleBars(); // 使用统一的切换方法
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
      if (_barsVisible) {
        _barsAnimController.forward();
      } else {
        _barsAnimController.reverse();
      }
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

    // 版本号递增，用于打断旧请求
    final currentVersion = ++_loadVersion;

    // 加载新章前保存当前进度（不阻塞新请求）
    if (_chapter != null) {
      _saveCurrentPosition(); // 不 await，允许打断
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

      // 打断检查：如果有新请求，放弃当前结果
      if (currentVersion != _loadVersion) {
        _logger.info(
          'Load interrupted, version $currentVersion != $_loadVersion',
        );
        return;
      }

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

        // 再次打断检查
        if (currentVersion != _loadVersion) {
          _logger.info(
            'Load interrupted after font, version $currentVersion != $_loadVersion',
          );
          return;
        }

        _logger.info(
          'Font loaded: $family (cache: ${settings.fontCacheEnabled}, limit: ${settings.fontCacheLimit})',
        );
      }

      if (mounted && currentVersion == _loadVersion) {
        setState(() {
          _chapter = chapter;
          _fontFamily = family;
          _loading = false;
          _lastScrollPercent = 0.0;
        });

        // 构建后恢复进度
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // 最终打断检查
          if (currentVersion != _loadVersion) return;

          await _restoreScrollPosition();

          // Bug修复：无论是否恢复进度，都保存当前章节到服务端
          // 确保点击章节进入后即使不滑动也能同步
          if (mounted && _chapter != null && currentVersion == _loadVersion) {
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
      // 打断时不处理错误
      if (currentVersion != _loadVersion) return;

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
    if (_targetSortNum > 1) {
      _targetSortNum--;
      _loadChapter(widget.bid, _targetSortNum);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已是第一章')));
    }
  }

  void _onNext() {
    if (_targetSortNum < widget.totalChapters) {
      _targetSortNum++;
      _loadChapter(widget.bid, _targetSortNum);
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
          // 主要内容层
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

          // 悬浮功能区
          _buildFloatingTopBar(context),
          _buildFloatingBottomControls(context),
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
          colorScheme:
              (settings.coverColorExtraction ? _dynamicColorScheme : null) ??
              Theme.of(context).colorScheme,
        ),
        child: content,
      ),
    );
  }

  _ReaderLayoutInfo _analyzeLayout(String content) {
    if (content.isEmpty) {
      return const _ReaderLayoutInfo(_ReaderLayoutMode.standard);
    }
    try {
      final doc = html_parser.parseFragment(content);

      // 检查是否为单图模式：整章只有一张图片且无有效文字
      final imgCount = doc.querySelectorAll('img').length;
      final textContent = doc.text?.trim() ?? '';

      if (imgCount == 1 && textContent.isEmpty) {
        return const _ReaderLayoutInfo(_ReaderLayoutMode.center);
      }

      // 获取有效子节点（忽略空白文本）
      final children =
          doc.nodes.where((n) {
            if (n is dom.Text) return n.text.trim().isNotEmpty;
            if (n is dom.Element) return true;
            return false;
          }).toList();

      bool endsWithImage = false;
      if (children.isNotEmpty) {
        final lastNode = children.last;
        if (lastNode is dom.Element) {
          if (lastNode.localName == 'img') {
            endsWithImage = true;
          } else if ({'p', 'div'}.contains(lastNode.localName) &&
              lastNode.children.length == 1 &&
              lastNode.children.first.localName == 'img') {
            endsWithImage = true;
          }
        }
      }

      // 检查沉浸式置顶模式
      // 条件：开头是图片，且紧接着是图片（连续>=2张），且全篇图片总数超过2张
      if (children.isNotEmpty) {
        int consecutiveImages = 0;
        for (final node in children) {
          bool isImg = false;
          if (node is dom.Element) {
            if (node.localName == 'img') {
              isImg = true;
            } else if ({'p', 'div'}.contains(node.localName) &&
                node.children.length == 1 &&
                node.children.first.localName == 'img') {
              // 处理 <p><img></p> 的情况
              isImg = true;
            }
          }
          if (isImg) {
            consecutiveImages++;
          } else {
            break;
          }
        }

        // 满足条件：开头连续图片>=2 且 总图片数>2
        if (consecutiveImages >= 2 && imgCount > 2) {
          return _ReaderLayoutInfo(
            _ReaderLayoutMode.immersive,
            endsWithImage: endsWithImage,
          );
        }
      }

      return _ReaderLayoutInfo(
        _ReaderLayoutMode.standard,
        endsWithImage: endsWithImage,
      );
    } catch (e) {
      return const _ReaderLayoutInfo(_ReaderLayoutMode.standard);
    }
  }

  Widget _buildWebContent(BuildContext context, AppSettings settings) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    // 获取阅读背景色和文字色
    final readerBackgroundColor = _getReaderBackgroundColor(settings);
    final readerTextColor = _getReaderTextColor(settings);

    // 分析布局模式
    final layoutInfo =
        _chapter != null
            ? _analyzeLayout(_chapter!.content)
            : const _ReaderLayoutInfo(_ReaderLayoutMode.standard);

    // HtmlWidget 配置
    final htmlWidget = HtmlWidget(
      _chapter!.content,
      textStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: settings.fontSize,
        height: 1.6,
        color: readerTextColor, // 应用阅读文字色
      ),
      // 自定义样式：实现文字带边距，图片满宽
      customStylesBuilder: (element) {
        // ... (lines 646-656) - This part is same logic but need to be careful with replace range
        // I will copy the original customStylesBuilder content or leave it if range allows.
        // The replace range includes _buildWebContent start, so I must provide full implementation or carefully slice.
        // It's safer to provide full implementation of _buildWebContent up to where layout is used.

        // 图片：强制满宽，无边距，消除底部空隙
        if (element.localName == 'img') {
          return {
            'width': '100%',
            'height': 'auto',
            'margin': '0',
            'padding': '0',
            'display': 'block',
            // 关键：消除图片底部的行高空隙
            'vertical-align': 'bottom',
          };
        }

        // 文本容器及其它块级元素
        if ({
          'p',
          'div',
          'section',
          'article',
          'blockquote',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'li',
        }.contains(element.localName)) {
          final hasImage = element.getElementsByTagName('img').isNotEmpty;

          if (hasImage) {
            // 有图片：无边距，无行高，满宽
            return {
              'margin': '0', // 确保无外边距，图片贴边
              'padding': '0',
              'line-height': '0',
              'text-align': 'center',
            };
          } else {
            // 纯文本：加水平边距
            final styles = <String, String>{
              'padding-left': '16px',
              'padding-right': '16px',
              'margin-bottom': '1em',
            };

            return styles;
          }
        }

        // 兜底
        if (element.localName == 'body') {
          return {'margin': '0', 'padding': '0', 'line-height': '1.6'};
        }
        return null;
      },
    );

    Widget content;

    if (layoutInfo.mode == _ReaderLayoutMode.center) {
      // 居中模式：使用 LayoutBuilder + Constraints 确保内容垂直居中
      content = LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: htmlWidget),
            ),
          );
        },
      );
    } else {
      // 标准模式 / 沉浸模式
      // 沉浸模式 padding=0，标准模式 padding=状态栏+20
      final double paddingTop =
          layoutInfo.mode == _ReaderLayoutMode.immersive ? 0 : topPadding + 20;

      // 底部留白逻辑：如果以图片结尾，且开启了endsWithImage，则底部留白为0
      final double paddingBottom =
          layoutInfo.endsWithImage ? 0 : 80.0 + bottomPadding;

      content = SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(0, paddingTop, 0, paddingBottom),
        child: htmlWidget,
      );
    }

    // 包裹背景色容器
    return Container(
      color: readerBackgroundColor, // 应用阅读背景色
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          // 滑动停止时强制刷新进度，确保百分比是最新的
          // 即使菜单不收起，也要能看到最新的 "已读 x%"
          if (mounted) setState(() {});
          return false;
        },
        child: content,
      ),
    );
  }

  // ==================== 悬浮控件 ====================

  /// 悬浮顶部功能区
  Widget _buildFloatingTopBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: AnimatedOpacity(
        opacity: _barsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_barsVisible,
          child: Row(
            children: [
              // 返回按钮 - AdaptiveFloatingActionButton
              // 返回按钮
              // TODO: iOS 26+ 液态玻璃按钮导致闪退，暂时禁用
              // if (PlatformInfo.isIOS26OrHigher())
              //   AdaptiveButton.sfSymbol(
              //     onPressed: () => Navigator.pop(context),
              //     sfSymbol: const SFSymbol('chevron.left'),
              //     style: AdaptiveButtonStyle.glass,
              //     size: AdaptiveButtonSize.medium,
              //     borderRadius: BorderRadius.circular(1000),
              //     useSmoothRectangleBorder: false,
              //   )
              // else
              Builder(
                builder: (context) {
                  final settings = ref.watch(settingsProvider);
                  final colorScheme =
                      (settings.coverColorExtraction
                          ? _dynamicColorScheme
                          : null) ??
                      Theme.of(context).colorScheme;
                  return AdaptiveFloatingActionButton(
                    mini: true,
                    onPressed: () => Navigator.pop(context),
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    child: Icon(
                      PlatformInfo.isIOS
                          ? CupertinoIcons.chevron_left
                          : Icons.arrow_back,
                      size: 20,
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),

              // 章节信息卡片 - 根据标题长度动态收缩
              // 使用 Flexible + Center：允许收缩，且在剩余空间居中
              Flexible(
                child: Center(
                  child: Builder(
                    builder: (context) {
                      // 根据阅读背景亮度动态计算文字颜色
                      final settings = ref.watch(settingsProvider);
                      final readerBgColor = _getReaderBackgroundColor(settings);
                      // computeLuminance 返回 0.0-1.0，越接近 1 越亮
                      final isLightBg = readerBgColor.computeLuminance() > 0.5;
                      final textColor = isLightBg ? Colors.black : Colors.white;
                      final subTextColor = textColor.withValues(alpha: 0.7);

                      return UniversalGlassPanel(
                        blurAmount: 15,
                        borderRadius: BorderRadius.circular(100),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 章节标题（支持简化）
                              Text(
                                _loading
                                    ? '加载中...'
                                    : (() {
                                      String title = _chapter?.title ?? '';
                                      if (title.isNotEmpty &&
                                          settings.cleanChapterTitle) {
                                        // 智能混合正则：
                                        // 处理 【第一话】 或非英文前缀
                                        // 处理 『「〈 分隔符
                                        // 保留纯英文标题
                                        final regex = RegExp(
                                          r'^\s*(?:【([^】]*)】.*|(?![a-zA-Z]+\s)([^\s『「〈]+)[\s『「〈].*)$',
                                        );
                                        final match = regex.firstMatch(title);
                                        if (match != null) {
                                          final extracted =
                                              (match.group(1) ?? '') +
                                              (match.group(2) ?? '');
                                          if (extracted.isNotEmpty) {
                                            title = extracted;
                                          }
                                        }
                                      }
                                      return title;
                                    })(),
                                style: Theme.of(
                                  context,
                                ).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 2),
                              // 阅读进度（clamp 确保 0-100%）
                              Text(
                                '$_timeString · 电量 $_batteryLevel% · 已读 ${(_lastScrollPercent.clamp(0.0, 1.0) * 100).toInt()}%',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: subTextColor,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 更多菜单按钮（章节列表 + 阅读背景）
              if (Platform.isIOS || Platform.isMacOS)
                AdaptivePopupMenuButton.icon<String>(
                  icon:
                      PlatformInfo.isIOS26OrHigher()
                          ? 'ellipsis'
                          : CupertinoIcons.ellipsis,
                  buttonStyle: PopupButtonStyle.glass,
                  items: [
                    AdaptivePopupMenuItem(
                      label: '章节列表',
                      icon:
                          PlatformInfo.isIOS26OrHigher()
                              ? 'list.bullet'
                              : CupertinoIcons.list_bullet,
                      value: 'chapters',
                    ),
                    AdaptivePopupMenuItem(
                      label: '阅读背景',
                      icon:
                          PlatformInfo.isIOS26OrHigher()
                              ? 'paintbrush'
                              : CupertinoIcons.paintbrush,
                      value: 'background',
                    ),
                  ],
                  onSelected: (index, item) {
                    switch (item.value) {
                      case 'chapters':
                        _showChapterListSheet(context);
                        break;
                      case 'background':
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ReaderBackgroundPage(),
                          ),
                        );
                        break;
                    }
                  },
                )
              else
                Builder(
                  builder: (context) {
                    // 根据阅读背景亮度动态计算图标颜色
                    final settings = ref.watch(settingsProvider);
                    final readerBgColor = _getReaderBackgroundColor(settings);
                    final isLightBg = readerBgColor.computeLuminance() > 0.5;
                    final iconColor = isLightBg ? Colors.black : Colors.white;

                    return PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz, color: iconColor),
                      itemBuilder: (context) {
                        final colorScheme = Theme.of(context).colorScheme;
                        return [
                          PopupMenuItem(
                            value: 'chapters',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.list,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                const Text('章节列表'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'background',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.palette_outlined,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                const Text('阅读背景'),
                              ],
                            ),
                          ),
                        ];
                      },
                      onSelected: (value) {
                        switch (value) {
                          case 'chapters':
                            _showChapterListSheet(context);
                            break;
                          case 'background':
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (context) => const ReaderBackgroundPage(),
                              ),
                            );
                            break;
                        }
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 悬浮底部功能区（上下章导航）
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
          child: IgnorePointer(
            ignoring: !_barsVisible,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 上一章
                // TODO: iOS 26+ 液态玻璃按钮导致闪退，暂时禁用
                // if (PlatformInfo.isIOS26OrHigher())
                //   AdaptiveButton.sfSymbol(
                //     onPressed: _targetSortNum > 1 ? _onPrev : null,
                //     sfSymbol: const SFSymbol('chevron.left'),
                //     style: AdaptiveButtonStyle.glass,
                //     size: AdaptiveButtonSize.medium,
                //     borderRadius: BorderRadius.circular(1000),
                //     useSmoothRectangleBorder: false,
                //   )
                // else
                Builder(
                  builder: (context) {
                    final settings = ref.watch(settingsProvider);
                    final colorScheme =
                        (settings.coverColorExtraction
                            ? _dynamicColorScheme
                            : null) ??
                        Theme.of(context).colorScheme;
                    return AdaptiveFloatingActionButton(
                      mini: true,
                      onPressed:
                          _chapter != null && _chapter!.sortNum > 1
                              ? _onPrev
                              : null,
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: Icon(
                        PlatformInfo.isIOS
                            ? CupertinoIcons.chevron_left
                            : Icons.chevron_left,
                        size: 20,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // 下一章
                // TODO: iOS 26+ 液态玻璃按钮导致闪退，暂时禁用
                // if (PlatformInfo.isIOS26OrHigher())
                //   AdaptiveButton.sfSymbol(
                //     onPressed:
                //         _targetSortNum < widget.totalChapters ? _onNext : null,
                //     sfSymbol: const SFSymbol('chevron.right'),
                //     style: AdaptiveButtonStyle.glass,
                //     size: AdaptiveButtonSize.medium,
                //     borderRadius: BorderRadius.circular(1000),
                //     useSmoothRectangleBorder: false,
                //   )
                // else
                Builder(
                  builder: (context) {
                    final settings = ref.watch(settingsProvider);
                    final colorScheme =
                        (settings.coverColorExtraction
                            ? _dynamicColorScheme
                            : null) ??
                        Theme.of(context).colorScheme;
                    return AdaptiveFloatingActionButton(
                      mini: true,
                      onPressed:
                          _chapter != null &&
                                  _chapter!.sortNum < widget.totalChapters
                              ? _onNext
                              : null,
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: Icon(
                        PlatformInfo.isIOS
                            ? CupertinoIcons.chevron_right
                            : Icons.chevron_right,
                        size: 20,
                      ),
                    );
                  },
                ),
              ],
            ),
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
          maxChildSize: 0.6,
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
                        // 移除 leading，改用 Row 在 title 中布局以保证对齐
                        title: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                '$sortNum',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyLarge?.copyWith(
                                  color:
                                      isCurrentChapter
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                  fontWeight:
                                      isCurrentChapter ? FontWeight.bold : null,
                                  height: 1.0, // 强制行高一致，减少字体度量差异的影响
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                chapter.title,
                                style: textTheme.bodyLarge?.copyWith(
                                  color:
                                      isCurrentChapter
                                          ? colorScheme.primary
                                          : null,
                                  fontWeight:
                                      isCurrentChapter ? FontWeight.bold : null,
                                  height: 1.0, // 强制行高一致
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
                            _targetSortNum = sortNum; // 同步目标章节号
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
