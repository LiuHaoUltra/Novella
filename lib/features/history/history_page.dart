import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/user_service.dart';
import 'package:novella/features/book/book_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _logger = Logger('HistoryPage');
  final _userService = UserService();
  final _bookService = BookService();

  List<Book> _books = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory({bool force = false}) async {
    if (!force && !_loading) {
      setState(() => _loading = true);
    }

    try {
      // Get book IDs from history
      final bookIds = await _userService.getReadHistory();

      if (bookIds.isEmpty) {
        setState(() {
          _books = [];
          _loading = false;
          _error = null;
        });
        return;
      }

      // Fetch book details for those IDs
      final books = await _bookService.getBooksByIds(bookIds);

      // Sort books by their order in history (most recent first)
      final sortedBooks = <Book>[];
      for (final id in bookIds) {
        final book = books.cast<Book?>().firstWhere(
          (b) => b?.id == id,
          orElse: () => null,
        );
        if (book != null) {
          sortedBooks.add(book);
        }
      }

      if (mounted) {
        setState(() {
          _books = sortedBooks;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      _logger.severe('Failed to fetch history: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('清空历史记录'),
            content: const Text('确定要清空所有阅读历史吗？此操作不可恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      final success = await _userService.clearReadHistory();
      if (success && mounted) {
        setState(() => _books = []);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已清空历史记录')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(context, colorScheme, textTheme),
            // Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _fetchHistory(force: true),
                child: _buildContent(context, colorScheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '历史',
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              // Clear button (moved first)
              if (_books.isNotEmpty)
                IconButton(
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '清空历史',
                ),
              // Refresh button (moved second)
              IconButton(
                onPressed: () => _fetchHistory(force: true),
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('加载失败', style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _fetchHistory(force: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_books.isEmpty) {
      return LayoutBuilder(
        builder:
            (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withAlpha(100),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无阅读记录',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      );
    }

    // Grid of books
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.58,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: _books.length,
      itemBuilder: (context, index) => _buildBookItem(_books[index]),
    );
  }

  Widget _buildBookItem(Book book) {
    final colorScheme = Theme.of(context).colorScheme;

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
                    ),
              ),
            )
            .then((_) {
              // Refresh history when returning from book detail
              if (mounted) {
                _fetchHistory(force: true);
              }
            });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cover
          Expanded(
            child: Hero(
              tag: 'cover_${book.id}',
              child: Card(
                elevation: 2,
                shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    book.cover.isNotEmpty
                        ? CachedNetworkImage(
                          imageUrl: book.cover,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder:
                              (_, __) => Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: Center(
                                  child: Icon(
                                    Icons.book_outlined,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          errorWidget:
                              (_, __, ___) => Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                        )
                        : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Center(
                            child: Icon(
                              Icons.book_outlined,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
              ),
            ),
          ),
          // Title - Fixed height container to prevent cover ratio issues
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
