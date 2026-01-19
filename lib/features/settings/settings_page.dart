import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novella/core/utils/font_manager.dart';
import 'package:novella/main.dart' show rustLibInitialized, rustLibInitError;
import 'package:novella/features/settings/source_code_page.dart';
import 'package:novella/features/settings/log_viewer_page.dart';
import 'package:novella/features/settings/sync_settings_section.dart';
import 'package:novella/features/auth/login_page.dart';
import 'package:novella/core/sync/sync_manager.dart';
import 'package:novella/features/book/book_detail_page.dart'
    show BookDetailPageState;
import 'package:novella/data/services/book_info_cache_service.dart';
import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:novella/features/settings/theme_selection_page.dart';

/// 设置状态模型
class AppSettings {
  final double fontSize;
  final String theme; // 'system'（系统）, 'light'（浅色）, 'dark'（深色）
  final String version; // App 版本号
  final String convertType; // 'none'（关闭）, 't2s'（繁转简）, 's2t'（简转繁）
  final bool showChapterNumber;
  final bool fontCacheEnabled;
  final int fontCacheLimit; // 10-60
  final String homeRankType; // 'daily'（日）, 'weekly'（周）, 'monthly'（月）
  final bool oledBlack;
  final bool cleanChapterTitle;
  final bool ignoreJapanese;
  final bool ignoreAI;
  final bool ignoreLevel6;
  final List<String> homeModuleOrder;
  final List<String> enabledHomeModules;
  final bool bookDetailCacheEnabled;
  final List<String> bookTypeBadgeScopes;
  final bool coverColorExtraction; // 封面取色开关
  final int seedColorValue; // 主题种子色 ARGB 值
  final bool useSystemColor; // 是否使用系统动态颜色
  final int dynamicSchemeVariant; // 动态配色方案变体索引 (0: TonalSpot, etc)
  final bool useCustomTheme; // 是否使用自定义主题模式 (Tab 状态)
  final bool notchedDisplayMode; // 异形屏适配模式（刘海屏/挖孔屏优化）

  static const defaultModuleOrder = ['stats', 'ranking', 'recentlyUpdated'];
  static const defaultEnabledModules = ['stats', 'ranking', 'recentlyUpdated'];
  static const defaultBookTypeBadgeScopes = [
    'ranking',
    'recent',
    'search',
    'shelf',
    'history',
  ];

  const AppSettings({
    this.fontSize = 18.0,
    this.theme = 'system',
    this.version = '', // 默认空，加载后更新
    this.convertType = 'none',
    this.showChapterNumber = true,
    this.fontCacheEnabled = true,
    this.fontCacheLimit = 30,
    this.homeRankType = 'weekly',
    this.oledBlack = false,
    this.cleanChapterTitle = true,
    this.ignoreJapanese = false,
    this.ignoreAI = false,
    this.ignoreLevel6 = true, // 默认开启 - 隐藏 Level6 书籍
    this.homeModuleOrder = defaultModuleOrder,
    this.enabledHomeModules = defaultEnabledModules,
    this.bookDetailCacheEnabled = true,
    this.bookTypeBadgeScopes = defaultBookTypeBadgeScopes,
    this.coverColorExtraction = false, // 默认关闭
    this.seedColorValue = 0xFFB71C1C, // 勃艮第红
    this.useSystemColor = false,
    this.dynamicSchemeVariant = 0, // 默认: TonalSpot
    this.useCustomTheme = false, // 默认使用预设 Tab
    this.notchedDisplayMode = false, // 默认关闭异形屏适配
  });

