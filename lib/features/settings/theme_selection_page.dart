import 'dart:io' show Platform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'settings_page.dart';
import 'widgets/color_picker_sheet.dart';

/// 预设颜色列表
const List<Color> kPresetColors = [
  Color(0xFFB71C1C), // 勃艮第红 (Burgundy)
  Color(0xFFE65100), // 陶土橙 (Terracotta)
  Color(0xFFFBC02D), // 含羞草黄 (Mustard/Gold)
  Color(0xFF2E7D32), // 森林绿 (Forest Green)
  Color(0xFF00796B), // 青绿松 (Teal)
  Color(0xFF0061A4), // 深海蓝 (Classic Blue)
  Color(0xFF6750A4), // 经典紫 (Baseline Purple)
  Color(0xFFFFFFFF), // 纯白 (White/Monochrome)
];

/// Pixel 风格主题选择页面
class ThemeSelectionPage extends ConsumerStatefulWidget {
  const ThemeSelectionPage({super.key});

  @override
  ConsumerState<ThemeSelectionPage> createState() => _ThemeSelectionPageState();
}

class _ThemeSelectionPageState extends ConsumerState<ThemeSelectionPage> {
  // 页面内临时状态（应用前预览）
  late int _tempSeedColor;
  late String _tempTheme;
  late bool _tempUseSystemColor;
  late int _tempVariant;
  int _selectedTab = 0; // 0: 预设颜色, 1: 自定颜色

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _tempSeedColor = settings.seedColorValue;
    _tempTheme = settings.theme;
    _tempUseSystemColor = settings.useSystemColor;
    _tempVariant = settings.dynamicSchemeVariant;

