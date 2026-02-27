import 'dart:math' as math;

import 'package:novella/src/widgets/book_cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/src/widgets/book_type_badge.dart';
import 'package:novella/src/widgets/book_cover_previewer.dart';

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

  final List<Book> _allValidBooks = [];
  bool _loading = true;
  int _currentFrontendPage = 1;
  int _nextBackendPage = 1;
  bool _hasReachedEnd = false;
  static const int _pageSize = 24; // 匹配后端限制/建议

  @override
  void initState() {
    super.initState();
    _fetchPage(1, isRefresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int frontendPage, {bool isRefresh = false}) async {
    final settings = ref.read(settingsProvider);

    if (isRefresh) {
      _allValidBooks.clear();
      _nextBackendPage = 1;
      _hasReachedEnd = false;
    }

    setState(() => _loading = true);

    try {
      int targetValidCount = frontendPage * _pageSize;

      // 如果当前积累的有效书籍不够这一页，且后端还没到底，则继续向后端请求
      while (_allValidBooks.length < targetValidCount && !_hasReachedEnd) {
        final result = await _bookService.getBookList(
          page: _nextBackendPage,
          size: _pageSize,
          order: 'latest',
          ignoreJapanese: settings.ignoreJapanese,
          ignoreAI: settings.ignoreAI,
        );

        final validBooks =
            settings.ignoreLevel6
                ? result.books.where((b) => b.level != 6).toList()
                : result.books;

        _allValidBooks.addAll(validBooks);

        if (_nextBackendPage >= result.totalPages || result.books.isEmpty) {
          _hasReachedEnd = true;
          break;
        } else {
          _nextBackendPage++;
        }
      }

      if (mounted) {
        setState(() {
          _currentFrontendPage = frontendPage;
          _loading = false;
        });

        // 翻页或者刷新时回到顶部
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
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

  bool get _canGoNext {
    if (!_hasReachedEnd) return true;
    int maxPages = (_allValidBooks.length / _pageSize).ceil();
    return _currentFrontendPage < maxPages;
  }

  Widget _buildPagination() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.tonalIcon(
            onPressed:
                _currentFrontendPage > 1 && !_loading
                    ? () => _fetchPage(_currentFrontendPage - 1)
                    : null,
            icon: const Icon(Icons.navigate_before),
            label: const Text('上一页'),
          ),
          const SizedBox(width: 16),
          Text(
            '第 $_currentFrontendPage 页',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.tonalIcon(
            onPressed:
                _canGoNext && !_loading
                    ? () => _fetchPage(_currentFrontendPage + 1)
                    : null,
            icon: const Icon(Icons.navigate_next),
            label: const Text('下一页'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final startIndex = (_currentFrontendPage - 1) * _pageSize;
    final endIndex = math.min(startIndex + _pageSize, _allValidBooks.length);
    final displayBooks =
        startIndex < _allValidBooks.length
            ? _allValidBooks.sublist(startIndex, endIndex)
            : <Book>[];

    return Scaffold(
      appBar: AppBar(title: const Text('最近更新')),
      body: RefreshIndicator(
        onRefresh: () => _fetchPage(1, isRefresh: true),
        child:
            _loading
                ? const Center(child: M3ELoadingIndicator())
                : displayBooks.isEmpty
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
                : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.58,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 12,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _buildBookCard(context, displayBooks[index]);
                        }, childCount: displayBooks.length),
                      ),
                    ),
                    if (_allValidBooks.isNotEmpty)
                      SliverToBoxAdapter(child: _buildPagination()),
                    // 给底部留点安全边距
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.paddingOf(context).bottom,
                      ),
                    ),
                  ],
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
                    child: BookCoverPreviewer(
                      coverUrl: book.cover,
                      child: BookCoverImage(
                        imageUrl: book.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                  // 书籍类型角标（Hero 内部）
                  if (ref
                      .watch(settingsProvider)
                      .isBookTypeBadgeEnabled('recent'))
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
