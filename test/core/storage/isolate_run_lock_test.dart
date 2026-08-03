import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/storage/isolate_run_lock.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('isolate_run_lock_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  IsolateRunLock makeLock({Duration? staleAfter}) => IsolateRunLock(
    name: 'test_run',
    staleAfter: staleAfter ?? const Duration(minutes: 20),
    directory: dir,
  );

  test('an uncontended lock is acquired', () async {
    final lock = makeLock();

    expect(await lock.tryAcquire(), isTrue);
    expect(lock.isHeld, isTrue);
  });

  test('a second holder is refused while the first holds it', () async {
    final first = makeLock();
    final second = makeLock();

    expect(await first.tryAcquire(), isTrue);
    expect(await second.tryAcquire(), isFalse);
    expect(second.isHeld, isFalse);
  });

  test('release lets the next holder in', () async {
    final first = makeLock();
    final second = makeLock();

    await first.tryAcquire();
    await first.release();

    expect(await second.tryAcquire(), isTrue);
    expect(first.isHeld, isFalse);
  });

  test('a stale lock is taken over', () async {
    final abandoned = makeLock(staleAfter: const Duration(minutes: 10));
    final fresh = makeLock(staleAfter: const Duration(minutes: 10));
    final start = DateTime(2026, 3, 1, 12);

    await abandoned.tryAcquire(now: start);

    // The holder was killed without releasing; 11 minutes later it's stale.
    expect(
      await fresh.tryAcquire(now: start.add(const Duration(minutes: 11))),
      isTrue,
    );
  });

  test('a lock is not stale before the timeout', () async {
    final holder = makeLock(staleAfter: const Duration(minutes: 10));
    final other = makeLock(staleAfter: const Duration(minutes: 10));
    final start = DateTime(2026, 3, 1, 12);

    await holder.tryAcquire(now: start);

    expect(
      await other.tryAcquire(now: start.add(const Duration(minutes: 9))),
      isFalse,
    );
  });

  test('a heartbeat keeps a long run from going stale', () async {
    final holder = makeLock(staleAfter: const Duration(minutes: 10));
    final other = makeLock(staleAfter: const Duration(minutes: 10));
    final start = DateTime(2026, 3, 1, 12);

    await holder.tryAcquire(now: start);
    await holder.heartbeat(now: start.add(const Duration(minutes: 9)));

    expect(
      await other.tryAcquire(now: start.add(const Duration(minutes: 11))),
      isFalse,
    );
  });

  test('a heartbeat from a non-holder is a no-op', () async {
    final holder = makeLock();
    final other = makeLock();

    await holder.tryAcquire();
    await other.heartbeat();

    expect(other.isHeld, isFalse);
  });

  test('release from a non-holder does not free the real holder', () async {
    final holder = makeLock();
    final other = makeLock();
    final third = makeLock();

    await holder.tryAcquire();
    await other.release();

    expect(await third.tryAcquire(), isFalse);
  });

  test('an unparseable lock file is treated as abandoned', () async {
    await File('${dir.path}/test_run.lock').writeAsString('not a timestamp');

    // Deadlocking every future run over a corrupt file would be worse than
    // taking the lock, so this must succeed.
    expect(await makeLock().tryAcquire(), isTrue);
  });

  test('an unreadable lock file fails closed', () async {
    // A directory sitting at the lock path stands in for any I/O error while
    // inspecting a lock we don't own: the read fails with something other than
    // "not found", so we can't rule out a live holder. The old code funnelled
    // every read failure into the same null as an absent file and proceeded,
    // which let a second isolate run alongside a live holder — the exact thing
    // this lock prevents.
    await Directory('${dir.path}/test_run.lock').create();

    final lock = makeLock();

    expect(await lock.tryAcquire(), isFalse);
    expect(lock.isHeld, isFalse);
  });

  test('a heartbeat rewrite is never observed as an abandoned lock', () async {
    // writeAsString truncates before writing, so a reader landing in that
    // window used to see an empty file, fail to parse a timestamp, and take
    // over a lock that was very much alive. The write goes through a temp file
    // and a rename now, which leaves no empty-file window to observe.
    final holder = makeLock(staleAfter: const Duration(minutes: 10));
    final other = makeLock(staleAfter: const Duration(minutes: 10));
    final start = DateTime(2026, 3, 1, 12);

    await holder.tryAcquire(now: start);

    final lockFile = File('${dir.path}/test_run.lock');
    for (var i = 1; i <= 20; i++) {
      final beat = start.add(Duration(seconds: i));
      final rewrite = holder.heartbeat(now: beat);
      // Read concurrently with the rewrite, without awaiting it first.
      final seen = await lockFile.readAsString();
      await rewrite;

      expect(
        DateTime.tryParse(seen.trim()),
        isNotNull,
        reason: 'lock file was observed empty or partial mid-heartbeat',
      );
    }

    expect(
      await other.tryAcquire(now: start.add(const Duration(minutes: 5))),
      isFalse,
    );
  });

  test('release is idempotent', () async {
    final lock = makeLock();

    await lock.tryAcquire();
    await lock.release();
    await lock.release();

    expect(lock.isHeld, isFalse);
  });
}
