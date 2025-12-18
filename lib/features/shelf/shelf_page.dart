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
  int _selectedSortIndex = 0;

  // Sort tabs
  final List<String> _sortLabels = ['默认', '更新', '进度', '书名', '分类'];

  // Navigation
  String? _currentFolderId;
  final List<ShelfItem> _breadcrumbs = []; // Track folder history

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

      // 2. Get items for current folder and fetch book details
      // Use force: force to allow reading from cache
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
    // 2. Get items for current folder.
    // We fetch full shelf first to ensure cache is hot if forcing.
    if (force) {
      await _userService.getShelf(forceRefresh: true);
    }

    // Read from cache (or recently fetched)
    final items = _userService.getShelfItems(_currentFolderId);

    // 3. Extract book IDs and fetch details
    final bookIds =
        items
            .where((e) => e.type == ShelfItemType.book)
            .map((e) => e.id as int)
            .toList();

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
        _items = items;
        _loading = false;
        _lastRefreshTime = DateTime.now();
      });
    }
  }

  void _enterFolder(ShelfItem folder) {
    setState(() {
      _breadcrumbs.add(folder);
      _currentFolderId = folder.id as String;
    });
    // Navigation doesn't need to force refresh from server, just filter local cache
    _refreshGrid(force: false);
  }

  void _navigateBack() {
    if (_breadcrumbs.isEmpty) return;

    setState(() {
      _breadcrumbs.removeLast();
      _currentFolderId =
          _breadcrumbs.isEmpty ? null : _breadcrumbs.last.id as String;
    });
    // Navigation doesn't need to force refresh from server
    _refreshGrid(force: false);
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('新建文件夹'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '文件夹名称'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('创建'),
              ),
            ],
          ),
    );

    if (name != null && name.isNotEmpty) {
      final id = await _userService.createFolder(name);
      if (id != null) {
        // Optimistic refresh: update grid from local cache immediately
        _refreshGrid(force: false);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('创建失败或重名')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: _breadcrumbs.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _navigateBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Custom header
              _buildHeader(context, colorScheme, textTheme),

              // Sort tabs
              _buildSortTabs(context, colorScheme),

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
                              if (item.type == ShelfItemType.folder) {
                                return _buildFolderItem(item);
                              } else {
                                return _buildBookItem(item);
                              }
                            },
                          ),
                        ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          // Back button or title
          if (_breadcrumbs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _navigateBack,
            )
          else
            const SizedBox(width: 8),

          // Title
          Expanded(
            child: Text(
              _breadcrumbs.isEmpty ? '书架' : _breadcrumbs.last.title,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Action buttons
          if (_breadcrumbs.isEmpty) ...[
            TextButton.icon(
              onPressed: _createFolder,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('导入'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                // TODO: Implement select mode
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('选择功能开发中...')));
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('选择'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
              ),
            ),
          ],

          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchShelf(force: true),
          ),
        ],
      ),
    );
  }

  Widget _buildSortTabs(BuildContext context, ColorScheme colorScheme) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _sortLabels.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedSortIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextButton(
              onPressed: () {
                setState(() {
                  _selectedSortIndex = index;
                });
                // TODO: Implement actual sorting logic
              },
              style: TextButton.styleFrom(
                foregroundColor:
                    isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                _sortLabels[index],
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFolderItem(ShelfItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => _enterFolder(item),
      onLongPress: () => _showFolderOptions(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  Icons.folder_outlined,
                  size: 48,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 36, // Fixed height for 2 lines of text
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookItem(ShelfItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final book = _bookDetails[item.id];

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => BookDetailPage(
                  bookId: item.id as int,
                  initialCoverUrl: book?.cover,
                  initialTitle: book?.title,
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
                        child: const Center(child: CircularProgressIndicator()),
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

  void _showFolderOptions(ShelfItem item) {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    '删除文件夹',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteFolder(item);
                  },
                ),
              ],
            ),
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

  Future<void> _confirmDeleteFolder(ShelfItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('删除 "${item.title}"?'),
            content: const Text('文件夹内的书籍将被移动到书架根目录。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _userService.deleteFolder(item.id as String);
      // Optimistic refresh
      _refreshGrid(force: false);
    }
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
