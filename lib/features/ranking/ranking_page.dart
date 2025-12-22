import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/src/widgets/book_type_badge.dart';

class RankingPage extends ConsumerStatefulWidget {
  final String initialType; // 'daily', 'weekly', 'monthly'

  const RankingPage({super.key, this.initialType = 'weekly'});

  @override
  ConsumerState<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends ConsumerState<RankingPage>
    with SingleTickerProviderStateMixin {
  final _logger = Logger('RankingPage');
  final _bookService = BookService();
  final _scrollController = ScrollController();

  late TabController _tabController;
  final Map<String, List<Book>> _cache = {};
  final Map<String, int> _displayedCount = {};
  bool _loading = true;
  bool _loadingMore = false;

  static const _tabs = [
    ('daily', '日榜', 1),
    ('weekly', '周榜', 7),
    ('monthly', '月榜', 31),
  ];
  static const int _pageSize = 24;

  @override
  void initState() {
    super.initState();
    final initialIndex = _tabs.indexWhere((t) => t.$1 == widget.initialType);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex >= 0 ? initialIndex : 1,
    );
    _tabController.addListener(_onTabChange);
    _scrollController.addListener(_onScroll);
    _fetchRanking();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChange() {
    if (!_tabController.indexIsChanging) {
      _fetchRanking();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  String get _currentType => _tabs[_tabController.index].$1;
  int get _currentDays => _tabs[_tabController.index].$3;

  Future<void> _fetchRanking({bool refresh = false}) async {
    if (!refresh && _cache.containsKey(_currentType)) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      var books = await _bookService.getRank(_currentDays);
      // Client-side Level6 filter
      final settings = ref.read(settingsProvider);
      if (settings.ignoreLevel6) {
        books = books.where((b) => b.level != 6).toList();
      }
      _cache[_currentType] = books;
      _displayedCount[_currentType] = _pageSize.clamp(0, books.length);
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      _logger.severe('Failed to fetch ranking: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('加载失败')));
      }
    }
  }

  void _loadMore() {
    final allBooks = _cache[_currentType] ?? [];
    final currentCount = _displayedCount[_currentType] ?? 0;

    if (_loadingMore || currentCount >= allBooks.length) return;

    setState(() => _loadingMore = true);

    // Simulate a brief delay for smooth UX
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          final newCount = (currentCount + _pageSize).clamp(0, allBooks.length);
          _displayedCount[_currentType] = newCount;
          _loadingMore = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final allBooks = _cache[_currentType] ?? [];
    final displayCount = _displayedCount[_currentType] ?? 0;
    final displayBooks = allBooks.take(displayCount).toList();
    final hasMore = displayCount < allBooks.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchRanking(refresh: true),
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : allBooks.isEmpty
                ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.leaderboard_outlined,
                        size: 64,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无数据',
                        style: textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
                : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount:
                      displayBooks.length + (hasMore && _loadingMore ? 3 : 0),
                  itemBuilder: (context, index) {
                    if (index >= displayBooks.length) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final book = displayBooks[index];
                    return _buildBookCard(context, book, index + 1);
                  },
                ),
      ),
    );
  }

  Widget _buildBookCard(BuildContext context, Book book, int rank) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroTag = 'ranking_cover_${book.id}';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => BookDetailPage(
                  bookId: book.id,
                  initialCoverUrl: book.cover,
                  initialTitle: book.title,
                  heroTag: heroTag,
                ),
          ),
        );
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
                  // Rank badge for top 3 (inside Hero)
                  if (rank <= 3)
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
                  // Book type badge (inside Hero)
                  if (ref
                      .watch(settingsProvider)
                      .isBookTypeBadgeEnabled('ranking'))
                    BookTypeBadge(category: book.category),
                ],
              ),
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
