import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:novella/features/book/book_detail_page.dart'
    show BookDetailPageState;
import 'package:novella/data/services/book_info_cache_service.dart';

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
  // 阅读背景颜色设置
  final bool readerUseThemeBackground; // 是否使用主题色背景（默认 true）
  final int readerBackgroundColor; // 自定义背景色 ARGB
  final int readerTextColor; // 自定义文字色 ARGB
  final int readerPresetIndex; // 预设方案索引 (0-4)
  final bool readerUseCustomColor; // 是否使用自定颜色 Tab (false = 预设)
  // iOS 显示样式（仅 iOS 平台有效）
  // 'md3' = Material Design 3（默认）, 'ios18' = iOS 18, 'ios26' = iOS 26 液态玻璃
  final String iosDisplayStyle;
  final bool autoCheckUpdate;
  final String ignoredUpdateVersion; // 忽略的更新版本号

  static const defaultModuleOrder = [
    'stats',
    'continueReading',
    'ranking',
    'recentlyUpdated',
  ];
  static const defaultEnabledModules = [
    'stats',
    'continueReading',
    'ranking',
    'recentlyUpdated',
  ];
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
    // 阅读背景颜色默认值
    this.readerUseThemeBackground = true, // 默认使用主题色
    this.readerBackgroundColor = 0xFFFFFFFF, // 默认白色背景
    this.readerTextColor = 0xFF000000, // 默认黑色文字
    this.readerPresetIndex = 0, // 默认第一个预设（白纸）
    this.readerUseCustomColor = false, // 默认使用预设
    this.iosDisplayStyle = 'md3', // 默认使用 MD3 样式
    this.autoCheckUpdate = true, // 默认开启自动检查
    this.ignoredUpdateVersion = '',
  });

  /// 是否使用 iOS 26 液态玻璃样式
  bool get useIOS26Style => iosDisplayStyle == 'ios26' && Platform.isIOS;

  /// 是否使用 iOS 18 样式
  bool get useIOS18Style => iosDisplayStyle == 'ios18' && Platform.isIOS;

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
    // 阅读背景颜色
    bool? readerUseThemeBackground,
    int? readerBackgroundColor,
    int? readerTextColor,
    int? readerPresetIndex,
    bool? readerUseCustomColor,
    String? iosDisplayStyle,
    bool? autoCheckUpdate,
    String? ignoredUpdateVersion,
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
      // 阅读背景颜色
      readerUseThemeBackground:
          readerUseThemeBackground ?? this.readerUseThemeBackground,
      readerBackgroundColor:
          readerBackgroundColor ?? this.readerBackgroundColor,
      readerTextColor: readerTextColor ?? this.readerTextColor,
      readerPresetIndex: readerPresetIndex ?? this.readerPresetIndex,
      readerUseCustomColor: readerUseCustomColor ?? this.readerUseCustomColor,
      iosDisplayStyle: iosDisplayStyle ?? this.iosDisplayStyle,
      autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      ignoredUpdateVersion: ignoredUpdateVersion ?? this.ignoredUpdateVersion,
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
      // 阅读背景颜色
      readerUseThemeBackground:
          prefs.getBool('setting_readerUseThemeBackground') ?? true,
      readerBackgroundColor:
          prefs.getInt('setting_readerBackgroundColor') ?? 0xFFFFFFFF,
      readerTextColor: prefs.getInt('setting_readerTextColor') ?? 0xFF000000,
      readerPresetIndex: prefs.getInt('setting_readerPresetIndex') ?? 0,
      readerUseCustomColor:
          prefs.getBool('setting_readerUseCustomColor') ?? false,
      iosDisplayStyle: prefs.getString('setting_iosDisplayStyle') ?? 'md3',
      autoCheckUpdate: prefs.getBool('setting_autoCheckUpdate') ?? true,
      ignoredUpdateVersion:
          prefs.getString('setting_ignoredUpdateVersion') ?? '',
    );

    // 同步 iOS 显示样式到 PlatformInfo
    if (Platform.isIOS) {
      PlatformInfo.styleOverride = state.iosDisplayStyle;
    }
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
    // 阅读背景颜色
    await prefs.setBool(
      'setting_readerUseThemeBackground',
      state.readerUseThemeBackground,
    );
    await prefs.setInt(
      'setting_readerBackgroundColor',
      state.readerBackgroundColor,
    );
    await prefs.setInt('setting_readerTextColor', state.readerTextColor);
    await prefs.setInt('setting_readerPresetIndex', state.readerPresetIndex);
    await prefs.setBool(
      'setting_readerUseCustomColor',
      state.readerUseCustomColor,
    );
    await prefs.setString('setting_iosDisplayStyle', state.iosDisplayStyle);
    await prefs.setBool('setting_autoCheckUpdate', state.autoCheckUpdate);
    await prefs.setString(
      'setting_ignoredUpdateVersion',
      state.ignoredUpdateVersion,
    );
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

  // ==================== 阅读背景颜色设置 ====================

  void setReaderUseThemeBackground(bool value) {
    state = state.copyWith(readerUseThemeBackground: value);
    _save();
  }

  void setReaderBackgroundColor(int colorValue) {
    state = state.copyWith(readerBackgroundColor: colorValue);
    _save();
  }

  void setReaderTextColor(int colorValue) {
    state = state.copyWith(readerTextColor: colorValue);
    _save();
  }

  void setReaderPresetIndex(int index) {
    state = state.copyWith(readerPresetIndex: index);
    _save();
  }

  void setReaderUseCustomColor(bool value) {
    state = state.copyWith(readerUseCustomColor: value);
    _save();
  }

  /// 一次性设置所有阅读背景相关参数
  void setReaderBackgroundConfig({
    required bool useThemeBackground,
    required int backgroundColor,
    required int textColor,
    required int presetIndex,
    required bool useCustomColor,
  }) {
    state = state.copyWith(
      readerUseThemeBackground: useThemeBackground,
      readerBackgroundColor: backgroundColor,
      readerTextColor: textColor,
      readerPresetIndex: presetIndex,
      readerUseCustomColor: useCustomColor,
    );
    _save();
  }

  // ==================== iOS 显示样式设置 ====================

  void setIosDisplayStyle(String value) {
    state = state.copyWith(iosDisplayStyle: value);
    _save();
    // 同步到 PlatformInfo
    if (Platform.isIOS) {
      PlatformInfo.styleOverride = value;
    }
  }

  void setAutoCheckUpdate(bool value) {
    state = state.copyWith(autoCheckUpdate: value);
    _save();
  }

  void setIgnoredUpdateVersion(String version) {
    state = state.copyWith(ignoredUpdateVersion: version);
    _save();
  }
}

/// 设置提供者
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
