import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_mark_service.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/user_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/src/widgets/book_type_badge.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => ShelfPageState();
}

class ShelfPageState extends State<ShelfPage> {
  final _logger = Logger('ShelfPage');
  final _bookService = BookService();
  final _userService = UserService();
  final _bookMarkService = BookMarkService();
  final _scrollController = ScrollController();

  // State
  List<ShelfItem> _items = [];
  final Map<int, Book> _bookDetails = {};
  bool _loading = true;
  bool _loadingMore = false;
  DateTime? _lastRefreshTime;
  int _displayedCount = 0;
  static const int _pageSize = 24;

  // Filter state - 0: default (all), 1: toRead, 2: reading, 3: finished
  int _selectedFilter = 0;
  Set<int> _markedBookIds = {};

  @override
  void initState() {
    super.initState();
    _userService.addListener(_onShelfChanged);
    _scrollController.addListener(_onScroll);
    _fetchShelf();
  }

  @override
  void dispose() {
    _userService.removeListener(_onShelfChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreItems();
    }
  }

  void _onShelfChanged() {
    if (mounted) {
      _logger.info('Shelf update received, refreshing grid...');
      // Refresh local view from cache
      _refreshGrid(force: false);
    }
  }

  /// Public method to refresh shelf from outside (silent, no loading indicator)
  void refresh() {
    // Use silent refresh to avoid showing loading spinner
    _refreshGrid(force: true);
  }

  Future<void> _fetchShelf({bool force = false}) async {
    if (!force &&
        _lastRefreshTime != null &&
        DateTime.now().difference(_lastRefreshTime!) <
            const Duration(seconds: 2)) {
      // Short debounce
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // 1. Ensure initialized
      await _userService.ensureInitialized();

      // 2. Get items and fetch book details
      await _refreshGrid(force: force);
    } catch (e) {
      _logger.severe('Error fetching shelf: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('加载失败')));
      }
    }
  }

  Future<void> _refreshGrid({bool force = false}) async {
    // Fetch full shelf first to ensure cache is hot if forcing.
    if (force) {
      await _userService.getShelf(forceRefresh: true);
    }

    // Read from cache (or recently fetched) - only get books (no folders)
    final allItems = _userService.getShelfItems();
    final bookItems =
        allItems.where((e) => e.type == ShelfItemType.book).toList();

    // Extract book IDs and fetch details
    final bookIds = bookItems.map((e) => e.id as int).toList();

    if (bookIds.isNotEmpty) {
      try {
        final books = await _bookService.getBooksByIds(bookIds);
        final bookMap = {for (var b in books) b.id: b};
        if (mounted) {
          setState(() {
            _bookDetails.addAll(bookMap);
          });
        }
      } catch (e) {
        _logger.warning('Failed to fetch book details: $e');
      }
    }

    if (mounted) {
      setState(() {
        _items = bookItems;
        _displayedCount = _pageSize.clamp(0, bookItems.length);
        _loading = false;
        _lastRefreshTime = DateTime.now();
      });
    }
  }

