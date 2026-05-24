plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.terraton.terraton_fan_app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.terraton.terraton_fan_app"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Release signing via environment variables (set by GitHub Actions).
        // Falls back to the Android debug keystore for local builds so that
        // build.ps1 and `flutter run --release` continue to work unchanged.
        create("release") {
            val keystorePath = System.getenv("KEYSTORE_PATH")
            if (!keystorePath.isNullOrBlank() && java.io.File(keystorePath).exists()) {
                storeFile     = java.io.File(keystorePath)
                storePassword = System.getenv("STORE_PASSWORD")
                keyAlias      = System.getenv("KEY_ALIAS")
                keyPassword   = System.getenv("KEY_PASSWORD")
            } else {
                // Local dev — use the auto-generated Android debug keystore.
                val debug = signingConfigs.getByName("debug")
                storeFile     = debug.storeFile
                storePassword = debug.storePassword
                keyAlias      = debug.keyAlias
                keyPassword   = debug.keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
