import 'package:novella/src/widgets/book_cover_image.dart';
import 'package:novella/core/utils/cover_url_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/sync/sync_manager.dart';
import 'package:novella/data/services/book_info_cache_service.dart';
import 'package:novella/data/services/book_mark_service.dart';
import 'package:novella/data/services/book_service.dart';
import 'package:novella/data/services/reading_progress_service.dart';
import 'package:novella/data/services/user_service.dart';
import 'package:novella/data/services/local_cover_service.dart';
import 'package:novella/features/reader/reader_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/data/models/comment.dart';
import 'package:novella/features/comment/comment_page.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';
import 'package:novella/src/widgets/book_cover_previewer.dart';

/// 骨架屏加载效果组件
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 4,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 书籍详情信息
class BookInfo {
  final int id;
  final String title;
  final String cover;
  final String author;
  final String introduction;
  final DateTime lastUpdatedAt;
  final String? lastUpdatedChapter;
  final int favorite;
  final int views;
  final bool canEdit;
  final List<ChapterInfo> chapters;
  final UserInfo? user;
  // 服务端返回的阅读进度
  final ServerReadPosition? serverReadPosition;

  BookInfo({
    required this.id,
    required this.title,
    required this.cover,
    required this.author,
    required this.introduction,
    required this.lastUpdatedAt,
    this.lastUpdatedChapter,
    required this.favorite,
    required this.views,
    required this.canEdit,
    required this.chapters,
    this.user,
    this.serverReadPosition,
  });

  factory BookInfo.fromJson(Map<dynamic, dynamic> json) {
    final book = json['Book'] as Map<dynamic, dynamic>? ?? json;
    final chapterList =
        (book['Chapter'] as List?)
            ?.map((e) => ChapterInfo.fromJson(e as Map<dynamic, dynamic>))
            .toList() ??
        [];

    // 解析服务端返回的阅读进度
    ServerReadPosition? readPos;
    final posData = json['ReadPosition'];
    if (posData != null && posData is Map) {
      readPos = ServerReadPosition.fromJson(posData);
    }

    return BookInfo(
      id: book['Id'] as int? ?? 0,
      title: book['Title'] as String? ?? 'Unknown',
      cover: book['Cover'] as String? ?? '',
      author: book['Author'] as String? ?? 'Unknown',
      introduction: book['Introduction'] as String? ?? '',
      lastUpdatedAt:
          DateTime.tryParse(book['LastUpdatedAt']?.toString() ?? '') ??
          DateTime.now(),
      lastUpdatedChapter: book['LastUpdatedChapter'] as String?,
      favorite: book['Favorite'] as int? ?? 0,
      views: book['Views'] as int? ?? 0,
      canEdit: book['CanEdit'] as bool? ?? false,
      chapters: chapterList,
      user: book['User'] != null ? UserInfo.fromJson(book['User']) : null,
      serverReadPosition: readPos,
    );
  }
}

/// 服务端阅读进度结构
class ServerReadPosition {
  final int? chapterId;
  final String? position; // XPath or scroll position string

  ServerReadPosition({this.chapterId, this.position});

  factory ServerReadPosition.fromJson(Map<dynamic, dynamic> json) {
    return ServerReadPosition(
      chapterId: json['ChapterId'] as int?,
      position: json['Position'] as String?,
    );
  }
}

class ChapterInfo {
  final int id;
  final String title;

  ChapterInfo({required this.id, required this.title});

  factory ChapterInfo.fromJson(Map<dynamic, dynamic> json) {
    return ChapterInfo(
      id: json['Id'] as int? ?? 0,
      title: json['Title'] as String? ?? '',
    );
  }
}

class UserInfo {
  final int id;
  final String userName;
  final String avatar;

  UserInfo({required this.id, required this.userName, required this.avatar});

  factory UserInfo.fromJson(Map<dynamic, dynamic> json) {
    return UserInfo(
      id: json['Id'] as int? ?? 0,
      userName: json['UserName'] as String? ?? '',
      avatar: json['Avatar'] as String? ?? '',
    );
  }
}

class BookDetailPage extends ConsumerStatefulWidget {
  final int bookId;
  final String? initialCoverUrl;
  final String? initialTitle;
  final String? heroTag;

  const BookDetailPage({
    super.key,
    required this.bookId,
    this.initialCoverUrl,
    this.initialTitle,
    this.heroTag,
  });

  @override
  ConsumerState<BookDetailPage> createState() => BookDetailPageState();
}

class BookDetailPageState extends ConsumerState<BookDetailPage> {
  final _logger = Logger('BookDetailPage');
  final _bookService = BookService();
  final _progressService = ReadingProgressService();
  final _userService = UserService();
  final _bookMarkService = BookMarkService();
  final _cacheService = BookInfoCacheService();
  final _localCoverService = LocalCoverService(); // 封面物理持久化服务

  // 本地标记状态
  BookMarkStatus _currentMark = BookMarkStatus.none;

