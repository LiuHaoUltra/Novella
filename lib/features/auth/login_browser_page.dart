import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novella/core/auth/auth_service.dart';

class LoginWebPage extends StatefulWidget {
  const LoginWebPage({super.key});

  @override
  State<LoginWebPage> createState() => _LoginWebPageState();
}

class _LoginWebPageState extends State<LoginWebPage> {
  InAppWebViewController? webViewController;
  final AuthService _authService = AuthService();
  Timer? _checkTimer;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    // 5分钟后停止自动轮询，避免资源浪费
    _timeoutTimer = Timer(const Duration(minutes: 5), () {
      if (mounted && _checkTimer != null) {
        _checkTimer?.cancel();
        _checkTimer = null;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("自动轮询已停止，请尝试刷新或重新登录")));
      }
    });
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Windows (伪装 Edge)
    const String uaWindows =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0";
    // Android (更新为三星 Galaxy S23, Chrome 120)
    const String uaAndroid =
        "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36";
    // iOS (伪装 iPhone 15 Pro, iOS 17.4)
    const String uaIOS =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

    return Scaffold(
      appBar: AppBar(
        title: const Text("登录并获取 Token"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (webViewController != null) {
                _extractTokenFromIndexedDB(webViewController!);
              }
            },
          ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri("https://www.lightnovel.app/login"),
        ),
        initialSettings: InAppWebViewSettings(
          // 全平台开启隐身模式
          incognito: true,

          // 配合隐身模式，禁用缓存
          cacheEnabled: false,

          // 三端分离 UA 设置
          userAgent:
              Platform.isWindows
                  ? uaWindows
                  : (Platform.isIOS ? uaIOS : uaAndroid),

          // iOS 特有配置
          isInspectable: false, // 生产环境关闭调试
          sharedCookiesEnabled: false, // 配合隐身模式
          // Android 必须开启混合合成
          useHybridComposition: true,

          // 基础配置
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          thirdPartyCookiesEnabled: false,
          safeBrowsingEnabled: false,
        ),

        onWebViewCreated: (controller) {
          webViewController = controller;

          // 注入反指纹脚本
          _injectAntiFingerprintScripts(controller);

          // 注册 Token 监听
          controller.addJavaScriptHandler(
            handlerName: 'tokenHandler',
            callback: (args) async {
              if (args.isNotEmpty) {
                final tokenData = args[0];
                debugPrint(">>> 成功获取 IndexedDB 数据: $tokenData");

                // 拿到数据后，立即取消定时器，避免重复跳转
                _checkTimer?.cancel();
                _checkTimer = null;
                _timeoutTimer?.cancel();

                await _handleTokenData(tokenData);
              }
            },
          );

          // 启动轮询
          // 每 2 秒尝试读取一次数据库
          _checkTimer = Timer.periodic(const Duration(seconds: 2), (
            timer,
          ) async {
            if (webViewController != null) {
              await _extractTokenFromIndexedDB(webViewController!);
            }
          });
        },

        onLoadStop: (controller, url) async {
          await _extractTokenFromIndexedDB(controller);
        },
      ),
    );
  }

  // 注入 JS 读取 IndexedDB
  Future<void> _extractTokenFromIndexedDB(
    InAppWebViewController controller,
  ) async {
    const String jsCode = """
      (function() {
        const dbName = 'LightNovelShelf'; 
        const storeName = 'USER_AUTHENTICATION'; 

        const request = indexedDB.open(dbName);

        request.onerror = function(event) {
          // 数据库可能还没创建，静默失败即可
        };

        request.onsuccess = function(event) {
          const db = event.target.result;
          
          if (!db.objectStoreNames.contains(storeName)) {
            return;
          }

          const transaction = db.transaction([storeName], 'readonly');
          const objectStore = transaction.objectStore(storeName);

          const getAllRequest = objectStore.getAll();

          getAllRequest.onsuccess = function(event) {
            const data = event.target.result;
            if (data && data.length > 0) {
              console.log("JS: Found token data, sending to Flutter...");
              window.flutter_inappwebview.callHandler('tokenHandler', JSON.stringify(data));
            }
          };
        };
      })();
    """;

    try {
      await controller.evaluateJavascript(source: jsCode);
    } catch (e) {
      // 忽略执行期间的错误
    }
  }

  Future<void> _handleTokenData(dynamic jsonString) async {
    try {
      // jsonString 应该是 JSON 字符串
      final dynamic data = jsonDecode(jsonString);

      String? refreshToken;
      String? accessToken;

      // 解析数据结构，寻找 Token
      if (data is List) {
        if (data.isNotEmpty) {
          // 遍历查找或取第一个
          for (final item in data) {
            if (item is Map) {
              if (item.containsKey('RefreshToken')) {
                refreshToken = item['RefreshToken'];
              }
              if (item.containsKey('Token')) {
                accessToken = item['Token'];
              }
              if (refreshToken != null) break;
            } else if (item is String) {
              refreshToken = item;
              break;
            }
          }
        }
      } else if (data is Map) {
        if (data.containsKey('RefreshToken')) {
          refreshToken = data['RefreshToken'];
        }
        if (data.containsKey('Token')) {
          accessToken = data['Token'];
        }
      }

      if (refreshToken != null && refreshToken.isNotEmpty) {
        // 保存 Token
        await _authService.saveTokens(accessToken ?? '', refreshToken);

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('登录成功，正在跳转...')));
          // 返回成功
          Navigator.of(context).pop({'refreshToken': refreshToken});
        }
      }
    } catch (e) {
      debugPrint("解析 Token 数据失败: $e");
    }
  }

  Future<void> _injectAntiFingerprintScripts(
    InAppWebViewController controller,
  ) async {
    // 基础脚本：移除 webdriver (所有平台通用)
    String script = """
      try {
        Object.defineProperty(navigator, 'webdriver', {
          get: () => undefined,
        });
      } catch (e) {}
    """;

    // Windows 专用：伪造 Plugins/Languages
    if (Platform.isWindows) {
      script += """
        try {
          // 伪造 Plugins
          Object.defineProperty(navigator, 'plugins', {
            get: () => [
              { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
              { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
              { name: 'Microsoft Edge PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' }
            ],
          });
          
          // 伪造 Languages
          Object.defineProperty(navigator, 'languages', {
            get: () => ['zh-CN', 'zh'],
          });

          // 补全 window.chrome
          if (!window.chrome) {
              window.chrome = { runtime: {} };
          }
        } catch (e) {}
      """;
    }

    // Android 专用：补全 Chrome 特征
    if (Platform.isAndroid) {
      script += """
        try {
          // 补全 window.chrome
          if (!window.chrome) {
            window.chrome = {
              runtime: {},
              loadTimes: function() {},
              csi: function() {},
              app: {}
            };
          }
          // notification 权限
          if (!('Notification' in window)) {
            window.Notification = { permission: 'default' };
          }
        } catch (e) {}
      """;
    }

    await controller.addUserScript(
      userScript: UserScript(
        source: script,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    );
  }
}
