import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novella/core/utils/font_manager.dart';
import 'package:novella/main.dart' show rustLibInitialized, rustLibInitError;
import 'dart:io' show Platform;

/// Settings state model
class AppSettings {
  final double fontSize;
  final String theme; // 'system', 'light', 'dark'
  final String convertType; // 'none', 't2s', 's2t'
  final bool showChapterNumber;
  final bool fontCacheEnabled;
  final int fontCacheLimit; // 10-60
  final String homeRankType; // 'daily', 'weekly', 'monthly'

  const AppSettings({
    this.fontSize = 18.0,
    this.theme = 'system',
    this.convertType = 'none',
    this.showChapterNumber = true,
    this.fontCacheEnabled = true,
    this.fontCacheLimit = 30,
    this.homeRankType = 'weekly',
  });

  AppSettings copyWith({
    double? fontSize,
    String? theme,
    String? convertType,
    bool? showChapterNumber,
    bool? fontCacheEnabled,
    int? fontCacheLimit,
    String? homeRankType,
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
      convertType: convertType ?? this.convertType,
      showChapterNumber: showChapterNumber ?? this.showChapterNumber,
      fontCacheEnabled: fontCacheEnabled ?? this.fontCacheEnabled,
      fontCacheLimit: fontCacheLimit ?? this.fontCacheLimit,
      homeRankType: homeRankType ?? this.homeRankType,
    );
  }
}

/// Settings notifier using Riverpod 3.x Notifier API
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _loadSettings();
    return const AppSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      fontSize: prefs.getDouble('setting_fontSize') ?? 18.0,
      theme: prefs.getString('setting_theme') ?? 'system',
      convertType: prefs.getString('setting_convertType') ?? 'none',
      showChapterNumber: prefs.getBool('setting_showChapterNumber') ?? true,
      fontCacheEnabled: prefs.getBool('setting_fontCacheEnabled') ?? true,
      fontCacheLimit: prefs.getInt('setting_fontCacheLimit') ?? 30,
      homeRankType: prefs.getString('setting_homeRankType') ?? 'weekly',
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('setting_fontSize', state.fontSize);
    await prefs.setString('setting_theme', state.theme);
    await prefs.setString('setting_convertType', state.convertType);
    await prefs.setBool('setting_showChapterNumber', state.showChapterNumber);
    await prefs.setBool('setting_fontCacheEnabled', state.fontCacheEnabled);
    await prefs.setInt('setting_fontCacheLimit', state.fontCacheLimit);
    await prefs.setString('setting_homeRankType', state.homeRankType);
  }

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
    _save();
  }

  void setTheme(String theme) {
    state = state.copyWith(theme: theme);
    _save();
  }

  void setConvertType(String type) {
    state = state.copyWith(convertType: type);
    _save();
  }

  void setShowChapterNumber(bool show) {
    state = state.copyWith(showChapterNumber: show);
    _save();
  }

  void setFontCacheEnabled(bool enabled) {
    state = state.copyWith(fontCacheEnabled: enabled);
    _save();
  }

  void setFontCacheLimit(int limit) {
    state = state.copyWith(fontCacheLimit: limit.clamp(10, 60));
    _save();
  }

  void setHomeRankType(String type) {
    state = state.copyWith(homeRankType: type);
    _save();
  }
}

