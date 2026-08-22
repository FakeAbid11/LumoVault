import 'content_category.dart';

/// A user-defined moderation rule that the analysis engine evaluates
/// against every analyzed media item.
///
/// Rules are stored as JSON in the settings repository and evaluated
/// in priority order (highest first). The first matching rule determines
/// the [ModerationAction] applied to the item.
class ModerationRule {
  const ModerationRule({
    required this.id,
    required this.name,
    this.description,
    required this.condition,
    this.action = ModerationAction.quarantine,
    this.isEnabled = true,
    this.priority = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory ModerationRule.fromJson(Map<String, dynamic> json) {
    return ModerationRule(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      condition: ModerationCondition.fromJson(
        json['condition'] as Map<String, dynamic>,
      ),
      action: ModerationAction.values[json['action'] as int? ?? 0],
      isEnabled: json['isEnabled'] as bool? ?? true,
      priority: json['priority'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  /// Unique identifier (UUID or monotonic int).
  final String id;

  /// Human-readable name shown in the rules list.
  final String name;

  /// Optional longer description.
  final String? description;

  /// The condition that determines when this rule matches.
  final ModerationCondition condition;

  /// Action to take when the condition is met.
  final ModerationAction action;

  /// Whether this rule is currently active.
  final bool isEnabled;

  /// Higher-priority rules are evaluated first.
  final int priority;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  ModerationRule copyWith({
    String? name,
    String? description,
    ModerationCondition? condition,
    ModerationAction? action,
    bool? isEnabled,
    int? priority,
    DateTime? updatedAt,
  }) {
    return ModerationRule(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      condition: condition ?? this.condition,
      action: action ?? this.action,
      isEnabled: isEnabled ?? this.isEnabled,
      priority: priority ?? this.priority,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'condition': condition.toJson(),
    'action': action.index,
    'isEnabled': isEnabled,
    'priority': priority,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

/// A condition that can be evaluated against a [ContentAnalysisResult].
///
/// Conditions compose via AND logic when multiple fields are set.
/// A null/absent field means "don't filter on this dimension".
class ModerationCondition {
  const ModerationCondition({
    this.minSensitivityLevel,
    this.targetCategories,
    this.requiredTags,
    this.excludedTags,
    this.minConfidence,
    this.maxFileSizeBytes,
    this.targetMimeTypes,
  });

  factory ModerationCondition.fromJson(Map<String, dynamic> json) {
    return ModerationCondition(
      minSensitivityLevel: json['minSensitivityLevel'] != null
          ? SensitivityLevel.values[json['minSensitivityLevel'] as int]
          : null,
      targetCategories: json['targetCategories'] != null
          ? (json['targetCategories'] as List)
                .map((i) => ContentCategory.values[i as int])
                .toList()
          : null,
      requiredTags: json['requiredTags'] != null
          ? (json['requiredTags'] as List)
                .map((i) => ContentTag.values[i as int])
                .toList()
          : null,
      excludedTags: json['excludedTags'] != null
          ? (json['excludedTags'] as List)
                .map((i) => ContentTag.values[i as int])
                .toList()
          : null,
      minConfidence: (json['minConfidence'] as num?)?.toDouble(),
      maxFileSizeBytes: json['maxFileSizeBytes'] as int?,
      targetMimeTypes: (json['targetMimeTypes'] as List?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  /// If set, items at or above this sensitivity level match.
  final SensitivityLevel? minSensitivityLevel;

  /// If non-empty, only items with one of these categories match.
  final List<ContentCategory>? targetCategories;

  /// If non-empty, the item must have ALL of these tags to match.
  final List<ContentTag>? requiredTags;

  /// If non-empty, the item must have NONE of these tags to match.
  final List<ContentTag>? excludedTags;

  /// Minimum confidence threshold (0.0–1.0) for the item to match.
  final double? minConfidence;

  /// Maximum file size in bytes; larger files do not match.
  final int? maxFileSizeBytes;

  /// If non-empty, only items with one of these MIME types match.
  final List<String>? targetMimeTypes;

  /// Whether [result] satisfies this condition.
  bool matches(
    ContentAnalysisResult result, {
    int? fileSizeBytes,
    String? mimeType,
  }) {
    if (minSensitivityLevel != null) {
      if (result.sensitivityLevel.index < minSensitivityLevel!.index) {
        return false;
      }
    }

    if (targetCategories != null && targetCategories!.isNotEmpty) {
      if (!targetCategories!.contains(result.primaryCategory)) return false;
    }

    if (requiredTags != null && requiredTags!.isNotEmpty) {
      for (final tag in requiredTags!) {
        if (!result.tags.contains(tag)) return false;
      }
    }

    if (excludedTags != null && excludedTags!.isNotEmpty) {
      for (final tag in excludedTags!) {
        if (result.tags.contains(tag)) return false;
      }
    }

    if (minConfidence != null) {
      if (result.confidence < minConfidence!) return false;
    }

    if (maxFileSizeBytes != null && fileSizeBytes != null) {
      if (fileSizeBytes > maxFileSizeBytes!) return false;
    }

    if (targetMimeTypes != null && targetMimeTypes!.isNotEmpty) {
      if (mimeType == null || !targetMimeTypes!.contains(mimeType)) {
        return false;
      }
    }

    return true;
  }

  Map<String, dynamic> toJson() => {
    if (minSensitivityLevel != null)
      'minSensitivityLevel': minSensitivityLevel!.index,
    if (targetCategories != null)
      'targetCategories': targetCategories!.map((c) => c.index).toList(),
    if (requiredTags != null)
      'requiredTags': requiredTags!.map((t) => t.index).toList(),
    if (excludedTags != null)
      'excludedTags': excludedTags!.map((t) => t.index).toList(),
    if (minConfidence != null) 'minConfidence': minConfidence,
    if (maxFileSizeBytes != null) 'maxFileSizeBytes': maxFileSizeBytes,
    if (targetMimeTypes != null) 'targetMimeTypes': targetMimeTypes,
  };
}

/// Aggregate statistics about content analysis across the library.
class ContentAnalysisStats {
  const ContentAnalysisStats({
    this.totalItems = 0,
    this.analyzedItems = 0,
    this.pendingItems = 0,
    this.categoryCounts = const {},
    this.sensitivityCounts = const {},
    this.actionCounts = const {},
    this.lastAnalyzedAt,
  });

  final int totalItems;
  final int analyzedItems;
  final int pendingItems;
  final Map<ContentCategory, int> categoryCounts;
  final Map<SensitivityLevel, int> sensitivityCounts;
  final Map<ModerationAction, int> actionCounts;
  final DateTime? lastAnalyzedAt;

  double get analyzedPercent =>
      totalItems > 0 ? analyzedItems / totalItems : 0.0;
}
