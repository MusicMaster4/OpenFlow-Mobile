plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jubar.voxora"
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
        applicationId = "com.jubar.voxora"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val updateChannel = providers.gradleProperty("openflowChannel").orNull ?: "stable"
        require(updateChannel == "stable" || updateChannel == "testing") {
            "openflowChannel must be stable or testing"
        }
        buildConfigField("String", "UPDATE_CHANNEL", "\"$updateChannel\"")
    }

    val releaseKeystore = System.getenv("OPENFLOW_ANDROID_KEYSTORE")
    val releaseStorePassword = System.getenv("OPENFLOW_ANDROID_STORE_PASSWORD")
    val releaseKeyAlias = System.getenv("OPENFLOW_ANDROID_KEY_ALIAS")
    val releaseKeyPassword = System.getenv("OPENFLOW_ANDROID_KEY_PASSWORD")
    val releaseSigning = if (
        releaseKeystore != null && releaseStorePassword != null &&
        releaseKeyAlias != null && releaseKeyPassword != null
    ) {
        signingConfigs.create("openflowRelease") {
            storeFile = file(releaseKeystore)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    } else null

    buildTypes {
        release {
            // Local release builds remain installable for development. CI requires
            // one persistent keystore so official upgrades keep the app's data.
            signingConfig = releaseSigning ?: signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        buildConfig = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
}
