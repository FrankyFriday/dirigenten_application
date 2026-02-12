import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("app/key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    throw GradleException("Keystore properties file not found: $keystorePropertiesFile")
}

android {
    namespace = "com.example.dirigenten_application"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.dirigenten_application"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            // zwingend File + Properties
            val storeFilePath = keystoreProperties.getProperty("storeFile")
                ?: throw GradleException("storeFile not found in key.properties")
            storeFile = file(storeFilePath)

            storePassword = keystoreProperties.getProperty("storePassword")
                ?: throw GradleException("storePassword not found in key.properties")

            keyAlias = keystoreProperties.getProperty("keyAlias")
                ?: throw GradleException("keyAlias not found in key.properties")

            keyPassword = keystoreProperties.getProperty("keyPassword")
                ?: throw GradleException("keyPassword not found in key.properties")
        }
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
