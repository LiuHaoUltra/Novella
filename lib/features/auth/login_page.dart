import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novella/core/auth/auth_service.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';
import 'package:novella/core/sync/gist_sync_service.dart';
import 'package:novella/core/sync/sync_crypto.dart';
import 'package:novella/core/sync/sync_manager.dart';
import 'package:novella/features/auth/login_turnstile_page.dart';
import 'package:novella/features/main_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// MD3 风格登录/引导页
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  bool _checkingLogin = true;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final isLoggedIn = await _authService.tryAutoLogin();
    if (mounted) {
      if (isLoggedIn) {
        // 自动登录成功
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const MainPage()));
      } else {
        // 显示登录页
        setState(() {
          _checkingLogin = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingLogin) {
      return const Scaffold(body: Center(child: M3ELoadingIndicator()));
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final systemIconsColor = isDark ? Brightness.light : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: systemIconsColor,

        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: systemIconsColor,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,

        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 60),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.login_rounded,
                          size: 36,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // 标题
                      Text(
                        '快速开始',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 副标题
                      Text(
                        '登录 轻书架 以同步你的章节进度和书架',
                        style: textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      // 登录按钮
                      FilledButton(
                        onPressed: () => _startLogin(context),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          '开始登录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold, // 加粗
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 从 GitHub 还原按钮
                      OutlinedButton(
                        onPressed: () => _startGitHubRestore(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          side: BorderSide(
                            color: colorScheme.outline.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          '从 GitHub 还原',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 底部文字链接
                      Center(
                        child: TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('需登录后使用，否则无法阅读书籍'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          },
                          child: Text(
                            '为什么需要登录？',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      // 底部沉浸式填充
                      SizedBox(height: bottomPadding + 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startLogin(BuildContext context) async {
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => const LoginTurnstilePage()),
    );

    if (result != null && context.mounted) {
      // 登录成功，跳转主页
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainPage()));
    }
  }

  Future<void> _startGitHubRestore(BuildContext context) async {
    final syncManager = SyncManager();

    try {
      // 1. 开始 Device Flow 获取验证码
      final flowData = await syncManager.startDeviceFlow();

      if (!context.mounted) return;

      // 2. 显示验证码对话框并等待用户授权
      final authorized = await _showDeviceCodeDialog(
        context,
        syncManager,
        flowData,
      );

      if (!authorized || !context.mounted) {
        return;
      }

      // 3. 输入同步密码
      final password = await _showPasswordInputDialog(context);
      if (password == null || !context.mounted) {
        return;
      }

      // 4. 尝试从 Gist 恢复数据
      final restored = await syncManager.restoreFromGist(password);

      if (!context.mounted) return;

      if (restored) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('数据还原成功！')));

        // 5. 验证恢复的凭据是否有效
        // 尝试使用 refresh token 刷新 session token 来验证
        final prefs = await SharedPreferences.getInstance();
        final refreshToken = prefs.getString('refresh_token');

        if (refreshToken == null || refreshToken.isEmpty) {
          // 没有找到 refresh token
          if (context.mounted) {
            _showTokenInvalidWarning(context, '未找到登录凭据');
          }
          return;
        }

        // 尝试刷新 session token 来验证 refresh token 有效性
        final isValid = await _authService.tryAutoLogin();

        if (!context.mounted) return;

        if (isValid) {
          // 凭据有效，跳转到主页
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainPage()),
          );
        } else {
          // 凭据无效，清除并显示警告
          await prefs.remove('auth_token');
          await prefs.remove('refresh_token');
          if (context.mounted) {
            _showTokenInvalidWarning(context, '云端保存的登录凭据已过期或无效');
          }
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未找到同步数据')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('恢复失败: $e')));
      }
    }
  }

  /// 显示 Token 无效的警告底部弹窗
  void _showTokenInvalidWarning(BuildContext context, String message) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final textTheme = Theme.of(sheetContext).textTheme;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  '凭据验证失败',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 副标题
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '$message，请使用网页登录重新获取',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 确定按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('我知道了'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _showDeviceCodeDialog(
    BuildContext context,
    SyncManager syncManager,
    DeviceFlowResponse flowData,
  ) async {
    bool success = false;
    int remainingSeconds = flowData.expiresIn;
    final expireTime = DateTime.now().add(
      Duration(seconds: flowData.expiresIn),
    );

    // 使用 ValueNotifier 控制对话框状态
    final dialogClosed = ValueNotifier<bool>(false);
    NavigatorState? navigator;
    Timer? uiTimer;

    // 在对话框显示后启动轮询
    Future<void> startPolling() async {
      try {
        final result = await syncManager.completeDeviceFlow(flowData);
        success = result;
      } catch (e) {
        success = false;
      } finally {
        uiTimer?.cancel();
        if (!dialogClosed.value && navigator?.mounted == true) {
          navigator?.pop();
        }
      }
    }

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        navigator = Navigator.of(sheetContext);
        bool pollStarted = false;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final textTheme = Theme.of(ctx).textTheme;

            if (!pollStarted) {
              pollStarted = true;

              // 启动 UI 倒计时
              uiTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                if (dialogClosed.value) {
                  t.cancel();
                  return;
                }
                final remaining =
                    expireTime.difference(DateTime.now()).inSeconds;
                if (remaining <= 0) {
                  t.cancel();
                }
                setSheetState(() {
                  remainingSeconds = remaining > 0 ? remaining : 0;
                });
              });

              // 启动轮询
              Future.microtask(() => startPolling());
            }

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      '连接 GitHub',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 副标题
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '请在浏览器中访问以下链接并输入验证码',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // 链接
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SelectableText(
                      flowData.verificationUri,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 验证码
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          flowData.userCode,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: flowData.userCode),
                            );
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('已复制验证码')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 倒计时
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '剩余时间: ${remainingSeconds ~/ 60}:${(remainingSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: remainingSeconds < 60 ? colorScheme.error : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 底部按钮
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              uiTimer?.cancel();
                              dialogClosed.value = true;
                              navigator?.pop();
                            },
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              launchUrl(Uri.parse(flowData.verificationUri));
                            },
                            child: const Text('打开浏览器'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );

    dialogClosed.value = true;
    return success;
  }

  Future<String?> _showPasswordInputDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;

    return showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final textTheme = Theme.of(ctx).textTheme;
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        '输入同步密码',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // 副标题
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        '请输入之前设置的同步密码以解密数据',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    // 输入框
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: controller,
                        obscureText: true,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: '同步密码',
                          errorText: errorText,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 底部按钮
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  () => Navigator.of(sheetContext).pop(null),
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final password = controller.text;
                                if (!SyncCrypto.isValidPassword(password)) {
                                  setState(() {
                                    errorText = '密码格式不正确';
                                  });
                                  return;
                                }
                                Navigator.of(sheetContext).pop(password);
                              },
                              child: const Text('确定'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