/// Provider for settings (Riverpod 3.x syntax)
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Settings page widget
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // Reading Settings Section
          _buildSectionHeader(context, '阅读设置'),

          // Font Size
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('字体大小'),
            subtitle: Text('${settings.fontSize.toInt()} px'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: settings.fontSize,
                min: 12,
                max: 32,
                divisions: 20,
                label: '${settings.fontSize.toInt()}',
                onChanged: (value) => notifier.setFontSize(value),
              ),
            ),
          ),

          // Text Conversion
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('繁简转换'),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'none', label: Text('关闭')),
                ButtonSegment(value: 't2s', label: Text('繁→简')),
                ButtonSegment(value: 's2t', label: Text('简→繁')),
              ],
              selected: {settings.convertType},
              onSelectionChanged: (selected) {
                notifier.setConvertType(selected.first);
              },
            ),
          ),

          // Show Chapter Number
          SwitchListTile(
            secondary: const Icon(Icons.format_list_numbered),
            title: const Text('显示章节序号'),
            value: settings.showChapterNumber,
            onChanged: (value) => notifier.setShowChapterNumber(value),
          ),

          const Divider(),

          // Appearance Section
          _buildSectionHeader(context, '外观'),

          // Theme
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('系统')),
                ButtonSegment(value: 'light', label: Text('浅色')),
                ButtonSegment(value: 'dark', label: Text('深色')),
              ],
              selected: {settings.theme},
              onSelectionChanged: (selected) {
                notifier.setTheme(selected.first);
              },
            ),
          ),

          // Home Rank Type
          ListTile(
            leading: const Icon(Icons.leaderboard_outlined),
            title: const Text('首页榜单'),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('日榜')),
                ButtonSegment(value: 'weekly', label: Text('周榜')),
                ButtonSegment(value: 'monthly', label: Text('月榜')),
              ],
              selected: {settings.homeRankType},
              onSelectionChanged: (selected) {
                notifier.setHomeRankType(selected.first);
              },
            ),
          ),

          const Divider(),

          // Cache Management Section
          _buildSectionHeader(context, '缓存管理'),

          // Font Cache Enable Switch
          SwitchListTile(
            secondary: const Icon(Icons.cached),
            title: const Text('启用字体缓存'),
            subtitle: Text(settings.fontCacheEnabled ? '启用' : '禁用'),
            value: settings.fontCacheEnabled,
            onChanged: (value) => notifier.setFontCacheEnabled(value),
          ),

          // Font Cache Limit Slider (only visible when cache is enabled)
          if (settings.fontCacheEnabled)
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('缓存容量'),
              subtitle: Text('保留 ${settings.fontCacheLimit} 本'),
              trailing: SizedBox(
                width: 180,
                child: Slider(
                  value: settings.fontCacheLimit.toDouble(),
                  min: 10,
                  max: 60,
                  divisions: 10,
                  label: '${settings.fontCacheLimit}',
                  onChanged:
                      (value) => notifier.setFontCacheLimit(value.toInt()),
                ),
              ),
            ),

          // Clear All Cache Button
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '清除所有字体缓存',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => _showClearCacheDialog(context),
          ),

          const Divider(),

          // About Section
          _buildSectionHeader(context, '关于'),

          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本'),
            subtitle: Text('1.0.0'),
          ),

          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源协议'),
            subtitle: const Text('MIT License'),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Novella',
                applicationVersion: '1.0.0',
              );
            },
          ),

          // Debug: RustLib FFI Status
          ListTile(
            leading: Icon(
              rustLibInitialized ? Icons.check_circle : Icons.error,
              color: rustLibInitialized ? Colors.green : colorScheme.error,
            ),
            title: const Text('Rust FFI 状态'),
            subtitle: Text(
              rustLibInitialized
                  ? '已初始化 (${Platform.isIOS
                      ? "iOS"
                      : Platform.isMacOS
                      ? "macOS"
                      : Platform.isAndroid
                      ? "Android"
                      : "Windows"})'
                  : '初始化失败: ${rustLibInitError ?? "未知错误"}',
              style: TextStyle(
                color: rustLibInitialized ? null : colorScheme.error,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Logout button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(context),
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('退出登录'),
            content: const Text('确认退出？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('auth_token');
                  await prefs.remove('refresh_token');
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
                child: const Text('确定'),
              ),
            ],
          ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            icon: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
              size: 48,
            ),
            title: const Text('清除字体缓存'),
            content: const Text('将删除所有缓存字体，下次阅读需重新加载。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);

                  // Show loading indicator
                  final scaffold = ScaffoldMessenger.of(context);
                  scaffold.showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 16),
                          Text('清除中'),
                        ],
                      ),
                      duration: Duration(seconds: 1),
                    ),
                  );

                  // Clear cache
                  final deletedCount = await FontManager().clearAllCaches();

                  // Show result
                  scaffold.hideCurrentSnackBar();
                  scaffold.showSnackBar(
                    SnackBar(
                      content: Text('已清除 $deletedCount 项'),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: '确定',
                        onPressed: () => scaffold.hideCurrentSnackBar(),
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('清除'),
              ),
            ],
          ),
    );
  }
}
