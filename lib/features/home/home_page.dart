import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/src/widgets/book_cover_image.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/reading_time_service.dart';
import 'package:novella/data/services/reading_progress_service.dart';
import 'package:novella/data/services/book_info_cache_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:novella/features/home/recently_updated_page.dart';
import 'package:novella/features/ranking/ranking_page.dart';
import 'package:novella/features/search/search_page.dart';
import 'package:novella/data/services/local_cover_service.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';
import 'package:novella/src/widgets/book_type_badge.dart';
import 'package:novella/src/widgets/book_cover_previewer.dart';
import 'package:novella/main.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with RouteAware {
  final _logger = Logger('HomePage');
  final _bookService = BookService();
  final _readingTimeService = ReadingTimeService();
  List<Book> _rankBooks = [];
  List<Book> _latestBooks = []; // 最近更新书籍
  bool _loading = true;

  String? _lastRankType;

  // 设置变更时标记需要刷新
  bool _needsRefresh = false;

  // 缓存上次的过滤设置用于检测变化
  bool? _lastIgnoreJapanese;
  bool? _lastIgnoreAI;
  bool? _lastIgnoreLevel6;

  // 阅读时长统计
  int _weeklyMinutes = 0;
  int _monthlyMinutes = 0;

  // 最后阅读的书籍信息
  Book? _lastReadBookInfo;
  ReadPosition? _lastReadPosition;
  final _progressService = ReadingProgressService();
  final _cacheService = BookInfoCacheService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 注册路由观察者
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    // 取消注册路由观察者
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // 当从其他页面返回此页面时触发
    _loadReadingStats();
    _fetchContinueReading(internalLoading: false);
  }

  @override
  void initState() {
    super.initState();
    // 延迟以确保设置加载完成
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _readingTimeService.recoverSession(); // 恢复/清除过期会话
      _fetchData(); // 获取榜单和最新数据
      _loadReadingStats();
      // 初始化过滤设置缓存
      final settings = ref.read(settingsProvider);
      _lastIgnoreJapanese = settings.ignoreJapanese;
      _lastIgnoreAI = settings.ignoreAI;
      _lastIgnoreLevel6 = settings.ignoreLevel6;
    });
  }

  /// 检查过滤设置是否变更
  void _checkFilterSettingsChanged() {
    final settings = ref.read(settingsProvider);
    if (_lastIgnoreJapanese != settings.ignoreJapanese ||
        _lastIgnoreAI != settings.ignoreAI ||
        _lastIgnoreLevel6 != settings.ignoreLevel6) {
      _needsRefresh = true;
      _lastIgnoreJapanese = settings.ignoreJapanese;
      _lastIgnoreAI = settings.ignoreAI;
      _lastIgnoreLevel6 = settings.ignoreLevel6;
    }
  }

  /// 加载阅读时长统计
  Future<void> _loadReadingStats() async {
    try {
      final weekly = await _readingTimeService.getWeeklyMinutes();
      final monthly = await _readingTimeService.getMonthlyMinutes();
      if (mounted) {
        setState(() {
          _weeklyMinutes = weekly;
          _monthlyMinutes = monthly;
        });
      }
    } catch (e) {
      _logger.warning('Failed to load reading stats: $e');
    }
  }

  int _rankTypeToDay(String type) {
    switch (type) {
      case 'daily':
        return 1;
      case 'monthly':
        return 31;
      default:
        return 7; // weekly
    }
  }

  String _rankTypeToLabel(String type) {
    switch (type) {
      case 'daily':
        return '日榜';
      case 'monthly':
        return '月榜';
      default:
        return '周榜';
    }
  }

  Future<void> _fetchData() async {
    final settings = ref.read(settingsProvider);
    setState(() => _loading = true);

    // 仅获取已启用模块的数据
    final futures = <Future<void>>[];
    if (settings.isModuleEnabled('ranking')) {
      futures.add(_fetchRanking(internalLoading: false));
    }
    if (settings.isModuleEnabled('recentlyUpdated')) {
      futures.add(_fetchLatestBooks(internalLoading: false));
    }
    if (settings.isModuleEnabled('continueReading')) {
      futures.add(_fetchContinueReading(internalLoading: false));
    }

    await Future.wait(futures);

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _fetchContinueReading({bool internalLoading = true}) async {
    try {
      if (internalLoading) setState(() => _loading = true);

      // 预热本地封面目录：确保后续 [`LocalShelfCover`](lib/features/home/home_page.dart:1068)
      // 在首次渲染“继续阅读”时就能同步命中本地文件，避免先显示网络封面再切换造成闪烁。
      await LocalCoverService().prewarm();

      final lastPos = await _progressService.getLastReadBook();
      if (lastPos != null) {
        // 1. 优先尝试使用 ReadPosition 自带的本地持久化元数据实现瞬产渲染
        if (lastPos.title != null && lastPos.cover != null) {
          final book = Book(
            id: lastPos.bookId,
            title: lastPos.title!,
            cover: lastPos.cover!,
            author: '', // 首页卡片暂不强制依赖作者信息
            lastUpdatedAt: DateTime.now(),
            category: null,
            level: 0,
          );
          if (mounted) {
            setState(() {
              _lastReadPosition = lastPos;
              _lastReadBookInfo = book;
            });
          }
          // 如果已有本地元数据，则后续的网络请求设为完全静默（且可选，仅用于同步最新状态）
          internalLoading = false;
        }

        // 2. 尝试从内存缓存快速加载 (用于覆盖老旧无元数据的记录)
        final cachedInfo = _cacheService.get(lastPos.bookId);
        if (cachedInfo != null && mounted && _lastReadBookInfo == null) {
          _updateContinueReadingState(lastPos, cachedInfo);
        }

        // 3. 网络更新详情
        final networkUpdate = _bookService
            .getBookInfo(lastPos.bookId)
            .then((info) {
              _cacheService.set(lastPos.bookId, info);
              if (mounted) {
                _updateContinueReadingState(lastPos, info);
              }
            })
            .catchError((e) {
              _logger.warning('Failed to update book info from network: $e');
              // 如果本地、缓存都没有，且网络失败，才打印警告
              if (_lastReadBookInfo == null && cachedInfo == null) {
                _logger.severe(
                  'Critical: No local/cache/network data for book ${lastPos.bookId}',
                );
              }
            });

        // 核心优化：如果已经有可显示的数据（本地元数据或内存缓存），则不 await 网络请求
        // 这样可以实现首页瞬间完成初始化流程。
        if (_lastReadBookInfo == null && cachedInfo == null) {
          await networkUpdate;
        }
      } else {
        if (mounted) {
          setState(() {
            _lastReadPosition = null;
            _lastReadBookInfo = null;
          });
        }
      }

      if (internalLoading && mounted) setState(() => _loading = false);
    } catch (e) {
      _logger.warning('Failed to fetch continue reading: $e');
      if (internalLoading && mounted) setState(() => _loading = false);
    }
  }

  /// 将封面 URL 规范化为“图片身份”用于比较。
  ///
  /// - 忽略 query / fragment（常见于 token、版本号等，会导致同图不同 URL）
  /// - 解析失败则回退到原始字符串
  String _canonicalCoverUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      return uri.replace(query: '', fragment: '').toString();
    } catch (_) {
      return url;
    }
  }

  void _updateContinueReadingState(ReadPosition pos, BookInfo info) {
    // 补全逻辑：如果本地记录缺失章节标题，尝试从最新的网络详情中补全
    ReadPosition effectivePos = pos;
    if (pos.chapterTitle == null || pos.chapterTitle!.isEmpty) {
      final matchingChapter =
          info.chapters.where((c) => c.id == pos.chapterId).firstOrNull;
      if (matchingChapter != null) {
        effectivePos = ReadPosition(
          bookId: pos.bookId,
          chapterId: pos.chapterId,
          sortNum: pos.sortNum,
          scrollPosition: pos.scrollPosition,
          title: pos.title ?? info.title,
          cover: pos.cover ?? info.cover,
          chapterTitle: matchingChapter.title,
        );
        // 静默持久化回填（仅元数据）：
        // 不得刷新 updatedAt / 不得更新 last_read_book_id / 不得触发 Gist 同步
        // 以免首页“继续阅读”展示逻辑污染多端基于 updatedAt 的合并决策。
        // ignore: unawaited_futures
        _progressService.backfillLocalReadMetadata(
          bookId: effectivePos.bookId,
          title: effectivePos.title,
          cover: effectivePos.cover,
          chapterTitle: effectivePos.chapterTitle,
        );
      }
    }

    // 性能优化：如果数据未变（含章节名），则不触发更新，防止图片重载闪烁
    final currentCover = _lastReadBookInfo?.cover;
    final nextCoverRaw =
        (pos.cover?.isNotEmpty == true) ? pos.cover! : info.cover;
    final currentCoverKey = _canonicalCoverUrl(currentCover);
    final nextCoverKey = _canonicalCoverUrl(nextCoverRaw);

    // 关键：用 canonical 进行“同图判等”，避免仅 query/token 变化导致 setState -> ImageProvider 变化 -> 闪烁。
    if (_lastReadBookInfo?.id == info.id &&
        currentCoverKey == nextCoverKey &&
        _lastReadPosition?.chapterId == effectivePos.chapterId &&
        _lastReadPosition?.chapterTitle == effectivePos.chapterTitle) {
      return;
    }

    // 如果“同图不同 URL”，则保持 cover 字符串稳定，避免 ImageProvider 重建导致闪一下。
    final stableCover =
        (currentCover?.isNotEmpty == true && currentCoverKey == nextCoverKey)
            ? currentCover!
            : nextCoverRaw;

    // 构建 Book 对象用于 UI 显示
    final book = Book(
      id: info.id,
      title: info.title,
      cover: stableCover,
      author: info.author,
      lastUpdatedAt: info.lastUpdatedAt,
      category: null,
      level: 0,
    );

    setState(() {
      _lastReadPosition = effectivePos;
      _lastReadBookInfo = book;
    });
  }

  Future<void> _fetchRanking({bool internalLoading = true}) async {
    final settings = ref.read(settingsProvider);
    final rankType = settings.homeRankType;

    try {
      if (internalLoading) setState(() => _loading = true);

      final days = _rankTypeToDay(rankType);

      // 排名也应用过滤规则
      var books = await _bookService.getRank(days);
      _logger.info('[Ranking] API returned ${books.length} books');
      // Client-side Level6 filter
      if (settings.ignoreLevel6) {
        final beforeFilter = books.length;
        books = books.where((b) => b.level != 6).toList();
        _logger.info(
          '[Ranking] Level6 filter: $beforeFilter -> ${books.length} (filtered ${beforeFilter - books.length})',
        );
      }

      if (mounted) {
        setState(() {
          _rankBooks = books;
          _lastRankType = rankType;
          if (internalLoading) _loading = false;
        });
      }
    } catch (e) {
      _logger.severe('Error fetching ranking: $e');
      if (internalLoading && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchLatestBooks({bool internalLoading = true}) async {
    final settings = ref.read(settingsProvider);
    try {
      if (internalLoading) setState(() => _loading = true);

      // 使用 getBookList 替代 getLatestBooks，因为后者服务端固定只返回6本
      final result = await _bookService.getBookList(
        page: 1,
        size: 9, // 请求足够多以补偿 Level6 过滤
        order: 'latest',
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      var books = result.books;
      _logger.info('[Recently Updated] API returned ${books.length} books');
      // Client-side Level6 filter
      if (settings.ignoreLevel6) {
        final beforeFilter = books.length;
        books = books.where((b) => b.level != 6).toList();
        _logger.info(
          '[Recently Updated] Level6 filter: $beforeFilter -> ${books.length} (filtered ${beforeFilter - books.length})',
        );
      }

      if (mounted) {
        setState(() {
          _latestBooks = books;
          if (internalLoading) _loading = false;
        });
      }
    } catch (e) {
      _logger.severe('Error fetching latest books: $e');
      if (internalLoading && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onRefresh() async {
    await _fetchData();
  }

  /// 获取指定类型榜单（设置变更时）
  Future<void> _fetchRankingForType(String rankType) async {
    setState(() {
      _loading = true;
    });

    try {
      final settings = ref.read(settingsProvider);
      final days = _rankTypeToDay(rankType);
      var books = await _bookService.getRank(days);
      _logger.info('[Ranking] API returned ${books.length} books');
      // Client-side Level6 filter
      if (settings.ignoreLevel6) {
        final beforeFilter = books.length;
        books = books.where((b) => b.level != 6).toList();
        _logger.info(
          '[Ranking] Level6 filter: $beforeFilter -> ${books.length} (filtered ${beforeFilter - books.length})',
        );
      }
      setState(() {
        _rankBooks = books;
        _loading = false;
      });
    } catch (e) {
      _logger.severe('Error fetching ranking: $e');
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('加载失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);

    // 检测过滤设置变更并标记需要刷新
    _checkFilterSettingsChanged();

    // 如果标记为需要刷新，触发重新加载
    if (_needsRefresh) {
      _needsRefresh = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchData();
      });
    }

    // 检测榜单类型变更并刷新，立即更新防止死循环
    if (_lastRankType != null && _lastRankType != settings.homeRankType) {
      final newType = settings.homeRankType;
      _lastRankType = newType; // 立即更新以防重复触发
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchRankingForType(newType);
      });
    }

    // 仅展示前 6 本（2 行）
    final previewBooks = _rankBooks.take(6).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          slivers: [
            // 大标题与搜索栏
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '发现',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const SearchPage(),
                                ),
                              )
                              .then((_) {
                                _loadReadingStats();
                                _fetchContinueReading(internalLoading: false);
                              });
                        },
                        tooltip: '搜索',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 基于排序的动态模块（仅启用）
            ...settings.homeModuleOrder
                .where((m) => settings.isModuleEnabled(m))
                .toList()
                .asMap()
                .entries
                .expand((entry) {
                  final index = entry.key;
                  final moduleId = entry.value;
                  final isFirst = index == 0;

                  switch (moduleId) {
                    case 'continueReading':
                      return _buildContinueReadingSection(
                        context,
                        isFirst: isFirst,
                      );
                    case 'stats':
                      return _buildStatsSection(context, isFirst: isFirst);
                    case 'recentlyUpdated':
                      return _buildRecentlyUpdatedSection(
                        context,
                        settings,
                        isFirst: isFirst,
                      );
                    case 'ranking':
                      return _buildRankingSection(
                        context,
                        settings,
                        previewBooks,
                        isFirst: isFirst,
                      );
                    default:
                      return <Widget>[];
                  }
                }),
            // 底部留白
            // 底部留白 (减去模块自带的 16px 底部间距)
            SliverToBoxAdapter(
              child: SizedBox(height: (settings.useIOS26Style ? 86 : 24) - 16),
            ),
          ],
        ),
      ),
    );
  }

  /// 格式化时长（分钟 -> 小时/分钟）
  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes 分钟';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '$hours 小时';
    }
    return '$hours 时 $mins 分';
  }

  /// 构建继续阅读模块
  List<Widget> _buildContinueReadingSection(
    BuildContext context, {
    bool isFirst = false,
  }) {
    if (_lastReadBookInfo == null || _lastReadPosition == null) return [];

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final book = _lastReadBookInfo!;
    final pos = _lastReadPosition!;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: isFirst ? 16 : 0, // 置顶时增加间距以达视觉平衡
            bottom: 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.only(bottom: 16), // 底部间距
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    // 快速进入书籍详情页
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder:
                                (_) => BookDetailPage(
                                  bookId: book.id,
                                  initialCoverUrl: book.cover,
                                  initialTitle: book.title,
                                  heroTag: 'continue_reading_${book.id}',
                                ),
                          ),
                        )
                        .then((_) {
                          _loadReadingStats();
                          _fetchContinueReading(internalLoading: false);
                        }); // 返回刷新
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // 封面
                        Hero(
                          tag: 'continue_reading_${book.id}',
                          // 冷启动首次点击时，详情页封面可能仍在占位阶段。
                          // 这里 push 阶段强制使用来源 Hero（首页侧）作为飞行物，
                          // 避免 Hero 飞行过程中从“真实封面”变成“灰色占位”造成观感退化。
                          flightShuttleBuilder: (
                            _,
                            __,
                            direction,
                            fromHeroContext,
                            toHeroContext,
                          ) {
                            final fromHero = fromHeroContext.widget as Hero;
                            final toHero = toHeroContext.widget as Hero;
                            return direction == HeroFlightDirection.push
                                ? fromHero.child
                                : toHero.child;
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LocalShelfCover(
                              bookId: book.id,
                              coverUrl: book.cover,
                              width: 48,
                              height: 72,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 信息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '继续阅读',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                book.title,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pos.chapterTitle?.isNotEmpty == true
                                    ? pos.chapterTitle!
                                    : '第 ${pos.sortNum} 章',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // 图标
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// 构建统计卡片区域
  List<Widget> _buildStatsSection(
    BuildContext context, {
    bool isFirst = false,
  }) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            isFirst ? 16 : 0, // 置顶时增加间距，非置顶保持紧凑
            16,
            16,
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  '本月阅读',
                  _formatDuration(_monthlyMinutes),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  '本周阅读',
                  _formatDuration(_weeklyMinutes),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// 构建最近更新区域
  List<Widget> _buildRecentlyUpdatedSection(
    BuildContext context,
    settings, {
    bool isFirst = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return [
      // 区域标题
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 8, 8, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '最近更新',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RecentlyUpdatedPage(),
                    ),
                  );
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('更多'), Icon(Icons.chevron_right, size: 20)],
                ),
              ),
            ],
          ),
        ),
      ),
      // Grid content
      _loading
          ? const SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: Center(child: M3ELoadingIndicator()),
            ),
          )
          : _latestBooks.isEmpty
          ? SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Center(
                child: Text(
                  '暂无更新',
                  style: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
          : SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.58,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final book = _latestBooks[index];
                if (index >= 6) return null;
                return _buildBookCard(context, book, 0, 'recent');
              }, childCount: _latestBooks.length > 6 ? 6 : _latestBooks.length),
            ),
          ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
  }

  /// 构建榜单区域
  List<Widget> _buildRankingSection(
    BuildContext context,
    settings,
    List<Book> previewBooks, {
    bool isFirst = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return [
      // 区域标题
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 8, 8, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '近期排行',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _rankTypeToLabel(settings.homeRankType),
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) =>
                              RankingPage(initialType: settings.homeRankType),
                    ),
                  );
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('更多'), Icon(Icons.chevron_right, size: 20)],
                ),
              ),
            ],
          ),
        ),
      ),
      // Grid content
      _loading
          ? const SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: Center(child: M3ELoadingIndicator()),
            ),
          )
          : previewBooks.isEmpty
          ? SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  '暂无数据',
                  style: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
          : SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.58,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final book = previewBooks[index];
                return _buildBookCard(context, book, index + 1, 'rank');
              }, childCount: previewBooks.length),
            ),
          ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String formattedDuration,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero, // 移除默认边距，确保宽度与继续阅读卡片对齐
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formattedDuration,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCard(
    BuildContext context,
    Book book,
    int rank,
    String source,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroTag = 'home_${source}_cover_${book.id}';

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder:
                    (_) => BookDetailPage(
                      bookId: book.id,
                      initialCoverUrl: book.cover,
                      initialTitle: book.title,
                      heroTag: heroTag,
                    ),
              ),
            )
            .then((_) {
              _loadReadingStats();
              _fetchContinueReading(internalLoading: false);
            });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Hero(
              tag: heroTag,
              child: Stack(
                children: [
                  Card(
                    elevation: 2,
                    shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: BookCoverPreviewer(
                      coverUrl: book.cover,
                      child: BookCoverImage(
                        imageUrl: book.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                  // 前三名排行角标（Hero 内部）
                  if (rank <= 3 && rank > 0)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              rank == 1
                                  ? const Color(0xFFFFD700) // Gold
                                  : rank == 2
                                  ? const Color(
                                    0xFF78909C,
                                  ) // Silver (blue-tinted)
                                  : const Color(0xFFCD7F32), // Bronze
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$rank',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // 书籍类型角标（Hero 内部）
                  if (ref
                      .watch(settingsProvider)
                      .isBookTypeBadgeEnabled(
                        source == 'rank' ? 'ranking' : 'recent',
                      ))
                    BookTypeBadge(category: book.category),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 36, // 固定高度容纳两行文字
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 专为“继续阅读”卡片设计的封面渲染组件
/// 优先使用物理本地文件实现 0 闪烁同步加载
class LocalShelfCover extends StatelessWidget {
  final int bookId;
  final String coverUrl;
  final double width;
  final double height;

  const LocalShelfCover({
    super.key,
    required this.bookId,
    required this.coverUrl,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final localPath = LocalCoverService().getLocalCoverPathSync(bookId);

    if (localPath.isNotEmpty && File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
        // 关键：启用 gaplessPlayback 并在组件重建时保持显示旧图
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          // 如果读取本地物理文件遇到损坏或异常，不抛出红屏错误，而是静默回退到带有 BlurHash 的网络封面
          return BookCoverImage(
            imageUrl: coverUrl,
            width: width,
            height: height,
          );
        },
      );
    }

    // 回退到网络缓存
    return BookCoverImage(imageUrl: coverUrl, width: width, height: height);
  }
}
