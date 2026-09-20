import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Platform surface used by [NotificationService].
///
/// Kept as an interface so tests can drive the service without a plugin
/// registrant — plain `flutter test` has no platform channels.
abstract class NotificationBackend {
  /// Prepare the platform plugin. Returns false when unavailable.
  Future<bool> initialize();

  /// Create (or update) an Android notification channel.
  Future<void> createChannel({
    required String id,
    required String name,
    required String description,
    required NotificationPriority priority,
  });

  /// Ask the user for permission to post notifications (Android 13+).
  Future<bool> requestPermission();

  /// Post or update a notification.
  Future<void> show(NotificationRequest request);

  /// Dismiss one notification.
  Future<void> cancel(int id);

  /// Dismiss every notification this app posted.
  Future<void> cancelAll();
}

/// Importance of a channel or notification, mapped per platform by the backend.
enum NotificationPriority { low, normal, high }

/// A single notification to post, including optional progress state.
@immutable
class NotificationRequest {
  const NotificationRequest({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.body,
    this.priority = NotificationPriority.normal,
    this.ongoing = false,
    this.showProgress = false,
    this.progress = 0,
    this.maxProgress = 0,
    this.indeterminate = false,
    this.payload,
  });

  final int id;
  final String channelId;
  final String channelName;
  final String title;
  final String body;
  final NotificationPriority priority;

  /// Non-dismissable notification, used for the running backup.
  final bool ongoing;

  final bool showProgress;
  final int progress;
  final int maxProgress;
  final bool indeterminate;
  final String? payload;
}

/// [NotificationBackend] backed by `flutter_local_notifications`.
class PluginNotificationBackend implements NotificationBackend {
  PluginNotificationBackend({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String _defaultIcon = '@mipmap/ic_launcher';

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<bool> initialize() async {
    return _guard(() async {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_defaultIcon),
        ),
      );
      return true;
    }, fallback: false);
  }

  @override
  Future<void> createChannel({
    required String id,
    required String name,
    required String description,
    required NotificationPriority priority,
  }) async {
    await _guard(() async {
      await _android?.createNotificationChannel(
        AndroidNotificationChannel(
          id,
          name,
          description: description,
          importance: _importance(priority),
        ),
      );
      return null;
    }, fallback: null);
  }

  @override
  Future<bool> requestPermission() async {
    return _guard(() async {
      final android = await _android?.requestNotificationsPermission();
      return android ?? false;
    }, fallback: false);
  }

  @override
  Future<void> show(NotificationRequest request) async {
    await _guard(() async {
      await _plugin.show(
        id: request.id,
        title: request.title,
        body: request.body,
        payload: request.payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            request.channelId,
            request.channelName,
            importance: _importance(request.priority),
            priority: _priority(request.priority),
            ongoing: request.ongoing,
            autoCancel: !request.ongoing,
            // Progress updates re-post the same id; alerting each time would
            // buzz the device on every file.
            onlyAlertOnce: request.showProgress,
            showProgress: request.showProgress,
            progress: request.progress,
            maxProgress: request.maxProgress,
            indeterminate: request.indeterminate,
          ),
        ),
      );
      return null;
    }, fallback: null);
  }

  @override
  Future<void> cancel(int id) async {
    await _guard(() async {
      await _plugin.cancel(id: id);
      return null;
    }, fallback: null);
  }

  @override
  Future<void> cancelAll() async {
    await _guard(() async {
      await _plugin.cancelAll();
      return null;
    }, fallback: null);
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Importance _importance(NotificationPriority priority) {
    return switch (priority) {
      NotificationPriority.low => Importance.low,
      NotificationPriority.normal => Importance.defaultImportance,
      NotificationPriority.high => Importance.high,
    };
  }

  Priority _priority(NotificationPriority priority) {
    return switch (priority) {
      NotificationPriority.low => Priority.low,
      NotificationPriority.normal => Priority.defaultPriority,
      NotificationPriority.high => Priority.high,
    };
  }

  /// Run [action], swallowing the platform failures that mean "no plugin here".
  ///
  /// A missing notification channel must never take down a backup, and
  /// MissingPluginException does not extend PlatformException, so both need
  /// their own clause.
  @visibleForTesting
  static Future<T> guard<T>(
    Future<T> Function() action, {
    required T fallback,
  }) async {
    try {
      return await action();
    } on MissingPluginException catch (e) {
      debugPrint('[Notifications] Plugin unavailable: ${e.message}');
      return fallback;
    } on PlatformException catch (e) {
      debugPrint('[Notifications] Platform error: ${e.code} ${e.message}');
      return fallback;
    }
  }

  Future<T> _guard<T>(Future<T> Function() action, {required T fallback}) =>
      guard(action, fallback: fallback);
}
