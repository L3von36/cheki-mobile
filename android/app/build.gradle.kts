import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: reads android/key.properties (never committed).
// When the file is absent (CI without secrets, local dev), release builds
// fall back to debug signing so `flutter build apk --release` always works.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "app.mahtem.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "app.mahtem.mobile"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Ship ARM only. 100% of the phones Mahtem serves run armeabi-v7a or
        // arm64-v8a; x86_64 exists for emulators and rare Intel devices and
        // was adding ~37 MB to the universal APK. Each ABI carries its own
        // copy of the Flutter engine + ML Kit OCR + barcode native libs.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    // Deflate native libraries inside the APK instead of storing them raw.
    // AGP's default keeps .so uncompressed so Android can mmap them straight
    // from the APK — that made the download (what users pay mobile data for)
    // ~2x bigger. With legacy packaging the installer extracts libs to disk
    // once, so installed size ends up roughly the same as before while the
    // DOWNLOAD drops by more than half.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Shrink the Java/Kotlin side with R8 and drop unused resources.
            // (Dart code is already AOT-compiled; the big wins come from the
            // ARM-only ABI filter + legacy packaging above.)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
