/// 封面 URL 工具函数
class CoverUrlUtils {
  CoverUrlUtils._();

  /// 从封面 URL 的 query parameter 中提取 blurhash 字符串
  ///
  /// 后端在封面 URL 中以 `?placeholder=<blurhash>` 形式附带 blurhash 数据。
  /// 对标 Web 端 `getPlaceholder()` 逻辑。
  static String? extractBlurHash(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final placeholder = uri.queryParameters['placeholder'];
      return (placeholder != null && placeholder.isNotEmpty)
          ? placeholder
          : null;
    } catch (_) {
      return null;
    }
  }
}
