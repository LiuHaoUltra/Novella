import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

void main() {
  testWidgets('BlurHash widget basic smoke test', (WidgetTester tester) async {
    const String testHash = 'LGF5]+Yk^6#M@-5c,1J5@[or[Q6.';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: BlurHash(
                hash: testHash,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BlurHash), findsOneWidget);

    final BlurHash blurHash = tester.widget(find.byType(BlurHash));
    expect(blurHash.hash, equals(testHash));
    expect(blurHash.image, isNull);
  });
}
