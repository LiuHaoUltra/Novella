import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/reading_time_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:novella/features/home/recently_updated_page.dart';
import 'package:novella/features/ranking/ranking_page.dart';
import 'package:novella/features/search/search_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/src/widgets/book_type_badge.dart';

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

  // Reading stats
  int _weeklyMinutes = 0;
  int _monthlyMinutes = 0;

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

    await Future.wait(futures);

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
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
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SearchPage(),
                            ),
                          );
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
                .expand((moduleId) {
                  switch (moduleId) {
                    case 'stats':
                      return _buildStatsSection(context);
                    case 'recentlyUpdated':
                      return _buildRecentlyUpdatedSection(context, settings);
                    case 'ranking':
                      return _buildRankingSection(
                        context,
                        settings,
                        previewBooks,
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

  /// 构建统计卡片区域
  List<Widget> _buildStatsSection(BuildContext context) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
  List<Widget> _buildRecentlyUpdatedSection(BuildContext context, settings) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return [
      // 区域标题
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
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
              child: Center(child: CircularProgressIndicator()),
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
    List<Book> previewBooks,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return [
      // 区域标题
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
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
              child: Center(child: CircularProgressIndicator()),
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
            .then((_) => _loadReadingStats());
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
                    child: CachedNetworkImage(
                      imageUrl: book.cover,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder:
                          (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(
                                Icons.book_outlined,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
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
