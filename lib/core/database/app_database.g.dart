// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MediaItemsTable extends MediaItems
    with TableInfo<$MediaItemsTable, MediaItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileHashMeta = const VerificationMeta(
    'fileHash',
  );
  @override
  late final GeneratedColumn<String> fileHash = GeneratedColumn<String>(
    'file_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _telegramMessageIdMeta = const VerificationMeta(
    'telegramMessageId',
  );
  @override
  late final GeneratedColumn<String> telegramMessageId =
      GeneratedColumn<String>(
        'telegram_message_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _telegramFileIdMeta = const VerificationMeta(
    'telegramFileId',
  );
  @override
  late final GeneratedColumn<String> telegramFileId = GeneratedColumn<String>(
    'telegram_file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scannedAtMeta = const VerificationMeta(
    'scannedAt',
  );
  @override
  late final GeneratedColumn<DateTime> scannedAt = GeneratedColumn<DateTime>(
    'scanned_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadedAtMeta = const VerificationMeta(
    'uploadedAt',
  );
  @override
  late final GeneratedColumn<DateTime> uploadedAt = GeneratedColumn<DateTime>(
    'uploaded_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backedUpAtMeta = const VerificationMeta(
    'backedUpAt',
  );
  @override
  late final GeneratedColumn<DateTime> backedUpAt = GeneratedColumn<DateTime>(
    'backed_up_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isHiddenMeta = const VerificationMeta(
    'isHidden',
  );
  @override
  late final GeneratedColumn<bool> isHidden = GeneratedColumn<bool>(
    'is_hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isTrashedMeta = const VerificationMeta(
    'isTrashed',
  );
  @override
  late final GeneratedColumn<bool> isTrashed = GeneratedColumn<bool>(
    'is_trashed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_trashed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _trashedAtMeta = const VerificationMeta(
    'trashedAt',
  );
  @override
  late final GeneratedColumn<DateTime> trashedAt = GeneratedColumn<DateTime>(
    'trashed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isExcludedMeta = const VerificationMeta(
    'isExcluded',
  );
  @override
  late final GeneratedColumn<bool> isExcluded = GeneratedColumn<bool>(
    'is_excluded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_excluded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _albumNameMeta = const VerificationMeta(
    'albumName',
  );
  @override
  late final GeneratedColumn<String> albumName = GeneratedColumn<String>(
    'album_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceFolderMeta = const VerificationMeta(
    'deviceFolder',
  );
  @override
  late final GeneratedColumn<String> deviceFolder = GeneratedColumn<String>(
    'device_folder',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> tags =
      GeneratedColumn<String>(
        'tags',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($MediaItemsTable.$convertertags);
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    localId,
    fileHash,
    telegramMessageId,
    telegramFileId,
    filePath,
    fileName,
    mimeType,
    fileSize,
    width,
    height,
    durationMs,
    createdAt,
    modifiedAt,
    scannedAt,
    uploadedAt,
    backedUpAt,
    status,
    errorMessage,
    isFavorite,
    isHidden,
    isArchived,
    isTrashed,
    trashedAt,
    isExcluded,
    albumName,
    deviceFolder,
    description,
    tags,
    thumbnailPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('file_hash')) {
      context.handle(
        _fileHashMeta,
        fileHash.isAcceptableOrUnknown(data['file_hash']!, _fileHashMeta),
      );
    } else if (isInserting) {
      context.missing(_fileHashMeta);
    }
    if (data.containsKey('telegram_message_id')) {
      context.handle(
        _telegramMessageIdMeta,
        telegramMessageId.isAcceptableOrUnknown(
          data['telegram_message_id']!,
          _telegramMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('telegram_file_id')) {
      context.handle(
        _telegramFileIdMeta,
        telegramFileId.isAcceptableOrUnknown(
          data['telegram_file_id']!,
          _telegramFileIdMeta,
        ),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('scanned_at')) {
      context.handle(
        _scannedAtMeta,
        scannedAt.isAcceptableOrUnknown(data['scanned_at']!, _scannedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_scannedAtMeta);
    }
    if (data.containsKey('uploaded_at')) {
      context.handle(
        _uploadedAtMeta,
        uploadedAt.isAcceptableOrUnknown(data['uploaded_at']!, _uploadedAtMeta),
      );
    }
    if (data.containsKey('backed_up_at')) {
      context.handle(
        _backedUpAtMeta,
        backedUpAt.isAcceptableOrUnknown(
          data['backed_up_at']!,
          _backedUpAtMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('is_hidden')) {
      context.handle(
        _isHiddenMeta,
        isHidden.isAcceptableOrUnknown(data['is_hidden']!, _isHiddenMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('is_trashed')) {
      context.handle(
        _isTrashedMeta,
        isTrashed.isAcceptableOrUnknown(data['is_trashed']!, _isTrashedMeta),
      );
    }
    if (data.containsKey('trashed_at')) {
      context.handle(
        _trashedAtMeta,
        trashedAt.isAcceptableOrUnknown(data['trashed_at']!, _trashedAtMeta),
      );
    }
    if (data.containsKey('is_excluded')) {
      context.handle(
        _isExcludedMeta,
        isExcluded.isAcceptableOrUnknown(data['is_excluded']!, _isExcludedMeta),
      );
    }
    if (data.containsKey('album_name')) {
      context.handle(
        _albumNameMeta,
        albumName.isAcceptableOrUnknown(data['album_name']!, _albumNameMeta),
      );
    }
    if (data.containsKey('device_folder')) {
      context.handle(
        _deviceFolderMeta,
        deviceFolder.isAcceptableOrUnknown(
          data['device_folder']!,
          _deviceFolderMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {localId},
  ];
  @override
  MediaItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      fileHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_hash'],
      )!,
      telegramMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}telegram_message_id'],
      ),
      telegramFileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}telegram_file_id'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      scannedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scanned_at'],
      )!,
      uploadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}uploaded_at'],
      ),
      backedUpAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}backed_up_at'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      isHidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_hidden'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      isTrashed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_trashed'],
      )!,
      trashedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}trashed_at'],
      ),
      isExcluded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_excluded'],
      )!,
      albumName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_name'],
      ),
      deviceFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_folder'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      tags: $MediaItemsTable.$convertertags.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tags'],
        )!,
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
    );
  }

  @override
  $MediaItemsTable createAlias(String alias) {
    return $MediaItemsTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $convertertags =
      const StringListConverter();
}

