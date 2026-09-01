import java.net.URI

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
val defaultVizorDeeplinkBaseUrl = "https://link.vizor.cash"
val vizorDeeplinkBaseUrl = providers.gradleProperty("VIZOR_DEEPLINK_BASE_URL")
    .orElse(providers.environmentVariable("VIZOR_DEEPLINK_BASE_URL"))
    .getOrElse(defaultVizorDeeplinkBaseUrl)
    .trim()
val vizorDeeplinkUri = URI(vizorDeeplinkBaseUrl)
require(
    vizorDeeplinkUri.scheme.equals("https", ignoreCase = true) &&
        !vizorDeeplinkUri.host.isNullOrBlank() &&
        vizorDeeplinkUri.rawUserInfo == null &&
        vizorDeeplinkUri.port == -1 &&
        (vizorDeeplinkUri.rawPath.isNullOrEmpty() || vizorDeeplinkUri.rawPath == "/") &&
        vizorDeeplinkUri.rawQuery == null &&
        vizorDeeplinkUri.rawFragment == null
) {
    "VIZOR_DEEPLINK_BASE_URL must be an HTTPS origin without a path, query, fragment, or port."
}
val vizorDeeplinkHost = vizorDeeplinkUri.host.lowercase()
val hasAndroidReleaseSigning = listOf(
    androidKeystorePath,
    androidKeystorePassword,
    androidKeyAlias,
    androidKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.keplr.vizor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.keplr.vizor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["vizorDeeplinkHost"] = vizorDeeplinkHost
        buildConfigField("String", "VIZOR_DEEPLINK_HOST", "\"$vizorDeeplinkHost\"")
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
