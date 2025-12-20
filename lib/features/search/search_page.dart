import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novella/features/settings/settings_page.dart';

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

  // State
  List<String> _history = [];
  List<Book> _results = [];
  int _currentPage = 1;
  int _totalPages = 0;
  bool _loading = false;
  bool _hasSearched = false;
  String? _pendingDeleteItem;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Auto focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
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

  Future<void> _search({int page = 1}) async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    _addToHistory(keyword);

    setState(() {
      _loading = true;
      _hasSearched = true;
    });

    try {
      final settings = ref.read(settingsProvider);
      final result = await _bookService.searchBooks(
        keyword,
        page: page,
        size: 9,
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      setState(() {
        _results = result.books;
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

  void _onHistoryTap(String keyword) {
    // Cancel any pending delete first
    if (_pendingDeleteItem != null && _pendingDeleteItem != keyword) {
      setState(() {
        _pendingDeleteItem = null;
      });
      return;
    }
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

    return Column(
      children: [
        // Pagination controls (only show if more than 1 page)
        if (_totalPages > 1)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed:
                      _currentPage > 1
                          ? () => _search(page: _currentPage - 1)
                          : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_currentPage / $_totalPages',
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      _currentPage < _totalPages
                          ? () => _search(page: _currentPage + 1)
                          : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),

        // Results grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.58,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final book = _results[index];
              return _buildBookCard(context, book);
            },
          ),
        ),
      ],
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