  AppSettings copyWith({
    double? fontSize,
    String? theme,
    String? version,
    String? convertType,
    bool? showChapterNumber,
    bool? fontCacheEnabled,
    int? fontCacheLimit,
    String? homeRankType,
    bool? oledBlack,
    bool? cleanChapterTitle,
    bool? ignoreJapanese,
    bool? ignoreAI,
    bool? ignoreLevel6,
    List<String>? homeModuleOrder,
    List<String>? enabledHomeModules,
    bool? bookDetailCacheEnabled,
    List<String>? bookTypeBadgeScopes,
    bool? coverColorExtraction,
    int? seedColorValue,
    bool? useSystemColor,
    int? dynamicSchemeVariant,
    bool? useCustomTheme,
    bool? notchedDisplayMode,
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
      version: version ?? this.version,
      convertType: convertType ?? this.convertType,
      showChapterNumber: showChapterNumber ?? this.showChapterNumber,
      fontCacheEnabled: fontCacheEnabled ?? this.fontCacheEnabled,
      fontCacheLimit: fontCacheLimit ?? this.fontCacheLimit,
      homeRankType: homeRankType ?? this.homeRankType,
      oledBlack: oledBlack ?? this.oledBlack,
      cleanChapterTitle: cleanChapterTitle ?? this.cleanChapterTitle,
      ignoreJapanese: ignoreJapanese ?? this.ignoreJapanese,
      ignoreAI: ignoreAI ?? this.ignoreAI,
      ignoreLevel6: ignoreLevel6 ?? this.ignoreLevel6,
      homeModuleOrder: homeModuleOrder ?? this.homeModuleOrder,
      enabledHomeModules: enabledHomeModules ?? this.enabledHomeModules,
      bookDetailCacheEnabled:
          bookDetailCacheEnabled ?? this.bookDetailCacheEnabled,
      bookTypeBadgeScopes: bookTypeBadgeScopes ?? this.bookTypeBadgeScopes,
      coverColorExtraction: coverColorExtraction ?? this.coverColorExtraction,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      useSystemColor: useSystemColor ?? this.useSystemColor,
      dynamicSchemeVariant:
          dynamicSchemeVariant ?? (this.dynamicSchemeVariant as int?) ?? 0,
      useCustomTheme: useCustomTheme ?? (this.useCustomTheme as bool?) ?? false,
      notchedDisplayMode: notchedDisplayMode ?? this.notchedDisplayMode,
    );
  }

  /// 检查模块是否启用
  bool isModuleEnabled(String moduleId) =>
      enabledHomeModules.contains(moduleId);

  /// 检查指定范围是否启用书籍类型角标
  bool isBookTypeBadgeEnabled(String scope) =>
      bookTypeBadgeScopes.contains(scope);
}

