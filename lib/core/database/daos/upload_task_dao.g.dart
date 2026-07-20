// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_task_dao.dart';

// ignore_for_file: type=lint
mixin _$UploadTaskDaoMixin on DatabaseAccessor<AppDatabase> {
  $UploadTasksTable get uploadTasks => attachedDatabase.uploadTasks;
  UploadTaskDaoManager get managers => UploadTaskDaoManager(this);
}

class UploadTaskDaoManager {
  final _$UploadTaskDaoMixin _db;
  UploadTaskDaoManager(this._db);
  $$UploadTasksTableTableManager get uploadTasks =>
      $$UploadTasksTableTableManager(_db.attachedDatabase, _db.uploadTasks);
}
