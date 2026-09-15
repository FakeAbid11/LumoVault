import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of version control.
//
// `android/key.properties` is gitignored (along with *.jks / *.keystore), so a
// checkout has no keystore and cannot produce a signed release. Rather than
// silently falling back to the debug keystore — which produced release APKs
// signed with the publicly-known Android debug key, unusable on Play and
// trivially re-signable — an absent file leaves the release build UNSIGNED and
// says so. Signing then has to be configured deliberately.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseSigning = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.lumovault.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications publishes AAR metadata requiring the
        // consuming app module to desugar the java.time APIs it uses for
        // scheduled notifications. Without this the build fails outright at
        // :app:checkDebugAarMetadata.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.lumovault.app"
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = keystoreProperties.getProperty("storeFile")
                    ?.let { rootProject.file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "LumoVault: android/key.properties not found — the release " +
                        "build will be UNSIGNED. See android/key.properties.example."
                )
            }
            // R8 minification and resource shrinking. The keep rules in
            // proguard-rules.pro protect Flutter embedding, WorkManager,
            // TDLib JNI, notifications, and biometrics from being stripped.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
