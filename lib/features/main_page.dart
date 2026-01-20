import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:novella/features/home/home_page.dart';
import 'package:novella/features/history/history_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/features/shelf/shelf_page.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  int _currentIndex = 0;
  final _shelfKey = GlobalKey<ShelfPageState>();
  final _historyKey = GlobalKey<HistoryPageState>();

  late final List<Widget> _pages = [
    const HomePage(),
    ShelfPage(key: _shelfKey),
    HistoryPage(key: _historyKey),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return AdaptiveScaffold(
      // 强制 TabBar 永远不缩小、不隐藏
      minimizeBehavior: TabBarMinimizeBehavior.never,
      // 主体内容
      body: IndexedStack(index: _currentIndex, children: _pages),
      // 自适应底部导航栏
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          // 切换标签时刷新页面
          if (index == 1) {
            _shelfKey.currentState?.refresh();
          } else if (index == 2) {
            _historyKey.currentState?.refresh();
          }
        },
        items: [
          // 发现
          AdaptiveNavigationDestination(
            icon:
                settings.useIOS26Style
                    ? 'safari.fill'
                    : PlatformInfo.isIOS
                    ? CupertinoIcons.compass
                    : Icons.explore_outlined,
            selectedIcon:
                PlatformInfo.isIOS ? CupertinoIcons.compass : Icons.explore,
            label: '发现',
          ),
          // 书架
          AdaptiveNavigationDestination(
            icon:
                settings.useIOS26Style
                    ? 'book.closed.fill'
                    : PlatformInfo.isIOS
                    ? CupertinoIcons.book
                    : Icons.book_outlined,
            selectedIcon:
                PlatformInfo.isIOS ? CupertinoIcons.book_solid : Icons.book,
            label: '书架',
          ),
          // 历史
          AdaptiveNavigationDestination(
            icon:
                settings.useIOS26Style
                    ? 'clock.fill'
                    : PlatformInfo.isIOS
                    ? CupertinoIcons.time
                    : Icons.history,
            selectedIcon:
                PlatformInfo.isIOS ? CupertinoIcons.time : Icons.history,
            label: '历史',
          ),
          // 设置
          AdaptiveNavigationDestination(
            icon:
                settings.useIOS26Style
                    ? 'gearshape.fill'
                    : PlatformInfo.isIOS
                    ? CupertinoIcons.settings
                    : Icons.settings_outlined,
            selectedIcon:
                PlatformInfo.isIOS ? CupertinoIcons.settings : Icons.settings,
            label: '设置',
          ),
        ],
      ),
    );
  }
}
