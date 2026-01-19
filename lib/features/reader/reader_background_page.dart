import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'widgets/reader_color_picker_sheet.dart';

/// 预设阅读配色方案
/// 每个方案包含：名称、背景色、文字色
class ReaderColorPreset {
  final String name;
  final Color backgroundColor;
  final Color textColor;

  const ReaderColorPreset({
    required this.name,
    required this.backgroundColor,
    required this.textColor,
  });
}

/// 预设配色列表
const List<ReaderColorPreset> kReaderPresets = [
  ReaderColorPreset(
    name: '白纸',
    backgroundColor: Color(0xFFFFFFFF),
    textColor: Color(0xFF1A1A1A),
  ),
  ReaderColorPreset(
    name: '羊皮纸',
    backgroundColor: Color(0xFFF5F0E6),
    textColor: Color(0xFF3E2723),
  ),
  ReaderColorPreset(
    name: '护眼绿',
    backgroundColor: Color(0xFFCCE8CF),
    textColor: Color(0xFF1B5E20),
  ),
  ReaderColorPreset(
    name: '深色',
    backgroundColor: Color(0xFF2D2D2D),
    textColor: Color(0xFFBDBDBD),
  ),
  ReaderColorPreset(
    name: '纯黑夜间',
    backgroundColor: Color(0xFF000000),
    textColor: Color(0xFF9E9E9E),
  ),
];

/// 阅读背景颜色设置页面
class ReaderBackgroundPage extends ConsumerStatefulWidget {
  const ReaderBackgroundPage({super.key});

  @override
  ConsumerState<ReaderBackgroundPage> createState() =>
      _ReaderBackgroundPageState();
}

class _ReaderBackgroundPageState extends ConsumerState<ReaderBackgroundPage> {
  // 页面内临时状态（应用前预览）
  late bool _tempUseThemeBackground;
  late int _tempBackgroundColor;
  late int _tempTextColor;
  late int _tempPresetIndex;
  int _selectedTab = 0; // 0: 预设颜色, 1: 自定颜色

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _tempUseThemeBackground = settings.readerUseThemeBackground;
    _tempBackgroundColor = settings.readerBackgroundColor;
    _tempTextColor = settings.readerTextColor;
    _tempPresetIndex = settings.readerPresetIndex;

