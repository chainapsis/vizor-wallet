import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'wallet reset clears migration metadata and keeps install prefs',
    () async {
      SharedPreferences.setMockInitialValues({
        ironwoodMigrationAnnouncementSeenStorageKey(
          network: 'main',
          accountUuid: 'old-account',
        ): true,
        ironwoodMigrationCompletionSeenStorageKey(
          network: 'test',
          accountUuid: 'orphan-account',
          completionId: 'completion-1',
        ): true,
        'unrelated_install_preference': 'keep',
      });
      addTearDown(() => SharedPreferences.setMockInitialValues({}));

      await clearIronwoodMigrationPreferencesForReset();

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getBool(
          ironwoodMigrationAnnouncementSeenStorageKey(
            network: 'main',
            accountUuid: 'old-account',
          ),
        ),
        isNull,
      );
      expect(
        preferences.getBool(
          ironwoodMigrationCompletionSeenStorageKey(
            network: 'test',
            accountUuid: 'orphan-account',
            completionId: 'completion-1',
          ),
        ),
        isNull,
      );
      expect(preferences.getString('unrelated_install_preference'), 'keep');
    },
  );
}
