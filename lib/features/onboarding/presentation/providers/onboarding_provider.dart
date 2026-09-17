import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../gallery/data/models/device_folder.dart';

/// Onboarding step enumeration.
enum OnboardingStep { welcome, permissions, folderSelection, telegramConnect }

/// Onboarding state.
class OnboardingState {
  const OnboardingState({
    this.currentStep = OnboardingStep.welcome,
    this.isCompleted = false,
    this.selectedFolders = const {},
    this.deviceFolders = const [],
  });

  final OnboardingStep currentStep;
  final bool isCompleted;
  final Set<String> selectedFolders;
  final List<DeviceFolder> deviceFolders;

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
    List<DeviceFolder>? deviceFolders,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      isCompleted: isCompleted ?? this.isCompleted,
      selectedFolders: selectedFolders ?? this.selectedFolders,
      deviceFolders: deviceFolders ?? this.deviceFolders,
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

  void setDeviceFolders(List<DeviceFolder> folders) {
    state = state.copyWith(deviceFolders: folders);
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
final onboardingCompletedProvider = StateProvider<bool>((ref) => false);
