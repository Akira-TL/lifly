import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePropertiesFile = rootProject.file("key.properties")
val releaseKeystoreProperties = Properties().apply {
    if (releaseKeystorePropertiesFile.exists()) {
        releaseKeystorePropertiesFile.inputStream().use(::load)
    }
}

fun releaseKeystoreValue(name: String): String =
    requireNotNull(releaseKeystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }) {
        "Missing Android release signing property '$name' in android/key.properties"
    }

android {
    namespace = "com.lifly.app"
    compileSdk = 37
    compileSdkMinor = 0
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lifly.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    sourceSets.getByName("main").jniLibs.srcDir(
        rootProject.file("../../../build/native-opaque/android")
    )

    signingConfigs {
        if (releaseKeystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = releaseKeystoreValue("keyAlias")
                keyPassword = releaseKeystoreValue("keyPassword")
                storeFile = file(releaseKeystoreValue("storeFile"))
                storePassword = releaseKeystoreValue("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // The keystore itself is ignored by Git and must never be committed.
            // Official release tasks are rejected below when signing is absent.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any {
        it.path.startsWith(":app:") && it.name.contains("Release", ignoreCase = true)
    }
    if (releaseRequested && !releaseKeystorePropertiesFile.exists()) {
        throw GradleException(
            "Android release signing is required. Configure android/key.properties; " +
                "unsigned release artifacts are not accepted."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