class MediaItemRow extends DataClass implements Insertable<MediaItemRow> {
  /// Local autoincrement primary key.
  final int id;

  /// Stable platform media id (photo_manager asset id).
  final String localId;

  /// Content hash used for dedup.
  final String fileHash;
  final String? telegramMessageId;
  final String? telegramFileId;
  final String filePath;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final int width;
  final int height;
  final int? durationMs;

  /// Indexed: the timeline and every album/favorite/search query sorts by
  /// `createdAt` descending.
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime scannedAt;
  final DateTime? uploadedAt;
  final DateTime? backedUpAt;

  /// Stored as the enum index of `MediaStatus`.
  final int status;
  final String? errorMessage;
  final bool isFavorite;
  final bool isHidden;
  final bool isArchived;
  final bool isTrashed;
  final DateTime? trashedAt;
  final bool isExcluded;
  final String? albumName;
  final String? deviceFolder;
  final String? description;

  /// JSON-encoded `List<String>`.
  final List<String> tags;
  final String? thumbnailPath;
  const MediaItemRow({
    required this.id,
    required this.localId,
    required this.fileHash,
    this.telegramMessageId,
    this.telegramFileId,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.width,
    required this.height,
    this.durationMs,
    required this.createdAt,
    required this.modifiedAt,
    required this.scannedAt,
    this.uploadedAt,
    this.backedUpAt,
    required this.status,
    this.errorMessage,
    required this.isFavorite,
    required this.isHidden,
    required this.isArchived,
    required this.isTrashed,
    this.trashedAt,
    required this.isExcluded,
    this.albumName,
    this.deviceFolder,
    this.description,
    required this.tags,
    this.thumbnailPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['local_id'] = Variable<String>(localId);
    map['file_hash'] = Variable<String>(fileHash);
    if (!nullToAbsent || telegramMessageId != null) {
      map['telegram_message_id'] = Variable<String>(telegramMessageId);
    }
    if (!nullToAbsent || telegramFileId != null) {
      map['telegram_file_id'] = Variable<String>(telegramFileId);
    }
    map['file_path'] = Variable<String>(filePath);
    map['file_name'] = Variable<String>(fileName);
    map['mime_type'] = Variable<String>(mimeType);
    map['file_size'] = Variable<int>(fileSize);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    map['scanned_at'] = Variable<DateTime>(scannedAt);
    if (!nullToAbsent || uploadedAt != null) {
      map['uploaded_at'] = Variable<DateTime>(uploadedAt);
    }
    if (!nullToAbsent || backedUpAt != null) {
      map['backed_up_at'] = Variable<DateTime>(backedUpAt);
    }
    map['status'] = Variable<int>(status);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['is_hidden'] = Variable<bool>(isHidden);
    map['is_archived'] = Variable<bool>(isArchived);
    map['is_trashed'] = Variable<bool>(isTrashed);
    if (!nullToAbsent || trashedAt != null) {
      map['trashed_at'] = Variable<DateTime>(trashedAt);
    }
    map['is_excluded'] = Variable<bool>(isExcluded);
    if (!nullToAbsent || albumName != null) {
      map['album_name'] = Variable<String>(albumName);
    }
    if (!nullToAbsent || deviceFolder != null) {
      map['device_folder'] = Variable<String>(deviceFolder);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    {
      map['tags'] = Variable<String>(
        $MediaItemsTable.$convertertags.toSql(tags),
      );
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    return map;
  }

  MediaItemsCompanion toCompanion(bool nullToAbsent) {
    return MediaItemsCompanion(
      id: Value(id),
      localId: Value(localId),
      fileHash: Value(fileHash),
      telegramMessageId: telegramMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(telegramMessageId),
      telegramFileId: telegramFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(telegramFileId),
      filePath: Value(filePath),
      fileName: Value(fileName),
      mimeType: Value(mimeType),
      fileSize: Value(fileSize),
      width: Value(width),
      height: Value(height),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
      scannedAt: Value(scannedAt),
      uploadedAt: uploadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedAt),
      backedUpAt: backedUpAt == null && nullToAbsent
          ? const Value.absent()
          : Value(backedUpAt),
      status: Value(status),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      isFavorite: Value(isFavorite),
      isHidden: Value(isHidden),
      isArchived: Value(isArchived),
      isTrashed: Value(isTrashed),
      trashedAt: trashedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(trashedAt),
      isExcluded: Value(isExcluded),
      albumName: albumName == null && nullToAbsent
          ? const Value.absent()
          : Value(albumName),
      deviceFolder: deviceFolder == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceFolder),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      tags: Value(tags),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
    );
  }

  factory MediaItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaItemRow(
      id: serializer.fromJson<int>(json['id']),
      localId: serializer.fromJson<String>(json['localId']),
      fileHash: serializer.fromJson<String>(json['fileHash']),
      telegramMessageId: serializer.fromJson<String?>(
        json['telegramMessageId'],
      ),
      telegramFileId: serializer.fromJson<String?>(json['telegramFileId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      fileName: serializer.fromJson<String>(json['fileName']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      scannedAt: serializer.fromJson<DateTime>(json['scannedAt']),
      uploadedAt: serializer.fromJson<DateTime?>(json['uploadedAt']),
      backedUpAt: serializer.fromJson<DateTime?>(json['backedUpAt']),
      status: serializer.fromJson<int>(json['status']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      isHidden: serializer.fromJson<bool>(json['isHidden']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      isTrashed: serializer.fromJson<bool>(json['isTrashed']),
      trashedAt: serializer.fromJson<DateTime?>(json['trashedAt']),
      isExcluded: serializer.fromJson<bool>(json['isExcluded']),
      albumName: serializer.fromJson<String?>(json['albumName']),
      deviceFolder: serializer.fromJson<String?>(json['deviceFolder']),
      description: serializer.fromJson<String?>(json['description']),
      tags: serializer.fromJson<List<String>>(json['tags']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'localId': serializer.toJson<String>(localId),
      'fileHash': serializer.toJson<String>(fileHash),
      'telegramMessageId': serializer.toJson<String?>(telegramMessageId),
      'telegramFileId': serializer.toJson<String?>(telegramFileId),
      'filePath': serializer.toJson<String>(filePath),
      'fileName': serializer.toJson<String>(fileName),
      'mimeType': serializer.toJson<String>(mimeType),
      'fileSize': serializer.toJson<int>(fileSize),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'durationMs': serializer.toJson<int?>(durationMs),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'scannedAt': serializer.toJson<DateTime>(scannedAt),
      'uploadedAt': serializer.toJson<DateTime?>(uploadedAt),
      'backedUpAt': serializer.toJson<DateTime?>(backedUpAt),
      'status': serializer.toJson<int>(status),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'isHidden': serializer.toJson<bool>(isHidden),
      'isArchived': serializer.toJson<bool>(isArchived),
      'isTrashed': serializer.toJson<bool>(isTrashed),
      'trashedAt': serializer.toJson<DateTime?>(trashedAt),
      'isExcluded': serializer.toJson<bool>(isExcluded),
      'albumName': serializer.toJson<String?>(albumName),
      'deviceFolder': serializer.toJson<String?>(deviceFolder),
      'description': serializer.toJson<String?>(description),
      'tags': serializer.toJson<List<String>>(tags),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
    };
  }

  MediaItemRow copyWith({
    int? id,
    String? localId,
    String? fileHash,
    Value<String?> telegramMessageId = const Value.absent(),
    Value<String?> telegramFileId = const Value.absent(),
    String? filePath,
    String? fileName,
    String? mimeType,
    int? fileSize,
    int? width,
    int? height,
    Value<int?> durationMs = const Value.absent(),
    DateTime? createdAt,
    DateTime? modifiedAt,
    DateTime? scannedAt,
    Value<DateTime?> uploadedAt = const Value.absent(),
    Value<DateTime?> backedUpAt = const Value.absent(),
    int? status,
    Value<String?> errorMessage = const Value.absent(),
    bool? isFavorite,
    bool? isHidden,
    bool? isArchived,
    bool? isTrashed,
    Value<DateTime?> trashedAt = const Value.absent(),
    bool? isExcluded,
    Value<String?> albumName = const Value.absent(),
    Value<String?> deviceFolder = const Value.absent(),
    Value<String?> description = const Value.absent(),
    List<String>? tags,
    Value<String?> thumbnailPath = const Value.absent(),
  }) => MediaItemRow(
    id: id ?? this.id,
    localId: localId ?? this.localId,
    fileHash: fileHash ?? this.fileHash,
    telegramMessageId: telegramMessageId.present
        ? telegramMessageId.value
        : this.telegramMessageId,
    telegramFileId: telegramFileId.present
        ? telegramFileId.value
        : this.telegramFileId,
    filePath: filePath ?? this.filePath,
    fileName: fileName ?? this.fileName,
    mimeType: mimeType ?? this.mimeType,
    fileSize: fileSize ?? this.fileSize,
    width: width ?? this.width,
    height: height ?? this.height,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    scannedAt: scannedAt ?? this.scannedAt,
    uploadedAt: uploadedAt.present ? uploadedAt.value : this.uploadedAt,
    backedUpAt: backedUpAt.present ? backedUpAt.value : this.backedUpAt,
    status: status ?? this.status,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    isFavorite: isFavorite ?? this.isFavorite,
    isHidden: isHidden ?? this.isHidden,
    isArchived: isArchived ?? this.isArchived,
    isTrashed: isTrashed ?? this.isTrashed,
    trashedAt: trashedAt.present ? trashedAt.value : this.trashedAt,
    isExcluded: isExcluded ?? this.isExcluded,
    albumName: albumName.present ? albumName.value : this.albumName,
    deviceFolder: deviceFolder.present ? deviceFolder.value : this.deviceFolder,
    description: description.present ? description.value : this.description,
    tags: tags ?? this.tags,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
  );
  MediaItemRow copyWithCompanion(MediaItemsCompanion data) {
    return MediaItemRow(
      id: data.id.present ? data.id.value : this.id,
      localId: data.localId.present ? data.localId.value : this.localId,
      fileHash: data.fileHash.present ? data.fileHash.value : this.fileHash,
      telegramMessageId: data.telegramMessageId.present
          ? data.telegramMessageId.value
          : this.telegramMessageId,
      telegramFileId: data.telegramFileId.present
          ? data.telegramFileId.value
          : this.telegramFileId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      scannedAt: data.scannedAt.present ? data.scannedAt.value : this.scannedAt,
      uploadedAt: data.uploadedAt.present
          ? data.uploadedAt.value
          : this.uploadedAt,
      backedUpAt: data.backedUpAt.present
          ? data.backedUpAt.value
          : this.backedUpAt,
      status: data.status.present ? data.status.value : this.status,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      isHidden: data.isHidden.present ? data.isHidden.value : this.isHidden,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      isTrashed: data.isTrashed.present ? data.isTrashed.value : this.isTrashed,
      trashedAt: data.trashedAt.present ? data.trashedAt.value : this.trashedAt,
      isExcluded: data.isExcluded.present
          ? data.isExcluded.value
          : this.isExcluded,
      albumName: data.albumName.present ? data.albumName.value : this.albumName,
      deviceFolder: data.deviceFolder.present
          ? data.deviceFolder.value
          : this.deviceFolder,
      description: data.description.present
          ? data.description.value
          : this.description,
      tags: data.tags.present ? data.tags.value : this.tags,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemRow(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('fileHash: $fileHash, ')
          ..write('telegramMessageId: $telegramMessageId, ')
          ..write('telegramFileId: $telegramFileId, ')
          ..write('filePath: $filePath, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('fileSize: $fileSize, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('scannedAt: $scannedAt, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('backedUpAt: $backedUpAt, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isHidden: $isHidden, ')
          ..write('isArchived: $isArchived, ')
          ..write('isTrashed: $isTrashed, ')
          ..write('trashedAt: $trashedAt, ')
          ..write('isExcluded: $isExcluded, ')
          ..write('albumName: $albumName, ')
          ..write('deviceFolder: $deviceFolder, ')
          ..write('description: $description, ')
          ..write('tags: $tags, ')
          ..write('thumbnailPath: $thumbnailPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    localId,
    fileHash,
    telegramMessageId,
    telegramFileId,
    filePath,
    fileName,
    mimeType,
    fileSize,
    width,
    height,
    durationMs,
    createdAt,
    modifiedAt,
    scannedAt,
    uploadedAt,
    backedUpAt,
    status,
    errorMessage,
    isFavorite,
    isHidden,
    isArchived,
    isTrashed,
    trashedAt,
    isExcluded,
    albumName,
    deviceFolder,
    description,
    tags,
    thumbnailPath,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaItemRow &&
          other.id == this.id &&
          other.localId == this.localId &&
          other.fileHash == this.fileHash &&
          other.telegramMessageId == this.telegramMessageId &&
          other.telegramFileId == this.telegramFileId &&
          other.filePath == this.filePath &&
          other.fileName == this.fileName &&
          other.mimeType == this.mimeType &&
          other.fileSize == this.fileSize &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.scannedAt == this.scannedAt &&
          other.uploadedAt == this.uploadedAt &&
          other.backedUpAt == this.backedUpAt &&
          other.status == this.status &&
          other.errorMessage == this.errorMessage &&
          other.isFavorite == this.isFavorite &&
          other.isHidden == this.isHidden &&
          other.isArchived == this.isArchived &&
          other.isTrashed == this.isTrashed &&
          other.trashedAt == this.trashedAt &&
          other.isExcluded == this.isExcluded &&
          other.albumName == this.albumName &&
          other.deviceFolder == this.deviceFolder &&
          other.description == this.description &&
          other.tags == this.tags &&
          other.thumbnailPath == this.thumbnailPath);
}

class MediaItemsCompanion extends UpdateCompanion<MediaItemRow> {
  final Value<int> id;
  final Value<String> localId;
  final Value<String> fileHash;
  final Value<String?> telegramMessageId;
  final Value<String?> telegramFileId;
  final Value<String> filePath;
  final Value<String> fileName;
  final Value<String> mimeType;
  final Value<int> fileSize;
  final Value<int> width;
  final Value<int> height;
  final Value<int?> durationMs;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<DateTime> scannedAt;
  final Value<DateTime?> uploadedAt;
  final Value<DateTime?> backedUpAt;
  final Value<int> status;
  final Value<String?> errorMessage;
  final Value<bool> isFavorite;
  final Value<bool> isHidden;
  final Value<bool> isArchived;
  final Value<bool> isTrashed;
  final Value<DateTime?> trashedAt;
  final Value<bool> isExcluded;
  final Value<String?> albumName;
  final Value<String?> deviceFolder;
  final Value<String?> description;
  final Value<List<String>> tags;
  final Value<String?> thumbnailPath;
  const MediaItemsCompanion({
    this.id = const Value.absent(),
    this.localId = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.telegramMessageId = const Value.absent(),
    this.telegramFileId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.backedUpAt = const Value.absent(),
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isTrashed = const Value.absent(),
    this.trashedAt = const Value.absent(),
    this.isExcluded = const Value.absent(),
    this.albumName = const Value.absent(),
    this.deviceFolder = const Value.absent(),
    this.description = const Value.absent(),
    this.tags = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
  });
  MediaItemsCompanion.insert({
    this.id = const Value.absent(),
    required String localId,
    required String fileHash,
    this.telegramMessageId = const Value.absent(),
    this.telegramFileId = const Value.absent(),
    required String filePath,
    required String fileName,
    required String mimeType,
    required int fileSize,
    required int width,
    required int height,
    this.durationMs = const Value.absent(),
    required DateTime createdAt,
    required DateTime modifiedAt,
    required DateTime scannedAt,
    this.uploadedAt = const Value.absent(),
    this.backedUpAt = const Value.absent(),
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isTrashed = const Value.absent(),
    this.trashedAt = const Value.absent(),
    this.isExcluded = const Value.absent(),
    this.albumName = const Value.absent(),
    this.deviceFolder = const Value.absent(),
    this.description = const Value.absent(),
    this.tags = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
  }) : localId = Value(localId),
       fileHash = Value(fileHash),
       filePath = Value(filePath),
       fileName = Value(fileName),
       mimeType = Value(mimeType),
       fileSize = Value(fileSize),
       width = Value(width),
       height = Value(height),
       createdAt = Value(createdAt),
       modifiedAt = Value(modifiedAt),
       scannedAt = Value(scannedAt);
  static Insertable<MediaItemRow> custom({
    Expression<int>? id,
    Expression<String>? localId,
    Expression<String>? fileHash,
    Expression<String>? telegramMessageId,
    Expression<String>? telegramFileId,
    Expression<String>? filePath,
    Expression<String>? fileName,
    Expression<String>? mimeType,
    Expression<int>? fileSize,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<DateTime>? scannedAt,
    Expression<DateTime>? uploadedAt,
    Expression<DateTime>? backedUpAt,
    Expression<int>? status,
    Expression<String>? errorMessage,
    Expression<bool>? isFavorite,
    Expression<bool>? isHidden,
    Expression<bool>? isArchived,
    Expression<bool>? isTrashed,
    Expression<DateTime>? trashedAt,
    Expression<bool>? isExcluded,
    Expression<String>? albumName,
    Expression<String>? deviceFolder,
    Expression<String>? description,
    Expression<String>? tags,
    Expression<String>? thumbnailPath,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localId != null) 'local_id': localId,
      if (fileHash != null) 'file_hash': fileHash,
      if (telegramMessageId != null) 'telegram_message_id': telegramMessageId,
      if (telegramFileId != null) 'telegram_file_id': telegramFileId,
      if (filePath != null) 'file_path': filePath,
      if (fileName != null) 'file_name': fileName,
      if (mimeType != null) 'mime_type': mimeType,
      if (fileSize != null) 'file_size': fileSize,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (scannedAt != null) 'scanned_at': scannedAt,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (backedUpAt != null) 'backed_up_at': backedUpAt,
      if (status != null) 'status': status,
      if (errorMessage != null) 'error_message': errorMessage,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (isHidden != null) 'is_hidden': isHidden,
      if (isArchived != null) 'is_archived': isArchived,
      if (isTrashed != null) 'is_trashed': isTrashed,
      if (trashedAt != null) 'trashed_at': trashedAt,
      if (isExcluded != null) 'is_excluded': isExcluded,
      if (albumName != null) 'album_name': albumName,
      if (deviceFolder != null) 'device_folder': deviceFolder,
      if (description != null) 'description': description,
      if (tags != null) 'tags': tags,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
    });
  }

  MediaItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? localId,
    Value<String>? fileHash,
    Value<String?>? telegramMessageId,
    Value<String?>? telegramFileId,
    Value<String>? filePath,
    Value<String>? fileName,
    Value<String>? mimeType,
    Value<int>? fileSize,
    Value<int>? width,
    Value<int>? height,
    Value<int?>? durationMs,
    Value<DateTime>? createdAt,
    Value<DateTime>? modifiedAt,
    Value<DateTime>? scannedAt,
    Value<DateTime?>? uploadedAt,
    Value<DateTime?>? backedUpAt,
    Value<int>? status,
    Value<String?>? errorMessage,
    Value<bool>? isFavorite,
    Value<bool>? isHidden,
    Value<bool>? isArchived,
    Value<bool>? isTrashed,
    Value<DateTime?>? trashedAt,
    Value<bool>? isExcluded,
    Value<String?>? albumName,
    Value<String?>? deviceFolder,
    Value<String?>? description,
    Value<List<String>>? tags,
    Value<String?>? thumbnailPath,
  }) {
    return MediaItemsCompanion(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      fileHash: fileHash ?? this.fileHash,
      telegramMessageId: telegramMessageId ?? this.telegramMessageId,
      telegramFileId: telegramFileId ?? this.telegramFileId,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      scannedAt: scannedAt ?? this.scannedAt,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      backedUpAt: backedUpAt ?? this.backedUpAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isFavorite: isFavorite ?? this.isFavorite,
      isHidden: isHidden ?? this.isHidden,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      trashedAt: trashedAt ?? this.trashedAt,
      isExcluded: isExcluded ?? this.isExcluded,
      albumName: albumName ?? this.albumName,
      deviceFolder: deviceFolder ?? this.deviceFolder,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (fileHash.present) {
      map['file_hash'] = Variable<String>(fileHash.value);
    }
    if (telegramMessageId.present) {
      map['telegram_message_id'] = Variable<String>(telegramMessageId.value);
    }
    if (telegramFileId.present) {
      map['telegram_file_id'] = Variable<String>(telegramFileId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (scannedAt.present) {
      map['scanned_at'] = Variable<DateTime>(scannedAt.value);
    }
    if (uploadedAt.present) {
      map['uploaded_at'] = Variable<DateTime>(uploadedAt.value);
    }
    if (backedUpAt.present) {
      map['backed_up_at'] = Variable<DateTime>(backedUpAt.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (isHidden.present) {
      map['is_hidden'] = Variable<bool>(isHidden.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (isTrashed.present) {
      map['is_trashed'] = Variable<bool>(isTrashed.value);
    }
    if (trashedAt.present) {
      map['trashed_at'] = Variable<DateTime>(trashedAt.value);
    }
    if (isExcluded.present) {
      map['is_excluded'] = Variable<bool>(isExcluded.value);
    }
    if (albumName.present) {
      map['album_name'] = Variable<String>(albumName.value);
    }
    if (deviceFolder.present) {
      map['device_folder'] = Variable<String>(deviceFolder.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(
        $MediaItemsTable.$convertertags.toSql(tags.value),
      );
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemsCompanion(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('fileHash: $fileHash, ')
          ..write('telegramMessageId: $telegramMessageId, ')
          ..write('telegramFileId: $telegramFileId, ')
          ..write('filePath: $filePath, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('fileSize: $fileSize, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('scannedAt: $scannedAt, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('backedUpAt: $backedUpAt, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isHidden: $isHidden, ')
          ..write('isArchived: $isArchived, ')
          ..write('isTrashed: $isTrashed, ')
          ..write('trashedAt: $trashedAt, ')
          ..write('isExcluded: $isExcluded, ')
          ..write('albumName: $albumName, ')
          ..write('deviceFolder: $deviceFolder, ')
          ..write('description: $description, ')
          ..write('tags: $tags, ')
          ..write('thumbnailPath: $thumbnailPath')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MediaItemsTable mediaItems = $MediaItemsTable(this);
  late final Index idxMediaItemsFileHash = Index(
    'idx_media_items_file_hash',
    'CREATE INDEX idx_media_items_file_hash ON media_items (file_hash)',
  );
  late final Index idxMediaItemsStatus = Index(
    'idx_media_items_status',
    'CREATE INDEX idx_media_items_status ON media_items (status)',
  );
  late final Index idxMediaItemsAlbumName = Index(
    'idx_media_items_album_name',
    'CREATE INDEX idx_media_items_album_name ON media_items (album_name)',
  );
  late final Index idxMediaItemsCreatedAt = Index(
    'idx_media_items_created_at',
    'CREATE INDEX idx_media_items_created_at ON media_items (created_at)',
  );
  late final Index idxMediaItemsIsFavorite = Index(
    'idx_media_items_is_favorite',
    'CREATE INDEX idx_media_items_is_favorite ON media_items (is_favorite)',
  );
  late final Index idxMediaItemsTrashedTrashedAt = Index(
    'idx_media_items_trashed_trashed_at',
    'CREATE INDEX idx_media_items_trashed_trashed_at ON media_items (is_trashed, trashed_at)',
  );
  late final MediaDao mediaDao = MediaDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    mediaItems,
    idxMediaItemsFileHash,
    idxMediaItemsStatus,
    idxMediaItemsAlbumName,
    idxMediaItemsCreatedAt,
    idxMediaItemsIsFavorite,
    idxMediaItemsTrashedTrashedAt,
  ];
}

typedef $$MediaItemsTableCreateCompanionBuilder =
    MediaItemsCompanion Function({
      Value<int> id,
      required String localId,
      required String fileHash,
      Value<String?> telegramMessageId,
      Value<String?> telegramFileId,
      required String filePath,
      required String fileName,
      required String mimeType,
      required int fileSize,
      required int width,
      required int height,
      Value<int?> durationMs,
      required DateTime createdAt,
      required DateTime modifiedAt,
      required DateTime scannedAt,
      Value<DateTime?> uploadedAt,
      Value<DateTime?> backedUpAt,
      Value<int> status,
      Value<String?> errorMessage,
      Value<bool> isFavorite,
      Value<bool> isHidden,
      Value<bool> isArchived,
      Value<bool> isTrashed,
      Value<DateTime?> trashedAt,
      Value<bool> isExcluded,
      Value<String?> albumName,
      Value<String?> deviceFolder,
      Value<String?> description,
      Value<List<String>> tags,
      Value<String?> thumbnailPath,
    });
typedef $$MediaItemsTableUpdateCompanionBuilder =
    MediaItemsCompanion Function({
      Value<int> id,
      Value<String> localId,
      Value<String> fileHash,
      Value<String?> telegramMessageId,
      Value<String?> telegramFileId,
      Value<String> filePath,
      Value<String> fileName,
      Value<String> mimeType,
      Value<int> fileSize,
      Value<int> width,
      Value<int> height,
      Value<int?> durationMs,
      Value<DateTime> createdAt,
      Value<DateTime> modifiedAt,
      Value<DateTime> scannedAt,
      Value<DateTime?> uploadedAt,
      Value<DateTime?> backedUpAt,
      Value<int> status,
      Value<String?> errorMessage,
      Value<bool> isFavorite,
      Value<bool> isHidden,
      Value<bool> isArchived,
      Value<bool> isTrashed,
      Value<DateTime?> trashedAt,
      Value<bool> isExcluded,
      Value<String?> albumName,
      Value<String?> deviceFolder,
      Value<String?> description,
      Value<List<String>> tags,
      Value<String?> thumbnailPath,
    });

class $$MediaItemsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get telegramMessageId => $composableBuilder(
    column: $table.telegramMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get telegramFileId => $composableBuilder(
    column: $table.telegramFileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scannedAt => $composableBuilder(
    column: $table.scannedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get backedUpAt => $composableBuilder(
    column: $table.backedUpAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTrashed => $composableBuilder(
    column: $table.isTrashed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get trashedAt => $composableBuilder(
    column: $table.trashedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isExcluded => $composableBuilder(
    column: $table.isExcluded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceFolder => $composableBuilder(
    column: $table.deviceFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String> get tags =>
      $composableBuilder(
        column: $table.tags,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get telegramMessageId => $composableBuilder(
    column: $table.telegramMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get telegramFileId => $composableBuilder(
    column: $table.telegramFileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scannedAt => $composableBuilder(
    column: $table.scannedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get backedUpAt => $composableBuilder(
    column: $table.backedUpAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTrashed => $composableBuilder(
    column: $table.isTrashed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get trashedAt => $composableBuilder(
    column: $table.trashedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isExcluded => $composableBuilder(
    column: $table.isExcluded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceFolder => $composableBuilder(
    column: $table.deviceFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get fileHash =>
      $composableBuilder(column: $table.fileHash, builder: (column) => column);

  GeneratedColumn<String> get telegramMessageId => $composableBuilder(
    column: $table.telegramMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get telegramFileId => $composableBuilder(
    column: $table.telegramFileId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scannedAt =>
      $composableBuilder(column: $table.scannedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get backedUpAt => $composableBuilder(
    column: $table.backedUpAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isHidden =>
      $composableBuilder(column: $table.isHidden, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isTrashed =>
      $composableBuilder(column: $table.isTrashed, builder: (column) => column);

  GeneratedColumn<DateTime> get trashedAt =>
      $composableBuilder(column: $table.trashedAt, builder: (column) => column);

  GeneratedColumn<bool> get isExcluded => $composableBuilder(
    column: $table.isExcluded,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumName =>
      $composableBuilder(column: $table.albumName, builder: (column) => column);

  GeneratedColumn<String> get deviceFolder => $composableBuilder(
    column: $table.deviceFolder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );
}

class $$MediaItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaItemsTable,
          MediaItemRow,
          $$MediaItemsTableFilterComposer,
          $$MediaItemsTableOrderingComposer,
          $$MediaItemsTableAnnotationComposer,
          $$MediaItemsTableCreateCompanionBuilder,
          $$MediaItemsTableUpdateCompanionBuilder,
          (
            MediaItemRow,
            BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItemRow>,
          ),
          MediaItemRow,
          PrefetchHooks Function()
        > {
  $$MediaItemsTableTableManager(_$AppDatabase db, $MediaItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<String> fileHash = const Value.absent(),
                Value<String?> telegramMessageId = const Value.absent(),
                Value<String?> telegramFileId = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<DateTime> scannedAt = const Value.absent(),
                Value<DateTime?> uploadedAt = const Value.absent(),
                Value<DateTime?> backedUpAt = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isTrashed = const Value.absent(),
                Value<DateTime?> trashedAt = const Value.absent(),
                Value<bool> isExcluded = const Value.absent(),
                Value<String?> albumName = const Value.absent(),
                Value<String?> deviceFolder = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<List<String>> tags = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
              }) => MediaItemsCompanion(
                id: id,
                localId: localId,
                fileHash: fileHash,
                telegramMessageId: telegramMessageId,
                telegramFileId: telegramFileId,
                filePath: filePath,
                fileName: fileName,
                mimeType: mimeType,
                fileSize: fileSize,
                width: width,
                height: height,
                durationMs: durationMs,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                scannedAt: scannedAt,
                uploadedAt: uploadedAt,
                backedUpAt: backedUpAt,
                status: status,
                errorMessage: errorMessage,
                isFavorite: isFavorite,
                isHidden: isHidden,
                isArchived: isArchived,
                isTrashed: isTrashed,
                trashedAt: trashedAt,
                isExcluded: isExcluded,
                albumName: albumName,
                deviceFolder: deviceFolder,
                description: description,
                tags: tags,
                thumbnailPath: thumbnailPath,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String localId,
                required String fileHash,
                Value<String?> telegramMessageId = const Value.absent(),
                Value<String?> telegramFileId = const Value.absent(),
                required String filePath,
                required String fileName,
                required String mimeType,
                required int fileSize,
                required int width,
                required int height,
                Value<int?> durationMs = const Value.absent(),
                required DateTime createdAt,
                required DateTime modifiedAt,
                required DateTime scannedAt,
                Value<DateTime?> uploadedAt = const Value.absent(),
                Value<DateTime?> backedUpAt = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isTrashed = const Value.absent(),
                Value<DateTime?> trashedAt = const Value.absent(),
                Value<bool> isExcluded = const Value.absent(),
                Value<String?> albumName = const Value.absent(),
                Value<String?> deviceFolder = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<List<String>> tags = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
              }) => MediaItemsCompanion.insert(
                id: id,
                localId: localId,
                fileHash: fileHash,
                telegramMessageId: telegramMessageId,
                telegramFileId: telegramFileId,
                filePath: filePath,
                fileName: fileName,
                mimeType: mimeType,
                fileSize: fileSize,
                width: width,
                height: height,
                durationMs: durationMs,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                scannedAt: scannedAt,
                uploadedAt: uploadedAt,
                backedUpAt: backedUpAt,
                status: status,
                errorMessage: errorMessage,
                isFavorite: isFavorite,
                isHidden: isHidden,
                isArchived: isArchived,
                isTrashed: isTrashed,
                trashedAt: trashedAt,
                isExcluded: isExcluded,
                albumName: albumName,
                deviceFolder: deviceFolder,
                description: description,
                tags: tags,
                thumbnailPath: thumbnailPath,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaItemsTable,
      MediaItemRow,
      $$MediaItemsTableFilterComposer,
      $$MediaItemsTableOrderingComposer,
      $$MediaItemsTableAnnotationComposer,
      $$MediaItemsTableCreateCompanionBuilder,
      $$MediaItemsTableUpdateCompanionBuilder,
      (
        MediaItemRow,
        BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItemRow>,
      ),
      MediaItemRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MediaItemsTableTableManager get mediaItems =>
      $$MediaItemsTableTableManager(_db, _db.mediaItems);
}
