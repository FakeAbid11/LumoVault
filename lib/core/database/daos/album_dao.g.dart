// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album_dao.dart';

// ignore_for_file: type=lint
mixin _$AlbumDaoMixin on DatabaseAccessor<AppDatabase> {
  $AlbumsTable get albums => attachedDatabase.albums;
  $AlbumItemsTable get albumItems => attachedDatabase.albumItems;
  $MediaItemsTable get mediaItems => attachedDatabase.mediaItems;
  AlbumDaoManager get managers => AlbumDaoManager(this);
}

class AlbumDaoManager {
  final _$AlbumDaoMixin _db;
  AlbumDaoManager(this._db);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db.attachedDatabase, _db.albums);
  $$AlbumItemsTableTableManager get albumItems =>
      $$AlbumItemsTableTableManager(_db.attachedDatabase, _db.albumItems);
  $$MediaItemsTableTableManager get mediaItems =>
      $$MediaItemsTableTableManager(_db.attachedDatabase, _db.mediaItems);
}
