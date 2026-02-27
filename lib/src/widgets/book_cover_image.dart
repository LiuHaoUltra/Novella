import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:novella/core/utils/cover_url_utils.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';

/// 统一封面图片组件
///
/// 使用 Stack 分层避免 placeholder 切换闪烁：
/// 底层 BlurHash → 上层 CachedNetworkImage 加载完直接覆盖。
class BookCoverImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final bool showLoading;
  final Duration fadeInDuration;

  const BookCoverImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth = 350, // 列表格子的合理极限宽度，足以提供视网膜级清晰度同时节省超大原图内存
    this.memCacheHeight,
    this.showLoading = true,
    this.fadeInDuration = const Duration(milliseconds: 200),
  });

  @override
  State<BookCoverImage> createState() => _BookCoverImageState();
}

class _BookCoverImageState extends State<BookCoverImage> {
  int _retryCount = 0;

  @override
  void didUpdateWidget(BookCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _retryCount = 0;
    }
  }

  void _retry() {
    if (!mounted) return;
    CachedNetworkImage.evictFromCache(widget.imageUrl).then((_) {
      if (mounted) {
        setState(() {
          _retryCount++;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // extractBlurHash 内含完整验证，返回 null 表示无效
    final blurHash = CoverUrlUtils.extractBlurHash(widget.imageUrl);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 底层：BlurHash 占位（或纯色回退）
          if (blurHash != null)
            BlurHash(
              hash: blurHash,
              imageFit: widget.fit,
              decodingWidth: 32,
              decodingHeight: 48,
              color: Colors.transparent,
            )
          else
            Container(
              color: colorScheme.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  Icons.book_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          // 上层：真实图片
          CachedNetworkImage(
            key: ValueKey('${widget.imageUrl}_$_retryCount'),
            imageUrl: widget.imageUrl,
            fit: widget.fit,
            memCacheWidth: widget.memCacheWidth,
            memCacheHeight: widget.memCacheHeight,
            fadeInDuration: widget.fadeInDuration,
            placeholder:
                (_, __) =>
                    widget.showLoading
                        ? Center(
                          child: M3ELoadingIndicator(
                            color:
                                blurHash != null
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        )
                        : const SizedBox.shrink(),
            errorWidget: (_, __, ___) {
              // 出错时自动重试一次
              if (_retryCount == 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _retry();
                });
              }

              return GestureDetector(
                onTap: _retry, // 暴露给用户手动点击的二次机制
                behavior: HitTestBehavior.opaque,
                child: Container(
                  // 有 BlurHash 时底衬透明且只加薄遮罩层以透出 BlurHash
                  color:
                      blurHash != null
                          ? Colors.black.withValues(alpha: 0.15)
                          : colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color:
                          blurHash != null
                              ? Colors.white.withValues(alpha: 0.75)
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
