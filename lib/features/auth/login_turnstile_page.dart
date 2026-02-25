import 'dart:async';

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';
import 'package:novella/core/auth/auth_service.dart';
import 'package:novella/core/config/turnstile_config.dart';
import 'package:novella/core/widgets/m3e_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 原生登录/注册/找回密码页面（MD3 Outlined），使用 Cloudflare Turnstile 获取 token。
class LoginTurnstilePage extends StatefulWidget {
  const LoginTurnstilePage({super.key});

  @override
  State<LoginTurnstilePage> createState() => _LoginTurnstilePageState();
}

class _LoginTurnstilePageState extends State<LoginTurnstilePage>
    with SingleTickerProviderStateMixin {
  // 对齐 Web 端邮箱正则
  static final _emailRegex = RegExp(
    r'^\w+([-+.]\w+)*@\w+([-.]?\w+)*\.\w+([-.]?\w+)*$',
    caseSensitive: false,
  );

  // Outlined 输入框统一样式
  static InputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  InputDecoration _dec({
    required String label,
    required IconData icon,
    Widget? suffix,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: _border(cs.outline),
      enabledBorder: _border(cs.outline),
      focusedBorder: _border(cs.primary),
      errorBorder: _border(cs.error),
      focusedErrorBorder: _border(cs.error),
      filled: true,
      fillColor: cs.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  final AuthService _authService = AuthService();
  late final TabController _tabController;

  // ─── 登录 ───
  final _loginFormKey = GlobalKey<FormState>();
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final TurnstileController _loginTurnstileController = TurnstileController();
  String? _loginTurnstileToken;
  TurnstileException? _loginTurnstileError;
  bool _loginSubmitting = false;
  bool _loginPasswordVisible = false;

  // ─── 注册 ───
  final _registerFormKey = GlobalKey<FormState>();
  final _registerUserNameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerPassword2Controller = TextEditingController();
  final _registerCodeController = TextEditingController();
  final _registerInviteCodeController = TextEditingController();
  final TurnstileController _registerTurnstileController =
      TurnstileController();
  String? _registerTurnstileToken;
  TurnstileException? _registerTurnstileError;
  bool _registerSubmitting = false;
  bool _sendingRegisterCode = false;
  int _registerCodeCooldown = 0;
  Timer? _registerCodeCooldownTimer;
  bool _registerPasswordVisible = false;
  bool _registerPassword2Visible = false;

  // ─── 找回密码 ───
  final _resetFormKey = GlobalKey<FormState>();
  final _resetEmailController = TextEditingController();
  final _resetCodeController = TextEditingController();
  final _resetPasswordController = TextEditingController();
  final _resetPassword2Controller = TextEditingController();
  final TurnstileController _resetTurnstileController = TurnstileController();
  String? _resetTurnstileToken;
  TurnstileException? _resetTurnstileError;
  bool _resetSubmitting = false;
  bool _sendingResetCode = false;
  int _resetCodeCooldown = 0;
  Timer? _resetCodeCooldownTimer;
  bool _resetPasswordVisible = false;
  bool _resetPassword2Visible = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  // 切换到某 Tab 时，清空该 Tab 的验证状态，避免 WebView 重建后显示旧"已通过"
  void _onTabChanged() {
    // 移除 if (!_tabController.indexIsChanging) return; 以支持滑动切换重建
    switch (_tabController.index) {
      case 0:
        setState(() {
          _loginTurnstileToken = null;
          _loginTurnstileError = null;
        });
      case 1:
        setState(() {
          _registerTurnstileToken = null;
          _registerTurnstileError = null;
        });
      case 2:
        setState(() {
          _resetTurnstileToken = null;
          _resetTurnstileError = null;
        });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerUserNameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerPassword2Controller.dispose();
    _registerCodeController.dispose();
    _registerInviteCodeController.dispose();
    _resetEmailController.dispose();
    _resetCodeController.dispose();
    _resetPasswordController.dispose();
    _resetPassword2Controller.dispose();
    _registerCodeCooldownTimer?.cancel();
    _resetCodeCooldownTimer?.cancel();
    super.dispose();
  }

  // ─── 校验 ───

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return '请输入邮箱';
    if (!_emailRegex.hasMatch(value)) return '请输入有效的邮箱地址';
    return null;
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return '请输入密码';
    if (value.length < 8) return '密码至少 8 位';
    return null;
  }

  // ─── 工具 ───

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
    );
  }

  String _getErrMsg(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  Future<void> _finishAndPopSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token') ?? '';
    if (!mounted) return;
    Navigator.of(context).pop({'refreshToken': refreshToken});
  }

  Future<String?> _requireTurnstileToken({
    required TurnstileController controller,
    required String? token,
    required VoidCallback clearLocalToken,
  }) async {
    final t = token;
    if (t == null || t.isEmpty) {
      _showSnack('请先完成人机验证');
      return null;
    }
    final expired = await controller.isExpired();
    if (expired) {
      clearLocalToken();
      _showSnack('验证已过期，请重新验证');
      await controller.refreshToken();
      return null;
    }
    return t;
  }

  void _startRegisterCooldown([int seconds = 60]) {
    _registerCodeCooldownTimer?.cancel();
    setState(() => _registerCodeCooldown = seconds);
    _registerCodeCooldownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) return;
      if (_registerCodeCooldown <= 1) {
        timer.cancel();
        setState(() => _registerCodeCooldown = 0);
        return;
      }
      setState(() => _registerCodeCooldown -= 1);
    });
  }

  void _startResetCooldown([int seconds = 60]) {
    _resetCodeCooldownTimer?.cancel();
    setState(() => _resetCodeCooldown = seconds);
    _resetCodeCooldownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) return;
      if (_resetCodeCooldown <= 1) {
        timer.cancel();
        setState(() => _resetCodeCooldown = 0);
        return;
      }
      setState(() => _resetCodeCooldown -= 1);
    });
  }

  // 一键发送注册验证码（token 已就绪）
  Future<void> _doSendRegisterCode(String token) async {
    setState(() => _sendingRegisterCode = true);
    try {
      await _authService.sendRegisterEmail(
        email: _registerEmailController.text.trim(),
        turnstileToken: token,
      );
      if (!mounted) return;
      _showSnack('验证码已发送，请检查邮箱');
      _startRegisterCooldown(60);
      // Web 端在这里不刷新 token，后续如果在倒计时后再次重试发送失败，会在 catch 块内自动刷新
    } catch (e) {
      if (!mounted) return;
      _showSnack('发送失败：${_getErrMsg(e)}');
      setState(() => _registerTurnstileToken = null);
      await _registerTurnstileController.refreshToken();
    } finally {
      if (mounted) setState(() => _sendingRegisterCode = false);
    }
  }

  // 一键发送找回密码验证码（token 已就绪）
  Future<void> _doSendResetCode(String token) async {
    setState(() => _sendingResetCode = true);
    try {
      await _authService.sendResetPasswordEmail(
        email: _resetEmailController.text.trim(),
        turnstileToken: token,
      );
      if (!mounted) return;
      _showSnack('验证码已发送，请检查邮箱');
      _startResetCooldown(60);
    } catch (e) {
      if (!mounted) return;
      _showSnack('发送失败：${_getErrMsg(e)}');
      setState(() => _resetTurnstileToken = null);
      await _resetTurnstileController.refreshToken();
    } finally {
      if (mounted) setState(() => _sendingResetCode = false);
    }
  }

  TurnstileOptions _defaultTurnstileOptions() => TurnstileOptions(
    size: TurnstileSize.flexible,
    theme: TurnstileTheme.auto,
    language: 'auto',
    refreshExpired: TurnstileRefreshExpired.auto,
    refreshTimeout: TurnstileRefreshTimeout.auto,
    retryAutomatically: true,
  );

  // ─── Turnstile 卡片 ───

  Widget _buildTurnstileBlock({
    required bool isActive,
    required String action,
    required TurnstileController controller,
    required String? token,
    required TurnstileException? error,
    required VoidCallback onForceRefresh,
    required ValueChanged<String> onTokenReceived,
    required VoidCallback onTokenExpired,
    required ValueChanged<TurnstileException> onError,
    required VoidCallback onTimeout,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hasToken = token != null && token.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '人机验证',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 使用固定高度的 SizedBox 约束 Turnstile 和占位，避免切换 Tab 时的伸缩跳动
          SizedBox(
            height: 65,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 背景云朵图标，右侧占位
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Icon(
                      Icons.cloud_outlined,
                      size: 32,
                      color: cs.primary.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                if (isActive)
                  CloudflareTurnstile(
                    siteKey: TurnstileConfig.siteKey,
                    baseUrl: TurnstileConfig.baseUrl,
                    action: action,
                    controller: controller,
                    options: _defaultTurnstileOptions(),
                    onTokenReceived: onTokenReceived,
                    onTokenExpired: onTokenExpired,
                    onError: onError,
                    onTimeout: onTimeout,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.bolt_outlined,
                size: 16,
                color: hasToken ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasToken ? '验证已通过' : '请完成验证后再继续',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              TextButton.icon(
                onPressed: onForceRefresh,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('重新验证'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(
              '验证失败：${error.message}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 大按钮 ───

  Widget _submitButton({
    required bool loading,
    required VoidCallback? onPressed,
    required String label,
  }) => FilledButton(
    onPressed: loading ? null : onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child:
        loading
            ? const SizedBox(
              height: 22,
              width: 22,
              child: M3ELoadingIndicator(size: 22),
            )
            : Text(label, style: const TextStyle(fontSize: 15)),
  );

  // ─── 验证码输入框（suffix 内嵌发送按钮 + 按下遮罩动效） ───

  Widget _sendCodeRow({
    required bool canSend,
    required bool sending,
    required int cooldown,
    required VoidCallback? onSend,
    required TextEditingController codeController,
    required String? Function(String?) validator,
  }) {
    final enabled = canSend && !sending;
    final cs = Theme.of(context).colorScheme;

    Widget suffixIcon;
    if (sending) {
      suffixIcon = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 18,
          width: 18,
          child: M3ELoadingIndicator(size: 18),
        ),
      );
    } else if (cooldown > 0) {
      suffixIcon = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${cooldown}s',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ],
        ),
      );
    } else {
      suffixIcon = IconButton(
        onPressed: enabled ? onSend : null,
        icon: Icon(
          Icons.send_rounded,
          size: 18,
          color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.38),
        ),
        visualDensity: VisualDensity.compact,
      );
    }

    return TextFormField(
      controller: codeController,
      decoration: _dec(
        label: '邮箱验证码',
        icon: Icons.tag_outlined,
        suffix: suffixIcon,
      ),
      keyboardType: TextInputType.number,
      validator: validator,
    );
  }

  // ─── 提示文字 ───

  Widget _tokenHint() => Text(
    '提示：人机验证 Token 有效期较短，验证通过后请尽快提交。',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    textAlign: TextAlign.center,
  );

  // ════════════════════════════════
  // 登录 Tab
  // ════════════════════════════════

  Widget _buildLoginTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Form(
        key: _loginFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 邮箱
            TextFormField(
              controller: _loginEmailController,
              decoration: _dec(label: '邮箱', icon: Icons.mail_outline),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: _validateEmail,
            ),
            const SizedBox(height: 14),
            // 密码
            TextFormField(
              controller: _loginPasswordController,
              decoration: _dec(
                label: '密码',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  onPressed:
                      () => setState(
                        () => _loginPasswordVisible = !_loginPasswordVisible,
                      ),
                  icon: Icon(
                    _loginPasswordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              obscureText: !_loginPasswordVisible,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              validator: _validatePassword,
            ),
            const SizedBox(height: 20),
            // Turnstile
            _buildTurnstileBlock(
              isActive: _tabController.index == 0,
              action: 'login',
              controller: _loginTurnstileController,
              token: _loginTurnstileToken,
              error: _loginTurnstileError,
              onForceRefresh: () async {
                setState(() {
                  _loginTurnstileToken = null;
                  _loginTurnstileError = null;
                });
                await _loginTurnstileController.refreshToken();
              },
              onTokenReceived:
                  (t) => setState(() {
                    _loginTurnstileToken = t;
                    _loginTurnstileError = null;
                  }),
              onTokenExpired: () => setState(() => _loginTurnstileToken = null),
              onError:
                  (e) => setState(() {
                    _loginTurnstileError = e;
                    _loginTurnstileToken = null;
                  }),
              onTimeout:
                  () => setState(() {
                    _loginTurnstileError = const TurnstileException(
                      'Turnstile 加载超时，请检查网络后重试',
                      retryable: true,
                    );
                    _loginTurnstileToken = null;
                  }),
            ),
            const SizedBox(height: 20),
            // 登录按钮
            _submitButton(
              loading: _loginSubmitting,
              label: '登录',
              onPressed: () async {
                final valid = _loginFormKey.currentState?.validate() ?? false;
                if (!valid) return;

                final token = await _requireTurnstileToken(
                  controller: _loginTurnstileController,
                  token: _loginTurnstileToken,
                  clearLocalToken:
                      () => setState(() => _loginTurnstileToken = null),
                );
                if (token == null) return;

                setState(() => _loginSubmitting = true);
                try {
                  await _authService.login(
                    _loginEmailController.text.trim(),
                    _loginPasswordController.text,
                    turnstileToken: token,
                  );
                  if (!mounted) return;
                  _showSnack('登录成功');
                  await _finishAndPopSuccess();
                } catch (e) {
                  if (!mounted) return;
                  _showSnack(_getErrMsg(e));
                  setState(() => _loginTurnstileToken = null);
                  await _loginTurnstileController.refreshToken();
                } finally {
                  if (mounted) setState(() => _loginSubmitting = false);
                }
              },
            ),
            const SizedBox(height: 12),
            _tokenHint(),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════
  // 注册 Tab
  // ════════════════════════════════

  Widget _buildRegisterTab() {
    final canSend = !_sendingRegisterCode && _registerCodeCooldown == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Form(
        key: _registerFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 用户名
            TextFormField(
              controller: _registerUserNameController,
              decoration: _dec(label: '用户名', icon: Icons.person_outline),
              textInputAction: TextInputAction.next,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return '请输入用户名';
                if (value.length < 2) return '用户名至少 2 位';
                return null;
              },
            ),
            const SizedBox(height: 14),
            // 邮箱
            TextFormField(
              controller: _registerEmailController,
              decoration: _dec(label: '邮箱', icon: Icons.mail_outline),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: _validateEmail,
            ),
            const SizedBox(height: 14),
            // 密码
            TextFormField(
              controller: _registerPasswordController,
              decoration: _dec(
                label: '密码',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  onPressed:
                      () => setState(
                        () =>
                            _registerPasswordVisible =
                                !_registerPasswordVisible,
                      ),
                  icon: Icon(
                    _registerPasswordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              obscureText: !_registerPasswordVisible,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: _validatePassword,
            ),
            const SizedBox(height: 14),
            // 确认密码
            TextFormField(
              controller: _registerPassword2Controller,
              decoration: _dec(
                label: '确认密码',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  onPressed:
                      () => setState(
                        () =>
                            _registerPassword2Visible =
                                !_registerPassword2Visible,
                      ),
                  icon: Icon(
                    _registerPassword2Visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              obscureText: !_registerPassword2Visible,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final value = v ?? '';
                if (value.isEmpty) return '请再次输入密码';
                if (value != _registerPasswordController.text) {
                  return '两次密码不一致';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            // 邀请码
            TextFormField(
              controller: _registerInviteCodeController,
              decoration: _dec(
                label: '邀请码',
                icon: Icons.card_giftcard_outlined,
              ),
              textInputAction: TextInputAction.next,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return '请输入邀请码';
                return null;
              },
            ),
            const SizedBox(height: 14),
            // 发送验证码 + 验证码输入（内嵌按钮）
            _sendCodeRow(
              canSend: canSend,
              sending: _sendingRegisterCode,
              cooldown: _registerCodeCooldown,
              codeController: _registerCodeController,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return '请输入验证码';
                if (value.length != 4) return '验证码应为 4 位';
                return null;
              },
              onSend: () async {
                final emailErr = _validateEmail(_registerEmailController.text);
                if (emailErr != null) {
                  _showSnack(emailErr);
                  return;
                }
                final t = _registerTurnstileToken;
                if (t == null || t.isEmpty) {
                  _showSnack('请先完成下方的人机验证');
                  return;
                }
                await _doSendRegisterCode(t);
              },
            ),
            const SizedBox(height: 20),
            // Turnstile（始终在最下方）
            _buildTurnstileBlock(
              isActive: _tabController.index == 1,
              action: 'register',
              controller: _registerTurnstileController,
              token: _registerTurnstileToken,
              error: _registerTurnstileError,
              onForceRefresh: () async {
                setState(() {
                  _registerTurnstileToken = null;
                  _registerTurnstileError = null;
                });
                await _registerTurnstileController.refreshToken();
              },
              onTokenReceived: (t) {
                setState(() {
                  _registerTurnstileToken = t;
                  _registerTurnstileError = null;
                });
              },
              onTokenExpired:
                  () => setState(() => _registerTurnstileToken = null),
              onError:
                  (e) => setState(() {
                    _registerTurnstileError = e;
                    _registerTurnstileToken = null;
                  }),
              onTimeout:
                  () => setState(() {
                    _registerTurnstileError = const TurnstileException(
                      'Turnstile 加载超时，请检查网络后重试',
                      retryable: true,
                    );
                    _registerTurnstileToken = null;
                  }),
            ),
            const SizedBox(height: 20),
            // 注册按钮
            _submitButton(
              loading: _registerSubmitting,
              label: '创建账号',
              onPressed: () async {
                final valid =
                    _registerFormKey.currentState?.validate() ?? false;
                if (!valid) return;

                setState(() => _registerSubmitting = true);
                try {
                  await _authService.register(
                    userName: _registerUserNameController.text.trim(),
                    email: _registerEmailController.text.trim(),
                    password: _registerPasswordController.text,
                    code: _registerCodeController.text.trim(),
                    inviteCode: _registerInviteCodeController.text.trim(),
                  );
                  if (!mounted) return;
                  _showSnack('注册成功');
                  await _finishAndPopSuccess();
                } catch (e) {
                  if (!mounted) return;
                  _showSnack(_getErrMsg(e));
                } finally {
                  if (mounted) {
                    setState(() => _registerSubmitting = false);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════
  // 找回密码 Tab
  // ════════════════════════════════

  Widget _buildResetTab() {
    final canSend = !_sendingResetCode && _resetCodeCooldown == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Form(
        key: _resetFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 邮箱
            TextFormField(
              controller: _resetEmailController,
              decoration: _dec(label: '邮箱', icon: Icons.mail_outline),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: _validateEmail,
            ),
            const SizedBox(height: 14),
            // 新密码
            TextFormField(
              controller: _resetPasswordController,
              decoration: _dec(
                label: '新密码',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  onPressed:
                      () => setState(
                        () => _resetPasswordVisible = !_resetPasswordVisible,
                      ),
                  icon: Icon(
                    _resetPasswordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              obscureText: !_resetPasswordVisible,
              textInputAction: TextInputAction.next,
              validator: _validatePassword,
            ),
            const SizedBox(height: 14),
            // 确认新密码
            TextFormField(
              controller: _resetPassword2Controller,
              decoration: _dec(
                label: '确认新密码',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  onPressed:
                      () => setState(
                        () => _resetPassword2Visible = !_resetPassword2Visible,
                      ),
                  icon: Icon(
                    _resetPassword2Visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              obscureText: !_resetPassword2Visible,
              textInputAction: TextInputAction.done,
              validator: (v) {
                final value = v ?? '';
                if (value.isEmpty) return '请再次输入新密码';
                if (value != _resetPasswordController.text) {
                  return '两次密码不一致';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            // 发送验证码 + 验证码输入
            _sendCodeRow(
              canSend: canSend,
              sending: _sendingResetCode,
              cooldown: _resetCodeCooldown,
              codeController: _resetCodeController,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return '请输入验证码';
                if (value.length != 4) return '验证码应为 4 位';
                return null;
              },
              onSend: () async {
                final emailErr = _validateEmail(_resetEmailController.text);
                if (emailErr != null) {
                  _showSnack(emailErr);
                  return;
                }
                final t = _resetTurnstileToken;
                if (t == null || t.isEmpty) {
                  _showSnack('请先完成下方的人机验证');
                  return;
                }
                await _doSendResetCode(t);
              },
            ),
            const SizedBox(height: 20),
            // Turnstile
            _buildTurnstileBlock(
              isActive: _tabController.index == 2,
              action: 'reset_password',
              controller: _resetTurnstileController,
              token: _resetTurnstileToken,
              error: _resetTurnstileError,
              onForceRefresh: () async {
                setState(() {
                  _resetTurnstileToken = null;
                  _resetTurnstileError = null;
                });
                await _resetTurnstileController.refreshToken();
              },
              onTokenReceived: (t) {
                setState(() {
                  _resetTurnstileToken = t;
                  _resetTurnstileError = null;
                });
              },
              onTokenExpired: () => setState(() => _resetTurnstileToken = null),
              onError:
                  (e) => setState(() {
                    _resetTurnstileError = e;
                    _resetTurnstileToken = null;
                  }),
              onTimeout:
                  () => setState(() {
                    _resetTurnstileError = const TurnstileException(
                      'Turnstile 加载超时，请检查网络后重试',
                      retryable: true,
                    );
                    _resetTurnstileToken = null;
                  }),
            ),
            const SizedBox(height: 20),

            // 重置按钮
            _submitButton(
              loading: _resetSubmitting,
              label: '重置密码',
              onPressed: () async {
                final valid = _resetFormKey.currentState?.validate() ?? false;
                if (!valid) return;

                setState(() => _resetSubmitting = true);
                try {
                  await _authService.resetPassword(
                    email: _resetEmailController.text.trim(),
                    code: _resetCodeController.text.trim(),
                    newPassword: _resetPasswordController.text,
                  );
                  if (!mounted) return;
                  _showSnack('密码已重置，请使用新密码登录');
                  _loginEmailController.text =
                      _resetEmailController.text.trim();
                  _tabController.animateTo(0);
                } catch (e) {
                  if (!mounted) return;
                  _showSnack('重置失败：${_getErrMsg(e)}');
                } finally {
                  if (mounted) setState(() => _resetSubmitting = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════
  // Build
  // ════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账号'),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [Tab(text: '登录'), Tab(text: '注册'), Tab(text: '找回密码')],
        ),
      ),
      body: ColoredBox(
        color: cs.surface,
        child: TabBarView(
          controller: _tabController,
          children: [
            SingleChildScrollView(child: _buildLoginTab()),
            SingleChildScrollView(child: _buildRegisterTab()),
            SingleChildScrollView(child: _buildResetTab()),
          ],
        ),
      ),
    );
  }
}
