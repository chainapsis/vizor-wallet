import 'package:shared_preferences/shared_preferences.dart';

const _announcementSeenPrefix = 'zcash_ironwood_migration_announcement_seen_';
const _completionSeenPrefix = 'zcash_ironwood_migration_completion_seen_';

String ironwoodMigrationAnnouncementSeenStorageKey({
  required String network,
  required String accountUuid,
}) {
  return '$_announcementSeenPrefix${network}_$accountUuid';
}

String ironwoodMigrationCompletionSeenStorageKey({
  required String network,
  required String accountUuid,
  required String completionId,
}) {
  return '$_completionSeenPrefix${network}_${accountUuid}_$completionId';
}

/// Deletes wallet/account-scoped migration presentation metadata.
///
/// These records intentionally live in SharedPreferences rather than secure
/// storage, so AppSecureStore.deleteAll() cannot remove them. Reset clears the
/// complete namespaces, including records left by accounts no longer listed in
/// the current wallet. Install-level preferences are not affected.
Future<void> clearIronwoodMigrationPreferencesForReset({
  Future<SharedPreferences> Function() openPreferences =
      SharedPreferences.getInstance,
}) async {
  final preferences = await openPreferences();
  final keys = preferences.getKeys().where(
    (key) =>
        key.startsWith(_announcementSeenPrefix) ||
        key.startsWith(_completionSeenPrefix),
  );
  for (final key in keys.toList(growable: false)) {
    await preferences.remove(key);
  }
}
