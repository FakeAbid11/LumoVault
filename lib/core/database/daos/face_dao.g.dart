// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'face_dao.dart';

// ignore_for_file: type=lint
mixin _$FaceDaoMixin on DatabaseAccessor<AppDatabase> {
  $FacesTable get faces => attachedDatabase.faces;
  $PeopleTable get people => attachedDatabase.people;
  $FacePersonsTable get facePersons => attachedDatabase.facePersons;
  $FaceScansTable get faceScans => attachedDatabase.faceScans;
  FaceDaoManager get managers => FaceDaoManager(this);
}

class FaceDaoManager {
  final _$FaceDaoMixin _db;
  FaceDaoManager(this._db);
  $$FacesTableTableManager get faces =>
      $$FacesTableTableManager(_db.attachedDatabase, _db.faces);
  $$PeopleTableTableManager get people =>
      $$PeopleTableTableManager(_db.attachedDatabase, _db.people);
  $$FacePersonsTableTableManager get facePersons =>
      $$FacePersonsTableTableManager(_db.attachedDatabase, _db.facePersons);
  $$FaceScansTableTableManager get faceScans =>
      $$FaceScansTableTableManager(_db.attachedDatabase, _db.faceScans);
}