    // 恢复 Tab 状态
    _selectedTab = settings.useCustomTheme ? 1 : 0;
  }

  void _apply() {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setTheme(_tempTheme);
    notifier.setSeedColor(_tempSeedColor);
    notifier.setUseSystemColor(_tempUseSystemColor);
    notifier.setDynamicSchemeVariant(_tempVariant);
    notifier.setUseCustomTheme(_selectedTab == 1);
    // 不自动返回，需要手动返回
  }

  String _getThemeModeLabel() {
    switch (_tempTheme) {
      case 'light':
        return '浅色模式';
      case 'dark':
        return '深色模式';
      default:
        return '跟随系统';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final hasChanges =
        settings.theme != _tempTheme ||
        settings.useCustomTheme != (_selectedTab == 1) ||
        settings.useSystemColor != _tempUseSystemColor ||
        settings.seedColorValue != _tempSeedColor ||
        settings.dynamicSchemeVariant != _tempVariant;

    // 使用 DynamicColorBuilder 获取系统颜色
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // 根据临时设置决定当前预览的亮度
        final previewBrightness =
            _tempTheme == 'dark'
                ? Brightness.dark
                : _tempTheme == 'light'
                ? Brightness.light
                : MediaQuery.platformBrightnessOf(context);

        // 决定使用的种子色：系统色或用户选择的预设色
        final effectiveSeedColor =
            _tempUseSystemColor && lightDynamic != null
                ? lightDynamic.primary
                : Color(_tempSeedColor);

        // 构建预览用的 ColorScheme
        final variant =
            _tempVariant >= 0 &&
                    _tempVariant < DynamicSchemeVariant.values.length
                ? DynamicSchemeVariant.values[_tempVariant]
                : DynamicSchemeVariant.tonalSpot;

        final previewColorScheme = ColorScheme.fromSeed(
          seedColor: effectiveSeedColor,
          brightness: previewBrightness,
          dynamicSchemeVariant: variant,
        );

        final previewTheme = ThemeData(
          useMaterial3: true,
          colorScheme: previewColorScheme,
          fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
        );

        // 整个页面使用 AnimatedTheme 实现平滑过渡
        return AnimatedTheme(
          data: previewTheme,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Builder(
            builder: (context) {
              final colors = Theme.of(context).colorScheme;
              return Scaffold(
                appBar: AppBar(
                  leading: const BackButton(),
                  title: const Text('主题与颜色'),
                  actions: [
                    FilledButton.tonal(
                      onPressed: hasChanges ? _apply : null,
                      child: const Text('应用'),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: SafeArea(
                  child: Column(
                    children: [
                      // 预览区域（不可点击）
                      Expanded(
                        child: Center(
                          child: IgnorePointer(
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: colors.outlineVariant.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.shadow.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: _buildPreviewContent(colors),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 底部控制面板
                      _buildBottomPanel(colors, effectiveSeedColor),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 华容道风格的预览内容
  Widget _buildPreviewContent(ColorScheme colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // 第一行：大 Primary 块 + 右侧窄列
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // 大 Primary 色块（2x2 的大块）
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.brush, color: colors.onPrimary, size: 48),
                          const SizedBox(height: 8),
                          Text(
                            '主色调',
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 右侧窄列：两个小块
                  Expanded(
                    child: Column(
                      children: [
                        // Secondary 块
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.secondary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.star,
                                color: colors.onSecondary,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Tertiary 块
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.tertiary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.favorite,
                                color: colors.onTertiary,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 第二行：控件展示区
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  // Switch + Button
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(
                                Icons.dark_mode,
                                color: colors.primary,
                                size: 20,
                              ),
                              Switch(value: true, onChanged: (_) {}),
                            ],
                          ),
                          FilledButton(
                            onPressed: () {},
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(32),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text('确认'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Chip 区域
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('选中'),
                            selected: true,
                            onSelected: (_) {},
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(height: 6),
                          Chip(
                            label: const Text('标签'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // FAB 区域
                  Container(
                    width: 64,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: FloatingActionButton.small(
                        onPressed: () {},
                        elevation: 2,
                        child: const Icon(Icons.add),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel(ColorScheme colors, Color effectiveSeedColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                  _selectedTab == 0 ? '选择种子颜色' : '选择自定义颜色',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),

                // 核心选择区域：预设列表 OR 自定义按钮 (高度锁定为 56)
                SizedBox(
                  height: 56,
                  child:
                      _selectedTab == 0
                          ? ScrollConfiguration(
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
                                  for (
                                    int i = 0;
                                    i < kPresetColors.length;
                                    i++
                                  ) ...[
                                    _buildColorOption(kPresetColors[i], colors),
                                    if (i < kPresetColors.length - 1)
                                      const SizedBox(width: 12),
                                  ],
                                ],
                              ),
                            ),
                          )
                          : _buildCustomColorButton(colors, effectiveSeedColor),
                ),

                const SizedBox(height: 24),

                // 深色模式控制行
                Row(
                  children: [
                    Text(
                      _getThemeModeLabel(),
                      style: TextStyle(color: colors.onSurface, fontSize: 16),
                    ),
                    const Spacer(),
                    _buildThemeModeSegmentedControl(colors),
                  ],
                ),

                const SizedBox(height: 16),

                // 下方选项：预设模式显示系统开关，自定义模式显示变体选择 (高度锁定为 48)
                SizedBox(
                  height: 48,
                  child:
                      _selectedTab == 0
                          ? Builder(
                            builder: (context) {
                              final isSupported =
                                  Platform.isAndroid || Platform.isWindows;
                              return Row(
                                children: [
                                  Text(
                                    isSupported ? '使用系统颜色' : '系统颜色不可用',
                                    style: TextStyle(
                                      color:
                                          isSupported
                                              ? colors.onSurface
                                              : colors.onSurface.withValues(
                                                alpha: 0.5,
                                              ),
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: _tempUseSystemColor,
                                    onChanged:
                                        isSupported
                                            ? (value) {
                                              setState(() {
                                                _tempUseSystemColor = value;
                                                // 重置变体为默认
                                                if (value) {
                                                  _tempVariant = 0;
                                                } else {
                                                  // 如果关闭系统色，恢复为选中颜色的逻辑（如果是纯白则单色）
                                                  if (_tempSeedColor ==
                                                      0xFFFFFFFF) {
                                                    _tempVariant =
                                                        DynamicSchemeVariant
                                                            .monochrome
                                                            .index;
                                                  } else {
                                                    _tempVariant = 0;
                                                  }
                                                }
                                              });
                                            }
                                            : null,
                                  ),
                                ],
                              );
                            },
                          )
                          : _buildVariantSelector(colors),
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

  Widget _buildColorOption(Color color, ColorScheme colors) {
    final isSelected = _tempSeedColor == color.toARGB32();
    final isDisabled = _tempUseSystemColor;

    return GestureDetector(
      onTap:
          isDisabled
              ? null
              : () {
                setState(() {
                  _tempSeedColor = color.toARGB32();
                  // 纯白特殊逻辑: 自动切换到单色变体
                  if (_tempSeedColor == 0xFFFFFFFF) {
                    _tempVariant = DynamicSchemeVariant.monochrome.index;
                  } else {
                    _tempVariant = DynamicSchemeVariant.tonalSpot.index;
                  }
                });
              },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDisabled ? color.withValues(alpha: 0.4) : color,
          border:
              isSelected && !isDisabled
                  ? Border.all(color: colors.onSurface, width: 3)
                  : Border.all(
                    color: colors.outline.withValues(alpha: 0.2),
                    width: 1,
                  ),
        ),
        child:
            isSelected && !isDisabled
                ? Icon(Icons.check, color: colors.surface)
                : null,
      ),
    );
  }

  /// 自定义颜色按钮
  Widget _buildCustomColorButton(ColorScheme colors, Color effectiveSeedColor) {
    return InkWell(
      onTap: () => _showColorPickerSheet(effectiveSeedColor),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: effectiveSeedColor,
                border: Border.all(color: colors.outline, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '#${effectiveSeedColor.toARGB32().toRadixString(16).toUpperCase().substring(2)}',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  '点击修改',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.colorize, color: colors.primary),
          ],
        ),
      ),
    );
  }

  /// 动态方案变体选择器 (行式下拉列表)
  Widget _buildVariantSelector(ColorScheme colors) {
    final variants = [
      (DynamicSchemeVariant.tonalSpot, '默认', 'Tonal Spot'),
      (DynamicSchemeVariant.monochrome, '单色', 'Monochrome'),
      (DynamicSchemeVariant.vibrant, '鲜艳', 'Vibrant'),
      (DynamicSchemeVariant.expressive, '表现力', 'Expressive'),
      (DynamicSchemeVariant.neutral, '中性', 'Neutral'),
      (DynamicSchemeVariant.rainbow, '彩虹', 'Rainbow'),
    ];

    // 检查 _tempVariant 有效性 (如果索引超出范围)
    final currentVariantItem = variants.firstWhere(
      (item) => item.$1.index == _tempVariant,
      orElse: () => variants[0], // 如果 _tempVariant 无效，默认使用第一个变体
    );
    final effectiveTempVariant = currentVariantItem.$1.index;

    return Row(
      children: [
        Text('动态方案变体', style: TextStyle(color: colors.onSurface, fontSize: 16)),
        const Spacer(),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: effectiveTempVariant,
              icon: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.unfold_more, size: 18),
              ),
              iconSize: 18,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
              ),
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: colors.surfaceContainerHigh,
              items:
                  variants.map((item) {
                    return DropdownMenuItem<int>(
                      value: item.$1.index,
                      child: Text(item.$2),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _tempVariant = value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showColorPickerSheet(Color currentColor) {
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
          child: BottomColorPickerSheet(
            initialColor: currentColor,
            onPreviewChange: (color) {
              setState(() {
                _tempSeedColor = color.toARGB32();
                // 纯白特殊逻辑: 自动切换到单色变体
                if (_tempSeedColor == 0xFFFFFFFF) {
                  _tempVariant = DynamicSchemeVariant.monochrome.index;
                }
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildThemeModeSegmentedControl(ColorScheme colors) {
    return SegmentedButton<String>(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.primaryContainer;
          }
          return colors.surfaceContainerHighest;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.onPrimaryContainer;
          }
          return colors.onSurfaceVariant;
        }),
        side: WidgetStateProperty.all(BorderSide.none),
        visualDensity: VisualDensity.compact,
      ),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'light', icon: Icon(Icons.light_mode, size: 20)),
        ButtonSegment(value: 'system', icon: Icon(Icons.auto_mode, size: 20)),
        ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode, size: 20)),
      ],
      selected: {_tempTheme},
      onSelectionChanged: (newSelection) {
        setState(() {
          _tempTheme = newSelection.first;
        });
      },
    );
  }

  /// Pixel 风格动态宽度 Tab 切换器
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
            label: '预设颜色',
            isSelected: _selectedTab == 0,
            colors: colors,
            onTap: () {
              if (_selectedTab != 0) {
                setState(() {
                  _selectedTab = 0;
                  // 切换回预设 Tab：重置为默认勃艮第红，重置变体
                  _tempSeedColor = 0xFFB71C1C;
                  _tempVariant = 0;
                  // 刷新 isMonochrome 状态（在 build 中处理）
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
                  // 切换到自定 Tab：强制关闭系统颜色，重置为默认勃艮第红，重置变体
                  _tempUseSystemColor = false;
                  _tempSeedColor = 0xFFB71C1C;
                  _tempVariant = 0;
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
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutExpo,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryContainer : Colors.transparent,
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
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutExpo,
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
