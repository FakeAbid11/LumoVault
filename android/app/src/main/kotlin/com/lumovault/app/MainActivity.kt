package com.lumovault.app

import android.app.PictureInPictureParams
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
