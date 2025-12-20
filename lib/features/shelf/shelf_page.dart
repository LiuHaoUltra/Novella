import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/user_service.dart';
import 'package:novella/features/book/book_detail_page.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  final _logger = Logger('ShelfPage');
  final _bookService = BookService();
  final _userService = UserService();

  // State
  List<ShelfItem> _items = [];
  final Map<int, Book> _bookDetails = {};
  bool _loading = true;
  DateTime? _lastRefreshTime;

  @override
  void initState() {
    super.initState();
    _userService.addListener(_onShelfChanged);
    _fetchShelf();
  }

  @override
  void dispose() {
    _userService.removeListener(_onShelfChanged);
    super.dispose();
  }

  void _onShelfChanged() {
    if (mounted) {
      _logger.info('Shelf update received, refreshing grid...');
      // Refresh local view from cache
      _refreshGrid(force: false);
    }
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
    final allItems = _userService.getShelfItems(null);
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
        _loading = false;
        _lastRefreshTime = DateTime.now();
      });
    }
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

            // Content
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_border,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '书架空空如也',
                              style: textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: () => _fetchShelf(force: true),
                        child: GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.58,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _buildBookItem(item);
                          },
                        ),
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
      },
      onLongPress: () => _showBookOptions(item, book?.title ?? 'Book'),
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
