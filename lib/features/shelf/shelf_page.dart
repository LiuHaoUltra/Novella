import 'package:novella/src/widgets/book_cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/data/models/book.dart';
import 'package:novella/data/services/book_mark_service.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/user_service.dart';
import 'package:novella/features/book/book_detail_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';
import 'package:novella/src/widgets/book_type_badge.dart';
import 'package:novella/src/widgets/book_cover_previewer.dart';

class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key});

  @override
  ConsumerState<ShelfPage> createState() => ShelfPageState();
}

class ShelfPageState extends ConsumerState<ShelfPage> {
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

  // 筛选状态 - 0: 默认（全部）, 1: 待读, 2: 在读, 3: 已读
  int _selectedFilter = 0;
  Set<int> _markedBookIds = {};

  // 多选状态
  bool _isMultiSelectMode = false;
  final Set<int> _selectedBookIds = {};

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

  /// 外部刷新书架的方法（静默刷新，无加载指示器）
  void refresh() {
    // 使用静默刷新避免显示加载转圈
    _refreshGrid(force: true);
  }

  Future<void> _fetchShelf({bool force = false}) async {
    if (!force &&
        _lastRefreshTime != null &&
        DateTime.now().difference(_lastRefreshTime!) <
            const Duration(seconds: 2)) {
      // 简短防抖
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // 1. 确保已初始化
      await _userService.ensureInitialized();

      // 2. 获取项目并拉取书籍详情
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
    // 如果强制刷新，先拉取完整书架以确保缓存是最新的
    if (force) {
      await _userService.getShelf(forceRefresh: true);
    }

    // 读取缓存（或最近拉取的数据） - 仅获取书籍（不含文件夹）
    final allItems = _userService.getShelfItems();
    final bookItems =
        allItems.where((e) => e.type == ShelfItemType.book).toList();

    // 提取书籍ID并拉取详情
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
        // 保持分页显示数量不倒退：
        // 从详情页返回时会触发刷新，如果这里强制重置为第一页（_pageSize），
        // 且用户当前滚动位置已加载超过一页，会出现“某本书突然消失、滚动后又出现”的错觉。
        // 典型场景：书架总数=25、_pageSize=24，则第25本书会在刷新后消失。
        final desiredCount = _displayedCount == 0 ? _pageSize : _displayedCount;
        _displayedCount = desiredCount.clamp(0, bookItems.length);
        _loading = false;
        _lastRefreshTime = DateTime.now();
      });
    }
  }

  void _loadMoreItems() {
    // 计算过滤后的项目以获取正确数量
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
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 自定义头部
            _buildHeader(context, colorScheme, textTheme),

            // 筛选标签页
            _buildFilterTabs(colorScheme),

            // 内容
            Expanded(
              child: Builder(
                builder: (context) {
                  // 计算过滤后的项目
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
                    return const Center(child: M3ELoadingIndicator());
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
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        settings.useIOS26Style ? 86 : 24,
                      ),
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
                          return const Center(child: M3ELoadingIndicator());
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
          // 标题
          Expanded(
            child: Text(
              '书架',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),

          // 删除按钮（仅在多选模式且有选中项时显示）
          if (_isMultiSelectMode && _selectedBookIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              color: Colors.red,
              onPressed: _confirmBatchDelete,
              tooltip: '删除所选 (${_selectedBookIds.length})',
            ),

          // 退出多选按钮（仅在多选模式显示）
          if (_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectedBookIds.clear();
                  _isMultiSelectMode = false;
                });
              },
              tooltip: '退出多选',
            ),

          // 进入多选按钮（仅在非多选模式显示）
          if (!_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: () => setState(() => _isMultiSelectMode = true),
              tooltip: '多选',
            ),

          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchShelf(force: true),
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }

  /// 构建筛选标签行
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

  /// 处理筛选标签切换
  Future<void> _onFilterChanged(int filterIndex) async {
    if (filterIndex == _selectedFilter) return;

    setState(() {
      _selectedFilter = filterIndex;
      _displayedCount = _pageSize; // 切换筛选时重置分页
    });

    // 非默认筛选时，从本地存储加载标记的书籍ID
    if (filterIndex > 0) {
      final status = BookMarkStatus.values[filterIndex];
      final markedIds = await _bookMarkService.getBooksWithStatus(status);
      if (mounted) {
        setState(() {
          _markedBookIds = markedIds;
        });
      }
    } else {
      // 重置为显示全部
      if (mounted) {
        setState(() {
          _markedBookIds = {};
        });
      }
    }
  }

  /// 获取筛选索引对应的图标
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

  /// 获取筛选索引对应的标签
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
        if (_isMultiSelectMode) {
          // 在多选模式下切换选中状态
          _toggleBookSelection(item.id as int);
        } else {
          // 正常跳转到详情页
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
          // 从详情页返回时刷新网格以反映更改
          _refreshGrid();
          // 如果筛选处于激活状态，也刷新标记的书籍ID
          if (_selectedFilter > 0) {
            final status = BookMarkStatus.values[_selectedFilter];
            final markedIds = await _bookMarkService.getBooksWithStatus(status);
            if (mounted) {
              setState(() {
                _markedBookIds = markedIds;
              });
            }
          }
        }
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 书籍封面图片
                        book == null
                            ? Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: const Center(child: M3ELoadingIndicator()),
                            )
                            : BookCoverPreviewer(
                              coverUrl: book.cover,
                              child: BookCoverImage(
                                imageUrl: book.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                        // 多选模式下选中书籍的红色遮罩
                        if (_isMultiSelectMode &&
                            _selectedBookIds.contains(item.id))
                          Container(
                            color: Colors.red.withValues(alpha: 0.6),
                            child: const Center(
                              child: Icon(
                                Icons.delete,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
            height: 36, // 固定高度容纳两行文字
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

  /// 在多选模式下切换书籍选中状态
  void _toggleBookSelection(int bookId) {
    setState(() {
      if (_selectedBookIds.contains(bookId)) {
        _selectedBookIds.remove(bookId);
      } else {
        _selectedBookIds.add(bookId);
      }
    });
  }

  /// 确认并执行批量删除
  Future<void> _confirmBatchDelete() async {
    final count = _selectedBookIds.length;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isDismissible: false,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  '移出书架',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '确定要将选中的 $count 本书移出书架吗？',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.delete, color: colorScheme.error),
                title: Text(
                  '确认移出',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () => Navigator.pop(context, true),
              ),
              ListTile(
                leading: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                title: const Text('取消'),
                onTap: () => Navigator.pop(context, false),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      for (final id in _selectedBookIds) {
        await _userService.removeFromShelf(id);
      }
      setState(() {
        _selectedBookIds.clear();
        _isMultiSelectMode = false;
      });
      _refreshGrid(force: false);
    }
  }
}
