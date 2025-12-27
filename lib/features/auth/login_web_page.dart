import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/auth/auth_service.dart';
import 'package:webview_windows/webview_windows.dart';

/// WebView 登录页（拦截 fetch 获取 token）
class LoginWebPage extends StatefulWidget {
  const LoginWebPage({super.key});

  @override
  State<LoginWebPage> createState() => _LoginWebPageState();
}

class _LoginWebPageState extends State<LoginWebPage> {
  final _controller = WebviewController();
  final _logger = Logger('LoginWebPage');
  final _authService = AuthService();

  // 静态标志确保环境仅初始化一次
  static bool _environmentInitialized = false;

  bool _isInitialized = false;
  bool _isInjecting = false;
  Timer? _pollingTimer;
  String _statusText = '正在初始化...';

  /// JS 拦截器捕获登录响应
  static const String _fetchInterceptorScript = '''
(function() {
  if (window.__novella_interceptor_installed) return;
  window.__novella_interceptor_installed = true;
  
  const originalFetch = window.fetch;
  window.fetch = async function(...args) {
    const response = await originalFetch.apply(this, args);
    
    try {
      const url = typeof args[0] === 'string' ? args[0] : (args[0]?.url || '');
      
      // 拦截登录接口
      if (url.includes('/api/user/login') || url.includes('/api/user/register')) {
        const clone = response.clone();
        const data = await clone.json();
        
        if (data && data.Token) {
          window.__novella_auth_data = JSON.stringify({
            token: data.Token,
            refreshToken: data.RefreshToken || ''
          });
          console.log('[Novella] Auth data captured!');
        }
      }
    } catch(e) {
      console.log('[Novella] Intercept error:', e);
    }
    
    return response;
  };
  
  console.log('[Novella] Fetch interceptor installed');
})();
''';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      // 初始化 WebView2 环境（仅一次）
      if (!_environmentInitialized) {
        try {
          // WebView2 调试配置：
          // - 代理：Clash/V2Ray
          // - 忽略证书错误（调试）
          // - 禁用特征指纹
          // - UA 设置
          // - 远程调试端口
          const debugArgs =
              '--proxy-server=http://127.0.0.1:7890 '
              '--ignore-certificate-errors '
              '--disable-features=msWebOOUI,msSmartScreenProtection '
              '--disable-gpu '
              '--remote-debugging-port=9222 '
              '--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
          await WebviewController.initializeEnvironment(
            additionalArguments: debugArgs,
          );
          _environmentInitialized = true;
          _logger.info('WebView2 environment initialized with debug flags');
        } catch (e) {
          // 环境可能已初始化
          _logger.warning('Environment init skipped: $e');
          _environmentInitialized = true;
        }
      }

      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // 设置自定义 UA 模拟 Chrome
      const chromeUA =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      await _controller.executeScript('''
        Object.defineProperty(navigator, 'userAgent', {
          get: function() { return '$chromeUA'; }
        });
      ''');

      // 监听导航以注入拦截器
      _controller.url.listen((url) {
        _logger.info('Navigation: $url');
        _injectInterceptor();
      });

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _statusText = '正在加载登录页面...';
      });

      // 注入拦截器后导航
      await _controller.loadUrl('about:blank');
      await Future.delayed(const Duration(milliseconds: 100));
      await _injectInterceptor();

      // 跳转登录页
      await _controller.loadUrl('https://www.lightnovel.app/login');

      // 开始轮询认证数据
      _startPolling();
    } catch (e) {
      _logger.severe('Failed to init webview: $e');
      if (mounted) {
        setState(() {
          _statusText = '初始化失败: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WebView 初始化失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _injectInterceptor() async {
    if (_isInjecting) return;
    _isInjecting = true;

    try {
      await _controller.executeScript(_fetchInterceptorScript);
      _logger.info('Fetch interceptor injected');
    } catch (e) {
      _logger.warning('Failed to inject interceptor: $e');
    } finally {
      _isInjecting = false;
    }
  }

  void _startPolling() {
    _logger.info('Starting auth data polling...');

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      try {
        // 检查捕获的认证数据
        final result = await _controller.executeScript(
          'window.__novella_auth_data || ""',
        );

        if (result != null &&
            result.toString().isNotEmpty &&
            result.toString() != 'null' &&
            result.toString() != '""') {
          String jsonStr = result.toString();
          // 移除引号
          if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
            jsonStr = jsonStr.substring(1, jsonStr.length - 1);
            // 反转义 JSON
            jsonStr = jsonStr.replaceAll(r'\"', '"');
          }

          _logger.info('Auth data captured: $jsonStr');

          try {
            final authData = json.decode(jsonStr) as Map<String, dynamic>;
            final token = authData['token'] as String?;
            final refreshToken = authData['refreshToken'] as String?;

            if (token != null && token.isNotEmpty) {
              timer.cancel();
              await _handleLoginSuccess(token, refreshToken ?? '');
            }
          } catch (parseError) {
            _logger.warning('Failed to parse auth data: $parseError');
          }
        }
      } catch (e) {
        // Ignore polling errors
      }
    });
  }

  Future<void> _handleLoginSuccess(String token, String refreshToken) async {
    _logger.info('Login successful! Token length: ${token.length}');

    if (!mounted) return;

    setState(() {
      _statusText = '登录成功，正在初始化...';
    });

    try {
      // 保存 Token
      await _authService.saveTokens(token, refreshToken);

      if (mounted) {
        // 返回成功及 Token
        Navigator.of(context).pop<Map<String, String>>({
          'token': token,
          'refreshToken': refreshToken,
        });
      }
    } catch (e) {
      _logger.severe('Failed to save tokens: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存登录信息失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _controller.dispose();
    super.dispose();
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
              _injectInterceptor();
            },
            tooltip: '刷新页面',
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // 浏览器视图
          Expanded(
            child:
                _isInitialized
                    ? Webview(_controller)
                    : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            _statusText,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
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
