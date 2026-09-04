plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val androidKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
val androidKeystorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val androidKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
val androidKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val allowUnsignedAndroidRelease =
    System.getenv("ANDROID_ALLOW_UNSIGNED_RELEASE") == "true"
val hasAndroidReleaseSigning = listOf(
    androidKeystorePath,
    androidKeystorePassword,
    androidKeyAlias,
    androidKeyPassword,
).all { !it.isNullOrBlank() }
val hasAnyAndroidReleaseSigning = listOf(
    androidKeystorePath,
    androidKeystorePassword,
    androidKeyAlias,
    androidKeyPassword,
).any { !it.isNullOrBlank() }

if (hasAnyAndroidReleaseSigning && !hasAndroidReleaseSigning) {
    throw GradleException(
        "Android release signing is only partially configured. Set all of " +
            "ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, " +
            "and ANDROID_KEY_PASSWORD, or unset all four."
    )
}

if (
    allowUnsignedAndroidRelease &&
    System.getenv("ANDROID_REQUIRE_RELEASE_SIGNING") == "true"
) {
    throw GradleException(
        "ANDROID_ALLOW_UNSIGNED_RELEASE and ANDROID_REQUIRE_RELEASE_SIGNING " +
            "cannot both be true."
    )
}

android {
    namespace = "com.keplr.vizor"
    // Keep the Android toolchain explicit so upstream and F-Droid builds do
    // not silently diverge when Flutter changes its defaults.
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = "28.2.13676358"

    dependenciesInfo {
        // APK channels cannot use the Play-encrypted dependency block. Keep
        // the default bundle behavior so Play uploads retain SDK insights.
        includeInApk = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.keplr.vizor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (hasAndroidReleaseSigning) {
            create("release") {
                storeFile = file(androidKeystorePath!!)
                storePassword = androidKeystorePassword
                keyAlias = androidKeyAlias
                keyPassword = androidKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasAndroidReleaseSigning) {
                signingConfigs.getByName("release")
            } else if (allowUnsignedAndroidRelease) {
                // F-Droid builds an unsigned APK, verifies it against the
                // upstream-signed APK, and publishes the upstream signature.
                null
            } else {
                if (
                    System.getenv("CI") == "true" ||
                    System.getenv("ANDROID_REQUIRE_RELEASE_SIGNING") == "true"
                ) {
                    throw GradleException(
                        "Android release signing requires ANDROID_KEYSTORE_PATH, " +
                            "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD."
                    )
                }
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Biometric passcode escrow (BiometricPrompt + Keystore-bound key).
    implementation("androidx.biometric:biometric:1.1.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.2.0")
}
