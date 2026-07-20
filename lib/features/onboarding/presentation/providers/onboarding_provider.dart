import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onboarding step enumeration.
enum OnboardingStep {
  welcome,
  permissions,
  folderSelection,
  initialScan,
  telegramConnect,
}

/// Onboarding state.
class OnboardingState {
  const OnboardingState({
    this.currentStep = OnboardingStep.welcome,
    this.isCompleted = false,
    this.selectedFolders = const {},
    this.photoCount = 0,
    this.videoCount = 0,
    this.estimatedSizeBytes = 0,
    this.isScanning = false,
    this.scanComplete = false,
  });

  final OnboardingStep currentStep;
  final bool isCompleted;
  final Set<String> selectedFolders;
  final int photoCount;
  final int videoCount;
  final int estimatedSizeBytes;
  final bool isScanning;
  final bool scanComplete;

  double get progress {
    const steps = OnboardingStep.values;
    final totalSteps = steps.length;
    final currentIndex = steps.indexOf(currentStep);
    return (currentIndex + 1) / totalSteps;
  }

  OnboardingState copyWith({
    OnboardingStep? currentStep,
    bool? isCompleted,
    Set<String>? selectedFolders,
    int? photoCount,
    int? videoCount,
    int? estimatedSizeBytes,
    bool? isScanning,
    bool? scanComplete,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      isCompleted: isCompleted ?? this.isCompleted,
      selectedFolders: selectedFolders ?? this.selectedFolders,
      photoCount: photoCount ?? this.photoCount,
      videoCount: videoCount ?? this.videoCount,
      estimatedSizeBytes: estimatedSizeBytes ?? this.estimatedSizeBytes,
      isScanning: isScanning ?? this.isScanning,
      scanComplete: scanComplete ?? this.scanComplete,
    );
  }
}

/// Notifier for managing onboarding state.
class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(const OnboardingState());

  void goToStep(OnboardingStep step) {
    state = state.copyWith(currentStep: step);
  }

  void nextStep() {
    final currentIndex = OnboardingStep.values.indexOf(state.currentStep);
    if (currentIndex < OnboardingStep.values.length - 1) {
      state = state.copyWith(
        currentStep: OnboardingStep.values[currentIndex + 1],
      );
    }
  }

  void previousStep() {
    final currentIndex = OnboardingStep.values.indexOf(state.currentStep);
    if (currentIndex > 0) {
      state = state.copyWith(
        currentStep: OnboardingStep.values[currentIndex - 1],
      );
    }
  }

  void toggleFolder(String folderPath) {
    final selected = Set<String>.from(state.selectedFolders);
    if (selected.contains(folderPath)) {
      selected.remove(folderPath);
    } else {
      selected.add(folderPath);
    }
    state = state.copyWith(selectedFolders: selected);
  }

  void selectAllFolders(List<String> folderPaths) {
    state = state.copyWith(selectedFolders: Set<String>.from(folderPaths));
  }

  void deselectAllFolders() {
    state = state.copyWith(selectedFolders: {});
  }

  void updateScanResults({
    required int photoCount,
    required int videoCount,
    required int estimatedSizeBytes,
  }) {
    state = state.copyWith(
      photoCount: photoCount,
      videoCount: videoCount,
      estimatedSizeBytes: estimatedSizeBytes,
    );
  }

  void startScan() {
    state = state.copyWith(isScanning: true, scanComplete: false);
  }

  void completeScan() {
    state = state.copyWith(isScanning: false, scanComplete: true);
  }

  void completeOnboarding() {
    state = state.copyWith(isCompleted: true);
  }

  void reset() {
    state = const OnboardingState();
  }
}

/// Provider for onboarding state.
final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
      return OnboardingNotifier();
    });

/// Provider for checking if onboarding is completed.
/// Uses a simple in-memory flag for now; Prompt 4 will add persistence.
final onboardingCompletedProvider = StateProvider<bool>((ref) => false);
