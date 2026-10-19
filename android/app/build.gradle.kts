import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play yükleme anahtarı depo dışında durur (bkz. store/google-play/listing_tr_en.md).
// Yol SUTVEGOL_ANDROID_CREDENTIALS ile değiştirilebilir. Dosya yoksa release derlemesi
// debug anahtarıyla imzalanır (yalnız `flutter run --release` için; Play'e yüklenemez).
val uploadCredentials = Properties().apply {
    val path = System.getenv("SUTVEGOL_ANDROID_CREDENTIALS")
        ?: "${System.getProperty("user.home")}/.android/sutvegol-release/credentials.properties"
    file(path).takeIf { it.isFile }?.inputStream()?.use { load(it) }
}

android {
    namespace = "com.globalmedia.sut_ve_gol"
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
        applicationId = "com.globalmedia.sut_ve_gol"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob uygulama kimliği (Android). Reklam birimleri lib/services/ad_service.dart →
        // AdUnits: release'de gerçek, debug ve --dart-define=ADMOB_TEST=true derlemelerinde test.
        manifestPlaceholders["admobAppId"] = System.getenv("ADMOB_APP_ID")
            ?: "ca-app-pub-5952420054302125~9450721786"
    }

    signingConfigs {
        if (uploadCredentials.getProperty("keystore") != null) {
            create("upload") {
                storeFile = file(uploadCredentials.getProperty("keystore"))
                storePassword = uploadCredentials.getProperty("store_password")
                keyAlias = uploadCredentials.getProperty("alias")
                keyPassword = uploadCredentials.getProperty("key_password")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
