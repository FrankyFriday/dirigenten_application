plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.dirigenten_application"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // Kotlin Compiler Optionen korrekt setzen
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            keyAlias = "dirigenten"
            keyPassword = "Franky-posaune03"
            storeFile = file("dirigenten-release.jks")
            storePassword = "Franky-posaune03"
        }
    }


    defaultConfig {
        applicationId = "com.example.dirigenten_application"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
