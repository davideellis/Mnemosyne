plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun Project.stringConfig(name: String, envName: String): String? {
    return providers.environmentVariable(envName).orNull
        ?: (findProperty(name) as String?)
}

val releaseKeystorePath =
    project.stringConfig("mnemosyne.android.keystorePath", "MNEMOSYNE_ANDROID_KEYSTORE_PATH")
val releaseKeystorePassword =
    project.stringConfig("mnemosyne.android.keystorePassword", "MNEMOSYNE_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias =
    project.stringConfig("mnemosyne.android.keyAlias", "MNEMOSYNE_ANDROID_KEY_ALIAS")
val releaseKeyPassword =
    project.stringConfig("mnemosyne.android.keyPassword", "MNEMOSYNE_ANDROID_KEY_PASSWORD")
val hasReleaseSigning =
    !releaseKeystorePath.isNullOrBlank() &&
        !releaseKeystorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "com.davideellis.mnemosyne"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.davideellis.mnemosyne"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "release" else "debug",
            )
        }
    }
}

flutter {
    source = "../.."
}
