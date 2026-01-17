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

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // Android: 使用内存级 Cookie，不写磁盘
          // iOS: 使用 WKWebsiteDataStore.nonPersistent()
          // Windows: 使用 InPrivate Profile
          incognito: true,

          // 配合隐身模式，禁用缓存（防止极个别情况写磁盘）
          cacheEnabled: false,

          // 动态 UA 设置 (Windows 必须伪装成 Edge，移动端伪装成 Pixel)
          userAgent:
              Platform.isWindows
                  ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
                  : "Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36",

          // Android 必须开启混合合成 (解决 GPU 指纹)
          useHybridComposition: true,

          // 允许 JS 和 数据库 (虽然是隐身的，但 Session 期间需要读写 DB)
          javaScriptEnabled: true,
          domStorageEnabled: true, // LocalStorage
          databaseEnabled: true, // IndexedDB
          // 禁用第三方 Cookie
          thirdPartyCookiesEnabled: false,
          safeBrowsingEnabled: false, // 反爬虫对抗配置
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
    const String script = """
      (function() {
        // 移除 navigator.webdriver
        Object.defineProperty(navigator, 'webdriver', {
          get: () => undefined,
        });

        // 伪造 Chrome 插件列表 (plugins)
        Object.defineProperty(navigator, 'plugins', {
          get: () => [1, 2, 3, 4, 5],
        });

        // 伪造 languages
        Object.defineProperty(navigator, 'languages', {
          get: () => ['zh-CN', 'zh'],
        });

        // WebGL 指纹混淆 (可选，视情况开启)
        try {
          const getParameter = WebGLRenderingContext.prototype.getParameter;
          WebGLRenderingContext.prototype.getParameter = function(parameter) {
            // UNMASKED_VENDOR_WEBGL
            if (parameter === 37445) {
              return 'Intel Inc.';
            }
            // UNMASKED_RENDERER_WEBGL
            if (parameter === 37446) {
              return 'Intel Iris OpenGL Engine';
            }
            return getParameter(parameter);
          };
        } catch (e) {}
      })();
    """;
    await controller.addUserScript(
      userScript: UserScript(
        source: script,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    );
  }
}
