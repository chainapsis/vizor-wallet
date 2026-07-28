import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/ironwood_migration_privacy_lock_config.dart';

void main() {
  test('production builds always enable the migration privacy lock', () {
    expect(
      resolveIronwoodMigrationPrivacyLockEnabled(
        debugMode: false,
        debugFlagEnabled: false,
      ),
      isTrue,
    );
  });

  test('debug builds require the explicit migration privacy-lock flag', () {
    expect(
      resolveIronwoodMigrationPrivacyLockEnabled(
        debugMode: true,
        debugFlagEnabled: false,
      ),
      isFalse,
    );
    expect(
      resolveIronwoodMigrationPrivacyLockEnabled(
        debugMode: true,
        debugFlagEnabled: true,
      ),
      isTrue,
    );
  });
}
