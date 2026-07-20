import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/backup/engine/upload_queue.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';

void main() {
  group('UploadPriorityCalculator', () {
    test('newer files get higher priority (lower score)', () {
      final recentItem = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/recent.jpg',
        fileName: 'recent.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024 * 1024, // 1MB
        width: 1920,
        height: 1080,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final oldItem = MediaItem(
        localId: '2',
        fileHash: 'hash2',
        filePath: '/path/old.jpg',
        fileName: 'old.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024 * 1024, // 1MB
        width: 1920,
        height: 1080,
        createdAt: DateTime.now().subtract(const Duration(days: 365)),
        modifiedAt: DateTime.now().subtract(const Duration(days: 365)),
        scannedAt: DateTime.now(),
      );

      final recentPriority = UploadPriorityCalculator.calculatePriority(
        item: recentItem,
        attemptCount: 0,
      );

      final oldPriority = UploadPriorityCalculator.calculatePriority(
        item: oldItem,
        attemptCount: 0,
      );

      expect(recentPriority, lessThan(oldPriority));
    });

    test('smaller files get higher priority (lower score)', () {
      final smallItem = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/small.jpg',
        fileName: 'small.jpg',
        mimeType: 'image/jpeg',
        fileSize: 100 * 1024, // 100KB
        width: 1920,
        height: 1080,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final largeItem = MediaItem(
        localId: '2',
        fileHash: 'hash2',
        filePath: '/path/large.jpg',
        fileName: 'large.jpg',
        mimeType: 'image/jpeg',
        fileSize: 100 * 1024 * 1024, // 100MB
        width: 1920,
        height: 1080,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final smallPriority = UploadPriorityCalculator.calculatePriority(
        item: smallItem,
        attemptCount: 0,
      );

      final largePriority = UploadPriorityCalculator.calculatePriority(
        item: largeItem,
        attemptCount: 0,
      );

      expect(smallPriority, lessThan(largePriority));
    });

    test('retried items get lower priority (higher score)', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024 * 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final firstAttempt = UploadPriorityCalculator.calculatePriority(
        item: item,
        attemptCount: 0,
      );

      final retryAttempt = UploadPriorityCalculator.calculatePriority(
        item: item,
        attemptCount: 2,
      );

      expect(firstAttempt, lessThan(retryAttempt));
    });

    test('user-initiated uploads jump the queue', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024 * 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime.now().subtract(const Duration(days: 365)),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final normalPriority = UploadPriorityCalculator.calculatePriority(
        item: item,
        attemptCount: 0,
      );

      final userInitiatedPriority = UploadPriorityCalculator.calculatePriority(
        item: item,
        attemptCount: 0,
        isUserInitiated: true,
      );

      expect(userInitiatedPriority, lessThan(normalPriority));
    });

    test('sortByPriority sorts ascending (highest priority first)', () {
      final tasks = [
        UploadTask(
          id: '1',
          mediaItemId: 'm1',
          localFilePath: '/a.jpg',
          fileName: 'a.jpg',
          fileSize: 100,
          fileHash: 'h1',
          priority: 50,
          createdAt: DateTime(2026, 1, 1),
        ),
        UploadTask(
          id: '2',
          mediaItemId: 'm2',
          localFilePath: '/b.jpg',
          fileName: 'b.jpg',
          fileSize: 200,
          fileHash: 'h2',
          priority: 10,
          createdAt: DateTime(2026, 1, 1),
        ),
        UploadTask(
          id: '3',
          mediaItemId: 'm3',
          localFilePath: '/c.jpg',
          fileName: 'c.jpg',
          fileSize: 300,
          fileHash: 'h3',
          priority: 30,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final sorted = UploadPriorityCalculator.sortByPriority(tasks);

      expect(sorted[0].priority, 10);
      expect(sorted[1].priority, 30);
      expect(sorted[2].priority, 50);
    });
  });

  group('UploadQueue', () {
    late UploadQueue queue;

    setUp(() {
      queue = UploadQueue(batchSize: 10, uploadDelayMs: 0);
    });

    tearDown(() {
      queue.dispose();
    });

    test('enqueue adds task to queue', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final task = queue.enqueue(item: item);

      expect(task, isNotNull);
      expect(queue.totalCount, 1);
      expect(queue.pendingCount, 1);
    });

    test('enqueue prevents duplicates', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final task1 = queue.enqueue(item: item);
      final task2 = queue.enqueue(item: item);

      expect(task1, isNotNull);
      expect(task2, isNull);
      expect(queue.totalCount, 1);
    });

    test('isAlreadyBackedUp prevents re-queue', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final task = queue.enqueue(item: item)!;
      queue.updateTask(
        task.copyWith(status: UploadStatus.completed, progress: 1.0),
      );

      expect(queue.isAlreadyBackedUp('hash1'), isTrue);
    });

    test('getNextBatch respects batch size', () {
      final items = List.generate(
        15,
        (i) => MediaItem(
          localId: '$i',
          fileHash: 'hash$i',
          filePath: '/path/test$i.jpg',
          fileName: 'test$i.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
        ),
      );

      queue.enqueueBatch(items);

      final batch = queue.getNextBatch();
      expect(batch.length, 10);
    });

    test('clearFinished removes completed and failed tasks', () {
      final items = List.generate(
        3,
        (i) => MediaItem(
          localId: '$i',
          fileHash: 'hash$i',
          filePath: '/path/test$i.jpg',
          fileName: 'test$i.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
        ),
      );

      final tasks = queue.enqueueBatch(items);
      queue.updateTask(tasks[0].copyWith(status: UploadStatus.completed));
      queue.updateTask(tasks[1].copyWith(status: UploadStatus.failed));
      // tasks[2] stays queued

      queue.clearFinished();

      expect(queue.totalCount, 1);
      expect(queue.pendingCount, 1);
    });

    test('retryAllFailed resets failed tasks to queued', () {
      final item = MediaItem(
        localId: '1',
        fileHash: 'hash1',
        filePath: '/path/test.jpg',
        fileName: 'test.jpg',
        mimeType: 'image/jpeg',
        fileSize: 1024,
        width: 1920,
        height: 1080,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        scannedAt: DateTime.now(),
      );

      final task = queue.enqueue(item: item)!;
      queue.updateTask(task.copyWith(status: UploadStatus.failed));

      expect(queue.failedCount, 1);

      queue.retryAllFailed();

      expect(queue.failedCount, 0);
      expect(queue.pendingCount, 1);
    });

    test('pauseAll and resumeAll toggle task states', () {
      final items = List.generate(
        3,
        (i) => MediaItem(
          localId: '$i',
          fileHash: 'hash$i',
          filePath: '/path/test$i.jpg',
          fileName: 'test$i.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
        ),
      );

      queue.enqueueBatch(items);

      queue.pauseAll();
      expect(queue.queuedTasks.length, 0);

      queue.resumeAll();
      expect(queue.queuedTasks.length, 3);
    });

    test('overallProgress calculates correctly', () {
      final items = List.generate(
        4,
        (i) => MediaItem(
          localId: '$i',
          fileHash: 'hash$i',
          filePath: '/path/test$i.jpg',
          fileName: 'test$i.jpg',
          mimeType: 'image/jpeg',
          fileSize: 1024,
          width: 1920,
          height: 1080,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          scannedAt: DateTime.now(),
        ),
      );

      final tasks = queue.enqueueBatch(items);
      queue.updateTask(tasks[0].copyWith(progress: 1.0));
      queue.updateTask(tasks[1].copyWith(progress: 0.5));
      queue.updateTask(tasks[2].copyWith(progress: 0.0));
      queue.updateTask(tasks[3].copyWith(progress: 0.0));

      expect(queue.overallProgress, closeTo(0.375, 0.01));
    });

    test('shouldSkipDuplicate detects duplicate completed tasks', () {
      final task = UploadTask(
        id: '1',
        mediaItemId: 'm1',
        localFilePath: '/a.jpg',
        fileName: 'a.jpg',
        fileSize: 100,
        fileHash: 'hash1',
        createdAt: DateTime(2026, 1, 1),
      );

      final duplicate = UploadTask(
        id: '2',
        mediaItemId: 'm2',
        localFilePath: '/b.jpg',
        fileName: 'b.jpg',
        fileSize: 200,
        fileHash: 'hash1',
        status: UploadStatus.completed,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(queue.shouldSkipDuplicate(task, [duplicate]), isTrue);
    });
  });
}
