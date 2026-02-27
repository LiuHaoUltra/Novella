import 'dart:math';
import 'package:flutter/painting.dart';

/// 封面 URL 工具函数
class CoverUrlUtils {
  CoverUrlUtils._();

  /// 从封面 URL 的 query parameter 中提取 blurhash 字符串
  ///
  /// 后端在封面 URL 中以 `?placeholder=<blurhash>` 形式附带 blurhash 数据。
  /// 对标 Web 端 `getPlaceholder()` 逻辑。
  /// 内含完整验证，仅返回合法的 hash 或 null。
  static String? extractBlurHash(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final hash = uri.queryParameters['placeholder'];
      if (hash == null || hash.length < 6) return null;

      // 验证所有字符属于 Base83 字符集
      for (var i = 0; i < hash.length; i++) {
        if (!_base83Chars.contains(hash[i])) return null;
      }

      // 验证长度与分量声明一致
      final sizeFlag = _decode83(hash[0]);
      final numY = (sizeFlag / 9).floor() + 1;
      final numX = (sizeFlag % 9) + 1;
      if (hash.length != 4 + 2 * numX * numY) return null;

      return hash;
    } catch (_) {
      return null;
    }
  }

  /// 从封面 URL 的 BlurHash 中直接提取主色调
  ///
  /// BlurHash DC 分量（第3-6字符）编码了图片的平均色。
  /// 纯数学运算，<1ms，无需下载图片。
  /// BlurHash 平均色普遍偏白，此方法会增强饱和度修正。
  static Color? extractSeedColor(String? url) {
    final hash = extractBlurHash(url);
    if (hash == null || hash.length < 6) return null;

    try {
      // 解码 DC 分量（平均色）
      final dcValue = _decode83(hash.substring(2, 6));
      final r = dcValue >> 16;
      final g = (dcValue >> 8) & 255;
      final b = dcValue & 255;

      final raw = Color.fromARGB(255, r, g, b);

      // BlurHash 平均色偏白淡，增强饱和度
      final hsl = HSLColor.fromColor(raw);
      return hsl
          .withSaturation(min(1.0, hsl.saturation * 1.5 + 0.1))
          .withLightness((hsl.lightness * 0.9).clamp(0.15, 0.75))
          .toColor();
    } catch (_) {
      return null;
    }
  }

  /// Base83 字符集（BlurHash 编码标准）
  static const _base83Chars =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#\$%*+,-.:;=?@[]^_{|}~';

  /// Base83 解码
  static int _decode83(String str) {
    var value = 0;
    for (var i = 0; i < str.length; i++) {
      final digit = _base83Chars.indexOf(str[i]);
      if (digit == -1) return 0;
      value = value * 83 + digit;
    }
    return value;
  }
}
