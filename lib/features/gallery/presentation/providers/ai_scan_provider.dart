import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';

/// State of the on-demand AI labeling scan.
class AiScanState {
  const AiScanState({
    this.running = false,
    this.completed = 0,
    this.total = 0,
    this.startedAt,
    this.error,
    this.lastLabels = const [],
  });

  final bool running;
  final int completed;
  final int total;
  final DateTime? startedAt;

  /// Why the last scan ended without finishing (model failed to load, no
  /// photos, nothing left to label). Surfaced on the Search screen's card.
  final String? error;

  /// The most recent labels detected, newest first (capped at 5).
  final List<String> lastLabels;

  /// Labeled items per minute so the UI can show an ETA.
  double get itemsPerMinute {
    if (startedAt == null || completed == 0) return 0;
    final minutes =
        DateTime.now().difference(startedAt!).inMilliseconds / 60000;
    if (minutes <= 0) return 0;
    return completed / minutes;
  }

  /// Estimated minutes remaining, or null while unknown/not running.
  double? get etaMinutes {
    final rate = itemsPerMinute;
    if (rate <= 0 || !running) return null;
    return (total - completed) / rate;
  }

  AiScanState copyWith({
    bool? running,
    int? completed,
    int? total,
    DateTime? startedAt,
    String? error,
    List<String>? lastLabels,
  }) {
    return AiScanState(
      running: running ?? this.running,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      startedAt: startedAt ?? this.startedAt,
      error: error,
      lastLabels: lastLabels ?? this.lastLabels,
    );
  }
}

/// Controller for the manual AI labeling scan.
///
/// Lives at provider scope — NOT in the Search screen's widget state — so
/// the scan keeps running when the user navigates away from the Search tab.
/// The old implementation looped inside the widget's `State` and silently
/// stopped the moment the screen unmounted, which made labeling a large
/// library an exercise in keeping one screen open.
final aiScanControllerProvider =
    NotifierProvider<AiScanController, AiScanState>(AiScanController.new);

class AiScanController extends Notifier<AiScanState> {
  bool _cancelRequested = false;

  @override
  AiScanState build() => const AiScanState();

  /// Label every device image that doesn't have AI labels yet.
  Future<void> start() async {
    if (state.running) return;

    // Set synchronously BEFORE the first await: two rapid taps used to both
    // pass the running check during the initial asset fetch and double-run
    // the scan; a stop() pressed in that window was also silently erased.
    _cancelRequested = false;
    state = const AiScanState(running: true);

    // Fetch ALL device images — not just items from folders included in
    // backup — so search covers the whole library.
    final allAssets = await ref.read(deviceAssetsProvider.future);
    final deviceImages = allAssets
        .where((a) => a.type == AssetType.image)
        .toList();
    if (deviceImages.isEmpty) {
      state = const AiScanState(error: 'No photos found on this device.');
      return;
    }

    final repository = ref.read(galleryRepositoryProvider);
    final labeledIds = repository.labeledLocalIds;
    final unlabeled = deviceImages
        .where((a) => !labeledIds.contains(a.id))
        .toList();
    if (unlabeled.isEmpty) {
      state = const AiScanState(error: 'All photos are already labeled.');
      return;
    }

    // The first manual scan flips on the hourly background auto-labeling.
    ref
        .read(appSettingsProvider.notifier)
        .updateField((s) => s.copyWith(aiScanEnabled: true));

    final classifier = ref.read(imageClassifierProvider);
    await classifier.init();
    if (!classifier.isReady) {
      debugPrint('[AiScan] Classifier failed to initialize');
      state = const AiScanState(
        error: 'AI model failed to load. Restart the app and try again.',
      );
      return;
    }

    state = state.copyWith(total: unlabeled.length, startedAt: DateTime.now());

    for (var i = 0; i < unlabeled.length; i++) {
      if (_cancelRequested) break;

      final asset = unlabeled[i];
      try {
        final labels = await classifier.classify(asset);
        debugPrint('[AiScan] ${asset.title ?? asset.id}: $labels');
        if (labels.isNotEmpty) {
          await repository.labelAnyMediaItem(asset.id, labels);
          state = state.copyWith(
            completed: i + 1,
            lastLabels: [
              ...labels,
              ...state.lastLabels,
            ].take(5).toList(),
          );
        } else {
          state = state.copyWith(completed: i + 1);
        }
      } catch (e) {
        debugPrint('[AiScan] Failed to classify ${asset.id}: $e');
        state = state.copyWith(completed: i + 1);
      }
    }

    state = state.copyWith(running: false);
    ref.invalidate(unlabeledItemsProvider);
    ref.invalidate(labeledCountProvider);
  }

  /// Stop after the current photo. Already-labeled photos keep their labels.
  void stop() {
    _cancelRequested = true;
  }
}
