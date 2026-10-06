/// Google Play integrations are available by default. Direct APK and F-Droid
/// builds explicitly opt out with --dart-define=VIZOR_DEGOOGLED=true.
/// Android Gradle reads the same define to exclude the Google Play review SDK.
const kVizorDegoogled = bool.fromEnvironment('VIZOR_DEGOOGLED');
