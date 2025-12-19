import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novella/core/utils/font_manager.dart';
import 'package:novella/main.dart' show rustLibInitialized, rustLibInitError;
import 'package:novella/features/settings/source_code_page.dart';
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
  final bool oledBlack;
  final bool cleanChapterTitle; // Clean chapter title for continue button

  const AppSettings({
    this.fontSize = 18.0,
    this.theme = 'system',
    this.convertType = 'none',
    this.showChapterNumber = true,
    this.fontCacheEnabled = true,
    this.fontCacheLimit = 30,
    this.homeRankType = 'weekly',
    this.oledBlack = false,
    this.cleanChapterTitle = false,
  });

  AppSettings copyWith({
    double? fontSize,
    String? theme,
    String? convertType,
    bool? showChapterNumber,
    bool? fontCacheEnabled,
    int? fontCacheLimit,
    String? homeRankType,
    bool? oledBlack,
    bool? cleanChapterTitle,
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
      convertType: convertType ?? this.convertType,
      showChapterNumber: showChapterNumber ?? this.showChapterNumber,
      fontCacheEnabled: fontCacheEnabled ?? this.fontCacheEnabled,
      fontCacheLimit: fontCacheLimit ?? this.fontCacheLimit,
      homeRankType: homeRankType ?? this.homeRankType,
      oledBlack: oledBlack ?? this.oledBlack,
      cleanChapterTitle: cleanChapterTitle ?? this.cleanChapterTitle,
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
      oledBlack: prefs.getBool('setting_oledBlack') ?? false,
      cleanChapterTitle: prefs.getBool('setting_cleanChapterTitle') ?? false,
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
    await prefs.setBool('setting_oledBlack', state.oledBlack);
    await prefs.setBool('setting_cleanChapterTitle', state.cleanChapterTitle);
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

  void setOledBlack(bool value) {
    state = state.copyWith(oledBlack: value);
    _save();
  }

  void setCleanChapterTitle(bool value) {
    state = state.copyWith(cleanChapterTitle: value);
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
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                '设置',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),

            // Reading Settings Section
            _buildSectionHeader(context, '阅读'),

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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    const {'none': '关闭', 't2s': '繁→简', 's2t': '简→繁'}[settings
                            .convertType] ??
                        '关闭',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap:
                  () => _showSelectionSheet<String>(
                    context: context,
                    title: '繁简转换',
                    currentValue: settings.convertType,
                    options: const {'none': '关闭', 't2s': '繁→简', 's2t': '简→繁'},
                    icons: const {
                      'none': Icons.close,
                      't2s': Icons.arrow_circle_down_outlined,
                      's2t': Icons.arrow_circle_up_outlined,
                    },
                    onSelected: (value) => notifier.setConvertType(value),
                  ),
            ),

            // Show Chapter Number
            SwitchListTile(
              secondary: const Icon(Icons.format_list_numbered),
              title: const Text('显示章节序号'),
              value: settings.showChapterNumber,
              onChanged: (value) => notifier.setShowChapterNumber(value),
            ),

            // Clean Chapter Title for continue button
            SwitchListTile(
              secondary: const Icon(Icons.auto_fix_high),
              title: const Text('简化章节标题'),
              subtitle: const Text('实验性功能，仅对续读按钮生效'),
              value: settings.cleanChapterTitle,
              onChanged: (value) => notifier.setCleanChapterTitle(value),
            ),

            const Divider(),

            // Appearance Section
            _buildSectionHeader(context, '外观'),

            // Theme
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('主题'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    const {'system': '系统', 'light': '浅色', 'dark': '深色'}[settings
                            .theme] ??
                        '系统',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap:
                  () => _showSelectionSheet<String>(
                    context: context,
                    title: '主题',
                    currentValue: settings.theme,
                    options: const {
                      'system': '系统',
                      'light': '浅色',
                      'dark': '深色',
                    },
                    icons: const {
                      'system': Icons.auto_mode,
                      'light': Icons.light_mode,
                      'dark': Icons.dark_mode,
                    },
                    onSelected: (value) => notifier.setTheme(value),
                  ),
            ),

            // Home Rank Type
            ListTile(
              leading: const Icon(Icons.leaderboard_outlined),
              title: const Text('首页榜单'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    const {
                          'daily': '日榜',
                          'weekly': '周榜',
                          'monthly': '月榜',
                        }[settings.homeRankType] ??
                        '周榜',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap:
                  () => _showSelectionSheet<String>(
                    context: context,
                    title: '首页榜单',
                    currentValue: settings.homeRankType,
                    options: const {
                      'daily': '日榜',
                      'weekly': '周榜',
                      'monthly': '月榜',
                    },
                    icons: const {
                      'daily': Icons.today,
                      'weekly': Icons.calendar_view_week,
                      'monthly': Icons.calendar_view_month,
                    },
                    onSelected: (value) => notifier.setHomeRankType(value),
                  ),
            ),

            // OLED Black Mode
            SwitchListTile(
              secondary: const Icon(Icons.contrast),
              title: const Text('纯黑模式'),
              subtitle: const Text('禁用封面取色，更深邃的黑色背景'),
              value: settings.oledBlack,
              onChanged:
                  colorScheme.brightness == Brightness.dark
                      ? (value) => notifier.setOledBlack(value)
                      : null,
            ),

            const Divider(),

            // Cache Management Section
            _buildSectionHeader(context, '缓存'),

            // Font Cache Enable Switch
            SwitchListTile(
              secondary: const Icon(Icons.cached),
              title: const Text('字体缓存'),
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
              title: const Text('源代码'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SourceCodePage(),
                  ),
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

  void _showSelectionSheet<T>({
    required BuildContext context,
    required String title,
    required T currentValue,
    required Map<T, String> options,
    required Map<T, IconData> icons,
    required ValueChanged<T> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              ...options.entries.map((entry) {
                final isSelected = entry.key == currentValue;
                return ListTile(
                  leading: Icon(
                    icons[entry.key],
                    color:
                        isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      color:
                          isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                      fontWeight: isSelected ? FontWeight.bold : null,
                    ),
                  ),
                  trailing:
                      isSelected
                          ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                          : null,
                  onTap: () {
                    onSelected(entry.key);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