/// 基于 Riverpod 3.x Notifier API 的设置通知器
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _loadSettings();
    return AppSettings(
      useSystemColor: Platform.isAndroid || Platform.isWindows,
      notchedDisplayMode: false, // 默认关闭异形屏适配
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();

    developer.log(
      'Loaded settings: ignoreJapanese=${prefs.getBool('setting_ignoreJapanese')}, ignoreAI=${prefs.getBool('setting_ignoreAI')}',
      name: 'Settings',
    );
    state = AppSettings(
      fontSize: prefs.getDouble('setting_fontSize') ?? 18.0,
      theme: prefs.getString('setting_theme') ?? 'system',
      version: packageInfo.version,
      convertType: prefs.getString('setting_convertType') ?? 'none',
      showChapterNumber: prefs.getBool('setting_showChapterNumber') ?? true,
      fontCacheEnabled: prefs.getBool('setting_fontCacheEnabled') ?? true,
      fontCacheLimit: prefs.getInt('setting_fontCacheLimit') ?? 30,
      homeRankType: prefs.getString('setting_homeRankType') ?? 'weekly',
      oledBlack: prefs.getBool('setting_oledBlack') ?? false,
      cleanChapterTitle: prefs.getBool('setting_cleanChapterTitle') ?? true,
      ignoreJapanese: prefs.getBool('setting_ignoreJapanese') ?? false,
      ignoreAI: prefs.getBool('setting_ignoreAI') ?? false,
      ignoreLevel6: prefs.getBool('setting_ignoreLevel6') ?? true, // 默认开启
      homeModuleOrder: List<String>.from(
        prefs.getStringList('setting_homeModuleOrder') ??
            AppSettings.defaultModuleOrder,
      ),
      enabledHomeModules: List<String>.from(
        prefs.getStringList('setting_enabledHomeModules') ??
            AppSettings.defaultEnabledModules,
      ),
      bookDetailCacheEnabled:
          prefs.getBool('setting_bookDetailCacheEnabled') ?? true,
      bookTypeBadgeScopes: List<String>.from(
        prefs.getStringList('setting_bookTypeBadgeScopes') ??
            AppSettings.defaultBookTypeBadgeScopes,
      ),
      coverColorExtraction:
          prefs.getBool('setting_coverColorExtraction') ?? false,
      seedColorValue: prefs.getInt('setting_seedColorValue') ?? 0xFFB71C1C,
      // 在 Android 和 Windows 上默认启用系统颜色
      useSystemColor:
          prefs.getBool('setting_useSystemColor') ??
          (Platform.isAndroid || Platform.isWindows),
      dynamicSchemeVariant: prefs.getInt('setting_dynamicSchemeVariant') ?? 0,
      useCustomTheme: prefs.getBool('setting_useCustomTheme') ?? false,
      notchedDisplayMode: prefs.getBool('setting_notchedDisplayMode') ?? false,
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
    await prefs.setBool('setting_ignoreJapanese', state.ignoreJapanese);
    await prefs.setBool('setting_ignoreAI', state.ignoreAI);
    await prefs.setBool('setting_ignoreLevel6', state.ignoreLevel6);
    await prefs.setStringList('setting_homeModuleOrder', state.homeModuleOrder);
    await prefs.setStringList(
      'setting_enabledHomeModules',
      state.enabledHomeModules,
    );
    await prefs.setBool(
      'setting_bookDetailCacheEnabled',
      state.bookDetailCacheEnabled,
    );
    await prefs.setStringList(
      'setting_bookTypeBadgeScopes',
      state.bookTypeBadgeScopes,
    );
    await prefs.setBool(
      'setting_coverColorExtraction',
      state.coverColorExtraction,
    );
    await prefs.setInt('setting_seedColorValue', state.seedColorValue);
    await prefs.setBool('setting_useSystemColor', state.useSystemColor);
    await prefs.setInt(
      'setting_dynamicSchemeVariant',
      state.dynamicSchemeVariant,
    );
    await prefs.setBool('setting_useCustomTheme', state.useCustomTheme);
    await prefs.setBool('setting_notchedDisplayMode', state.notchedDisplayMode);
  }

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
    _save();
  }

  void setTheme(String theme) {
    state = state.copyWith(theme: theme);
    _save();
    // 清除书籍详情页缓存以强制重新提取新主题的颜色
    BookDetailPageState.clearColorCache();
    BookInfoCacheService().clear();
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
    // 只有在禁用封面取色时才允许开启纯黑模式
    // UI 层也应做限制，这里做二次防护
    if (state.coverColorExtraction && value) {
      return;
    }
    state = state.copyWith(oledBlack: value);
    _save();
  }

  void setCoverColorExtraction(bool value) {
    // 开启封面取色时，强制关闭纯黑模式
    if (value) {
      state = state.copyWith(coverColorExtraction: value, oledBlack: false);
    } else {
      state = state.copyWith(coverColorExtraction: value);
    }
    _save();
    // 清除缓存以重新提取（或不再提取）
    BookDetailPageState.clearColorCache();
    BookInfoCacheService().clear();
  }

  void setCleanChapterTitle(bool value) {
    state = state.copyWith(cleanChapterTitle: value);
    _save();
  }

  void setIgnoreJapanese(bool value) {
    state = state.copyWith(ignoreJapanese: value);
    _save();
  }

  void setIgnoreAI(bool value) {
    state = state.copyWith(ignoreAI: value);
    _save();
  }

  void setIgnoreLevel6(bool value) {
    state = state.copyWith(ignoreLevel6: value);
    _save();
  }

  void setHomeModuleOrder(List<String> order) {
    state = state.copyWith(homeModuleOrder: order);
    _save();
  }

  void setEnabledHomeModules(List<String> modules) {
    state = state.copyWith(enabledHomeModules: modules);
    _save();
  }

  void setBookDetailCacheEnabled(bool value) {
    state = state.copyWith(bookDetailCacheEnabled: value);
    _save();
  }

  /// 同时更新排序和启用模块
  void setHomeModuleConfig({
    required List<String> order,
    required List<String> enabled,
  }) {
    state = state.copyWith(homeModuleOrder: order, enabledHomeModules: enabled);
    _save();
  }

  void setBookTypeBadgeScopes(List<String> scopes) {
    state = state.copyWith(bookTypeBadgeScopes: scopes);
    _save();
  }

  void setSeedColor(int colorValue) {
    state = state.copyWith(seedColorValue: colorValue);
    _save();
    // 清除缓存以应用新主题色
    BookDetailPageState.clearColorCache();
    BookInfoCacheService().clear();
  }

  void setUseSystemColor(bool value) {
    state = state.copyWith(useSystemColor: value);
    _save();
    // 清除缓存以应用新主题色
    BookDetailPageState.clearColorCache();
    BookInfoCacheService().clear();
  }

  void setDynamicSchemeVariant(int variantIndex) {
    state = state.copyWith(dynamicSchemeVariant: variantIndex);
    _save();
    // 清除缓存以应用新变体
    BookDetailPageState.clearColorCache();
    BookInfoCacheService().clear();
  }

  void setUseCustomTheme(bool useCustom) {
    state = state.copyWith(useCustomTheme: useCustom);
    _save();
  }

  void setNotchedDisplayMode(bool value) {
    state = state.copyWith(notchedDisplayMode: value);
    _save();
  }
}

