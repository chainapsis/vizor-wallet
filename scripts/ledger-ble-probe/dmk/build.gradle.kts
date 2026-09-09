plugins {
    id("com.android.application") version "8.11.1"
    id("org.jetbrains.kotlin.android") version "2.2.20"
}
android {
    namespace = "app.vizor.dmkprobe"
    compileSdk = 36
    defaultConfig {
        applicationId = "app.vizor.dmkprobe"
        minSdk = 30
        targetSdk = 32
        versionCode = 1
        versionName = "1"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    sourceSets["main"].java.srcDir(layout.buildDirectory.dir("handler-source"))
    sourceSets["test"].java.srcDir("../../../android/app/src/test/kotlin")
}
val copyHandler by tasks.registering(Copy::class) {
    from("../../../android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt")
    into(layout.buildDirectory.dir("handler-source/com/keplr/vizor"))
}
tasks.named("preBuild") { dependsOn(copyHandler) }
dependencies {
    implementation("androidx.core:core:1.16.0")
    implementation("io.github.ledgerhq:device-management-kit:0.0.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.18.0")
}
