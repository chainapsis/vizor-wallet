import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/windows_update_prompt_policy.dart';

void main() {
  test('account setup and wallet writes suppress updates and restart', () {
    for (final route in [
      '/welcome',
      '/add-account',
      '/gift',
      '/gift/set-password',
      '/gift/passcode',
      '/gift/customise',
      '/setup/backup',
      '/setup/education/intro',
      '/setup/education/address-types',
      '/setup/education/things-to-know',
      '/onboarding/customise-account',
      '/onboarding/ledger/birthday',
      '/import/method',
      '/import/hardware',
      '/import-keystone/set-password',
      '/lost-password',
      '/send/review',
      '/settings/secret-passphrase',
      '/settings/viewing-key',
      '/settings/change-password',
      '/settings/uninstall',
    ]) {
      expect(
        canShowWindowsUpdatePromptAtLocation(route),
        isFalse,
        reason: route,
      );
    }
  });

  test('unlock and ordinary screens retain update availability', () {
    for (final route in [
      '/unlock',
      '/home',
      '/activity',
      '/settings',
      '/settings/endpoint',
      '/gift-history',
      '/setup/backup-history',
    ]) {
      expect(
        canShowWindowsUpdatePromptAtLocation(route),
        isTrue,
        reason: route,
      );
    }
  });
}
