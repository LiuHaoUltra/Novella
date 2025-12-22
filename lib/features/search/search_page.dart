import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/src/widgets/book_type_badge.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _logger = Logger('SearchPage');
  final _bookService = BookService();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  // State
  List<String> _history = [];
  List<Book> _results = [];
  int _currentPage = 1;
  int _totalPages = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasSearched = false;
  String? _pendingDeleteItem;
  String _lastKeyword = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _scrollController.addListener(_onScroll);
    // Auto focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
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

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    setState(() {
      _history = history;
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', _history);
  }

  void _addToHistory(String keyword) {
    if (keyword.isEmpty) return;
    setState(() {
      // Remove if exists, then add to front
      _history.remove(keyword);
      _history.insert(0, keyword);
      // Keep max 20 items
      if (_history.length > 20) {
        _history = _history.sublist(0, 20);
      }
    });
    _saveHistory();
  }

  void _removeFromHistory(String keyword) {
    setState(() {
      _history.remove(keyword);
      _pendingDeleteItem = null;
    });
    _saveHistory();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('清空搜索历史'),
            content: const Text('确定要清空所有搜索记录吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      setState(() {
        _history.clear();
      });
      _saveHistory();
    }
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    _addToHistory(keyword);
    _lastKeyword = keyword;

    setState(() {
      _loading = true;
      _hasSearched = true;
      _results = [];
      _currentPage = 1;
      _totalPages = 0;
    });

    try {
      final settings = ref.read(settingsProvider);
      final result = await _bookService.searchBooks(
        keyword,
        page: 1,
        size: 24,
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      // Client-side Level6 filter
      final filteredBooks =
          settings.ignoreLevel6
              ? result.books.where((b) => b.level != 6).toList()
              : result.books;
      setState(() {
        _results = filteredBooks;
        _currentPage = result.currentPage;
        _totalPages = result.totalPages;
        _loading = false;
      });
    } catch (e) {
      _logger.severe('Search failed: $e');
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('搜索失败')));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_lastKeyword.isEmpty) return;

    setState(() => _loadingMore = true);

    try {
      final settings = ref.read(settingsProvider);
      final nextPage = _currentPage + 1;
      final result = await _bookService.searchBooks(
        _lastKeyword,
        page: nextPage,
        size: 24,
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
          _results.addAll(filteredBooks);
          _currentPage = nextPage;
          _totalPages = result.totalPages;
          _loadingMore = false;
        });
      }
    } catch (e) {
      _logger.severe('Load more failed: $e');
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _onHistoryTap(String keyword) {
    // Cancel any pending delete first
    if (_pendingDeleteItem != null && _pendingDeleteItem != keyword) {
      setState(() {
        _pendingDeleteItem = null;
      });
      return;
    }
    // Dismiss keyboard before searching
    FocusScope.of(context).unfocus();
    _searchController.text = keyword;
    _search();
  }

  void _onHistoryLongPress(String keyword) {
    setState(() {
      _pendingDeleteItem = keyword;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: '搜索书籍...',
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _search(),
            ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _hasSearched
              ? _buildSearchResults(colorScheme, textTheme)
              : _buildHistorySection(colorScheme, textTheme),
    );
  }

  Widget _buildHistorySection(ColorScheme colorScheme, TextTheme textTheme) {
    return GestureDetector(
      onTap: () {
        // Cancel pending delete when tapping empty area
        if (_pendingDeleteItem != null) {
          setState(() {
            _pendingDeleteItem = null;
          });
        }
      },
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '搜索历史',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_history.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearHistory,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // History chips
            if (_history.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '暂无搜索记录',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _history.map((keyword) {
                      final isPendingDelete = _pendingDeleteItem == keyword;
                      return GestureDetector(
                        onTap: () {
                          if (isPendingDelete) {
                            _removeFromHistory(keyword);
                          } else {
                            _onHistoryTap(keyword);
                          }
                        },
                        onLongPress: () => _onHistoryLongPress(keyword),
                        child: Chip(
                          label: Text(
                            isPendingDelete ? '删除?' : keyword,
                            style: TextStyle(
                              color:
                                  isPendingDelete
                                      ? colorScheme.error
                                      : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          backgroundColor:
                              isPendingDelete
                                  ? colorScheme.errorContainer
                                  : colorScheme.surfaceContainerHighest,
                          side: BorderSide.none,
                        ),
                      );
                    }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme colorScheme, TextTheme textTheme) {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '没有找到相关书籍',
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.58,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: _results.length + (_loadingMore ? 3 : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final book = _results[index];
        return _buildBookCard(context, book);
      },
    );
  }

  Widget _buildBookCard(BuildContext context, Book book) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroTag = 'search_cover_${book.id}';

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
                      .isBookTypeBadgeEnabled('search'))
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
