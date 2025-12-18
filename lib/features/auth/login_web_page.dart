import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/auth/auth_service.dart';
import 'package:webview_windows/webview_windows.dart';

/// WebView page for login with fetch interceptor to capture tokens
class LoginWebPage extends StatefulWidget {
  const LoginWebPage({super.key});

  @override
  State<LoginWebPage> createState() => _LoginWebPageState();
}

class _LoginWebPageState extends State<LoginWebPage> {
  final _controller = WebviewController();
  final _logger = Logger('LoginWebPage');
  final _authService = AuthService();

  // Static flag to ensure environment is initialized only once
  static bool _environmentInitialized = false;

  bool _isInitialized = false;
  bool _isInjecting = false;
  Timer? _pollingTimer;
  String _statusText = '正在初始化...';

  /// JavaScript interceptor to capture login API response
  static const String _fetchInterceptorScript = '''
(function() {
  if (window.__novella_interceptor_installed) return;
  window.__novella_interceptor_installed = true;
  
  const originalFetch = window.fetch;
  window.fetch = async function(...args) {
    const response = await originalFetch.apply(this, args);
    
    try {
      const url = typeof args[0] === 'string' ? args[0] : (args[0]?.url || '');
      
      // Intercept login API response
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
      // Initialize WebView2 environment with proxy settings (only once)
      if (!_environmentInitialized) {
        try {
          // WebView2 debug configuration:
          // - proxy-server: Use Clash/V2Ray proxy
          // - ignore-certificate-errors: Bypass SSL issues (debug only!)
          // - disable-features=msWebOOUI: Reduce browser fingerprinting
          // - user-agent: Set at env level to take effect before page load
          // - remote-debugging-port: Enable Edge DevTools debugging
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
          // Environment might already be initialized from a previous session
          _logger.warning('Environment init skipped: $e');
          _environmentInitialized = true;
        }
      }

      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // Set custom User-Agent to mimic standard Chrome browser
      const chromeUA =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      await _controller.executeScript('''
        Object.defineProperty(navigator, 'userAgent', {
          get: function() { return '$chromeUA'; }
        });
      ''');

      // Listen for navigation events to inject interceptor
      _controller.url.listen((url) {
        _logger.info('Navigation: $url');
        _injectInterceptor();
      });

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _statusText = '正在加载登录页面...';
      });

      // First inject interceptor, then navigate
      await _controller.loadUrl('about:blank');
      await Future.delayed(const Duration(milliseconds: 100));
      await _injectInterceptor();

      // Navigate to login page
      await _controller.loadUrl('https://www.lightnovel.app/login');

      // Start polling for auth data
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
        // Check for captured auth data
        final result = await _controller.executeScript(
          'window.__novella_auth_data || ""',
        );

        if (result != null &&
            result.toString().isNotEmpty &&
            result.toString() != 'null' &&
            result.toString() != '""') {
          String jsonStr = result.toString();
          // Remove surrounding quotes if present
          if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
            jsonStr = jsonStr.substring(1, jsonStr.length - 1);
            // Unescape the JSON string
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
      // Save tokens
      await _authService.saveTokens(token, refreshToken);

      if (mounted) {
        // Return success with tokens
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
          // Status bar
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
          // WebView
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
