import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novella/core/sync/gist_sync_service.dart';
import 'package:novella/core/sync/sync_crypto.dart';
import 'package:novella/core/sync/sync_manager.dart';
import 'package:url_launcher/url_launcher.dart';

/// 云同步设置区域
class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  State<SyncSettingsSection> createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection> {
  final _syncManager = SyncManager();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _syncManager.init();
    _syncManager.addListener(_onSyncUpdate);
  }

  @override
  void dispose() {
    _syncManager.removeListener(_onSyncUpdate);
    super.dispose();
  }

  void _onSyncUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '云同步',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),

        if (_syncManager.isConnected) ...[
          // 已连接状态
          ListTile(
            leading: Icon(Icons.cloud_done, color: Colors.green[600]),
            title: const Text('已连接 GitHub'),
            subtitle:
                _syncManager.lastSyncTime != null
                    ? Text('上次同步: ${_formatTime(_syncManager.lastSyncTime!)}')
                    : const Text('尚未同步'),
          ),

          // 手动同步按钮
          ListTile(
            leading:
                _loading
                    ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.sync),
            title: const Text('立即同步'),
            subtitle:
                _syncManager.errorMessage != null
                    ? Text(
                      _syncManager.errorMessage!,
                      style: TextStyle(color: colorScheme.error),
                    )
                    : null,
            onTap: _loading ? null : _handleSync,
          ),

          // 断开连接
          ListTile(
            leading: Icon(Icons.link_off, color: colorScheme.error),
            title: Text('断开连接', style: TextStyle(color: colorScheme.error)),
            onTap: _handleDisconnect,
          ),
        ] else ...[
          // 未连接状态
          ListTile(
            leading: const Icon(Icons.cloud_off),
            title: const Text('未连接'),
            subtitle: const Text('连接 GitHub 以同步书签、阅读进度等数据'),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton.icon(
              onPressed: _loading ? null : _handleConnect,
              icon:
                  _loading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.login),
              label: const Text('连接 GitHub'),
            ),
          ),
        ],
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  Future<void> _handleConnect() async {
    setState(() => _loading = true);

    try {
      // 1. 开始 Device Flow
      final flowData = await _syncManager.startDeviceFlow();

      // 2. 显示 User Code 对话框
      if (!mounted) return;
      final success = await _showDeviceCodeDialog(flowData);

      if (success && mounted) {
        // 3. 检查密码 (无密码则提示设置)
        final existingPassword = await _syncManager.getSyncPassword();
        if (existingPassword == null) {
          await _showSetPasswordDialog();
        }

        // 4. 初次同步
        await _syncManager.sync();

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('连接成功！')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('连接失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _showDeviceCodeDialog(DeviceFlowResponse flowData) async {
    bool success = false;
    int remainingSeconds = flowData.expiresIn;
    final expireTime = DateTime.now().add(
      Duration(seconds: flowData.expiresIn),
    ); // 计算过期时间

    // 使用 ValueNotifier 控制对话框状态
    final dialogClosed = ValueNotifier<bool>(false);
    NavigatorState? navigator;
    Timer? timer; // UI 倒计时定时器

    // 在对话框显示后启动轮询
    Future<void> startPolling() async {
      try {
        final result = await _syncManager.completeDeviceFlow(
          flowData,
          // 移除 onTick，不再依赖轮询回调更新 UI
        );
        success = result;
      } catch (e) {
        success = false;
      } finally {
        timer?.cancel(); // 停止倒计时
        if (!dialogClosed.value && navigator?.mounted == true) {
          navigator?.pop();
        }
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // 保存 navigator 引用
        navigator = Navigator.of(dialogContext);
        bool pollStarted = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 确保只启动一次轮询和定时器
            if (!pollStarted) {
              pollStarted = true;

              // 启动 UI 倒计时 (每秒刷新)
              timer = Timer.periodic(const Duration(seconds: 1), (t) {
                if (dialogClosed.value) {
                  t.cancel();
                  return;
                }

                final remaining =
                    expireTime.difference(DateTime.now()).inSeconds;
                if (remaining <= 0) {
                  t.cancel();
                }

                // 只有当秒数变化时才刷新（其实每秒都会变）
                setDialogState(() {
                  remainingSeconds = remaining > 0 ? remaining : 0;
                });
              });

              // 延迟启动轮询任务
              Future.microtask(() => startPolling());
            }

            return AlertDialog(
              title: const Text('连接 GitHub'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('请在浏览器中访问：'),
                  const SizedBox(height: 8),
                  SelectableText(
                    flowData.verificationUri,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('然后输入验证码：'),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        flowData.userCode,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: flowData.userCode),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制验证码')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '剩余时间: ${remainingSeconds ~/ 60}:${(remainingSeconds % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color:
                          remainingSeconds < 60
                              ? Theme.of(context).colorScheme.error
                              : null,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    launchUrl(Uri.parse(flowData.verificationUri));
                  },
                  child: const Text('打开浏览器'),
                ),
                TextButton(
                  onPressed: () {
                    dialogClosed.value = true;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );

    dialogClosed.value = true;
    return success;
  }

  Future<void> _showSetPasswordDialog() async {
    final controller = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('设置同步密码'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('此密码用于加密同步数据。'),
                  const Text(
                    '请牢记密码，忘记将无法恢复数据！',
                    style: TextStyle(color: Colors.orange),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: '密码 (大小写字母+数字, 8-32位)',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.vpn_key, size: 16),
                        label: const Text('生成并复制强密码'),
                        onPressed: () {
                          final newPassword =
                              SyncCrypto.generateSecurePassword();
                          controller.text = newPassword;
                          Clipboard.setData(ClipboardData(text: newPassword));
                          setDialogState(() {
                            if (SyncCrypto.isValidPassword(newPassword)) {
                              errorText = '已生成强密码并复制到剪贴板！';
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () async {
                    final password = controller.text;
                    if (!SyncCrypto.isValidPassword(password)) {
                      setDialogState(() {
                        errorText = '需包含大小写字母和数字，8-32位';
                      });
                      return;
                    }
                    await _syncManager.setSyncPassword(password);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleSync() async {
    setState(() => _loading = true);
    try {
      await _syncManager.sync();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('同步成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('同步失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('断开连接'),
            content: const Text('断开后需重新授权才能同步。已保存的同步密码会保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('断开'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _syncManager.disconnect();
      if (mounted) setState(() {});
    }
  }
}
