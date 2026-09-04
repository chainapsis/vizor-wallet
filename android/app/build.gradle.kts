import java.net.URI
import java.util.Base64

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
// The deeplink origin has exactly one knob, and it is Dart's:
// `--dart-define=VIZOR_DEEPLINK_BASE_URL`. Flutter forwards every dart-define
// to Gradle as `-Pdart-defines=<base64("KEY=VALUE")>,...`, so decoding that
// property here derives the manifest placeholder and BuildConfig host from the
// same string `VizorDeepLink` compiles in. A second Gradle-only property or
// env var would let the two drift, which is why there is no longer one.
// (iOS keeps its own VIZOR_DEEPLINK_HOST in the Flutter xcconfigs.)
val dartDefines: Map<String, String> = providers.gradleProperty("dart-defines")
    .orNull
    ?.split(",")
    ?.mapNotNull { encoded ->
        val entry = encoded.trim()
        if (entry.isEmpty()) return@mapNotNull null
        val decoded = runCatching {
            String(Base64.getDecoder().decode(entry), Charsets.UTF_8)
        }.getOrNull() ?: return@mapNotNull null
        val separator = decoded.indexOf('=')
        if (separator <= 0) {
            null
        } else {
            decoded.substring(0, separator) to decoded.substring(separator + 1)
        }
    }
    ?.toMap()
    .orEmpty()

val defaultVizorDeeplinkBaseUrl = "https://link.vizor.cash"
val vizorDeeplinkBaseUrl = (
    dartDefines["VIZOR_DEEPLINK_BASE_URL"] ?: defaultVizorDeeplinkBaseUrl
    ).trim()
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

    buildFeatures {
        buildConfig = true
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
