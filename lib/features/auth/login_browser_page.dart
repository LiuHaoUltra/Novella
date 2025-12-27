import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/auth/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// 浏览器登录页面
/// 仅需输入 RefreshToken
class LoginBrowserPage extends StatefulWidget {
  const LoginBrowserPage({super.key});

  @override
  State<LoginBrowserPage> createState() => _LoginBrowserPageState();
}

class _LoginBrowserPageState extends State<LoginBrowserPage> {
  final _logger = Logger('LoginBrowserPage');
  final _authService = AuthService();
  final _refreshTokenController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  static const String _loginUrl = 'https://www.lightnovel.app/login';

  @override
  void dispose() {
    _refreshTokenController.dispose();
    super.dispose();
  }

  Future<void> _openBrowserLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse(_loginUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _logger.info('Opened login page in system browser');
      } else {
        throw Exception('无法打开浏览器');
      }
    } catch (e) {
      _logger.severe('Failed to open browser: $e');
      if (mounted) {
        setState(() => _errorMessage = '无法打开浏览器: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitRefreshToken() async {
    final refreshToken = _refreshTokenController.text.trim();

    if (refreshToken.isEmpty) {
      setState(() => _errorMessage = '请输入 RefreshToken');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 保存 refresh token，随后 AuthService 自动刷新 session token
      await _authService.saveTokens('', refreshToken);
      _logger.info('RefreshToken saved, will auto-refresh session token');

      if (mounted) {
        Navigator.of(
          context,
        ).pop<Map<String, String>>({'refreshToken': refreshToken});
      }
    } catch (e) {
      _logger.severe('Failed to save token: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '保存 Token 失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _refreshTokenController.text = data!.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 说明卡片
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 24,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '登录步骤',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildStep(context, '1', '点击下方按钮在浏览器中登录'),
                    _buildStep(context, '2', '登录成功后，按 F12 打开开发者工具'),
                    _buildStep(
                      context,
                      '3',
                      '找到 Application → IndexedDB → LightNovelShelf → USER_AUTHENTICATION',
                    ),
                    _buildStep(context, '4', '复制 RefreshToken 的值粘贴到下方'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 打开浏览器按钮
            FilledButton.icon(
              onPressed: _isLoading ? null : _openBrowserLogin,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('在浏览器中登录'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Token 输入区域
            Text(
              '输入 RefreshToken',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '输入后自动完成会话刷新',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // 输入框
            TextField(
              controller: _refreshTokenController,
              decoration: InputDecoration(
                labelText: 'RefreshToken',
                hintText: '从浏览器复制的 RefreshToken',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: _pasteFromClipboard,
                  tooltip: '粘贴',
                ),
              ),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 24),

            // 提交按钮
            FilledButton(
              onPressed: _isLoading ? null : _submitRefreshToken,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child:
                  _isLoading
                      ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('确认登录'),
            ),

            // 错误信息
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Card(
                color: colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, String number, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
