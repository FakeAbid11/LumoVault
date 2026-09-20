package com.lumovault.app

import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine.
 *
 * Extends FlutterFragmentActivity rather than FlutterActivity because
 * local_auth's Android implementation shows BiometricPrompt from a
 * FragmentActivity; with a plain FlutterActivity it fails at runtime.
 */
class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "lumo.app/package"
    private val PIP_CHANNEL = "lumo.app/pip"
    private val SETTINGS_CHANNEL = "lumo.app/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getPackageName") {
                    result.success(packageName)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchComponent" -> {
                        val pkg = call.argument<String>("package")
                        val activity = call.argument<String>("activity")
                        val action = call.argument<String>("action")
                        val extras = call.argument<Map<String, String>>("extras")
                        if (pkg == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent()
                            if (!action.isNullOrEmpty()) intent.action = action
                            if (!activity.isNullOrEmpty()) {
                                intent.component = ComponentName(pkg, activity)
                            } else if (!action.isNullOrEmpty()) {
                                // Action-only: restrict resolution to this package.
                                intent.setPackage(pkg)
                            }
                            extras?.forEach { (key, value) ->
                                intent.putExtra(key, value)
                            }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "openAppDetails" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$pkg")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "openBatteryOptimizations" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Some OEM ROMs lack the global exemption list —
                            // fall back to this app's details page.
                            try {
                                val fallback = Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(fallback)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        try {
                            val width = call.argument<Int>("width") ?: 16
                            val height = call.argument<Int>("height") ?: 9
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(width, height))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", e.message, null)
                        }
                    }
                    "isInPip" -> {
                        result.success(isInPictureInPictureMode)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Notify Flutter about PiP mode changes
        val flutterEngine = flutterEngine ?: return
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
            .invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }
}
