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
  List<Book> _latestBooks = []; // Recently updated books
  bool _loading = true;
  DateTime? _lastRefreshTime;
  String? _lastRankType;

  // Reading stats
  int _weeklyMinutes = 0;
  int _monthlyMinutes = 0;

  @override
  void initState() {
    super.initState();
    // Delay to allow settings to load
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _readingTimeService
          .recoverSession(); // Recover/Clear stale sessions
      _fetchData(); // Fetch both ranking and latest
      _loadReadingStats();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh reading stats when returning to this page (e.g. from bottom nav switch)
    _loadReadingStats();
  }

  /// Load reading time statistics
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

    // Only fetch data for enabled modules
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
        _lastRefreshTime = DateTime.now();
      });
    }
  }

  Future<void> _fetchRanking({bool internalLoading = true}) async {
    final settings = ref.read(settingsProvider);
    final rankType = settings.homeRankType;

    try {
      if (internalLoading) setState(() => _loading = true);

      final days = _rankTypeToDay(rankType);
      // Pass ignore filters to ranking as well since we updated BookService
      var books = await _bookService.getRank(days);
      // Client-side Level6 filter
      if (settings.ignoreLevel6) {
        books = books.where((b) => b.level != 6).toList();
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

      var books = await _bookService.getLatestBooks(
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      // Client-side Level6 filter
      if (settings.ignoreLevel6) {
        books = books.where((b) => b.level != 6).toList();
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

  /// Fetch ranking for a specific type (used when settings change)
  Future<void> _fetchRankingForType(String rankType) async {
    setState(() {
      _loading = true;
    });

    try {
      final settings = ref.read(settingsProvider);
      final days = _rankTypeToDay(rankType);
      var books = await _bookService.getRank(days);
      // Client-side Level6 filter
      if (settings.ignoreLevel6) {
        books = books.where((b) => b.level != 6).toList();
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

    // Refresh if rank type changed - update immediately to prevent infinite loop
    if (_lastRankType != null && _lastRankType != settings.homeRankType) {
      final newType = settings.homeRankType;
      _lastRankType = newType; // Update immediately to prevent re-triggering
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchRankingForType(newType);
      });
    }

    // Only show first 9 books (3 rows)
    final previewBooks = _rankBooks.take(9).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          slivers: [
            // Big Title Header with Search
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
            // Dynamic modules based on order (only enabled ones)
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
            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }

  /// Build stats cards section
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
                  '$_monthlyMinutes',
                  '分钟',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(context, '本周阅读', '$_weeklyMinutes', '分钟'),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Build recently updated section
  List<Widget> _buildRecentlyUpdatedSection(BuildContext context, settings) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return [
      // Section header
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
                if (index >= 9) return null;
                return _buildBookCard(context, book, 0, 'recent');
              }, childCount: _latestBooks.length > 9 ? 9 : _latestBooks.length),
            ),
          ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
  }

  /// Build ranking section
  List<Widget> _buildRankingSection(
    BuildContext context,
    settings,
    List<Book> previewBooks,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return [
      // Section header
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
    ];
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    String unit,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
            child: Stack(
              children: [
                Hero(
                  tag: heroTag,
                  child: Card(
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
                ),
                // Rank badge for top 3
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
                // Book type badge - use 'ranking' scope for rank section, 'recent' for recent section
                if (ref
                    .watch(settingsProvider)
                    .isBookTypeBadgeEnabled(
                      source == 'rank' ? 'ranking' : 'recent',
                    ))
                  BookTypeBadge(category: book.category),
              ],
            ),
          ),
          SizedBox(
            height: 36, // Fixed height for 2 lines of text
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
