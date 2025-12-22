import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/src/widgets/book_type_badge.dart';

class RecentlyUpdatedPage extends ConsumerStatefulWidget {
  const RecentlyUpdatedPage({super.key});

  @override
  ConsumerState<RecentlyUpdatedPage> createState() =>
      _RecentlyUpdatedPageState();
}

class _RecentlyUpdatedPageState extends ConsumerState<RecentlyUpdatedPage> {
  final _logger = Logger('RecentlyUpdatedPage');
  final _bookService = BookService();
  final _scrollController = ScrollController();

  List<Book> _books = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _currentPage = 1;
  int _totalPages = 1;
  static const int _pageSize = 24; // Match backend limit/recommendation

  @override
  void initState() {
    super.initState();
    _fetchBooks();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && !_loadingMore && _currentPage < _totalPages) {
        _loadMore();
      }
    }
  }

  Future<void> _fetchBooks({bool refresh = false}) async {
    final settings = ref.read(settingsProvider);
    if (refresh) {
      setState(() => _loading = true);
    }

    try {
      final result = await _bookService.getBookList(
        page: 1,
        size: _pageSize,
        order: 'latest',
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      // Client-side Level6 filter
      final filteredBooks =
          settings.ignoreLevel6
              ? result.books.where((b) => b.level != 6).toList()
              : result.books;

      if (mounted) {
        setState(() {
          _books = filteredBooks;
          _currentPage = 1;
          _totalPages = result.totalPages;
          _loading = false;
        });
      }
    } catch (e) {
      _logger.severe('Failed to fetch books: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('加载失败')));
      }
    }
  }

  Future<void> _loadMore() async {
    final settings = ref.read(settingsProvider);
    setState(() => _loadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final result = await _bookService.getBookList(
        page: nextPage,
        size: _pageSize,
        order: 'latest',
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      // Client-side Level6 filter
      final filteredBooks =
          settings.ignoreLevel6
              ? result.books.where((b) => b.level != 6).toList()
              : result.books;

      if (mounted) {
        setState(() {
          _books.addAll(filteredBooks);
          _currentPage = nextPage;
          _totalPages = result.totalPages;
          _loadingMore = false;
        });
      }
    } catch (e) {
      _logger.severe('Failed to load more books: $e');
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('最近更新')),
      body: RefreshIndicator(
        onRefresh: () => _fetchBooks(refresh: true),
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _books.isEmpty
                ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.update_disabled,
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
                  itemCount: _books.length + (_loadingMore ? 3 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _books.length) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final book = _books[index];
                    return _buildBookCard(context, book);
                  },
                ),
      ),
    );
  }

  Widget _buildBookCard(BuildContext context, Book book) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroTag = 'recent_cover_${book.id}';

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
                  // Book type badge (inside Hero)
                  if (ref
                      .watch(settingsProvider)
                      .isBookTypeBadgeEnabled('recent'))
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
