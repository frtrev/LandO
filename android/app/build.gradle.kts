import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val mapsProperties = Properties().apply {
    val file = rootProject.file("maps.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

val uploadProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasUploadSigning = listOf("storeFile", "storePassword", "keyPassword", "keyAlias")
    .all { !uploadProperties.getProperty(it).isNullOrBlank() }
val developmentSigning = providers.environmentVariable("LANDO_DEVELOPMENT_SIGNING").orNull == "true"

// Never publish a debug-signed or accidentally unsigned Play bundle.
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any { it.path.startsWith(":app:") && it.name.endsWith("Release") }
    val playBundleRequested = allTasks.any { it.path == ":app:bundleRelease" }
    if (releaseRequested) {
        check(!(developmentSigning && playBundleRequested)) { "Play bundles cannot use development/debug signing." }
        check(hasUploadSigning || developmentSigning) {
            "Release signing is missing. Configure android/key.properties with your upload key. " +
            "For APK-only local development, explicitly set LANDO_DEVELOPMENT_SIGNING=true."
        }
        check(!mapsProperties.getProperty("MAPS_API_KEY").isNullOrBlank()) {
            "A restricted Android Maps/Places key is required for release. Configure android/maps.properties."
        }
    }
}

android {
    namespace = "com.neotheone.lando"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.neotheone.lando"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        manifestPlaceholders["MAPS_API_KEY"] = mapsProperties.getProperty("MAPS_API_KEY", "")
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            if (hasUploadSigning) {
                storeFile = rootProject.file(uploadProperties.getProperty("storeFile"))
                storePassword = uploadProperties.getProperty("storePassword")
                keyAlias = uploadProperties.getProperty("keyAlias")
                keyPassword = uploadProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (developmentSigning) "debug" else "upload")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Native Places SDK uses the same Android-restricted key as the map.
dependencies {
    implementation("com.google.android.libraries.places:places:5.0.0")
}
