import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:novella/core/utils/cover_url_utils.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';

/// 长按封面预览组件
///
/// 包裹封面组件，提供长按预览大图的功能
class BookCoverPreviewer extends StatefulWidget {
  final Widget child;
  final String? coverUrl;
  final double borderRadius;

  const BookCoverPreviewer({
    super.key,
    required this.child,
    required this.coverUrl,
    this.borderRadius = 12.0,
  });

  @override
  State<BookCoverPreviewer> createState() => _BookCoverPreviewerState();
}

class _BookCoverPreviewerState extends State<BookCoverPreviewer>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _showOverlay(BuildContext context) {
    if (widget.coverUrl == null || widget.coverUrl!.isEmpty) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // 背景模糊层
            Positioned.fill(
              child: FadeTransition(
                opacity: _animation,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.black.withValues(alpha: 0.7)),
                ),
              ),
            ),
            // 图片层
            Center(
              child: FadeTransition(
                opacity: _animation,
                child: ScaleTransition(
                  scale: _animation,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.9,
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      child: CachedNetworkImage(
                        imageUrl: widget.coverUrl!,
                        fit: BoxFit.contain,
                        placeholder: (context, url) {
                          final blurHash = CoverUrlUtils.extractBlurHash(
                            widget.coverUrl,
                          );
                          if (blurHash != null) {
                            return BlurHash(
                              hash: blurHash,
                              imageFit: BoxFit.contain,
                            );
                          }
                          return Container(
                            color: Colors.grey[800],
                            child: const Center(
                              child: M3ELoadingIndicator(color: Colors.white),
                            ),
                          );
                        },
                        errorWidget:
                            (context, url, error) => Container(
                              color: Colors.grey[800],
                              padding: const EdgeInsets.all(20),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.broken_image,
                                    color: Colors.white70,
                                    size: 48,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '加载失败',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      decoration: TextDecoration.none,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    _controller.forward();
  }

  void _removeOverlay() async {
    if (_overlayEntry != null) {
      await _controller.reverse();
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coverUrl == null || widget.coverUrl!.isEmpty) {
      return widget.child;
    }

    return GestureDetector(
      onLongPressStart: (_) => _showOverlay(context),
      onLongPressEnd: (_) => _removeOverlay(),
      // 同时也监听取消，例如手指划出区域或系统事件干扰
      onLongPressCancel: () => _removeOverlay(),
      child: widget.child,
    );
  }
}
