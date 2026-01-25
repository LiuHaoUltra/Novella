import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novella/features/settings/settings_provider.dart';
import 'package:novella/features/settings/widgets/settings_ui_helper.dart';

import 'package:novella/features/settings/widgets/settings_header_card.dart';

class ContentSettingsPage extends ConsumerWidget {
  const ContentSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(),
          const SliverToBoxAdapter(
            child: SettingsHeaderCard(
              icon: Icons.dashboard_customize,
              title: '内容设置',
              subtitle: '管理首页的显示方式，并控制展现的内容',
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              // 书籍过滤
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
                    () => SettingsUIHelper.showSelectionSheet<String>(
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

              // 类型标记
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
              const SizedBox(height: 32),
            ]),
          ),
        ],
      ),
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

  String _getHomeModuleSummary(AppSettings settings) {
    final enabledCount = settings.enabledHomeModules.length;
    if (enabledCount == 0) return '不要全部关闭啦';
    if (enabledCount == 4) return '全部';
    return '$enabledCount 个模块';
  }

  void _showModuleOrderSheet(BuildContext context) {
    const moduleLabels = {
      'continueReading': '继续阅读',
      'stats': '阅读统计',
      'recentlyUpdated': '最近更新',
      'ranking': '近期排行',
    };
    const moduleIcons = {
      'continueReading': Icons.play_circle_outline,
      'stats': Icons.timer_outlined,
      'recentlyUpdated': Icons.update,
      'ranking': Icons.leaderboard_outlined,
    };
    const allModules = [
      'continueReading',
      'stats',
      'ranking',
      'recentlyUpdated',
    ];

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
