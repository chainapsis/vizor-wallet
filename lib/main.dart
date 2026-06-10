import 'app.dart';
import 'src/core/layout/app_form_factor.dart';

export 'app.dart' show log;

Future<void> main() {
  // Mobile builds must pass --dart-define=VIZOR_FORM_FACTOR=mobile so the
  // compile-time design-token selection matches the platform. Fail fast in
  // debug instead of silently rendering the wrong token set.
  assert(debugCheckFormFactorMatchesPlatform());
  return runZcashWalletApp();
}
