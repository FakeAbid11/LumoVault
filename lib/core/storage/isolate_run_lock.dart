import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// What a lock file currently claims: who owns it, and when they last beat.
typedef _LockOwner = ({String token, DateTime at});

/// A cross-isolate advisory lock backed by a file on disk.
///
/// WorkManager runs its callback dispatcher in a **separate isolate** from the
/// UI. TDLib keeps an exclusive lock on its own database directory, so if the
/// foreground app is connected and a background worker also tries to connect,
/// the worker's upload attempts fail for the whole run. This lets whoever gets
/// there first claim the backup path and the other side back off cleanly.
///
/// Advisory, not a kernel lock: a process killed while holding the lock leaves
/// the file behind, so a held lock older than [staleAfter] is treated as
/// abandoned and can be taken over.
class IsolateRunLock {
  IsolateRunLock({
    required this.name,
    this.staleAfter = const Duration(minutes: 20),
    this.directory,
  });

  /// File name (without extension) identifying what is being locked.
  final String name;

  /// How long a held lock stays valid without a heartbeat.
  final Duration staleAfter;

  /// Where the lock file lives. Defaults to the app documents directory.
  final Directory? directory;

  File? _file;
  bool _held = false;

  /// Uniquely identifies *this instance* inside the lock file.
  ///
  /// Without it, a takeover is untraceable: isolate A's lock goes stale, B
  /// claims the file, and when A finally finishes its `release()` deleted B's
  /// lock unconditionally — freeing a run that was very much alive and letting
  /// a third isolate start a concurrent backup against the same TDLib database.
  /// [release] and [heartbeat] now check the token first.
  final String _ownerToken =
      '${_tokenCounter++}-'
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_rng.nextInt(0x7FFFFFFF).toRadixString(36)}';

  static int _tokenCounter = 0;
  static final Random _rng = Random.secure();

  /// Whether this instance currently holds the lock.
  bool get isHeld => _held;

  /// Try to claim the lock. Returns false when another isolate holds a lock
  /// that hasn't gone stale yet.
  ///
  /// The two I/O failure modes deliberately go opposite ways. Failing to *read*
  /// the existing lock returns false: we can't rule out a live holder, so
  /// running anyway risks the concurrent TDLib access this exists to prevent.
  /// Failing to *write* our own claim returns true: nothing is holding the
  /// lock, we just can't record that we took it, and refusing would disable
  /// background backup outright on a device where the file can't be written.
  ///
  /// Acquiring always sets [isHeld] true; releasing or a failed acquire both
  /// clear it. A caller that gets true back still has to [release] when done.
  Future<bool> tryAcquire({DateTime? now}) async {
    final at = now ?? DateTime.now();

    // Inspecting the current holder and writing our own claim are separated on
    // purpose. These used to share one catch that granted the lock on *any*
    // error — so a transient failure reading a lock another isolate was
    // actively holding fell through to "proceed anyway", which is precisely
    // the concurrent run the lock exists to prevent. A read we can't complete
    // means we can't rule out a live holder, so it has to fail closed.
    final File file;
    final _LockOwner? holder;
    try {
      file = await _resolveFile();
      holder = await _readOwner(file);
    } catch (e) {
      debugPrint('[IsolateRunLock] Could not read $name, backing off: $e');
      _held = false;
      return false;
    }

    // A heartbeat we can't parse is worse than no lock at all — treat it as
    // abandoned rather than deadlocking every future run.
    final heldAt = holder?.at;
    if (heldAt != null && at.difference(heldAt) < staleAfter) {
      return false;
    }
    if (heldAt != null) {
      debugPrint('[IsolateRunLock] Taking over stale lock: $name');
    }

    try {
      await _writeOwner(file, at);
      _held = true;
      return true;
    } catch (e) {
      // Nothing is holding the lock, we just can't record that we took it. No
      // coordination is possible either way, so allow the run: refusing would
      // disable background backup entirely on a device where the lock file
      // can't be written.
      debugPrint('[IsolateRunLock] Could not claim $name, proceeding: $e');
      _held = true;
      return true;
    }
  }

  /// Refresh the heartbeat so a long run isn't mistaken for an abandoned one.
  ///
  /// Stops beating once the lock has been taken over: continuing would extend
  /// a claim we no longer own and keep a third isolate out indefinitely.
  Future<void> heartbeat({DateTime? now}) async {
    if (!_held) return;
    try {
      final file = await _resolveFile();
      final owner = await _readOwner(file);
      if (owner != null && owner.token != _ownerToken) {
        debugPrint('[IsolateRunLock] Lost $name to another holder');
        _held = false;
        return;
      }
      await _writeOwner(file, now ?? DateTime.now());
    } catch (e) {
      debugPrint('[IsolateRunLock] Heartbeat failed for $name: $e');
    }
  }

  /// Release the lock. Safe to call when not held.
  ///
  /// Deletes only a lock we still own. A pre-takeover holder used to delete
  /// whoever's lock happened to be at the path, silently freeing a live run.
  Future<void> release() async {
    if (!_held) return;
    _held = false;
    try {
      final file = await _resolveFile();
      final owner = await _readOwner(file);
      // owner == null means the file is already gone (or corrupt beyond use),
      // so there is nothing left to honour and deleting is harmless.
      if (owner == null || owner.token == _ownerToken) {
        if (await file.exists()) await file.delete();
      } else {
        debugPrint(
          '[IsolateRunLock] Left $name alone: taken over by another holder',
        );
      }
    } catch (e) {
      debugPrint('[IsolateRunLock] Release failed for $name: $e');
    }
  }

  /// Read the current holder, or null when nothing holds the lock.
  ///
  /// Only a missing file counts as "nothing holds it". Every other I/O failure
  /// propagates so [tryAcquire] can fail closed: a read we couldn't complete
  /// says nothing about whether another isolate is running, and this used to
  /// swallow all of them into the same null as an absent file. Checking
  /// `exists()` first doesn't help — it also reports false for a path we can't
  /// open, which is the case that has to fail closed.
  ///
  /// A file we *can* read but can't parse still returns null: see [tryAcquire].
  Future<_LockOwner?> _readOwner(File file) async {
    final String contents;
    try {
      contents = await file.readAsString();
    } on PathNotFoundException {
      return null;
    }
    // Format is "<owner token> <iso-8601 heartbeat>". A single-field file is a
    // lock written by a build that predated owner tokens: still a live holder,
    // just one we can't attribute, so it reports an empty token and a takeover
    // simply overwrites it.
    final parts = contents.trim().split(' ');
    final String token;
    final String heartbeat;
    if (parts.length >= 2) {
      token = parts.first;
      heartbeat = parts.last;
    } else {
      token = '';
      heartbeat = parts.first;
    }
    final at = DateTime.tryParse(heartbeat);
    if (at == null) return null;
    return (token: token, at: at);
  }

  /// Write this holder's token and an ISO-8601 heartbeat to the lock file.
  ///
  /// Via a temp file and a rename, because [File.writeAsString] truncates
  /// before it writes: another isolate reading mid-write would see an empty
  /// file, fail to parse a timestamp, and conclude the lock was abandoned —
  /// exactly the takeover this class exists to prevent. Rename within one
  /// directory is atomic on the platforms we ship to, so a reader sees either
  /// the old value or the new one.
  ///
  /// Falls back to a direct write if the rename isn't possible, since a
  /// slightly racy heartbeat beats no heartbeat at all.
  Future<void> _writeOwner(File file, DateTime at) async {
    final contents = '$_ownerToken ${at.toIso8601String()}';
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsString(contents, flush: true);
      await temp.rename(file.path);
    } on FileSystemException {
      await file.writeAsString(contents, flush: true);
    }
  }

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = directory ?? await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/$name.lock');
  }
}