  // 颜色提取缓存（静态共享）
  // 键格式："bookId_dark" 或 "bookId_light"
  static final Map<String, List<Color>> _colorCache = {};
  // ColorScheme 缓存（静态共享）
  static final Map<String, ColorScheme> _schemeCache = {};

  // 监听亮度变化以更新主题
  Brightness? _currentBrightness;

  /// 清除所有颜色缓存
  static void clearColorCache() {
    _colorCache.clear();
    _schemeCache.clear();
  }

  // 静态缓存当前书籍信息供 ReaderPage 使用
  // 退出详情页时自动释放
  static String? cachedBookName;
  static List<ChapterInfo>? cachedChapterList;

  /// 清除阅读器缓存
  static void clearReaderCache() {
    cachedBookName = null;
    cachedChapterList = null;
  }

  BookInfo? _bookInfo;
  ReadPosition? _readPosition;
  bool _loading = true;
  bool _isInShelf = false;
  bool _shelfLoading = false;
  String? _error;

  // Gradient colors extracted from cover
  List<Color>? _gradientColors;
  bool _coverLoadFailed = false;
  bool _colorsExtracted = false; // Track if we already extracted colors

  // 从阅读器返回后的短暂窗口：优先展示本地刚更新的进度，避免服务端进度延迟导致按钮不更新或回退
  DateTime? _suppressServerPositionUntil;

  // 基于封面的动态配色方案
  ColorScheme? _dynamicColorScheme;

  /// 格式化相对时间（仿 dayjs）
  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    final seconds = diff.inSeconds;
    final minutes = diff.inMinutes;
    final hours = diff.inHours;
    final days = diff.inDays;

    if (seconds < 45) {
      return '刚刚';
    } else if (seconds < 90) {
      return '1分钟前';
    } else if (minutes < 45) {
      return '$minutes分钟前';
    } else if (minutes < 90) {
      return '1小时前';
    } else if (hours < 22) {
      return '$hours小时前';
    } else if (hours < 36) {
      return '1天前';
    } else if (days < 26) {
      final roundedDays = (hours / 24).round(); // Use rounding like dayjs
      return '$roundedDays天前';
    } else if (days < 46) {
      return '1个月前';
    } else if (days < 320) {
      final months = (days / 30.4).round(); // Average days per month
      return '$months个月前';
    } else if (days < 548) {
      return '1年前';
    } else {
      final years = (days / 365.25).round(); // Account for leap years
      return '$years年前';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBookInfo();
  }

