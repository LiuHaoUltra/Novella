import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:novella/core/utils/cover_url_utils.dart';

/// 统一封面图片组件
///
/// 自动从 URL 提取 blurhash 作为加载占位符，
/// 无 blurhash 时回退到纯色 + 图标。
class BookCoverImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;

  const BookCoverImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final blurHash = CoverUrlUtils.extractBlurHash(imageUrl);

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      placeholder:
          (_, __) =>
              blurHash != null
                  ? BlurHash(hash: blurHash, imageFit: fit)
                  : Container(
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
    );
  }
}
