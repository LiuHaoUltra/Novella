import 'package:flutter_test/flutter_test.dart';
import 'package:novella/core/network/request_queue.dart';

void main() {
  group('RequestQueue', () {
    test('allows 5 requests immediately', () async {
      // Create a fresh queue instance would be ideal but it's a singleton.
      // Since it's a singleton, state persists. Ideally we should make it testable/resettable.
      // For now, we assume this is the first test running.

      final queue = RequestQueue();
      int completedCount = 0;

      final futures = <Future>[];
      for (int i = 0; i < 5; i++) {
        futures.add(
          queue.enqueue(() async {
            completedCount++;
            return i;
          }),
        );
      }

      await Future.wait(futures);
      expect(completedCount, 5);
    });

    test('6th request waits', () async {
      // Since previous test consumed the burst, we need to wait for window to clear?
      // The previous test finished instantly (or close to it).
      // The window is 5 seconds.
      // So the previous 5 requests have timestamps ~NOW.
      // The 6th request should block until ~NOW + 5s.

      final queue = RequestQueue();
      final stopwatch = Stopwatch()..start();

      await queue.enqueue(() async {
        return 6;
      });

      stopwatch.stop();
      // Should have waited at least 4+ seconds (allowing for execution time)
      // But simply asserting it took > 4000ms is a good check.
      // Note: exact timing in tests can be flaky, but here the delay is significant (5s).

      expect(stopwatch.elapsedMilliseconds, greaterThan(4000));
    });

    test('bypass queue works', () async {
      final queue = RequestQueue();
      final stopwatch = Stopwatch()..start();

      await queue.enqueue(() async {
        return 'bypass';
      }, bypassQueue: true);

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