/// 设置提供者（Riverpod 3.x 语法）
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// 设置页面组件
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

            // 阅读设置区域
            _buildSectionHeader(context, '阅读'),

            // 字体大小
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

            // 繁简转换
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
                    subtitle: '阅读时自动转换文字',
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

            // 显示章节序号
            SwitchListTile(
              secondary: const Icon(Icons.format_list_numbered),
              title: const Text('显示章节序号'),
              value: settings.showChapterNumber,
              onChanged: (value) => notifier.setShowChapterNumber(value),
            ),

            // 简化续读按钮的章节标题
            SwitchListTile(
              secondary: const Icon(Icons.auto_fix_high),
              title: const Text('简化章节标题'),
              subtitle: const Text('实验性功能，仅对续读按钮生效'),
              value: settings.cleanChapterTitle,
              onChanged: (value) => notifier.setCleanChapterTitle(value),
            ),

            // 异形屏适配模式
            SwitchListTile(
              secondary: const Icon(Icons.smartphone),
              title: const Text('异形屏优化'),
              subtitle: const Text('为刘海屏/挖孔屏优化阅读体验'),
              value: settings.notchedDisplayMode,
              onChanged: (value) => notifier.setNotchedDisplayMode(value),
            ),

            const Divider(),

            // 内容过滤区域
            _buildSectionHeader(context, '内容'),
            ListTile(
              leading: const Icon(Icons.filter_list),
              title: const Text('书籍过滤'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getFilterSummary(settings),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap: () => _showContentFilterSheet(context),
            ),

            // 首页榜单类型
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
                    subtitle: '选择首页排行榜的时间范围',
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

            // 首页模块排序
            ListTile(
              leading: const Icon(Icons.reorder),
              title: const Text('首页管理'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getHomeModuleSummary(settings),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap: () => _showModuleOrderSheet(context),
            ),

            // Book Type Badge Scopes
            ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: const Text('类型标记'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getBookTypeBadgeSummary(settings),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap: () => _showBookTypeBadgeSheet(context),
            ),

            const Divider(),

            // 外观区域
            _buildSectionHeader(context, '外观'),

            // 主题与颜色
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('主题与颜色'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // 使用当前主题的 primary 色（已考虑系统颜色）
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ThemeSelectionPage(),
                  ),
                );
              },
            ),

            // 封面取色
            SwitchListTile(
              secondary: const Icon(Icons.colorize),
              title: const Text('封面取色'),
              subtitle: const Text('从封面提取颜色作为详情页主题'),
              value: settings.coverColorExtraction,
              onChanged: (value) => notifier.setCoverColorExtraction(value),
            ),

            // OLED 纯黑模式
            SwitchListTile(
              secondary: const Icon(Icons.contrast),
              title: const Text('纯黑模式'),
              subtitle: Text(
                settings.coverColorExtraction ? '需关闭封面取色' : '更深邃的黑色背景',
              ),
              value: settings.oledBlack,
              onChanged:
                  // 仅在深色模式且未开启封面取色时可用
                  (colorScheme.brightness == Brightness.dark &&
                          !settings.coverColorExtraction)
                      ? (value) => notifier.setOledBlack(value)
                      : null,
            ),

            const Divider(),

            // 缓存管理区域
            _buildSectionHeader(context, '缓存'),

            // 书籍详情页缓存
            SwitchListTile(
              secondary: const Icon(Icons.menu_book),
              title: const Text('详情页缓存'),
              subtitle: const Text('缓存访问过的书籍详情，仅限单次会话'),
              value: settings.bookDetailCacheEnabled,
              onChanged: (value) => notifier.setBookDetailCacheEnabled(value),
            ),

            // 字体缓存开关
            SwitchListTile(
              secondary: const Icon(Icons.cached),
              title: const Text('字体缓存'),
              subtitle: Text(settings.fontCacheEnabled ? '启用' : '禁用'),
              value: settings.fontCacheEnabled,
              onChanged: (value) => notifier.setFontCacheEnabled(value),
            ),

            // 字体缓存限制滑块（仅在启用缓存时显示）
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

            // 清除所有缓存按钮
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

            // 云同步区域
            const SyncSettingsSection(),

            const Divider(),

            // 关于区域
            _buildSectionHeader(context, '关于'),

            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('版本'),
              subtitle: Text(settings.version),
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

            // 调试日志
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('调试日志'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const LogViewerPage(),
                  ),
                );
              },
            ),

            // 调试：RustLib FFI 状态
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

            // 退出登录按钮
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
    final syncManager = SyncManager();
    final isGistConnected = syncManager.isConnected;

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
                  '退出登录',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 副标题
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  isGistConnected ? '请先断开 GitHub 连接后再退出登录' : '确认退出当前账号？',
                  style: textTheme.bodySmall?.copyWith(
                    color:
                        isGistConnected
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            isGistConnected
                                ? null
                                : () async {
                                  // 先关闭底部弹窗
                                  Navigator.pop(sheetContext);

                                  // 清除 token
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.remove('auth_token');
                                  await prefs.remove('refresh_token');

                                  // 跳转到登录页
                                  if (context.mounted) {
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                        builder: (_) => const LoginPage(),
                                      ),
                                      (route) => false,
                                    );
                                  }
                                },
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          disabledBackgroundColor: colorScheme.error.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        child: const Text('退出'),
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
  }

  void _showClearCacheDialog(BuildContext context) {
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
                  '清除字体缓存',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 副标题
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '将删除所有缓存字体，下次阅读需重新加载',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          Navigator.pop(sheetContext);

                          // 显示加载指示器
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

                          // 清除缓存
                          final deletedCount =
                              await FontManager().clearAllCaches();

                          // 显示结果
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
                          backgroundColor: colorScheme.error,
                        ),
                        child: const Text('清除'),
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
  }

  void _showSelectionSheet<T>({
    required BuildContext context,
    required String title,
    String? subtitle,
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
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
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
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ...options.entries.map((entry) {
                final isSelected = entry.key == currentValue;
                return ListTile(
                  leading: Icon(
                    icons[entry.key],
                    color:
                        isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      color: isSelected ? colorScheme.primary : null,
                      fontWeight: isSelected ? FontWeight.bold : null,
                    ),
                  ),
                  trailing:
                      isSelected
                          ? Icon(Icons.check, color: colorScheme.primary)
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

  String _getFilterSummary(AppSettings settings) {
    final filters = <String>[];
    if (settings.ignoreJapanese) filters.add('日语');
    if (settings.ignoreAI) filters.add('AI');
    if (settings.ignoreLevel6) filters.add('Level6');
    if (filters.isEmpty) return '关闭';
    return filters.join(', ');
  }

  void _showContentFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            final notifier = ref.read(settingsProvider.notifier);
            final colorScheme = Theme.of(context).colorScheme;

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
                      '书籍过滤',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '仅对首页推荐和搜索生效',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.translate,
                      color:
                          settings.ignoreJapanese
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      '忽略日语小说',
                      style: TextStyle(
                        color:
                            settings.ignoreJapanese
                                ? colorScheme.primary
                                : null,
                        fontWeight:
                            settings.ignoreJapanese ? FontWeight.bold : null,
                      ),
                    ),
                    trailing: Switch(
                      value: settings.ignoreJapanese,
                      onChanged: (value) => notifier.setIgnoreJapanese(value),
                    ),
                    onTap:
                        () => notifier.setIgnoreJapanese(
                          !settings.ignoreJapanese,
                        ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.smart_toy_outlined,
                      color:
                          settings.ignoreAI
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      '忽略 AI 生成',
                      style: TextStyle(
                        color: settings.ignoreAI ? colorScheme.primary : null,
                        fontWeight: settings.ignoreAI ? FontWeight.bold : null,
                      ),
                    ),
                    trailing: Switch(
                      value: settings.ignoreAI,
                      onChanged: (value) => notifier.setIgnoreAI(value),
                    ),
                    onTap: () => notifier.setIgnoreAI(!settings.ignoreAI),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.lock_outline,
                      color:
                          settings.ignoreLevel6
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      '忽略 Level 6 书籍',
                      style: TextStyle(
                        color:
                            settings.ignoreLevel6 ? colorScheme.primary : null,
                        fontWeight:
                            settings.ignoreLevel6 ? FontWeight.bold : null,
                      ),
                    ),
                    trailing: Switch(
                      value: settings.ignoreLevel6,
                      onChanged: (value) => notifier.setIgnoreLevel6(value),
                    ),
                    onTap:
                        () => notifier.setIgnoreLevel6(!settings.ignoreLevel6),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showModuleOrderSheet(BuildContext context) {
    const moduleLabels = {
      'stats': '阅读统计',
      'recentlyUpdated': '最近更新',
      'ranking': '近期排行',
    };
    const moduleIcons = {
      'stats': Icons.timer_outlined,
      'recentlyUpdated': Icons.update,
      'ranking': Icons.leaderboard_outlined,
    };
    const allModules = ['stats', 'ranking', 'recentlyUpdated'];

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            final notifier = ref.read(settingsProvider.notifier);
            final colorScheme = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;

            // Separate enabled and disabled modules
            final enabledModules =
                settings.homeModuleOrder
                    .where((m) => settings.enabledHomeModules.contains(m))
                    .toList();
            final disabledModules =
                allModules
                    .where((m) => !settings.enabledHomeModules.contains(m))
                    .toList();

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
                      '首页管理',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '点击切换启用状态，拖拽调整顺序',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // Enabled section header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      '已启用',
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Enabled modules - reorderable
                  if (enabledModules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        '无启用模块',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ReorderableListView(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorder: (oldIndex, newIndex) {
                        final newEnabledOrder = List<String>.from(
                          enabledModules,
                        );
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = newEnabledOrder.removeAt(oldIndex);
                        newEnabledOrder.insert(newIndex, item);
                        // Rebuild full order: enabled modules first, then disabled
                        final newOrder = [
                          ...newEnabledOrder,
                          ...disabledModules,
                        ];
                        notifier.setHomeModuleOrder(newOrder);
                      },
                      children: [
                        for (int i = 0; i < enabledModules.length; i++)
                          ListTile(
                            key: ValueKey(enabledModules[i]),
                            leading: Icon(
                              moduleIcons[enabledModules[i]],
                              color: colorScheme.primary,
                            ),
                            title: Text(
                              moduleLabels[enabledModules[i]] ??
                                  enabledModules[i],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.remove_circle_outline,
                                    color: colorScheme.error,
                                  ),
                                  onPressed: () {
                                    final newEnabled = List<String>.from(
                                      settings.enabledHomeModules,
                                    )..remove(enabledModules[i]);
                                    notifier.setEnabledHomeModules(newEnabled);
                                  },
                                  tooltip: '禁用',
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(
                                      Icons.drag_handle,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  // Disabled section header
                  if (disabledModules.isNotEmpty) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        '已禁用',
                        style: textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Disabled modules - grayed out, tap to enable
                    ...disabledModules.map(
                      (moduleId) => ListTile(
                        leading: Icon(
                          moduleIcons[moduleId],
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        title: Text(
                          moduleLabels[moduleId] ?? moduleId,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.add_circle_outline,
                            color: colorScheme.primary,
                          ),
                          onPressed: () {
                            final newEnabled = List<String>.from(
                              settings.enabledHomeModules,
                            )..add(moduleId);
                            // Also add to order if not present
                            final newOrder = List<String>.from(
                              settings.homeModuleOrder,
                            );
                            if (!newOrder.contains(moduleId)) {
                              newOrder.add(moduleId);
                            }
                            notifier.setHomeModuleConfig(
                              order: newOrder,
                              enabled: newEnabled,
                            );
                          },
                          tooltip: '启用',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getHomeModuleSummary(AppSettings settings) {
    final enabledCount = settings.enabledHomeModules.length;
    if (enabledCount == 0) return '不要全部关闭啦';
    if (enabledCount == 3) return '全部';
    return '$enabledCount 个模块';
  }

  String _getBookTypeBadgeSummary(AppSettings settings) {
    final enabledCount = settings.bookTypeBadgeScopes.length;
    if (enabledCount == 0) return '关闭';
    if (enabledCount == 5) return '全部';
    return '$enabledCount 个区域';
  }

  void _showBookTypeBadgeSheet(BuildContext context) {
    const scopeLabels = {
      'ranking': '排行榜',
      'recent': '最近更新',
      'search': '搜索',
      'shelf': '书架',
      'history': '历史',
    };
    const scopeIcons = {
      'ranking': Icons.leaderboard_outlined,
      'recent': Icons.update,
      'search': Icons.search,
      'shelf': Icons.collections_bookmark_outlined,
      'history': Icons.history,
    };
    const allScopes = ['ranking', 'recent', 'search', 'shelf', 'history'];

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            final notifier = ref.read(settingsProvider.notifier);
            final colorScheme = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;

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
                      '类型标记',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '在封面右下角显示书籍类型图标（录入/翻译/转载）',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ...allScopes.map((scopeId) {
                    final isEnabled = settings.bookTypeBadgeScopes.contains(
                      scopeId,
                    );
                    return ListTile(
                      leading: Icon(
                        scopeIcons[scopeId],
                        color:
                            isEnabled
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        scopeLabels[scopeId] ?? scopeId,
                        style: TextStyle(
                          color: isEnabled ? colorScheme.primary : null,
                          fontWeight: isEnabled ? FontWeight.bold : null,
                        ),
                      ),
                      trailing: Switch(
                        value: isEnabled,
                        onChanged: (value) {
                          final newScopes = List<String>.from(
                            settings.bookTypeBadgeScopes,
                          );
                          if (value) {
                            if (!newScopes.contains(scopeId)) {
                              newScopes.add(scopeId);
                            }
                          } else {
                            newScopes.remove(scopeId);
                          }
                          notifier.setBookTypeBadgeScopes(newScopes);
                        },
                      ),
                      onTap: () {
                        final newScopes = List<String>.from(
                          settings.bookTypeBadgeScopes,
                        );
                        if (isEnabled) {
                          newScopes.remove(scopeId);
                        } else {
                          newScopes.add(scopeId);
                        }
                        notifier.setBookTypeBadgeScopes(newScopes);
                      },
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