    // 恢复 Tab 状态
    _selectedTab = settings.readerUseCustomColor ? 1 : 0;
  }

  void _apply() {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setReaderBackgroundConfig(
      useThemeBackground: _tempUseThemeBackground,
      backgroundColor: _tempBackgroundColor,
      textColor: _tempTextColor,
      presetIndex: _tempPresetIndex,
      useCustomColor: _selectedTab == 1,
    );
  }

  /// 获取当前预览使用的背景色
  Color get _effectiveBackgroundColor {
    if (_tempUseThemeBackground) {
      // 使用主题色 - 返回 null 表示使用主题色
      return Theme.of(context).colorScheme.surface;
    }
    if (_selectedTab == 0) {
      // 预设模式
      return kReaderPresets[_tempPresetIndex].backgroundColor;
    } else {
      // 自定义模式
      return Color(_tempBackgroundColor);
    }
  }

  /// 获取当前预览使用的文字色
  Color get _effectiveTextColor {
    if (_tempUseThemeBackground) {
      return Theme.of(context).colorScheme.onSurface;
    }
    if (_selectedTab == 0) {
      return kReaderPresets[_tempPresetIndex].textColor;
    } else {
      return Color(_tempTextColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final hasChanges =
        settings.readerUseThemeBackground != _tempUseThemeBackground ||
        settings.readerBackgroundColor != _tempBackgroundColor ||
        settings.readerTextColor != _tempTextColor ||
        settings.readerPresetIndex != _tempPresetIndex ||
        settings.readerUseCustomColor != (_selectedTab == 1);

    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('阅读背景'),
        actions: [
          FilledButton.tonal(
            onPressed: hasChanges ? _apply : null,
            child: const Text('应用'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 预览区域
            Expanded(
              child: Center(
                child: IgnorePointer(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: _effectiveBackgroundColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: 0.1),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _buildPreviewContent(),
                    ),
                  ),
                ),
              ),
            ),

            // 底部控制面板
            _buildBottomPanel(colors),
          ],
        ),
      ),
    );
  }

  /// 预览内容：模拟阅读页面
  Widget _buildPreviewContent() {
    final textColor = _effectiveTextColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节标题
            Text(
              '第一章 示例标题',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // 正文内容
            Expanded(
              child: Text(
                '这是一段示例文字，用于预览当前选择的背景颜色和文字颜色效果。'
                '\n\n'
                '良好的文字与背景对比度可以有效减少眼睛疲劳，提升阅读体验。'
                '\n\n'
                '选择适合自己阅读习惯的配色方案，让阅读更加舒适愉悦。',
                style: TextStyle(color: textColor, fontSize: 16, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel(ColorScheme colors) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 控制卡片
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedTab == 0 ? '选择预设方案' : '自定义配色',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),

                // 核心选择区域（高度锁定为 56）
                SizedBox(
                  height: 56,
                  child:
                      _selectedTab == 0
                          ? _buildPresetSelector(colors)
                          : _buildCustomColorButton(colors),
                ),

                const SizedBox(height: 24),

                // 使用主题色开关
                Row(
                  children: [
                    Text(
                      '使用主题色背景',
                      style: TextStyle(color: colors.onSurface, fontSize: 16),
                    ),
                    const Spacer(),
                    Switch(
                      value: _tempUseThemeBackground,
                      onChanged: (value) {
                        setState(() {
                          _tempUseThemeBackground = value;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Tab 切换器
          _buildBottomTabSwitcher(colors),
        ],
      ),
    );
  }

  /// 预设颜色选择器
  Widget _buildPresetSelector(ColorScheme colors) {
    final isDisabled = _tempUseThemeBackground;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        child: Row(
          children: [
            for (int i = 0; i < kReaderPresets.length; i++) ...[
              _buildPresetOption(i, colors, isDisabled),
              if (i < kReaderPresets.length - 1) const SizedBox(width: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPresetOption(int index, ColorScheme colors, bool isDisabled) {
    final preset = kReaderPresets[index];
    final isSelected = _tempPresetIndex == index;

    return GestureDetector(
      onTap:
          isDisabled
              ? null
              : () {
                setState(() {
                  _tempPresetIndex = index;
                });
              },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 72,
        height: 56,
        decoration: BoxDecoration(
          color:
              isDisabled
                  ? preset.backgroundColor.withValues(alpha: 0.4)
                  : preset.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border:
              isSelected && !isDisabled
                  ? Border.all(color: colors.onSurface, width: 3)
                  : Border.all(
                    color: colors.outline.withValues(alpha: 0.2),
                    width: 1,
                  ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected && !isDisabled)
              Icon(Icons.check, color: preset.textColor, size: 20)
            else
              Text(
                'Aa',
                style: TextStyle(
                  color:
                      isDisabled
                          ? preset.textColor.withValues(alpha: 0.4)
                          : preset.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              preset.name,
              style: TextStyle(
                color:
                    isDisabled
                        ? preset.textColor.withValues(alpha: 0.4)
                        : preset.textColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 自定义颜色按钮
  Widget _buildCustomColorButton(ColorScheme colors) {
    final bgColor = Color(_tempBackgroundColor);
    final textColor = Color(_tempTextColor);
    final isDisabled = _tempUseThemeBackground;

    return GestureDetector(
      onTap: isDisabled ? null : _showColorPickerSheet,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:
              isDisabled
                  ? colors.surfaceContainerHigh.withValues(alpha: 0.5)
                  : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            // 背景色预览
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDisabled ? bgColor.withValues(alpha: 0.5) : bgColor,
                border: Border.all(color: colors.outline, width: 1),
              ),
            ),
            const SizedBox(width: 8),
            // 文字色预览
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    isDisabled ? textColor.withValues(alpha: 0.5) : textColor,
                border: Border.all(color: colors.outline, width: 1),
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '背景 #${bgColor.toARGB32().toRadixString(16).toUpperCase().substring(2)}',
                  style: TextStyle(
                    color:
                        isDisabled
                            ? colors.onSurface.withValues(alpha: 0.5)
                            : colors.onSurface,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                Text(
                  '文字 #${textColor.toARGB32().toRadixString(16).toUpperCase().substring(2)}',
                  style: TextStyle(
                    color:
                        isDisabled
                            ? colors.onSurfaceVariant.withValues(alpha: 0.5)
                            : colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(
              Icons.colorize,
              color:
                  isDisabled
                      ? colors.primary.withValues(alpha: 0.5)
                      : colors.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPickerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ReaderColorPickerSheet(
            initialBackgroundColor: Color(_tempBackgroundColor),
            initialTextColor: Color(_tempTextColor),
            onBackgroundColorChange: (color) {
              setState(() {
                _tempBackgroundColor = color.toARGB32();
              });
            },
            onTextColorChange: (color) {
              setState(() {
                _tempTextColor = color.toARGB32();
              });
            },
          ),
        );
      },
    );
  }

  /// Pixel 风格 Tab 切换器
  Widget _buildBottomTabSwitcher(ColorScheme colors) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _PixelTabItem(
            icon: Icons.palette_outlined,
            label: '预设配色',
            isSelected: _selectedTab == 0,
            colors: colors,
            onTap: () {
              if (_selectedTab != 0) {
                setState(() {
                  _selectedTab = 0;
                });
              }
            },
          ),
          _PixelTabItem(
            icon: Icons.colorize_outlined,
            label: '自定颜色',
            isSelected: _selectedTab == 1,
            colors: colors,
            onTap: () {
              if (_selectedTab != 1) {
                setState(() {
                  _selectedTab = 1;
                });
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Pixel 风格 Tab 项组件
class _PixelTabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final ColorScheme colors;
  final VoidCallback onTap;

  const _PixelTabItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: isSelected ? 6 : 4,
      child: AnimatedContainer(
        duration: Duration(milliseconds: isSelected ? 1000 : 80),
        curve: isSelected ? Curves.fastLinearToSlowEaseIn : Curves.easeOut,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? colors.primaryContainer
                  : colors.primaryContainer.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(24),
        ),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSize(
                  duration: Duration(milliseconds: isSelected ? 1000 : 80),
                  curve:
                      isSelected
                          ? Curves.fastLinearToSlowEaseIn
                          : Curves.easeOut,
                  child:
                      isSelected
                          ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              icon,
                              color: colors.onPrimaryContainer,
                              size: 18,
                            ),
                          )
                          : const SizedBox.shrink(),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color:
                        isSelected
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
