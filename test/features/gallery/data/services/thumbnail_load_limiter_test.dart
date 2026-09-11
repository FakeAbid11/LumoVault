import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/services/thumbnail_load_limiter.dart';

void main() {
  test('caps concurrent loads under a burst', () async {
    final limiter = ThumbnailLoadLimiter(maxConcurrent: 6);
    var inFlight = 0;
    var maxInFlight = 0;
    var completed = 0;

    final gate = Completer<void>();
    final tasks = List.generate(20, (i) {
      return limiter.run(() async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await gate.future;
        inFlight--;
        completed++;
        return i;
      });
    });

    // Let the burst settle into the limiter.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(maxInFlight, lessThanOrEqualTo(6));
    expect(completed, 0, reason: 'all slots held by the open gate');

    gate.complete();
    await Future.wait(tasks);

    expect(completed, 20);
    expect(maxInFlight, lessThanOrEqualTo(6));
    expect(maxInFlight, greaterThanOrEqualTo(1));
  });

  test('wakes queued loads one slot at a time (no lost wakeups)', () async {
    final limiter = ThumbnailLoadLimiter(maxConcurrent: 2);
    final order = <int>[];

    Future<int> task(int id, Duration delay) {
      return limiter.run(() async {
        await Future<void>.delayed(delay);
        order.add(id);
        return id;
      });
    }

    // Staggered delays: queued tasks complete out of order but all complete.
    final results = await Future.wait([
      task(1, const Duration(milliseconds: 30)),
      task(2, const Duration(milliseconds: 10)),
      task(3, const Duration(milliseconds: 20)),
      task(4, Duration.zero),
    ]);

    expect(results, [1, 2, 3, 4]);
    expect(order, hasLength(4));
  });
}
