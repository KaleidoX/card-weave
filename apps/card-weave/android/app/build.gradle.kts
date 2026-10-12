plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    buildFeatures { buildConfig = true }
    namespace = "io.cardweave.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        buildConfigField("boolean", "SOFTWARE_RENDERING", (System.getenv("CARDWEAVE_SOFTWARE_RENDERING") == "1").toString())
        applicationId = if (System.getenv("CARDWEAVE_ACCEPTANCE") == "1") "io.cardweave.app.acceptance" else "io.cardweave.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        val targetAbi = System.getenv("CARDWEAVE_ABI") ?: "x86_64"
        require(targetAbi in setOf("x86_64", "arm64-v8a")) { "Unsupported CARDWEAVE_ABI" }
        ndk {
            abiFilters.clear()
            abiFilters.add(targetAbi)
        }
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
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

val rustlsLock = file("../../rust/Cargo.lock").readText()
val rustlsAndroidVersion = Regex("name = \"rustls-platform-verifier-android\"\\s+version = \"([^\"]+)\"")
    .find(rustlsLock)?.groupValues?.get(1)
    ?: error("rustls-platform-verifier-android missing from Cargo.lock")
repositories {
    maven {
        url = uri(System.getenv("CARDWEAVE_RUSTLS_MAVEN") ?: "https://raw.githubusercontent.com/rustls/rustls-platform-verifier/maven-archive/android-release-support/maven")
        content { includeGroup("org.rustls") }
    }
}
dependencies {
    implementation("org.rustls:rustls-platform-verifier:$rustlsAndroidVersion")
}
