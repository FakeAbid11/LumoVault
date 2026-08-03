# LumoVault R8/ProGuard keep rules.
#
# Referenced by app/build.gradle.kts, which sets isMinifyEnabled = true and
# isShrinkResources = true for the release build — so these rules ARE
# exercised by every release build. They protect reflective entry points
# (Flutter embedding, WorkManager workers, TDLib JNI, notifications,
# biometrics) that R8 cannot see are reachable.
#
# These rules only take effect in a release build; `flutter run` and
# `flutter test` never exercise them. Changes here need verifying with an
# actual `flutter build apk --release` run on a device.

# --- Flutter embedding -------------------------------------------------------
# The engine resolves these by name from native code / generated registrants.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- WorkManager background tasks -------------------------------------------
# Workers are instantiated reflectively by class name from WorkManager's
# database, so a renamed worker class fails at run time, not build time.
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# --- TDLib (consumed via the `tdlib` pub package) ---------------------------
# The client bridges Dart <-> native through JNI; the Java-side entry points
# must keep their names for the native library to find them.
-keep class org.drinkless.** { *; }
-keep class org.drinkless.tdlib.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Local notifications / scheduled work -----------------------------------
# Notification receivers and the Gson models used to persist scheduled
# notifications across reboots are both resolved reflectively.
-keep class com.dexterous.** { *; }
-keepclassmembers class com.dexterous.** { *; }
-keep class * extends android.app.NotificationChannel { *; }

# --- Biometrics / secure storage --------------------------------------------
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# --- Kotlin metadata ---------------------------------------------------------
# Stripping this breaks reflection-based Kotlin interop in plugins.
-keep class kotlin.Metadata { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# --- Crash reporting ---------------------------------------------------------
# Obfuscated stack traces are unreadable without these.
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
