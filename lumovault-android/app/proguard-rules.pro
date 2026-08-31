# Add project specific ProGuard rules here.
-keepattributes *Annotation*

# Hilt
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }

# Room
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-dontwarn androidx.room.paging.**

# TDLib
-keep class org.drinkless.td.** { *; }
-keep class com.google.gson.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Sentry
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Mapbox
-keep class com.mapbox.** { *; }
-dontwarn com.mapbox.**

# ONNX Runtime
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# Keep data classes for serialization
-keepclassmembers class com.lumovault.core.database.entities.** { *; }
-keepclassmembers class com.lumovault.core.tdlib.** { *; }
