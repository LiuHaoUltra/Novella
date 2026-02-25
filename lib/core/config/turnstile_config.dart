/// Cloudflare Turnstile 配置（与 Web 端保持一致）。
///
/// 站点 Key 来源：Web-master/.env -> VUE_CAPTCHA_SITE_KEY
///
/// 注意：Turnstile 的 site key 不是机密信息，但仍建议集中管理，避免散落在各处。
abstract final class TurnstileConfig {
  /// Cloudflare Turnstile site key (public).
  static const String siteKey = '0x4AAAAAAADgWLX3ngufVh5F';

  /// Turnstile widget 运行时的 baseUrl。
  ///
  /// 该值需要与 Cloudflare 后台中「允许的域名」匹配（否则 widget 可能无法通过验证）。
  static const String baseUrl = 'https://www.lightnovel.app';
}
