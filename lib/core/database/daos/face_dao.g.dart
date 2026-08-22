// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'face_dao.dart';

// ignore_for_file: type=lint
mixin _$FaceDaoMixin on DatabaseAccessor<AppDatabase> {
  $FacesTable get faces => attachedDatabase.faces;
  $FaceGroupsTable get faceGroups => attachedDatabase.faceGroups;
  FaceDaoManager get managers => FaceDaoManager(this);
}

class FaceDaoManager {
  final _$FaceDaoMixin _db;
  FaceDaoManager(this._db);
  $$FacesTableTableManager get faces =>
      $$FacesTableTableManager(_db.attachedDatabase, _db.faces);
  $$FaceGroupsTableTableManager get faceGroups =>
      $$FaceGroupsTableTableManager(_db.attachedDatabase, _db.faceGroups);
}
