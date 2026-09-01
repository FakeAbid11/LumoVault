package com.lumovault.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPackageName" -> result.success(packageName)
                    "openMiuiAutostart" -> result.success(openMiuiAutostart())
                    "openMiuiBatterySettings" ->
                        result.success(openMiuiBatterySettings())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Opens MIUI's Autostart management page (Security Center), falling back
     * to this app's App Info page when no MIUI activity matches.
     *
     * `url_launcher` cannot do this: the Autostart page is a non-exported
     * activity inside `com.miui.securitycenter`, reachable only through an
     * explicit component intent fired via `startActivity` — which, unlike
     * `resolveActivity`/`canLaunchUrl`, is not subject to Android 11+
     * package-visibility filtering. Unresolvable activities surface as
     * [ActivityNotFoundException] (or [SecurityException] on builds that
     * refuse third-party starts), so each candidate is tried in order and
     * the first success wins.
     */
    private fun openMiuiAutostart(): Boolean {
        val candidates = listOf(
            // MIUI 10+ Security Center: the Autostart management activity.
            Intent().setClassName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            // Older MIUI builds expose the permission editor via these actions.
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .setPackage("com.miui.securitycenter"),
            Intent("com.miui.securitycenter.action.APP_PERM_EDITOR"),
        )
        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // Candidate not present on this MIUI version — try the next.
            } catch (_: SecurityException) {
                // Build refuses third-party starts of this activity — try the next.
            }
        }

        // Nothing matched: open the App Info page, where MIUI surfaces this
        // app's "Other permissions" and battery controls.
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    /**
     * Opens the battery-saver / background-activity settings for this app,
     * falling back through progressively more generic pages.
     *
     * MIUI replaces Android's stock battery-optimization dialog with its own
     * PowerKeeper/Security Center pages, and the generic
     * `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` prompt is suppressed or
     * silently no-ops on many MIUI/HyperOS builds — so the explicit per-app
     * PowerKeeper activity is tried first, exactly like [openMiuiAutostart].
     *
     * Every candidate launch failure surfaces as [ActivityNotFoundException]
     * (or [SecurityException]), so each is tried in order and the first
     * success wins; the final fallback is the always-resolvable App Info
     * page.
     */
    private fun openMiuiBatterySettings(): Boolean {
        val appName = applicationInfo.loadLabel(packageManager).toString()
        val miuiCandidates = listOf(
            // PowerKeeper: MIUI's per-app "Battery saver" page, where
            // "No restrictions" and background-activity controls live.
            Intent().setClassName(
                "com.miui.powerkeeper",
                "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
            )
                .putExtra("package_name", packageName)
                .putExtra("package_label", appName),
            // Some builds expose PowerKeeper's UI under the Security Center.
            Intent().setClassName(
                "com.miui.securitycenter",
                "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
            )
                .putExtra("package_name", packageName)
                .putExtra("package_label", appName),
        )
        for (intent in miuiCandidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // Candidate not present on this MIUI version — try the next.
            } catch (_: SecurityException) {
                // Build refuses third-party starts of this activity — try the next.
            }
        }

        // AOSP battery-optimization prompt: the correct destination on stock
        // Android (Samsung/Huawei/OnePlus/Oppo builds reach this after their
        // MIUI candidates miss).
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return true
        } catch (_: ActivityNotFoundException) {
            // ROM strips the prompt — fall through to App Info.
        } catch (_: SecurityException) {
            // Manifest permission not honored on this build — fall through.
        }

        // App Info: always resolvable, exposes the per-app battery controls.
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
