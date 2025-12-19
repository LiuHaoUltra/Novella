import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:novella/features/auth/login_page.dart';
import 'package:novella/features/settings/settings_page.dart';
import 'package:novella/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

// === 新增：加载策略控制函数 ===
// 这里的逻辑至关重要：
// - iOS/macOS: 库被静态链接到了主程序中，所以要在当前进程(process)里找，而不是找文件。
// - Windows/Android: 库是作为外部文件存在的，所以要打开指定的文件名。
ExternalLibrary _loadLibrary() {
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS 静态链接关键点：直接在当前可执行文件中查找符号
    // iKnowHowToUseIt: 确认理解静态链接的使用方式
    return ExternalLibrary.process(iKnowHowToUseIt: true);
  } else if (Platform.isWindows) {
    return ExternalLibrary.open('novella_native.dll');
  } else {
    // Android
    return ExternalLibrary.open('libnovella_native.so');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('Flutter: WidgetsInitialized');

  try {
    // Initialize Rust FFI for WOFF2 font conversion
    print('Flutter: Initializing RustLib...');

    // === 关键修改：手动指定加载方式 ===
    // 不再使用默认的 init()，而是传入我们要它找的那个“库”
    await RustLib.init(externalLibrary: _loadLibrary());

    print('Flutter: RustLib Initialized');
  } catch (e, stack) {
    print('Flutter: Failed to initialize RustLib: $e');
    print(stack);
  }

  try {
    print('Flutter: Initializing WindowManager...');
    await windowManager.ensureInitialized();
    print('Flutter: WindowManager Initialized');

    WindowOptions windowOptions = const WindowOptions(
      size: Size(450, 850),
      minimumSize: Size(400, 800),
      maximumSize: Size(500, 1000), // Constraint for prototype
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Novella',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      print('Flutter: Window Ready to Show');
      await windowManager.show();
      await windowManager.focus();
      print('Flutter: Window Should be Visible');
    });
  } catch (e, stack) {
    print('Flutter: Failed to initialize WindowManager: $e');
    print(stack);
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _agreed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkDisclaimer();
  }

  Future<void> _checkDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    final agreed = prefs.getBool('disclaimer_agreed') ?? false;
    setState(() {
      _agreed = agreed;
      _loading = false;
    });
  }

  Future<void> _agree() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disclaimer_agreed', true);
    setState(() {
      _agreed = true;
    });
  }

  ThemeMode _getThemeMode(String theme) {
    switch (theme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Novella',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _getThemeMode(settings.theme),
      home:
          _loading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _agreed
              ? const LoginPage()
              : DisclaimerPage(onAgree: _agree),
    );
  }
}

class DisclaimerPage extends StatelessWidget {
  final VoidCallback onAgree;

  const DisclaimerPage({super.key, required this.onAgree});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用须知')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Colors.orange,
            ),
            const SizedBox(height: 24),
            const Text(
              '免责声明',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              '本软件仅供学习交流。请勿高频操作，风险自负。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onAgree,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: const Text('同意并继续'),
            ),
          ],
        ),
      ),
    );
  }
}
