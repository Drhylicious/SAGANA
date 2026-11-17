import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details (git-ignored). See the signing config below.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Phone notifications need the Firebase config file from the Firebase console
// (Project settings > Your apps > Android > google-services.json). Without it the
// app still builds and runs, with in-app notifications only.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.sp3cooperative.sagana"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sp3cooperative.sagana"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // The permanent SAGANA release key. Phones only accept an APK as an update
        // when it is signed with the same key as the installed app, so this key
        // must never change and must be backed up (see android/key.properties).
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Release builds are signed with the permanent key only. Without
            // android/key.properties the build stops (see below) instead of
            // quietly producing an APK signed with a throwaway debug key.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        it.name.contains("Release") && (it.name.startsWith("assemble") || it.name.startsWith("bundle") || it.name.startsWith("package"))
    }
    if (buildsRelease && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "android/key.properties was not found. Release APKs must be signed with the " +
                "permanent SAGANA key. Restore key.properties and the .jks file from your backup."
        )
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
