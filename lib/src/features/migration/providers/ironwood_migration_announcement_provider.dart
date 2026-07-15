import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/chain_upgrade_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

const kIronwoodMigrationReadyPhase = 'ready_to_prepare';
const kIronwoodMigrationReleaseNotesUrl =
    'https://tachyon.z.cash/blog/auditing-orchard-supply/';

String ironwoodMigrationAnnouncementSeenStorageKey({
  required String network,
  required String accountUuid,
}) {
  return 'zcash_ironwood_migration_announcement_seen_${network}_$accountUuid';
}

abstract class IronwoodMigrationAnnouncementStore {
  Future<bool> isSeen({required String network, required String accountUuid});

  Future<void> markSeen({required String network, required String accountUuid});
}

class SharedPreferencesIronwoodMigrationAnnouncementStore
    implements IronwoodMigrationAnnouncementStore {
  const SharedPreferencesIronwoodMigrationAnnouncementStore();

  @override
  Future<bool> isSeen({
    required String network,
    required String accountUuid,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(
          ironwoodMigrationAnnouncementSeenStorageKey(
            network: network,
            accountUuid: accountUuid,
          ),
        ) ??
        false;
  }

  @override
  Future<void> markSeen({
    required String network,
    required String accountUuid,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      ironwoodMigrationAnnouncementSeenStorageKey(
        network: network,
        accountUuid: accountUuid,
      ),
      true,
    );
  }
}

typedef OrchardMigrationStatusGetter =
    Future<rust_sync.MigrationStatus> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });

typedef WalletDbPathGetter = Future<String> Function();

class IronwoodMigrationAnnouncementState {
  const IronwoodMigrationAnnouncementState._({
    required this.visible,
    this.network,
    this.accountUuid,
    this.status,
  });

  const IronwoodMigrationAnnouncementState.hidden() : this._(visible: false);

  const IronwoodMigrationAnnouncementState.visible({
    required String network,
    required String accountUuid,
    required rust_sync.MigrationStatus status,
  }) : this._(
         visible: true,
         network: network,
         accountUuid: accountUuid,
         status: status,
       );

  final bool visible;
  final String? network;
  final String? accountUuid;
  final rust_sync.MigrationStatus? status;
}

final ironwoodMigrationAnnouncementStoreProvider =
    Provider<IronwoodMigrationAnnouncementStore>(
      (_) => const SharedPreferencesIronwoodMigrationAnnouncementStore(),
    );

final orchardMigrationStatusGetterProvider =
    Provider<OrchardMigrationStatusGetter>(
      (_) => rust_sync.getOrchardMigrationStatus,
    );

final walletDbPathGetterProvider = Provider<WalletDbPathGetter>(
  (_) => getWalletDbPath,
);

final ironwoodMigrationAnnouncementProvider =
    FutureProvider<IronwoodMigrationAnnouncementState>((ref) async {
      final chainStatus = ref.watch(chainUpgradeStatusProvider).value;
      if (chainStatus?.ironwoodActiveAtTip != true) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      final accountState = ref.watch(accountProvider).value;
      final accountUuid = accountState?.activeAccountUuid;
      if (accountUuid == null) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      final sync = (ref.watch(syncProvider).value ?? SyncState())
          .scopedToAccount(accountUuid);
      if (!sync.hasAccountScopedData ||
          sync.isSyncing ||
          sync.isBackgroundMode ||
          sync.failure != null ||
          sync.error != null) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      if (sync.orchardBalance <= BigInt.zero &&
          sync.orchardPendingBalance <= BigInt.zero) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      final endpoint = ref.watch(rpcEndpointProvider);
      final network = endpoint.networkName;
      final store = ref.watch(ironwoodMigrationAnnouncementStoreProvider);
      if (await store.isSeen(network: network, accountUuid: accountUuid)) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      final dbPath = await ref.watch(walletDbPathGetterProvider)();
      final status = await ref.watch(orchardMigrationStatusGetterProvider)(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      );
      if (status.phase != kIronwoodMigrationReadyPhase) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      return IronwoodMigrationAnnouncementState.visible(
        network: network,
        accountUuid: accountUuid,
        status: status,
      );
    });
