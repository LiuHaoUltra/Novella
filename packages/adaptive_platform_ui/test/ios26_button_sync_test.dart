import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_button.dart';
import 'package:flutter/cupertino.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IOS26Button Sync Test', () {
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      log.clear();
      // 拦截前 10 个可能的 Channel ID，应对静态变量递增
      for (int i = 0; i < 10; i++) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              MethodChannel('adaptive_platform_ui/ios26_button_$i'),
              (MethodCall methodCall) async {
                log.add(methodCall);
                return null;
              },
            );
      }
    });

    testWidgets(
      'should sync enabled state when onPressed changes from null to closure',
      (WidgetTester tester) async {
        // 1. 初始渲染，onPressed 为 null (禁用状态)
        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              child: IOS26Button(onPressed: null, label: 'Test'),
            ),
          ),
        );

        // 验证初次渲染并未发送 setEnabled (因为创建参数里已经包含了)
        // 或者如果发送了，我们先清除 log
        log.clear();

        // 2. 更新 Widget，赋予 onPressed (启用状态)
        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              child: IOS26Button(onPressed: () {}, label: 'Test'),
            ),
          ),
        );

        // 验证是否发送了 setEnabled 消息
        final setEnabledCalls = log.where((m) => m.method == 'setEnabled');
        expect(
          setEnabledCalls,
          isNotEmpty,
          reason:
              'Should send setEnabled when onPressed changes from null to non-null',
        );
        expect(setEnabledCalls.last.arguments['enabled'], isTrue);
      },
    );

    testWidgets(
      'should sync disabled state when onPressed changes from closure to null',
      (WidgetTester tester) async {
        // 1. 初始渲染，onPressed 为有效函数 (启用状态)
        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              child: IOS26Button(onPressed: () {}, label: 'Test'),
            ),
          ),
        );
        log.clear();

        // 2. 更新 Widget，onPressed 设为 null (禁用状态)
        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              child: IOS26Button(onPressed: null, label: 'Test'),
            ),
          ),
        );

        // 验证是否发送了 setEnabled(false) 消息
        final setEnabledCalls = log.where((m) => m.method == 'setEnabled');
        expect(setEnabledCalls, isNotEmpty);
        expect(setEnabledCalls.last.arguments['enabled'], isFalse);
      },
    );
  });
}