  @override
  void dispose() {
    // 退出详情页时清除阅读器缓存
    clearReaderCache();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    if (_currentBrightness == null) {
      // 首次调用：尝试恢复缓存或提取颜色
      _tryRestoreCachedColors(isDark);
      if (!_colorsExtracted) {
        final coverUrl = widget.initialCoverUrl ?? _bookInfo?.cover;
        if (coverUrl != null && coverUrl.isNotEmpty) {
          _extractColors(coverUrl, isDark);
        }
      }
    } else if (_currentBrightness != brightness) {
      // 主题变化：重新提取
      _logger.info(
        'Theme changed from $_currentBrightness to $brightness, re-extracting colors',
      );
      _gradientColors = null;
      _dynamicColorScheme = null;
      _colorsExtracted = false;
      final coverUrl = widget.initialCoverUrl ?? _bookInfo?.cover;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        _extractColors(coverUrl, isDark);
      }
    }
    _currentBrightness = brightness;
  }

  /// 尝试同步恢复缓存颜色
  void _tryRestoreCachedColors(bool isDark) {
    final cacheKey = '${widget.bookId}_${isDark ? 'dark' : 'light'}';

    if (_colorCache.containsKey(cacheKey) &&
        _schemeCache.containsKey(cacheKey)) {
      _gradientColors = _colorCache[cacheKey]!;
      _dynamicColorScheme = _schemeCache[cacheKey]!;
      _colorsExtracted = true;
    }
  }

  /// 根据主题调整颜色以提升质感
  Color _adjustColorForTheme(Color color, bool isDark) {
    final hsl = HSLColor.fromColor(color);
    if (isDark) {
      // 深色模式：显著降低亮度
      // 保持 0.05-0.25 区间
      return hsl
          .withLightness((hsl.lightness * 0.4).clamp(0.05, 0.25))
          .withSaturation((hsl.saturation * 1.1).clamp(0.0, 1.0))
          .toColor();
    } else {
      // 浅色模式：提升亮度，柔化饱和度
      return hsl
          .withLightness((hsl.lightness * 0.8 + 0.3).clamp(0.5, 0.85))
          .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.8))
          .toColor();
    }
  }

  /// 从封面 BlurHash 提取主色调生成渐变背景
  void _extractColors(String coverUrl, bool isDark) {
    final settings = ref.read(settingsProvider);
    // 如果禁用了封面取色，则不执行
    if (!settings.coverColorExtraction) {
      return;
    }

    if (coverUrl.isEmpty) {
      setState(() => _coverLoadFailed = true);
      return;
    }

    // 优先检查缓存
    final cacheKey = '${widget.bookId}_${isDark ? 'dark' : 'light'}';
    if (_colorCache.containsKey(cacheKey) &&
        _schemeCache.containsKey(cacheKey)) {
      _gradientColors = _colorCache[cacheKey]!;
      _dynamicColorScheme = _schemeCache[cacheKey]!;
      _colorsExtracted = true;
      if (mounted) setState(() {});
      return;
    }

    // 从 BlurHash DC 分量同步提取主色
    final seedColor = CoverUrlUtils.extractSeedColor(coverUrl);
    if (seedColor == null) {
      return;
    }

    // 构建渐变色
    final color1 = _adjustColorForTheme(seedColor, isDark);
    final color2 = _adjustColorForTheme(
      Color.lerp(seedColor, isDark ? Colors.black : Colors.white, 0.4)!,
      isDark,
    );
    final middleColor = Color.lerp(color1, color2, 0.5)!;
    final adjustedColors = [color1, middleColor, color2];

    // 缓存渐变色
    _colorCache[cacheKey] = List.from(adjustedColors);

    // 生成 ColorScheme
    final dynamicScheme = ColorScheme.fromSeed(
      seedColor: color1,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
    _schemeCache[cacheKey] = dynamicScheme;

    if (mounted) {
      setState(() {
        _gradientColors = adjustedColors;
        _dynamicColorScheme = dynamicScheme;
      });
    }
    _colorsExtracted = true;
  }

  Future<void> _loadBookInfo({bool forceRefresh = false}) async {
    final settings = ref.read(settingsProvider);

    // 尝试使用缓存
    if (!forceRefresh && settings.bookDetailCacheEnabled) {
      final cached = _cacheService.get(widget.bookId);
      if (cached != null) {
        // 使用缓存数据并刷新进度
        _bookInfo = cached;
        // 关键：即使使用缓存，也要优先采用服务端章节进度作为权威源。
        // 本地仅用于同章时保留章节内 scroll。
        await _refreshReadingProgress();
        if (mounted && _loading) {
          setState(() => _loading = false);
        }
        // 必要时提取颜色
        if (mounted && !_colorsExtracted && _gradientColors == null) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          _extractColors(cached.cover, isDark);
        }

        // 后台同步最新数据
        // 确保多端同步生效
        _fetchServerDataInBackground();
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await _bookService.getBookInfo(widget.bookId);
      // 触发封面保存
      _localCoverService.saveCover(info.id, info.cover);

      // 尝试从双源获取进度
      ReadPosition? position;

      // 1. 尝试使用服务端返回的进度
      if (info.serverReadPosition != null &&
          info.serverReadPosition!.chapterId != null) {
        final serverChapterId = info.serverReadPosition!.chapterId!;

        // 在章节列表中查找 sortNum
        int? sortNum;
        double scrollPosition = 0.0;

        for (int i = 0; i < info.chapters.length; i++) {
          if (info.chapters[i].id == serverChapterId) {
            sortNum = i + 1; // sortNum is 1-indexed
            break;
          }
        }

        // 忽略服务端章节内位置（格式不兼容），仅同步章节ID
        scrollPosition = 0.0;

        if (sortNum != null) {
          position = ReadPosition(
            bookId: widget.bookId,
            chapterId: serverChapterId,
            sortNum: sortNum,
            scrollPosition: scrollPosition,
          );
          _logger.info(
            'Using server position: chapter $sortNum @ ${(scrollPosition * 100).toStringAsFixed(1)}%',
          );
        }
      }

      // 2. 获取本地进度
      final localPosition = await _progressService.getLocalScrollPosition(
        widget.bookId,
      );

      // 3. 进度决策：仅当服务端章节 > 本地章节时使用服务端
      if (position != null) {
        if (localPosition != null &&
            position.sortNum == localPosition.sortNum) {
          // 章节相同，优先使用本地（保留章节内位置）
          position = localPosition;
          _logger.info(
            'Using local position (same chapter): chapter ${position.sortNum}',
          );
        } else {
          // 章节不同（无论前后），使用服务端（位置归零）
          _logger.info(
            'Using server position (diff chapter): chapter ${position.sortNum}',
          );
        }
      } else {
        // 无服务端进度，使用本地
        position = localPosition;
        if (position != null) {
          _logger.info('Using local position: chapter ${position.sortNum}');
        }
      }

      // 确保加载书架状态
      await _userService.ensureInitialized();

      if (mounted) {
        // 检查主题以调整颜色
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // 加载本地标记
        final mark = await _bookMarkService.getBookMark(widget.bookId);
        setState(() {
          _bookInfo = info;
          _readPosition = position;
          _isInShelf = _userService.isInShelf(widget.bookId);
          _currentMark = mark;
          _loading = false;
        });
        // 若未提取则提取颜色
        if (!_colorsExtracted && _gradientColors == null) {
          _extractColors(info.cover, isDark);
        }
        // 缓存书籍信息
        if (settings.bookDetailCacheEnabled) {
          _cacheService.set(widget.bookId, info);
        }
        // 缓存书名和章节列表供 ReaderPage 使用
        cachedBookName = info.title;
        cachedChapterList = info.chapters;
      }
    } catch (e) {
      _logger.severe('Failed to load book info: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 仅刷新阅读进度（不请求书籍详情）
  Future<void> _refreshReadingProgress() async {
    try {
      // 本地进度（用于保留章节内 scroll）
      ReadPosition? localPosition = await _progressService
          .getLocalScrollPosition(widget.bookId);

      // 服务端章节进度（权威源）：从已加载/缓存的 _bookInfo 中提取
      ReadPosition? serverPosition;
      final info = _bookInfo;
      if (info != null &&
          info.serverReadPosition != null &&
          info.serverReadPosition!.chapterId != null) {
        final serverChapterId = info.serverReadPosition!.chapterId!;

        int? sortNum;
        for (int i = 0; i < info.chapters.length; i++) {
          if (info.chapters[i].id == serverChapterId) {
            sortNum = i + 1;
            break;
          }
        }

        if (sortNum != null) {
          serverPosition = ReadPosition(
            bookId: widget.bookId,
            chapterId: serverChapterId,
            sortNum: sortNum,
            scrollPosition: 0.0, // 服务端章节内位置不兼容，保持 0
          );
        }
      }

      // 章节号严格以服务端为准；仅当“同一章节”时才使用本地 scroll
      ReadPosition? effectivePosition;
      if (serverPosition != null) {
        if (localPosition != null &&
            localPosition.sortNum == serverPosition.sortNum) {
          effectivePosition = localPosition;
        } else {
          effectivePosition = serverPosition;
        }
      } else {
        effectivePosition = localPosition;
      }

      // 获取本地标记
      final mark = await _bookMarkService.getBookMark(widget.bookId);
      // 检查书架状态
      await _userService.ensureInitialized();

      if (mounted) {
        setState(() {
          _readPosition = effectivePosition;
          _isInShelf = _userService.isInShelf(widget.bookId);
          _currentMark = mark;
        });
      }
    } catch (e) {
      _logger.warning('Failed to refresh reading progress: $e');
    }
  }

  /// 后台拉取数据并选择性更新
  /// 对比详情字段，仅更新变更部分
  Future<void> _fetchServerDataInBackground() async {
    try {
      final info = await _bookService.getBookInfo(widget.bookId);

      if (!mounted || _bookInfo == null) return;

      final cached = _bookInfo!;
      bool needsUpdate = false;

      // 对比书籍信息
      final bool infoChanged =
          cached.title != info.title ||
          cached.author != info.author ||
          cached.introduction != info.introduction ||
          cached.cover != info.cover ||
          cached.favorite != info.favorite ||
          cached.views != info.views ||
          cached.lastUpdatedAt != info.lastUpdatedAt ||
          cached.lastUpdatedChapter != info.lastUpdatedChapter ||
          cached.chapters.length != info.chapters.length;

      if (infoChanged) {
        _logger.info('Background sync: book info changed, updating UI');
        needsUpdate = true;
      }

      // 提取服务端进度
      ReadPosition? serverPosition;
      if (info.serverReadPosition != null &&
          info.serverReadPosition!.chapterId != null) {
        final serverChapterId = info.serverReadPosition!.chapterId!;

        int? sortNum;
        double scrollPosition = 0.0;

        for (int i = 0; i < info.chapters.length; i++) {
          if (info.chapters[i].id == serverChapterId) {
            sortNum = i + 1;
            break;
          }
        }

        // 忽略服务端章节内位置（格式不兼容），仅同步章节ID
        scrollPosition = 0.0;

        if (sortNum != null) {
          serverPosition = ReadPosition(
            bookId: widget.bookId,
            chapterId: serverChapterId,
            sortNum: sortNum,
            scrollPosition: scrollPosition,
          );
        }
      }

      // 章节级进度权威源：服务端
      // 规则：若 serverPosition 存在，UI 章节号永远以 server 为准；
      // 仅当同章时，保留本地 scroll。
      bool positionChanged = false;
      ReadPosition? effectivePosition;
      if (serverPosition != null) {
        final localPos = await _progressService.getLocalScrollPosition(
          widget.bookId,
        );
        if (localPos != null && localPos.sortNum == serverPosition.sortNum) {
          effectivePosition = localPos;
        } else {
          effectivePosition = serverPosition;
        }

        if (_readPosition == null) {
          positionChanged = true;
        } else if (_readPosition!.sortNum != effectivePosition.sortNum ||
            _readPosition!.chapterId != effectivePosition.chapterId) {
          positionChanged = true;
        }
      }

      // 应用变更
      if (mounted && (needsUpdate || positionChanged)) {
        setState(() {
          if (needsUpdate) {
            _bookInfo = info;
          }
          if (positionChanged) {
            final suppressUntil = _suppressServerPositionUntil;
            final suppress =
                suppressUntil != null && DateTime.now().isBefore(suppressUntil);

            // 刚从阅读器返回时优先保持本地进度，避免服务端进度延迟导致按钮不更新或回退。
            if (!suppress) {
              _readPosition = effectivePosition;
            }
          }
        });
      }

      // 更新缓存
      final settings = ref.read(settingsProvider);
      if (settings.bookDetailCacheEnabled) {
        _cacheService.set(widget.bookId, info);
      }
    } catch (e) {
      _logger.warning('Background sync failed: $e');
      // 忽略错误（已有缓存）
    }
  }

  void _startReading({int sortNum = 1}) {
    // 获取封面 URL 用于阅读器动态色
    final coverUrl =
        widget.initialCoverUrl?.isNotEmpty == true
            ? widget.initialCoverUrl!
            : (_bookInfo?.cover ?? '');

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (_) => ReaderPage(
                  bid: widget.bookId,
                  sortNum: sortNum,
                  totalChapters: _bookInfo!.chapters.length,
                  coverUrl: coverUrl,
                  bookTitle: _bookInfo?.title ?? widget.initialTitle,
                ),
          ),
        )
        .then((_) {
          if (!mounted) return;

          // 1) 先用本地进度即时刷新按钮（同设备刚读完的反馈）
          // 2) 短暂抑制服务端章节号覆盖，避免服务端进度延迟造成“按钮不更新/又回退”
          _suppressServerPositionUntil = DateTime.now().add(
            const Duration(seconds: 8),
          );

          _refreshReadingProgressPreferLocal();

          // 静默拉取一次最新服务端数据（用于更新详情信息/服务端章节号）
          // ignore: unawaited_futures
          Future.microtask(() => _fetchServerDataInBackground());
        });
  }

  /// 从阅读器返回时优先采用本地进度（即时更新 UI）
  /// 注：章节号权威源仍然是服务端；这里只用于同设备的“立刻更新按钮”。
  Future<void> _refreshReadingProgressPreferLocal() async {
    try {
      final localPosition = await _progressService.getLocalScrollPosition(
        widget.bookId,
      );
      final mark = await _bookMarkService.getBookMark(widget.bookId);
      await _userService.ensureInitialized();

      if (mounted) {
        setState(() {
          _readPosition = localPosition;
          _isInShelf = _userService.isInShelf(widget.bookId);
          _currentMark = mark;
        });
      }
    } catch (e) {
      _logger.warning('Failed to refresh local reading progress: $e');
    }
  }

  void _continueReading() {
    final syncManager = SyncManager();

    // 检查是否开启了 Gist 同步但尚未完成
    if (syncManager.isConnected && syncManager.status == SyncStatus.syncing) {
      _showSyncWarningSheet();
      return;
    }

    final sortNum = _readPosition?.sortNum ?? 1;
    _startReading(sortNum: sortNum);
  }

  /// 显示同步未完成警告弹窗
  void _showSyncWarningSheet() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
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
                child: Row(
                  children: [
                    Icon(Icons.sync, color: colorScheme.tertiary),
                    const SizedBox(width: 12),
                    Text(
                      '同步进行中',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  '云端进度正在同步，现在进入阅读可能无法恢复到最新位置。',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.play_arrow, color: colorScheme.primary),
                title: const Text('继续阅读'),
                subtitle: const Text('忽略同步状态，立即进入'),
                onTap: () {
                  Navigator.pop(context);
                  final sortNum = _readPosition?.sortNum ?? 1;
                  _startReading(sortNum: sortNum);
                },
              ),
              ListTile(
                leading: Icon(Icons.hourglass_top, color: colorScheme.tertiary),
                title: const Text('等待同步'),
                subtitle: const Text('稍后再试'),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleShelf() async {
    setState(() => _shelfLoading = true);

    try {
      bool success;
      if (_isInShelf) {
        success = await _userService.removeFromShelf(widget.bookId);
      } else {
        success = await _userService.addToShelf(widget.bookId);
      }

      if (mounted && success) {
        setState(() {
          _isInShelf = !_isInShelf;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isInShelf ? '已加入书架' : '已移出书架'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _logger.severe('Failed to toggle shelf: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _shelfLoading = false);
      }
    }
  }

  /// 获取标记状态图标
  IconData _getMarkIcon(BookMarkStatus status) {
    switch (status) {
      case BookMarkStatus.none:
        return Icons.bookmark_border;
      case BookMarkStatus.toRead:
        return Icons.schedule;
      case BookMarkStatus.reading:
        return Icons.auto_stories;
      case BookMarkStatus.finished:
        return Icons.check_circle_outline;
    }
  }

  /// 显示标记状态底部菜单
  void _showMarkBookSheet() {
    // 检查是否已加入书架
    if (!_isInShelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先将书籍加入书架'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    '标记此书籍',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Subtitle
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '选择当前状态',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // Options
                _buildMarkOption(
                  context,
                  BookMarkStatus.toRead,
                  Icons.schedule,
                  '待读',
                  colorScheme,
                ),
                _buildMarkOption(
                  context,
                  BookMarkStatus.reading,
                  Icons.auto_stories,
                  '在读',
                  colorScheme,
                ),
                _buildMarkOption(
                  context,
                  BookMarkStatus.finished,
                  Icons.check_circle_outline,
                  '已读',
                  colorScheme,
                ),
                // Clear mark option if already marked
                if (_currentMark != BookMarkStatus.none)
                  _buildMarkOption(
                    context,
                    BookMarkStatus.none,
                    Icons.clear,
                    '清除标记',
                    colorScheme,
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  Widget _buildMarkOption(
    BuildContext context,
    BookMarkStatus status,
    IconData icon,
    String label,
    ColorScheme colorScheme,
  ) {
    final isSelected = _currentMark == status;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? colorScheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      trailing:
          isSelected ? Icon(Icons.check, color: colorScheme.primary) : null,
      onTap: () async {
        Navigator.pop(context);
        await _bookMarkService.setBookMark(widget.bookId, status);
        if (mounted) {
          setState(() {
            _currentMark = status;
          });
          if (status != BookMarkStatus.none) {
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text('已标记为${status.displayName}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check OLED black mode setting
    final settings = ref.watch(settingsProvider);
    final isOled =
        settings.oledBlack && Theme.of(context).brightness == Brightness.dark;

    // Use dynamic ColorScheme if available AND not in OLED mode
    // OLED mode uses system default colors for pure black experience
    // Also check coverColorExtraction setting
    final baseColorScheme = Theme.of(context).colorScheme;
    final colorScheme =
        (isOled ||
                _dynamicColorScheme == null ||
                !settings.coverColorExtraction)
            ? baseColorScheme
            : _dynamicColorScheme!;

    // 检查是否有封面需要提取颜色
    // 只要有初始封面或已加载的封面，且未失败，就认为需要等待
    final hasCover =
        (widget.initialCoverUrl != null &&
            widget.initialCoverUrl!.isNotEmpty) ||
        (_bookInfo?.cover != null && _bookInfo!.cover.isNotEmpty);

    // 是否需要等待颜色提取
    // 1. 尚未提取完成
    // 2. 封面加载未标记失败
    // 3. 确实有封面 URL (无封面则不等待)
    // 4. 非 OLED 模式 (OLED 模式不提取颜色)
    // 5. 开启了封面取色
    final shouldWaitColors =
        !_colorsExtracted &&
        !_coverLoadFailed &&
        hasCover &&
        !isOled &&
        settings.coverColorExtraction;

    // 加载中 OR 需要等待颜色提取时，显示预览/骨架屏
    // 这样可以防止内容先出来，背景后变色的闪烁
    if (_loading || shouldWaitColors) {
      // 如果没有任何封面信息且正在加载，也显示骨架屏
      if (widget.initialCoverUrl != null ||
          widget.initialTitle != null ||
          _loading) {
        return _buildThemedScaffold(
          context,
          colorScheme,
          _buildLoadingPreview(colorScheme),
          isOled: isOled,
        );
      }
    }

    return _buildThemedScaffold(
      context,
      colorScheme,
      _loading
          ? const Center(child: M3ELoadingIndicator())
          : _error != null
          ? _buildErrorView()
          : _buildContent(colorScheme),
      isOled: isOled,
    );
  }

  /// 动态配色可用时使用动画过渡
  /// 使用 AnimatedTheme 平滑过渡
  /// 缓存恢复时跳过动画防闪烁
  /// OLED 模式禁用动态配色
  Widget _buildThemedScaffold(
    BuildContext context,
    ColorScheme colorScheme,
    Widget body, {
    bool isOled = false,
  }) {
    // 已提取（缓存）则跳过动画
    // 防止导航闪烁
    final shouldAnimate = !_colorsExtracted || _dynamicColorScheme == null;

    // OLED 模式强制使用系统主题
    final effectiveColorScheme =
        isOled
            ? Theme.of(context).colorScheme
            : (_dynamicColorScheme ?? Theme.of(context).colorScheme);

    return AnimatedTheme(
      // 600ms 平滑淡入时长
      duration:
          shouldAnimate ? const Duration(milliseconds: 600) : Duration.zero,
      curve: Curves.easeInOutCubic,
      data: Theme.of(context).copyWith(colorScheme: effectiveColorScheme),
      child: Scaffold(body: body),
    );
  }

  Widget _buildLoadingPreview(ColorScheme colorScheme) {
    final settings = ref.watch(settingsProvider);
    final isOled =
        settings.oledBlack && Theme.of(context).brightness == Brightness.dark;
    final coverUrl = widget.initialCoverUrl ?? '';
    final title = widget.initialTitle ?? '';

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Stack(
              fit: StackFit.expand,
              children: [
                // 渐变背景或加载占位
                if (!isOled &&
                    _gradientColors != null &&
                    settings.coverColorExtraction)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _gradientColors!,
                      ),
                    ),
                  )
                else
                  Container(
                    color:
                        isOled
                            ? Colors.black
                            : Theme.of(context).scaffoldBackgroundColor,
                  ),
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(40),
                        Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withAlpha(120),
                        Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withAlpha(200),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                      stops: const [0.0, 0.3, 0.5, 0.7, 0.9, 1.0],
                    ),
                  ),
                ),
                // 封面标题预览
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Cover
                      Hero(
                        tag: widget.heroTag ?? 'cover_${widget.bookId}',
                        child: Container(
                          width: 100,
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(60),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child:
                                coverUrl.isNotEmpty
                                    ? BookCoverPreviewer(
                                      borderRadius: 8.0,
                                      coverUrl: coverUrl,
                                      child: BookCoverImage(
                                        imageUrl: coverUrl,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                    : Container(
                                      color:
                                          colorScheme.surfaceContainerHighest,
                                      child: const Center(
                                        child: Icon(
                                          Icons.menu_book_rounded,
                                          size: 40,
                                          color: Color(0xFF888888),
                                        ),
                                      ),
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (title.isNotEmpty)
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 8),
                            // 作者加载骨架
                            ShimmerBox(width: 80, height: 16, borderRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 内容骨架屏
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 元数据 Chips 骨架
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShimmerBox(width: 55, height: 26, borderRadius: 8),
                  ShimmerBox(width: 70, height: 26, borderRadius: 8),
                  ShimmerBox(width: 55, height: 26, borderRadius: 8),
                ],
              ),
              const SizedBox(height: 20),
              // 操作按钮骨架
              Row(
                children: [
                  ShimmerBox(width: 56, height: 56, borderRadius: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShimmerBox(
                      width: double.infinity,
                      height: 56,
                      borderRadius: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // 简介骨架
              ShimmerBox(width: double.infinity, height: 80, borderRadius: 16),
              const SizedBox(height: 24),
              // 列表区域骨架
              // 匹配下方视觉权重
              ShimmerBox(width: double.infinity, height: 300, borderRadius: 16),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('加载失败', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadBookInfo,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    final settings = ref.watch(settingsProvider);
    final isOled =
        settings.oledBlack && Theme.of(context).brightness == Brightness.dark;
    final book = _bookInfo!;
    // 复用封面 URL 利用缓存
    final coverUrl =
        widget.initialCoverUrl?.isNotEmpty == true
            ? widget.initialCoverUrl!
            : book.cover;

    return CustomScrollView(
      slivers: [
        // 现代风格头部（模糊背景+浮动封面）
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          stretch: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          // 调整右侧按钮边距以匹配左侧返回按钮视觉位置
          actionsPadding: const EdgeInsets.only(right: 12),
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Stack(
              fit: StackFit.expand,
              children: [
                // 提取色渐变背景或降级
                if (!isOled &&
                    _gradientColors != null &&
                    !_coverLoadFailed &&
                    settings.coverColorExtraction)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors:
                            _gradientColors!.length >= 3
                                ? [
                                  _gradientColors![0],
                                  Color.lerp(
                                    _gradientColors![0],
                                    _gradientColors![1],
                                    0.5,
                                  )!,
                                  _gradientColors![1],
                                  Color.lerp(
                                    _gradientColors![1],
                                    _gradientColors![2],
                                    0.5,
                                  )!,
                                  _gradientColors![2],
                                ]
                                : [
                                  _gradientColors!.first,
                                  Color.lerp(
                                    _gradientColors!.first,
                                    _gradientColors!.last,
                                    0.3,
                                  )!,
                                  Color.lerp(
                                    _gradientColors!.first,
                                    _gradientColors!.last,
                                    0.7,
                                  )!,
                                  _gradientColors!.last,
                                ],
                        stops:
                            _gradientColors!.length >= 3
                                ? const [0.0, 0.25, 0.5, 0.75, 1.0]
                                : const [0.0, 0.35, 0.65, 1.0],
                      ),
                    ),
                  )
                else
                  // 默认背景：使用 Scaffold 背景色
                  Container(
                    color:
                        isOled
                            ? Colors.black
                            : Theme.of(context).scaffoldBackgroundColor,
                  ),
                // 平滑过渡渐变遮罩
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
                        Theme.of(context).scaffoldBackgroundColor.withAlpha(40),
                        Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withAlpha(120),
                        Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withAlpha(200),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                      stops: const [0.0, 0.3, 0.5, 0.7, 0.9, 1.0],
                    ),
                  ),
                ),

                // 移除淡出层以增强对比
                // 封面标题层
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 浮动封面卡片
                      Hero(
                        tag: widget.heroTag ?? 'cover_${book.id}',
                        child: Container(
                          width: 100,
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(60),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child:
                                coverUrl.isEmpty
                                    ? Container(
                                      color: const Color(0xFF3A3A3A),
                                      child: const Center(
                                        child: Icon(
                                          Icons.menu_book_rounded,
                                          size: 40,
                                          color: Color(0xFF888888),
                                        ),
                                      ),
                                    )
                                    : BookCoverPreviewer(
                                      borderRadius: 8.0,
                                      coverUrl: coverUrl,
                                      child: BookCoverImage(
                                        imageUrl: coverUrl,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 标题与作者
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              book.title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (book.author.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                book.author,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (context) => CommentPage(
                          type: CommentType.booked,
                          id: widget.bookId,
                          title: book.title,
                        ),
                  ),
                );
              },
              icon: const Icon(Icons.comment_outlined),
              tooltip: '评论',
            ),
          ],
        ),

        // 内容区域
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 数据栏（极简 Chips）
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildMetaChip(
                      Icons.favorite_outline,
                      '${book.favorite}',
                      colorScheme,
                    ),
                    _buildMetaChip(
                      Icons.visibility_outlined,
                      '${book.views}',
                      colorScheme,
                    ),
                    _buildMetaChip(
                      Icons.library_books_outlined,
                      '${book.chapters.length} 章',
                      colorScheme,
                    ),
                    // 显示标记状态
                    if (_currentMark != BookMarkStatus.none)
                      _buildMetaChip(
                        _getMarkIcon(_currentMark),
                        _currentMark.displayName,
                        colorScheme,
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // 全宽现代风格操作按钮
                Row(
                  children: [
                    // 书架/标记开关
                    _shelfLoading
                        ? Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: M3ELoadingIndicator(size: 20),
                            ),
                          ),
                        )
                        : Material(
                          color:
                              _isInShelf
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: _toggleShelf,
                            onLongPress: _showMarkBookSheet,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              child: Icon(
                                _isInShelf
                                    ? Icons.bookmark
                                    : Icons.bookmark_outline,
                                color:
                                    _isInShelf
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    const SizedBox(width: 12),
                    // 阅读按钮
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _continueReading,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow_rounded, size: 22),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _readPosition != null
                                      ? (() {
                                        // 根据 ID 查找章节标题
                                        final chapter = book.chapters
                                            .cast<ChapterInfo?>()
                                            .firstWhere(
                                              (c) =>
                                                  c?.id ==
                                                  _readPosition!.chapterId,
                                              orElse: () => null,
                                            );
                                        if (chapter != null &&
                                            chapter.title.isNotEmpty) {
                                          String title = chapter.title;

                                          // 若开启则清洗标题
                                          final settings = ref.read(
                                            settingsProvider,
                                          );
                                          if (settings.cleanChapterTitle) {
                                            // 智能混合正则：
                                            // 处理 【第一话】 或非英文前缀
                                            // 处理 『「〈 分隔符
                                            // 保留纯英文标题
                                            final regex = RegExp(
                                              r'^\s*(?:【([^】]*)】.*|(?![a-zA-Z]+\s)([^\s『「〈]+)[\s『「〈].*)$',
                                            );
                                            final match = regex.firstMatch(
                                              title,
                                            );
                                            if (match != null) {
                                              // 合并分组
                                              final extracted =
                                                  (match.group(1) ?? '') +
                                                  (match.group(2) ?? '');
                                              if (extracted.isNotEmpty) {
                                                title = extracted;
                                              }
                                            }
                                          }

                                          // 截断长标题
                                          if (title.length > 15) {
                                            title =
                                                '${title.substring(0, 15)}...';
                                          }
                                          return '续读 · $title';
                                        }
                                        return '续读';
                                      })()
                                      : '开始阅读',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 简介（可展开）
                if (book.introduction.isNotEmpty) ...[
                  _buildSectionTitle('简介'),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _showFullIntro(context, book.introduction),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _stripHtml(book.introduction),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.6,
                          fontSize: 14,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Update info - subtle
                ...[
                  Builder(
                    builder: (context) {
                      final relativeTime = _formatRelativeTime(
                        book.lastUpdatedAt,
                      );
                      // Use last chapter from chapters list for accuracy
                      final lastChapterTitle =
                          book.chapters.isNotEmpty
                              ? book.chapters.last.title
                              : null;
                      final hasChapter =
                          lastChapterTitle != null &&
                          lastChapterTitle.isNotEmpty;
                      final displayText =
                          hasChapter
                              ? '最新: $relativeTime - $lastChapterTitle'
                              : '最新: $relativeTime';

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withAlpha(
                            128,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.update_outlined,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                displayText,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                // Chapter list header
                _buildSectionTitle('章节'),
              ],
            ),
          ),
        ),

        // Chapter list - clean and minimal
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final chapter = book.chapters[index];
              final sortNum = index + 1;
              final isCurrentChapter = _readPosition?.sortNum == sortNum;

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                leading: Container(
                  width: 32,
                  alignment: Alignment.center,
                  child: Text(
                    '$sortNum',
                    style: TextStyle(
                      color:
                          isCurrentChapter
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                      fontWeight:
                          isCurrentChapter ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                title: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrentChapter ? colorScheme.primary : null,
                    fontWeight: isCurrentChapter ? FontWeight.w600 : null,
                    fontSize: 14,
                  ),
                ),
                trailing:
                    isCurrentChapter
                        ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '当前',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                        : null,
                onTap: () => _startReading(sortNum: sortNum),
              );
            }, childCount: book.chapters.length),
          ),
        ),

        // Bottom safe area
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: 40 + MediaQuery.of(context).padding.bottom,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String value, ColorScheme colorScheme) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showFullIntro(BuildContext context, String intro) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder:
                (context, scrollController) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '简介',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        children: [
                          Text(
                            _stripHtml(intro),
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.8,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  /// Simple HTML tag stripper
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
  }
}
