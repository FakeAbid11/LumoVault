package dev.fluttercommunity.workmanager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import com.google.common.util.concurrent.ListenableFuture
import dev.fluttercommunity.workmanager.pigeon.TaskStatus
import dev.fluttercommunity.workmanager.pigeon.WorkmanagerFlutterApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.view.FlutterCallbackInformation
import java.util.Random

/**
 * A simple worker that posts your input back to your Flutter application.
 *
 * It will block the background thread until a value of either true or false is received back from Flutter code.
 */
class BackgroundWorker(
    applicationContext: Context,
    private val workerParams: WorkerParameters,
) : ListenableWorker(applicationContext, workerParams) {
    private lateinit var flutterApi: WorkmanagerFlutterApi

    companion object {
        const val PAYLOAD_KEY = "dev.fluttercommunity.workmanager.INPUT_DATA"
        const val DART_TASK_KEY = "dev.fluttercommunity.workmanager.DART_TASK"

        // LumoVault fork: inputData keys (see background_backup_service.dart)
        // that opt a long-running task into a dataSync foreground service. The
        // Dart scheduler prefixes inputData keys with "payload_" on the way in
        // (see WorkManagerUtils.buildData), so they are read with that prefix.
        private const val FG_FLAG_KEY = "payload_lumo_foreground"
        private const val FG_CHANNEL_ID_KEY = "payload_lumo_fg_channel_id"
        private const val FG_NOTIFICATION_ID_KEY = "payload_lumo_fg_notification_id"
        private const val FG_TITLE_KEY = "payload_lumo_fg_title"
        private const val FG_TEXT_KEY = "payload_lumo_fg_text"
        private const val DEFAULT_FG_CHANNEL_ID = "backup_progress"
        private const val DEFAULT_FG_NOTIFICATION_ID = 1001

        private val flutterLoader = FlutterLoader()
    }

    private val payload
        get() =
            workerParams.inputData.keyValueMap
                .filter { it.key.startsWith("payload_") }
                .mapKeys { it.key.replace("payload_", "") }
                .mapValues {
                    when (it.value) {
                        is Array<*> -> (it.value as Array<*>).asList()
                        else -> it.value
                    }
                }

    private val dartTask
        get() = workerParams.inputData.getString(DART_TASK_KEY)

    private val runAttemptCount = workerParams.runAttemptCount
    private val randomThreadIdentifier = Random().nextInt()
    private var engine: FlutterEngine? = null

    private var startTime: Long = 0

    private var completer: CallbackToFutureAdapter.Completer<Result>? = null

    private var resolvableFuture =
        CallbackToFutureAdapter.getFuture { completer ->
            this.completer = completer
            null
        }

    override fun startWork(): ListenableFuture<Result> {
        startTime = System.currentTimeMillis()

        // LumoVault fork: promote long-running backup tasks to a dataSync
        // foreground service before doing any work, so they get extended runtime
        // and survive Doze. No-op for tasks that did not opt in via inputData.
        maybePromoteToForeground()

        val backgroundEngine = FlutterEngine(applicationContext)
        engine = backgroundEngine
        registerPlugins(backgroundEngine)

        if (!flutterLoader.initialized()) {
            flutterLoader.startInitialization(applicationContext)
        }

        flutterLoader.ensureInitializationCompleteAsync(
            applicationContext,
            null,
            Handler(Looper.getMainLooper()),
        ) {
            val callbackHandle = SharedPreferenceHelper.getCallbackHandle(applicationContext)
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle)

            if (callbackInfo == null) {
                val exception = IllegalStateException("Failed to resolve Dart callback for handle $callbackHandle")
                WorkmanagerDebug.onExceptionEncountered(applicationContext, null, exception)
                completer?.set(Result.failure())
                return@ensureInitializationCompleteAsync
            }

            val localDartTask = dartTask

            if (localDartTask == null) {
                val exception = IllegalStateException("Dart task is null")
                WorkmanagerDebug.onExceptionEncountered(applicationContext, null, exception)
                completer?.set(Result.failure())
                return@ensureInitializationCompleteAsync
            }

            val dartBundlePath = flutterLoader.findAppBundlePath()

            val taskInfo =
                TaskDebugInfo(
                    taskName = localDartTask,
                    inputData = payload,
                    startTime = startTime,
                    callbackHandle = callbackHandle,
                    callbackInfo = callbackInfo?.callbackName,
                )

            val startStatus = if (runAttemptCount > 0) TaskStatus.RETRYING else TaskStatus.STARTED
            WorkmanagerDebug.onTaskStatusUpdate(applicationContext, taskInfo, startStatus)

            engine?.let { engine ->
                flutterApi = WorkmanagerFlutterApi(engine.dartExecutor.binaryMessenger)

                engine.dartExecutor.executeDartCallback(
                    DartExecutor.DartCallback(
                        applicationContext.assets,
                        dartBundlePath,
                        callbackInfo,
                    ),
                )

                // Initialize the background channel
                flutterApi.backgroundChannelInitialized {
                    // Channel is initialized, now execute the task
                    executeBackgroundTask()
                }
            }
        }

        return resolvableFuture
    }

    override fun onStopped() {
        stopEngine(null)
    }

    private fun stopEngine(
        result: Result?,
        errorMessage: String? = null,
    ) {
        val fetchDuration = System.currentTimeMillis() - startTime

        val localDartTask = dartTask

        if (localDartTask == null) {
            val exception = IllegalStateException("Dart task is null")
            WorkmanagerDebug.onExceptionEncountered(applicationContext, null, exception)
            completer?.set(Result.failure())
            return
        }

        val taskInfo =
            TaskDebugInfo(
                taskName = localDartTask,
                inputData = payload,
                startTime = startTime,
            )

        val taskResult =
            TaskResult(
                success = result is Result.Success,
                duration = fetchDuration,
                error =
                    when (result) {
                        is Result.Failure -> errorMessage ?: "Task failed"
                        else -> null
                    },
            )

        val status =
            when (result) {
                is Result.Success -> TaskStatus.COMPLETED
                is Result.Retry -> TaskStatus.RESCHEDULED
                else -> TaskStatus.FAILED
            }
        WorkmanagerDebug.onTaskStatusUpdate(applicationContext, taskInfo, status, taskResult)

        // No result indicates we were signalled to stop by WorkManager.  The result is already
        // STOPPED, so no need to resolve another one.
        if (result != null) {
            this.completer?.set(result)
        }

        // If stopEngine is called from `onStopped`, it may not be from the main thread.
        Handler(Looper.getMainLooper()).post {
            engine?.destroy()
            engine = null
        }
    }

    private fun executeBackgroundTask() {
        // Convert payload to the format expected by Pigeon (Map<String?, Object?>)
        val pigeonPayload = payload.mapKeys { it.key as String? }.mapValues { it.value as Object? }

        val localDartTask = dartTask

        if (localDartTask == null) {
            val exception = IllegalStateException("Dart task is null")
            WorkmanagerDebug.onExceptionEncountered(applicationContext, null, exception)

            stopEngine(Result.failure(), exception.message)
            return
        }

        flutterApi.executeTask(localDartTask, pigeonPayload) { result ->
            when {
                result.isSuccess -> {
                    val wasSuccessful = result.getOrNull() ?: false
                    stopEngine(if (wasSuccessful) Result.success() else Result.retry())
                }
                result.isFailure -> {
                    val exception = result.exceptionOrNull()
                    // Don't call onExceptionEncountered for Dart task failures
                    // These are handled as normal failures via onTaskStatusUpdate
                    stopEngine(Result.failure(), exception?.message)
                }
            }
        }
    }

    /**
     * LumoVault fork: when the task opted in via inputData, promote this worker
     * to a `dataSync` foreground service so it is exempt from the ~10-minute
     * WorkManager execution limit and from Doze/App Standby.
     *
     * The notification identity (channel id + notification id) is passed from
     * Dart so it matches the app's own "backup progress" notification — the Dart
     * side then updates that same notification with live progress, keeping it a
     * single notification rather than two.
     *
     * Failures are non-fatal (matching [registerPlugins]): the task still runs,
     * just under the standard background limits.
     */
    private fun maybePromoteToForeground() {
        try {
            val data = workerParams.inputData.keyValueMap
            val wantsForeground = data[FG_FLAG_KEY] as? Boolean ?: false
            if (!wantsForeground) return

            val channelId = data[FG_CHANNEL_ID_KEY] as? String ?: DEFAULT_FG_CHANNEL_ID
            // Pigeon/WorkManager may deliver the id as Int or Long depending on
            // the codec, so accept either.
            val notificationId =
                when (val raw = data[FG_NOTIFICATION_ID_KEY]) {
                    is Int -> raw
                    is Long -> raw.toInt()
                    else -> DEFAULT_FG_NOTIFICATION_ID
                }
            val title = data[FG_TITLE_KEY] as? String ?: "Working…"
            val text = data[FG_TEXT_KEY] as? String ?: ""

            ensureChannel(channelId)

            val notification =
                NotificationCompat
                    .Builder(applicationContext, channelId)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setSmallIcon(applicationContext.applicationInfo.icon)
                    .setOngoing(true)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .build()

            val foregroundInfo =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ForegroundInfo(
                        notificationId,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                } else {
                    ForegroundInfo(notificationId, notification)
                }
            setForegroundAsync(foregroundInfo)
        } catch (e: Exception) {
            WorkmanagerDebug.onExceptionEncountered(applicationContext, null, e)
        }
    }

    /**
     * Idempotently create the notification channel the foreground notification
     * posts to. The native worker can run before the Dart isolate re-creates the
     * app's channels, so it cannot assume the channel already exists; recreating
     * an existing channel is a no-op, and the id matches the Dart-side
     * `backup_progress` channel.
     */
    private fun ensureChannel(channelId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        if (manager != null && manager.getNotificationChannel(channelId) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Backup progress",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }

    /**
     * Registers every app plugin with the background isolate's [engine].
     *
     * LumoVault fork: upstream workmanager_android creates the background
     * FlutterEngine without registering plugins, so the background isolate
     * has no platform channels and any plugin call (e.g. tdlib) throws
     * MissingPluginException. The Flutter tooling generates
     * `io.flutter.plugins.GeneratedPluginRegistrant` into the *app* module,
     * which this plugin library cannot reference at compile time — so it is
     * looked up reflectively instead. It is present at runtime for any
     * `flutter build` output and is annotated `@Keep`, so it survives R8
     * shrinking. Registration failures are non-fatal: the task still runs,
     * just without plugins.
     */
    private fun registerPlugins(engine: FlutterEngine) {
        try {
            val registrant = Class.forName("io.flutter.plugins.GeneratedPluginRegistrant")
            registrant
                .getMethod("registerWith", FlutterEngine::class.java)
                .invoke(null, engine)
        } catch (e: Exception) {
            WorkmanagerDebug.onExceptionEncountered(applicationContext, null, e)
        }
    }
}
