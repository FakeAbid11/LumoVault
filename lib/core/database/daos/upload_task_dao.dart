import 'package:drift/drift.dart';

import '../app_database.dart';
import '../../../features/gallery/data/models/upload_task.dart';

part 'upload_task_dao.g.dart';

/// Data-access object for the `UploadTasks` table.
///
/// Additive query surface for the future drift-backed transfer queue. Methods
/// return raw [UploadTaskRow]s; translation to the `UploadTask` domain model
/// happens via the mappers in `upload_task_mapper.dart`.
@DriftAccessor(tables: [UploadTasks])
class UploadTaskDao extends DatabaseAccessor<AppDatabase>
    with _$UploadTaskDaoMixin {
  UploadTaskDao(super.db);

  /// All tasks ordered by priority then creation time.
  Future<List<UploadTaskRow>> allTasks() {
    return (select(uploadTasks)..orderBy([
          (t) => OrderingTerm.asc(t.priority),
          (t) => OrderingTerm.asc(t.createdAt),
        ]))
        .get();
  }

  /// Tasks with the given status.
  Future<List<UploadTaskRow>> byStatus(UploadStatus status) {
    return (select(uploadTasks)
          ..where((t) => t.status.equals(status.index))
          ..orderBy([
            (t) => OrderingTerm.asc(t.priority),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
  }

  /// Number of tasks currently queued.
  Future<int> queuedCount() async {
    final count = countAll();
    final query = selectOnly(uploadTasks)
      ..addColumns([count])
      ..where(uploadTasks.status.equals(UploadStatus.queued.index));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Insert or replace a task by id.
  Future<void> upsert(UploadTasksCompanion companion) async {
    await into(uploadTasks).insertOnConflictUpdate(companion);
  }

  /// Remove a task by id.
  Future<int> deleteById(String id) {
    return (delete(uploadTasks)..where((t) => t.id.equals(id))).go();
  }

  /// Remove all terminal (completed/failed) tasks.
  Future<int> clearFinished() {
    return (delete(uploadTasks)..where(
          (t) =>
              t.status.equals(UploadStatus.completed.index) |
              t.status.equals(UploadStatus.failed.index),
        ))
        .go();
  }
}
