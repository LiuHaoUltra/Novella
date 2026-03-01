import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novella/core/auth/auth_service.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 使用网页端的 RefreshToken 手动登录（兜底入口）。
///
/// 说明：RefreshToken 是长期凭据，用于调用 `/api/user/refresh_token` 换取短期 SessionToken。
/// App 平时只需要持久化 RefreshToken，并在需要时自动刷新 SessionToken。
class RefreshTokenLoginPage extends StatefulWidget {
  const RefreshTokenLoginPage({super.key});

  @override
  State<RefreshTokenLoginPage> createState() => _RefreshTokenLoginPageState();
}

class _RefreshTokenLoginPageState extends State<RefreshTokenLoginPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _tokenController = TextEditingController();

  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) return;

    setState(() {
      _tokenController.text = text;
      _tokenController.selection = TextSelection.fromPosition(
        TextPosition(offset: _tokenController.text.length),
      );
      _errorText = null;
    });
  }

  Future<void> _submit() async {
    final refreshToken = _tokenController.text.trim();
    if (refreshToken.isEmpty) {
      setState(() => _errorText = '请输入 RefreshToken');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 先落盘 refresh_token，并清理旧的 session token，避免误用缓存。
      await prefs.setString('refresh_token', refreshToken);
      await prefs.remove('auth_token');
      _authService.invalidateSessionTokenCache();

      // 严格校验：必须实际走 refresh_token -> session token 刷新成功。
      final ok = await _authService.tryAutoLogin();
      if (!mounted) return;

      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }

      // 校验失败：清除无效凭据，避免下次冷启动自动登录循环失败。
      await prefs.remove('auth_token');
      await prefs.remove('refresh_token');
      _authService.invalidateSessionTokenCache();

      if (!mounted) return;
      setState(() {
        _errorText = 'RefreshToken 无效或已过期，请在网页端重新获取';
      });
    } on Object catch (e) {
      // 发生异常也尽量不要污染后续登录流程
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_token');
        await prefs.remove('refresh_token');
        _authService.invalidateSessionTokenCache();
      } on Object catch (_) {}

      if (!mounted) return;
      setState(() {
        _errorText = '验证失败：$e';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('手动登录')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        '如何获取 RefreshToken',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在桌面浏览器登录轻书架 Web 后\n按下 F12 在开发者工具中找到：',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(
                      'Application → IndexedDB → LightNovelShelf → USER_AUTHENTICATION\n复制其中的 RefreshToken 值',
                      style: tt.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '注意：RefreshToken 等同于账号凭据，请勿泄露给他人。',
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '填入令牌',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    enabled: !_submitting,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'RefreshToken',
                      hintText: '在此处粘贴',
                      prefixIcon: const Icon(Icons.key_outlined),
                      errorText: _errorText,
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_outlined),
                        onPressed: _submitting ? null : _pasteFromClipboard,
                        tooltip: '从剪贴板粘贴',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child:
                          _submitting
                              ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: M3ELoadingIndicator(size: 22),
                              )
                              : const Text('验证并登录'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Token 说明',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• SessionToken：短期会话令牌\n'
                    '• RefreshToken：长期刷新令牌',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
