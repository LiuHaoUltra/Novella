import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

const _defaultSize = 32;

/// Displays the blurhash [hash] and the fades into the [image] over the course
/// of [duration].
class BlurHash extends StatefulWidget {
  const BlurHash({
    super.key,
    required this.hash,
    this.color = Colors.blueGrey,
    this.imageFit = BoxFit.fill,
    this.decodingWidth = _defaultSize,
    this.decodingHeight = _defaultSize,
    this.image,
    this.onDecoded,
    this.onDisplayed,
    this.onReady,
    this.onStarted,
    this.duration = const Duration(milliseconds: 1000),
    this.httpHeaders = const {},
    this.curve = Curves.easeOut,
    this.errorBuilder,
    this.optimizationMode = BlurHashOptimizationMode.none,
  })  : assert(decodingWidth > 0),
        assert(decodingHeight != 0);

  /// Callback when hash is decoded
  final VoidCallback? onDecoded;

  /// Callback when hash is displayed.
  final VoidCallback? onDisplayed;

  /// Callback when image is downloaded
  final VoidCallback? onReady;

  /// Callback when image is downloaded
  final VoidCallback? onStarted;

  /// Hash to decode
  final String hash;

  /// Displayed background color before decoding
  final Color color;

  /// How to fit decoded & downloaded image
  final BoxFit imageFit;

  /// Decoding definition
  final int decodingWidth;

  /// Decoding definition
  final int decodingHeight;

  /// Remote resource to download
  final String? image;

  final Duration duration;

  final Curve curve;

  /// Http headers for secure call like bearer
  final Map<String, String> httpHeaders;

  /// Network image errorBuilder
  final ImageErrorWidgetBuilder? errorBuilder;

  /// The optimization mode to use for decoding
  final BlurHashOptimizationMode optimizationMode;

  @override
  BlurHashState createState() => BlurHashState();
}

class BlurHashState extends State<BlurHash> {
  ui.Image? _decodedImage;
  late bool loaded;
  late bool loading;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    _decodeImage();
    loaded = false;
    loading = false;
  }

  @override
  void didUpdateWidget(BlurHash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hash != oldWidget.hash ||
        widget.image != oldWidget.image ||
        widget.decodingWidth != oldWidget.decodingWidth ||
        widget.decodingHeight != oldWidget.decodingHeight ||
        widget.optimizationMode != oldWidget.optimizationMode) {
      _init();
    }
  }

  void _decodeImage() async {
    try {
      final image = await blurHashDecodeImage(
        blurHash: widget.hash,
        width: widget.decodingWidth,
        height: widget.decodingHeight,
        optimizationMode: widget.optimizationMode,
      );
      if (mounted) {
        final oldImage = _decodedImage;
        setState(() {
          _decodedImage = image;
        });
        oldImage?.dispose();
        widget.onDecoded?.call();
      } else {
        image.dispose();
      }
    } catch (_) {
      // Ignore
    }
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          buildBlurHashBackground(),
          if (widget.image != null) prepareDisplayedImage(widget.image!),
        ],
      );

  Widget prepareDisplayedImage(String image) => Image.network(
        image,
        fit: widget.imageFit,
        headers: widget.httpHeaders,
        errorBuilder: widget.errorBuilder,
        loadingBuilder: (context, img, loadingProgress) {
          // Download started
          if (loading == false) {
            loading = true;
            widget.onStarted?.call();
          }

          if (loadingProgress == null) {
            // Image is now loaded, trigger the event
            loaded = true;
            widget.onReady?.call();
            return _DisplayImage(
              duration: widget.duration,
              curve: widget.curve,
              onCompleted: () => widget.onDisplayed?.call(),
              child: img,
            );
          } else {
            return const SizedBox();
          }
        },
      );

  /// Decode the blurhash then display the resulting Image
  Widget buildBlurHashBackground() => _decodedImage != null
      ? RawImage(
          image: _decodedImage,
          fit: widget.imageFit,
          width: double.infinity,
          height: double.infinity,
        )
      : Container(color: widget.color);
}

// Inner display details & controls
class _DisplayImage extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final VoidCallback onCompleted;

  const _DisplayImage({
    this.duration = const Duration(milliseconds: 800),
    required this.curve,
    required this.onCompleted,
    required this.child,
  });

  @override
  _DisplayImageState createState() => _DisplayImageState();
}

class _DisplayImageState extends State<_DisplayImage>
    with SingleTickerProviderStateMixin {
  late Animation<double> opacity;
  late AnimationController controller;

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: opacity, child: widget.child);

  @override
  void initState() {
    super.initState();
    controller = AnimationController(duration: widget.duration, vsync: this);
    final curved = CurvedAnimation(parent: controller, curve: widget.curve);
    opacity = Tween<double>(begin: .0, end: 1.0).animate(curved);
    controller.forward();

    curved.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onCompleted.call();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
