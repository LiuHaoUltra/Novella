import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:novella/features/home/home_page.dart';
import 'package:novella/features/history/history_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/features/shelf/shelf_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
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
    return AdaptiveScaffold(
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
        items: const [
          // 发现
          AdaptiveNavigationDestination(icon: 'safari', label: '发现'),
          // 书架
          AdaptiveNavigationDestination(icon: 'bookmark', label: '书架'),
          // 历史
          AdaptiveNavigationDestination(
            icon: 'clock.arrow.circlepath',
            label: '历史',
          ),
          // 设置
          AdaptiveNavigationDestination(icon: 'gearshape', label: '设置'),
        ],
      ),
    );
  }
}
