allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some published Android plugins (e.g. tdlib) predate AGP's mandatory
// `namespace` field and only declare a `package` attribute in their
// AndroidManifest.xml. AGP 8+ fails to configure those modules unless a
// namespace is set. Since these come from pub.dev, we can't edit their
// source directly, so we backfill the namespace here by reading it out of
// each subproject's own manifest.
subprojects {
    val fixMissingNamespace: () -> Unit = {
        val androidExtension = extensions.findByName("android")
        if (androidExtension is com.android.build.gradle.BaseExtension &&
            androidExtension.namespace == null
        ) {
            val manifestFile = androidExtension.sourceSets.getByName("main").manifest.srcFile
            if (manifestFile.exists()) {
                val parsedManifest = groovy.xml.XmlParser().parse(manifestFile)
                val packageName = parsedManifest.attribute("package") as String?
                if (!packageName.isNullOrBlank()) {
                    androidExtension.namespace = packageName
                }
            }
        }
    }
    // :app is forced to evaluate early by evaluationDependsOn(":app") above, so by
    // the time we get here it may already be evaluated — calling afterEvaluate on an
    // already-evaluated project throws. Run immediately in that case instead.
    if (project.state.executed) {
        fixMissingNamespace()
    } else {
        afterEvaluate { fixMissingNamespace() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Some published Android plugins (e.g. photo_manager) don't pin their own
// Java/Kotlin compile target, so it silently defaults to whatever JDK is
// running Gradle (e.g. 21) instead of matching the project's javac target
// (17), causing an "Inconsistent JVM-target compatibility" failure. We
// can't edit that plugin's source, so force every subproject's compile
// tasks onto the same JVM target from the root build.
subprojects {
    // :app is forced to evaluate early via evaluationDependsOn(":app") above, which
    // finalizes its DSL before this block runs — trying to set compileOptions on an
    // already-finalized extension throws "sourceCompatibility has been finalized".
    // :app also already sets these correctly itself, so it doesn't need this fix;
    // only third-party plugin subprojects (which don't) do.
    if (project.name == "app") return@subprojects

    val pinJvmTarget: () -> Unit = {
        // Setting compileOptions on the extension (rather than the JavaCompile
        // task directly) matters here: AGP wires the javac task's source/target
        // compatibility from this extension property during its own internal
        // finalization, which runs later than a plain afterEvaluate callback.
        // Setting the task property directly gets silently overwritten by that
        // later AGP step, which is why plugins like workmanager_android kept
        // reverting to their own hardcoded 1.8.
        val androidExtension = extensions.findByName("android")
        if (androidExtension is com.android.build.gradle.BaseExtension) {
            androidExtension.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
            androidExtension.compileOptions.targetCompatibility = JavaVersion.VERSION_17
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            kotlinOptions {
                jvmTarget = JavaVersion.VERSION_17.toString()
            }
        }
    }
    if (project.state.executed) {
        pinJvmTarget()
    } else {
        afterEvaluate { pinJvmTarget() }
    }
}
