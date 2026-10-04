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

        // NOTE on ABIs: AGP forbids ndk.abiFilters alongside the splits
        // configuration the Flutter gradle plugin manages. The universal APK
        // is narrowed to ARM via `--target-platform=android-arm,android-arm64`
        // on the build command (see .github/workflows/release.yml). x86_64
        // only exists for emulators/rare Intel devices and was adding ~37 MB
        // to the universal APK — every real phone runs armeabi-v7a/arm64.
    }

    // Deflate native libraries inside the APK instead of storing them raw.
    // AGP's default keeps .so uncompressed so Android can mmap them straight
    // from the APK — that made the download (what users pay mobile data for)
    // ~2x bigger. With legacy packaging the installer extracts libs to disk
    // once, so installed size ends up roughly the same as before while the
    // DOWNLOAD drops by more than half.
    //
    // Also drop third-party x86_64 libs (ML Kit OCR pipeline, barcode
    // engine, Sentry) at packaging time — Flutter's own x86_64 binaries
    // already respect --target-platform, but bundled AARs otherwise still
    // ship an x86_64 copy of every lib (~9 MB of dead weight, since an
    // x86_64 device could never run the app without its engine anyway).
    packaging {
        jniLibs {
            useLegacyPackaging = true
            excludes += setOf("lib/x86_64/**")
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
