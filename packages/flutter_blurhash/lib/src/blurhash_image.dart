import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

const _defaultSize = 32;

class BlurHashImage extends ImageProvider<BlurHashImage> {
  /// Creates an object that decodes a [blurHash] as an image.
  ///
  /// The arguments must not be null.
  const BlurHashImage(this.blurHash,
      {this.decodingWidth = _defaultSize,
      this.decodingHeight = _defaultSize,
      this.scale = 1.0});

  /// The bytes to decode into an image.
  final String blurHash;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

  /// Decoding definition
  final int decodingWidth;

  /// Decoding definition
  final int decodingHeight;

  @override
  Future<BlurHashImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<BlurHashImage>(this);

  @override
  ImageStreamCompleter loadImage(
          BlurHashImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_loadAsync(key));

  Future<ImageInfo> _loadAsync(BlurHashImage key) async {
    assert(key == this);

    final image = await blurHashDecodeImage(
      blurHash: blurHash,
      width: decodingWidth,
      height: decodingHeight,
    );
    return ImageInfo(image: image, scale: key.scale);
  }

  @override
  bool operator ==(Object other) => other.runtimeType != runtimeType
      ? false
      : other is BlurHashImage &&
          other.blurHash == blurHash &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(blurHash.hashCode, scale);

  @override
  String toString() => '$runtimeType($blurHash, scale: $scale)';
}
