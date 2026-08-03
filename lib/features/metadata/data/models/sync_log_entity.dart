/// SyncLog entity per PRD Section 5.1 Collection 7.
///
/// Tracks sync operations for conflict resolution and diagnostics.
/// Each metadata change (upload, download, update, delete) is logged
/// with timestamps and success/failure status.
class SyncLogEntity {
  const SyncLogEntity({
    this.id,
    required this.mediaItemId,
    required this.operation,
    required this.timestamp,
    this.details,
    this.success = true,
    this.error,
  });

  factory SyncLogEntity.fromJson(Map<String, dynamic> json) {
    return SyncLogEntity(
      id: json['id'] as int?,
      mediaItemId: json['mediaItemId'] as String? ?? '',
      operation: json['operation'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      details: json['details'] as String?,
      success: json['success'] as bool? ?? true,
      error: json['error'] as String?,
    );
  }
  final int? id;
  final String mediaItemId;
  final String operation;
  final DateTime timestamp;
  final String? details;
  final bool success;
  final String? error;

  SyncLogEntity copyWith({
    int? id,
    String? mediaItemId,
    String? operation,
    DateTime? timestamp,
    String? details,
    bool? success,
    String? error,
  }) {
    return SyncLogEntity(
      id: id ?? this.id,
      mediaItemId: mediaItemId ?? this.mediaItemId,
      operation: operation ?? this.operation,
      timestamp: timestamp ?? this.timestamp,
      details: details ?? this.details,
      success: success ?? this.success,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mediaItemId': mediaItemId,
      'operation': operation,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'details': details,
      'success': success,
      'error': error,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncLogEntity &&
          runtimeType == other.runtimeType &&
          mediaItemId == other.mediaItemId &&
          operation == other.operation &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      mediaItemId.hashCode ^ operation.hashCode ^ timestamp.hashCode;

  @override
  String toString() =>
      'SyncLogEntity(mediaItemId: $mediaItemId, operation: $operation, '
      'timestamp: $timestamp, success: $success)';
}