  void _loadMoreItems() {
    // Compute filtered items to get correct count
    final filteredItems =
        _selectedFilter == 0
            ? _items
            : _items.where((item) => _markedBookIds.contains(item.id)).toList();

    if (_loadingMore || _displayedCount >= filteredItems.length) return;

    setState(() => _loadingMore = true);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _displayedCount = (_displayedCount + _pageSize).clamp(
            0,
            filteredItems.length,
          );
          _loadingMore = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Custom header
            _buildHeader(context, colorScheme, textTheme),

            // Filter tabs
            _buildFilterTabs(colorScheme),

            // Content
            Expanded(
              child: Builder(
                builder: (context) {
                  // Compute filtered items
                  final allFilteredItems =
                      _selectedFilter == 0
                          ? _items
                          : _items
                              .where((item) => _markedBookIds.contains(item.id))
                              .toList();
                  final displayItems =
                      allFilteredItems.take(_displayedCount).toList();
                  final hasMore = _displayedCount < allFilteredItems.length;

                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (allFilteredItems.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedFilter == 0
                                ? Icons.bookmark_border
                                : _getFilterIcon(_selectedFilter),
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedFilter == 0
                                ? '书架空空如也'
                                : '没有标记为${_getFilterLabel(_selectedFilter)}的书籍',
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => _fetchShelf(force: true),
                    child: GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.58,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 12,
                          ),
                      itemCount:
                          displayItems.length +
                          (hasMore && _loadingMore ? 3 : 0),
                      itemBuilder: (context, index) {
                        if (index >= displayItems.length) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final item = displayItems[index];
                        return _buildBookItem(item);
                      },
                    ),
                  );
                },
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
        children: [
          // Title
          Expanded(
            child: Text(
              '书架',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),

          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchShelf(force: true),
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }

  /// Build the filter tabs row
  Widget _buildFilterTabs(ColorScheme colorScheme) {
    final labels = ['默认', '待读', '在读', '已读'];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = _selectedFilter == index;
          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _onFilterChanged(index),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color:
                        isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Handle filter tab change
  Future<void> _onFilterChanged(int filterIndex) async {
    if (filterIndex == _selectedFilter) return;

    setState(() {
      _selectedFilter = filterIndex;
      _displayedCount = _pageSize; // Reset pagination when filter changes
    });

    // For non-default filter, load marked book IDs from local storage
    if (filterIndex > 0) {
      final status = BookMarkStatus.values[filterIndex];
      final markedIds = await _bookMarkService.getBooksWithStatus(status);
      if (mounted) {
        setState(() {
          _markedBookIds = markedIds;
        });
      }
    } else {
      // Reset to show all
      if (mounted) {
        setState(() {
          _markedBookIds = {};
        });
      }
    }
  }

  /// Get icon for filter index
  IconData _getFilterIcon(int filterIndex) {
    switch (filterIndex) {
      case 1:
        return Icons.schedule;
      case 2:
        return Icons.auto_stories;
      case 3:
        return Icons.check_circle_outline;
      default:
        return Icons.bookmark_border;
    }
  }

  /// Get label for filter index
  String _getFilterLabel(int filterIndex) {
    switch (filterIndex) {
      case 1:
        return '待读';
      case 2:
        return '在读';
      case 3:
        return '已读';
      default:
        return '';
    }
  }

  Widget _buildBookItem(ShelfItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final book = _bookDetails[item.id];
    final heroTag = 'shelf_cover_${item.id}';

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => BookDetailPage(
                  bookId: item.id as int,
                  initialCoverUrl: book?.cover,
                  initialTitle: book?.title,
                  heroTag: heroTag,
                ),
          ),
        );
        // Refresh grid when returning from detail page to reflect any changes
        _refreshGrid();
        // Also refresh marked book IDs if filter is active
        if (_selectedFilter > 0) {
          final status = BookMarkStatus.values[_selectedFilter];
          final markedIds = await _bookMarkService.getBooksWithStatus(status);
          if (mounted) {
            setState(() {
              _markedBookIds = markedIds;
            });
          }
        }
      },
      onLongPress: () => _showBookOptions(item, book?.title ?? 'Book'),
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
                    child:
                        book == null
                            ? Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                            : CachedNetworkImage(
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
                  Consumer(
                    builder: (context, ref, _) {
                      if (ref
                          .watch(settingsProvider)
                          .isBookTypeBadgeEnabled('shelf')) {
                        return BookTypeBadge(category: book?.category);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 36, // Fixed height for 2 lines of text
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
              child: Text(
                book?.title ?? '',
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

  void _showBookOptions(ShelfItem item, String title) {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.playlist_remove, color: Colors.red),
                  title: const Text(
                    '移出书架',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmRemoveBook(item, title);
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _confirmRemoveBook(ShelfItem item, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('移出 "$title"?'),
            content: const Text('确定要将这本书移出书架吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移出'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _userService.removeFromShelf(item.id as int);
      // Optimistic refresh
      _refreshGrid(force: false);
    }
  }
}
