import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:novella/src/widgets/book_cover_image.dart';

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
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
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
                    height: MediaQuery.of(context).size.height * 0.65,
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
                    child: AspectRatio(
                      aspectRatio:
                          0.68, // 匹配绝大多数轻小说封面的物理黄金比例，保证加载前后由于约束突变而造成的先大后小抖动
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius,
                        ),
                        child: BookCoverImage(
                          imageUrl: widget.coverUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 1000, // 预览图保留高清解析度
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

  void _removeOverlay() {
    if (_overlayEntry != null) {
      if (!mounted) {
        _overlayEntry?.remove();
        _overlayEntry = null;
        return;
      }

      _controller.reverse().whenComplete(() {
        if (mounted) {
          _overlayEntry?.remove();
          _overlayEntry = null;
        }
      });
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
