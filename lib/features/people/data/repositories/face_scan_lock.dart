/// Name of the cross-isolate lock guarding the face-scan pipeline.
///
/// Shared by the in-app scan ([FaceScanController], UI isolate) and the
/// background `kFaceScanTask` handler (WorkManager isolate) so only one ONNX
/// detection pipeline ever runs at a time. Lives in its own file because both
/// sides need it: the backup service already imports the people providers,
/// so importing the engine back from there would create an import cycle.
const String kFaceScanLockName = 'face_scan';

/// Schedules the one-off background face scan; set at bootstrap (main.dart)
/// to [BackgroundBackupService.registerFaceScanOneOff].
///
/// A hook rather than a direct import: the people feature must not import the
/// backup engine (the engine already imports people providers), and the hook
/// keeps widget tests free of any WorkManager surface.
Future<void> Function()? scheduleOneOffFaceScan;
