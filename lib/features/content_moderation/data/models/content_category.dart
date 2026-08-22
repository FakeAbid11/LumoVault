/// High-level content categories for media classification.
///
/// Categories are mutually exclusive at the top level — every analyzed item
/// receives exactly one primary [ContentCategory]. Subcategories and tags
/// provide finer granularity.
enum ContentCategory {
  /// General photos: landscapes, cityscapes, nature, architecture.
  general,

  /// People: portraits, group photos, selfies.
  people,

  /// Documents: screenshots of text, scanned papers, receipts.
  documents,

  /// Screenshots: device screenshots, memes, social media captures.
  screenshots,

  /// Food: photos of meals, recipes, restaurants.
  food,

  /// Animals: pets, wildlife, livestock.
  animals,

  /// Vehicles: cars, bikes, planes, boats.
  vehicles,

  /// Nature: plants, flowers, forests, mountains, water.
  nature,

  /// Night / low-light: taken in dark environments.
  night,

  /// Abstract / artistic: paintings, illustrations, patterns.
  artistic,

  /// Sensitive: content flagged by moderation rules (NSFW, violence, etc.).
  sensitive,

  /// Unclassified: analysis not yet performed or failed.
  unclassified,
}

/// Finer-grained labels that can be attached alongside the primary category.
///
/// A single media item may carry multiple tags — e.g. a photo of a person's
/// dog at a beach could be tagged `people`, `animals`, and `nature`.
enum ContentTag {
  selfie,
  groupPhoto,
  portrait,
  landscape,
  indoor,
  outdoor,
  text,
  meme,
  receipt,
  receiptDocument,
  barcode,
  qrCode,
  vehicle,
  pet,
  wildlife,
  food,
  drink,
  dessert,
  sunset,
  sunrise,
  rainy,
  snowy,
  underwater,
  aerial,
  macro,
  longExposure,
  panorama,
  blackAndWhite,
  blurry,
  lowQuality,
}

/// Severity level for moderation-flagged content.
enum SensitivityLevel {
  /// Clean — no moderation concern.
  safe,

  /// Mildly sensitive — e.g. medical imagery, mild violence in news photos.
  mild,

  /// Moderately sensitive — e.g. partial nudity, graphic injury.
  moderate,

  /// Highly sensitive — e.g. explicit content, graphic violence.
  high,

  /// Blocked — content that violates the user's configured policy.
  blocked,
}

/// The result of a single moderation analysis pass on one media item.
///
/// Persisted in the `ContentAnalysisResults` drift table and updated
/// incrementally as the engine processes the library.
class ContentAnalysisResult {
  const ContentAnalysisResult({
    required this.mediaItemId,
    this.primaryCategory = ContentCategory.unclassified,
    this.tags = const [],
    this.sensitivityLevel = SensitivityLevel.safe,
    this.confidence = 0.0,
    this.moderationAction = ModerationAction.none,
    this.analyzedAt,
    this.analyzerVersion = '1.0',
    this.metadata = const {},
  });

  /// The [MediaItem.localId] this result refers to.
  final String mediaItemId;

  /// Highest-confidence top-level category.
  final ContentCategory primaryCategory;

  /// Additional tags (may be empty).
  final List<ContentTag> tags;

  /// Moderation sensitivity classification.
  final SensitivityLevel sensitivityLevel;

  /// Overall confidence of the classification (0.0–1.0).
  final double confidence;

  /// Action that was (or should be) taken by the moderation engine.
  final ModerationAction moderationAction;

  /// When the analysis was performed.
  final DateTime? analyzedAt;

  /// Version string of the analyzer that produced this result.
  final String analyzerVersion;

  /// Arbitrary key-value metadata (e.g. detected object counts).
  final Map<String, String> metadata;

  ContentAnalysisResult copyWith({
    ContentCategory? primaryCategory,
    List<ContentTag>? tags,
    SensitivityLevel? sensitivityLevel,
    double? confidence,
    ModerationAction? moderationAction,
    DateTime? analyzedAt,
    String? analyzerVersion,
    Map<String, String>? metadata,
  }) {
    return ContentAnalysisResult(
      mediaItemId: mediaItemId,
      primaryCategory: primaryCategory ?? this.primaryCategory,
      tags: tags ?? this.tags,
      sensitivityLevel: sensitivityLevel ?? this.sensitivityLevel,
      confidence: confidence ?? this.confidence,
      moderationAction: moderationAction ?? this.moderationAction,
      analyzedAt: analyzedAt ?? this.analyzedAt,
      analyzerVersion: analyzerVersion ?? this.analyzerVersion,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Action the moderation engine may take on a flagged item.
enum ModerationAction {
  /// No action needed.
  none,

  /// Move to the hidden album.
  hide,

  /// Move to the quarantine review queue.
  quarantine,

  /// Skip backup — keep locally but do not upload.
  excludeFromBackup,

  /// Automatically delete the item.
  delete,
}
