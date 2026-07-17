import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/chain_upgrade_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/ironwood_migration_phases.dart';

export '../models/ironwood_migration_phases.dart';

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

class IronwoodMigrationStatusRequest {
  const IronwoodMigrationStatusRequest({
    required this.network,
    required this.accountUuid,
  });

  final String network;
  final String accountUuid;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is IronwoodMigrationStatusRequest &&
            other.network == network &&
            other.accountUuid == accountUuid;
  }

  @override
  int get hashCode => Object.hash(network, accountUuid);
}

class IronwoodMigrationInputs {
  const IronwoodMigrationInputs({
    required this.ironwoodActiveAtTip,
    required this.network,
    required this.accountUuid,
    required this.accountName,
    required this.profilePictureId,
    required this.hasAccountScopedData,
    required this.isSyncing,
    required this.isBackgroundMode,
    required this.isSyncComplete,
    required this.hasSyncFailure,
    required this.orchardBalance,
    required this.orchardPendingBalance,
    required this.ironwoodBalance,
    required this.ironwoodPendingBalance,
  });

  final bool ironwoodActiveAtTip;
  final String network;
  final String? accountUuid;
  final String accountName;
  final String profilePictureId;
  final bool hasAccountScopedData;
  final bool isSyncing;
  final bool isBackgroundMode;
  final bool isSyncComplete;
  final bool hasSyncFailure;
  final BigInt orchardBalance;
  final BigInt orchardPendingBalance;
  final BigInt ironwoodBalance;
  final BigInt ironwoodPendingBalance;

  bool get hasOrchardFunds =>
      orchardBalance > BigInt.zero || orchardPendingBalance > BigInt.zero;

  bool get hasIronwoodSpendableFunds => ironwoodBalance > BigInt.zero;

  bool get hasIronwoodPendingFunds => ironwoodPendingBalance > BigInt.zero;

  IronwoodMigrationStatusRequest? get statusRequest {
    final uuid = accountUuid;
    if (uuid == null) return null;
    return IronwoodMigrationStatusRequest(network: network, accountUuid: uuid);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is IronwoodMigrationInputs &&
            other.ironwoodActiveAtTip == ironwoodActiveAtTip &&
            other.network == network &&
            other.accountUuid == accountUuid &&
            other.accountName == accountName &&
            other.profilePictureId == profilePictureId &&
            other.hasAccountScopedData == hasAccountScopedData &&
            other.isSyncing == isSyncing &&
            other.isBackgroundMode == isBackgroundMode &&
            other.isSyncComplete == isSyncComplete &&
            other.hasSyncFailure == hasSyncFailure &&
            other.orchardBalance == orchardBalance &&
            other.orchardPendingBalance == orchardPendingBalance &&
            other.ironwoodBalance == ironwoodBalance &&
            other.ironwoodPendingBalance == ironwoodPendingBalance;
  }

  @override
  int get hashCode => Object.hash(
    ironwoodActiveAtTip,
    network,
    accountUuid,
    accountName,
    profilePictureId,
    hasAccountScopedData,
    isSyncing,
    isBackgroundMode,
    isSyncComplete,
    hasSyncFailure,
    orchardBalance,
    orchardPendingBalance,
    ironwoodBalance,
    ironwoodPendingBalance,
  );
}

class _IronwoodMigrationAccountInputs {
  const _IronwoodMigrationAccountInputs({
    required this.accountUuid,
    required this.accountName,
    required this.profilePictureId,
  });

  final String? accountUuid;
  final String accountName;
  final String profilePictureId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _IronwoodMigrationAccountInputs &&
            other.accountUuid == accountUuid &&
            other.accountName == accountName &&
            other.profilePictureId == profilePictureId;
  }

  @override
  int get hashCode => Object.hash(accountUuid, accountName, profilePictureId);
}

class _IronwoodMigrationSyncInputs {
  const _IronwoodMigrationSyncInputs({
    required this.hasAccountScopedData,
    required this.isSyncing,
    required this.isBackgroundMode,
    required this.isSyncComplete,
    required this.hasSyncFailure,
    required this.orchardBalance,
    required this.orchardPendingBalance,
    required this.ironwoodBalance,
    required this.ironwoodPendingBalance,
  });

  final bool hasAccountScopedData;
  final bool isSyncing;
  final bool isBackgroundMode;
  final bool isSyncComplete;
  final bool hasSyncFailure;
  final BigInt orchardBalance;
  final BigInt orchardPendingBalance;
  final BigInt ironwoodBalance;
  final BigInt ironwoodPendingBalance;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _IronwoodMigrationSyncInputs &&
            other.hasAccountScopedData == hasAccountScopedData &&
            other.isSyncing == isSyncing &&
            other.isBackgroundMode == isBackgroundMode &&
            other.isSyncComplete == isSyncComplete &&
            other.hasSyncFailure == hasSyncFailure &&
            other.orchardBalance == orchardBalance &&
            other.orchardPendingBalance == orchardPendingBalance &&
            other.ironwoodBalance == ironwoodBalance &&
            other.ironwoodPendingBalance == ironwoodPendingBalance;
  }

  @override
  int get hashCode => Object.hash(
    hasAccountScopedData,
    isSyncing,
    isBackgroundMode,
    isSyncComplete,
    hasSyncFailure,
    orchardBalance,
    orchardPendingBalance,
    ironwoodBalance,
    ironwoodPendingBalance,
  );
}

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

enum IronwoodHomeMigrationCtaMode { hidden, start, resume }

class IronwoodHomeMigrationCtaState {
  const IronwoodHomeMigrationCtaState._({
    required this.mode,
    this.network,
    this.accountUuid,
    this.status,
  });

  const IronwoodHomeMigrationCtaState.hidden()
    : this._(mode: IronwoodHomeMigrationCtaMode.hidden);

  const IronwoodHomeMigrationCtaState.start({
    required String network,
    required String accountUuid,
    rust_sync.MigrationStatus? status,
  }) : this._(
         mode: IronwoodHomeMigrationCtaMode.start,
         network: network,
         accountUuid: accountUuid,
         status: status,
       );

  const IronwoodHomeMigrationCtaState.resume({
    required String network,
    required String accountUuid,
    required rust_sync.MigrationStatus status,
  }) : this._(
         mode: IronwoodHomeMigrationCtaMode.resume,
         network: network,
         accountUuid: accountUuid,
         status: status,
       );

  final IronwoodHomeMigrationCtaMode mode;
  final String? network;
  final String? accountUuid;
  final rust_sync.MigrationStatus? status;

  bool get visible => mode != IronwoodHomeMigrationCtaMode.hidden;

  String get buttonLabel => switch (mode) {
    IronwoodHomeMigrationCtaMode.start => 'Migrate to Ironwood Pool',
    IronwoodHomeMigrationCtaMode.resume => 'Continue migration',
    IronwoodHomeMigrationCtaMode.hidden => '',
  };
}

enum IronwoodPostMigrationMode {
  inactive,
  unavailable,
  notNeeded,
  required,
  inProgress,
  pendingIronwoodSpendability,
  complete,
}

class IronwoodPostMigrationState {
  const IronwoodPostMigrationState._({
    required this.mode,
    this.network,
    this.accountUuid,
    this.status,
  });

  const IronwoodPostMigrationState.inactive()
    : this._(mode: IronwoodPostMigrationMode.inactive);

  const IronwoodPostMigrationState.unavailable()
    : this._(mode: IronwoodPostMigrationMode.unavailable);

  const IronwoodPostMigrationState.notNeeded({
    required String network,
    required String accountUuid,
    rust_sync.MigrationStatus? status,
  }) : this._(
         mode: IronwoodPostMigrationMode.notNeeded,
         network: network,
         accountUuid: accountUuid,
         status: status,
       );

  const IronwoodPostMigrationState.required({
    required String network,
    required String accountUuid,
    rust_sync.MigrationStatus? status,
  }) : this._(
         mode: IronwoodPostMigrationMode.required,
         network: network,
         accountUuid: accountUuid,
         status: status,
       );

  const IronwoodPostMigrationState.inProgress({
    required String network,
    required String accountUuid,
    required rust_sync.MigrationStatus status,
  }) : this._(
         mode: IronwoodPostMigrationMode.inProgress,
         network: network,
         accountUuid: accountUuid,
         status: status,
       );

  const IronwoodPostMigrationState.pendingIronwoodSpendability({
    required String network,
    required String accountUuid,
    rust_sync.MigrationStatus? status,
  }) : this._(
         mode: IronwoodPostMigrationMode.pendingIronwoodSpendability,
         network: network,
         accountUuid: accountUuid,
         status: status,
       );

  const IronwoodPostMigrationState.complete({
    required String network,
    required String accountUuid,
    rust_sync.MigrationStatus? status,
  }) : this._(
         mode: IronwoodPostMigrationMode.complete,
         network: network,
         accountUuid: accountUuid,
         status: status,
       );

  final IronwoodPostMigrationMode mode;
  final String? network;
  final String? accountUuid;
  final rust_sync.MigrationStatus? status;

  bool get locksNavigation =>
      mode == IronwoodPostMigrationMode.required ||
      mode == IronwoodPostMigrationMode.inProgress;
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

final ironwoodMigrationInputsProvider = Provider<IronwoodMigrationInputs>((
  ref,
) {
  final activeAccount = ref.watch(
    accountProvider.select((accountAsync) {
      final accountState = accountAsync.value;
      final activeAccountUuid = accountState?.activeAccountUuid;
      AccountInfo? activeAccount;
      if (activeAccountUuid != null) {
        for (final account in accountState?.accounts ?? const <AccountInfo>[]) {
          if (account.uuid == activeAccountUuid) {
            activeAccount = account;
            break;
          }
        }
      }

      return _IronwoodMigrationAccountInputs(
        accountUuid: activeAccountUuid,
        accountName: activeAccount?.name ?? 'Username',
        profilePictureId:
            activeAccount?.profilePictureId ?? kDefaultProfilePictureId,
      );
    }),
  );
  final sync = ref.watch(
    syncProvider.select((syncAsync) {
      final scoped = (syncAsync.value ?? SyncState()).scopedToAccount(
        activeAccount.accountUuid,
      );
      return _IronwoodMigrationSyncInputs(
        hasAccountScopedData: scoped.hasAccountScopedData,
        isSyncing: scoped.isSyncing,
        isBackgroundMode: scoped.isBackgroundMode,
        isSyncComplete: scoped.isSyncComplete,
        hasSyncFailure: scoped.failure != null || scoped.error != null,
        orchardBalance: scoped.orchardBalance,
        orchardPendingBalance: scoped.orchardPendingBalance,
        ironwoodBalance: scoped.ironwoodBalance,
        ironwoodPendingBalance: scoped.ironwoodPendingBalance,
      );
    }),
  );
  final ironwoodActiveAtTip = ref.watch(
    chainUpgradeStatusProvider.select(
      (chainAsync) => chainAsync.value?.ironwoodActiveAtTip == true,
    ),
  );
  final network = ref.watch(
    rpcEndpointProvider.select((endpoint) => endpoint.networkName),
  );

  return IronwoodMigrationInputs(
    ironwoodActiveAtTip: ironwoodActiveAtTip,
    network: network,
    accountUuid: activeAccount.accountUuid,
    accountName: activeAccount.accountName,
    profilePictureId: activeAccount.profilePictureId,
    hasAccountScopedData: sync.hasAccountScopedData,
    isSyncing: sync.isSyncing,
    isBackgroundMode: sync.isBackgroundMode,
    isSyncComplete: sync.isSyncComplete,
    hasSyncFailure: sync.hasSyncFailure,
    orchardBalance: sync.orchardBalance,
    orchardPendingBalance: sync.orchardPendingBalance,
    ironwoodBalance: sync.ironwoodBalance,
    ironwoodPendingBalance: sync.ironwoodPendingBalance,
  );
});

final ironwoodMigrationStatusProvider =
    FutureProvider.family<
      rust_sync.MigrationStatus,
      IronwoodMigrationStatusRequest
    >((ref, request) async {
      ref.watch(
        syncProvider.select((syncAsync) {
          final scoped = (syncAsync.value ?? SyncState()).scopedToAccount(
            request.accountUuid,
          );
          return _IronwoodMigrationSyncInputs(
            hasAccountScopedData: scoped.hasAccountScopedData,
            isSyncing: scoped.isSyncing,
            isBackgroundMode: scoped.isBackgroundMode,
            isSyncComplete: scoped.isSyncComplete,
            hasSyncFailure: scoped.failure != null || scoped.error != null,
            orchardBalance: scoped.orchardBalance,
            orchardPendingBalance: scoped.orchardPendingBalance,
            ironwoodBalance: scoped.ironwoodBalance,
            ironwoodPendingBalance: scoped.ironwoodPendingBalance,
          );
        }),
      );
      final dbPath = await ref.watch(walletDbPathGetterProvider)();
      final getStatus = ref.watch(orchardMigrationStatusGetterProvider);
      return getStatus(
        dbPath: dbPath,
        network: request.network,
        accountUuid: request.accountUuid,
      );
    });

final ironwoodPostMigrationStateProvider =
    FutureProvider<IronwoodPostMigrationState>((ref) async {
      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      return _loadIronwoodPostMigrationState(ref, inputs);
    });

final ironwoodMigrationAnnouncementProvider =
    FutureProvider<IronwoodMigrationAnnouncementState>((ref) async {
      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      if (!inputs.ironwoodActiveAtTip) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      final accountUuid = inputs.accountUuid;
      if (accountUuid == null) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      if (!inputs.hasAccountScopedData ||
          inputs.isSyncing ||
          inputs.isBackgroundMode ||
          inputs.hasSyncFailure) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      if (!inputs.hasOrchardFunds) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      final store = ref.watch(ironwoodMigrationAnnouncementStoreProvider);
      if (await store.isSeen(
        network: inputs.network,
        accountUuid: accountUuid,
      )) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      final request = inputs.statusRequest;
      if (request == null) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }
      final status = await ref.watch(
        ironwoodMigrationStatusProvider(request).future,
      );
      if (status.phase != kIronwoodMigrationReadyPhase) {
        return const IronwoodMigrationAnnouncementState.hidden();
      }

      return IronwoodMigrationAnnouncementState.visible(
        network: inputs.network,
        accountUuid: accountUuid,
        status: status,
      );
    });

final ironwoodHomeMigrationCtaProvider =
    FutureProvider<IronwoodHomeMigrationCtaState>((ref) async {
      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      final postMigrationState = await _loadIronwoodPostMigrationState(
        ref,
        inputs,
      );
      return _homeMigrationCtaForPostMigrationState(postMigrationState);
    });

final _ironwoodHomeMigrationPresentationCacheProvider =
    Provider<_IronwoodHomeMigrationPresentationCache>(
      (_) => _IronwoodHomeMigrationPresentationCache(),
    );

/// Stable Home/sidebar presentation state.
///
/// The fresh CTA intentionally hides new migration requirements while sync is
/// running, because a rescan can temporarily make spent Orchard notes appear
/// spendable. The Home UI should not flicker back to the normal balance card
/// after a requirement or active run has already been confirmed, so this
/// provider keeps the last visible CTA for the same network/account until a
/// completed, account-scoped sync state says migration is no longer needed.
final ironwoodHomeMigrationPresentationProvider =
    Provider<IronwoodHomeMigrationCtaState>((ref) {
      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      final postMigrationAsync = ref.watch(ironwoodPostMigrationStateProvider);
      final postMigrationState = postMigrationAsync.value;
      final current = postMigrationState == null
          ? const IronwoodHomeMigrationCtaState.hidden()
          : _homeMigrationCtaForPostMigrationState(postMigrationState);
      final cache = ref.watch(_ironwoodHomeMigrationPresentationCacheProvider);

      if (current.visible && _ctaMatchesInputs(current, inputs)) {
        cache.lastVisible = current;
        return current;
      }

      final cached = cache.lastVisible;
      if (cached != null &&
          _ctaMatchesInputs(cached, inputs) &&
          _shouldPreserveHomeMigrationPresentation(
            inputs,
            postMigrationState,
          )) {
        return cached;
      }

      cache.lastVisible = null;
      return const IronwoodHomeMigrationCtaState.hidden();
    });

final ironwoodMigrationRouteCtaProvider =
    FutureProvider<IronwoodHomeMigrationCtaState>((ref) async {
      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      if (!inputs.ironwoodActiveAtTip) {
        return const IronwoodHomeMigrationCtaState.hidden();
      }

      final accountUuid = inputs.accountUuid;
      if (accountUuid == null) {
        return const IronwoodHomeMigrationCtaState.hidden();
      }

      final request = inputs.statusRequest;
      if (request == null) {
        return const IronwoodHomeMigrationCtaState.hidden();
      }
      final status = await ref.watch(
        ironwoodMigrationStatusProvider(request).future,
      );

      if (status.phase == kIronwoodMigrationCompletePhase) {
        return IronwoodHomeMigrationCtaState.resume(
          network: inputs.network,
          accountUuid: accountUuid,
          status: status,
        );
      }

      if (_shouldResumeIronwoodMigration(status)) {
        return IronwoodHomeMigrationCtaState.resume(
          network: inputs.network,
          accountUuid: accountUuid,
          status: status,
        );
      }

      if (inputs.isSyncing || inputs.isBackgroundMode) {
        return const IronwoodHomeMigrationCtaState.hidden();
      }

      if (inputs.hasAccountScopedData &&
          !inputs.hasSyncFailure &&
          inputs.hasOrchardFunds &&
          _shouldStartIronwoodMigration(status.phase)) {
        return IronwoodHomeMigrationCtaState.start(
          network: inputs.network,
          accountUuid: accountUuid,
          status: status,
        );
      }

      return const IronwoodHomeMigrationCtaState.hidden();
    });

class _IronwoodHomeMigrationPresentationCache {
  IronwoodHomeMigrationCtaState? lastVisible;
}

IronwoodHomeMigrationCtaState _homeMigrationCtaForPostMigrationState(
  IronwoodPostMigrationState postMigrationState,
) {
  final network = postMigrationState.network;
  final accountUuid = postMigrationState.accountUuid;
  if (network == null || accountUuid == null) {
    return const IronwoodHomeMigrationCtaState.hidden();
  }

  if (postMigrationState.mode == IronwoodPostMigrationMode.inProgress) {
    final status = postMigrationState.status;
    if (status == null) {
      return const IronwoodHomeMigrationCtaState.hidden();
    }
    return IronwoodHomeMigrationCtaState.resume(
      network: network,
      accountUuid: accountUuid,
      status: status,
    );
  }

  if (postMigrationState.mode == IronwoodPostMigrationMode.required) {
    return IronwoodHomeMigrationCtaState.start(
      network: network,
      accountUuid: accountUuid,
      status: postMigrationState.status,
    );
  }

  return const IronwoodHomeMigrationCtaState.hidden();
}

bool _ctaMatchesInputs(
  IronwoodHomeMigrationCtaState cta,
  IronwoodMigrationInputs inputs,
) {
  return cta.network == inputs.network && cta.accountUuid == inputs.accountUuid;
}

bool _shouldPreserveHomeMigrationPresentation(
  IronwoodMigrationInputs inputs,
  IronwoodPostMigrationState? postMigrationState,
) {
  if (!inputs.ironwoodActiveAtTip || inputs.accountUuid == null) {
    return false;
  }

  return postMigrationState == null ||
      inputs.isSyncing ||
      inputs.isBackgroundMode ||
      inputs.hasSyncFailure ||
      !inputs.hasAccountScopedData ||
      !inputs.isSyncComplete ||
      postMigrationState.mode == IronwoodPostMigrationMode.unavailable;
}

Future<IronwoodPostMigrationState> _loadIronwoodPostMigrationState(
  Ref ref,
  IronwoodMigrationInputs inputs,
) async {
  if (!inputs.ironwoodActiveAtTip) {
    return const IronwoodPostMigrationState.inactive();
  }

  final accountUuid = inputs.accountUuid;
  if (accountUuid == null) {
    return const IronwoodPostMigrationState.unavailable();
  }

  if (!inputs.hasAccountScopedData || inputs.hasSyncFailure) {
    return const IronwoodPostMigrationState.unavailable();
  }

  rust_sync.MigrationStatus status;
  try {
    final dbPath = await ref.watch(walletDbPathGetterProvider)();
    final getStatus = ref.watch(orchardMigrationStatusGetterProvider);
    status = await getStatus(
      dbPath: dbPath,
      network: inputs.network,
      accountUuid: accountUuid,
    );
  } catch (_) {
    if (inputs.isSyncing || inputs.isBackgroundMode) {
      return const IronwoodPostMigrationState.unavailable();
    }
    return _postMigrationStateForStatusLookupFailure(inputs, accountUuid);
  }

  return _postMigrationStateForStatus(
    inputs: inputs,
    accountUuid: accountUuid,
    status: status,
  );
}

IronwoodPostMigrationState _postMigrationStateForStatusLookupFailure(
  IronwoodMigrationInputs inputs,
  String accountUuid,
) {
  if (inputs.isSyncing || inputs.isBackgroundMode) {
    return const IronwoodPostMigrationState.unavailable();
  }
  if (inputs.hasOrchardFunds) {
    return IronwoodPostMigrationState.required(
      network: inputs.network,
      accountUuid: accountUuid,
    );
  }
  if (inputs.hasIronwoodSpendableFunds) {
    return IronwoodPostMigrationState.complete(
      network: inputs.network,
      accountUuid: accountUuid,
    );
  }
  if (inputs.hasIronwoodPendingFunds) {
    return IronwoodPostMigrationState.pendingIronwoodSpendability(
      network: inputs.network,
      accountUuid: accountUuid,
    );
  }
  return const IronwoodPostMigrationState.unavailable();
}

IronwoodPostMigrationState _postMigrationStateForStatus({
  required IronwoodMigrationInputs inputs,
  required String accountUuid,
  required rust_sync.MigrationStatus status,
}) {
  if (_shouldResumeIronwoodMigration(status)) {
    return IronwoodPostMigrationState.inProgress(
      network: inputs.network,
      accountUuid: accountUuid,
      status: status,
    );
  }

  // A rewind/rescan can temporarily make already-spent Orchard notes look
  // spendable. Only derive a new migration requirement from settled balances.
  if (inputs.isSyncing || inputs.isBackgroundMode) {
    return const IronwoodPostMigrationState.unavailable();
  }

  if (inputs.hasOrchardFunds && _shouldStartIronwoodMigration(status.phase)) {
    return IronwoodPostMigrationState.required(
      network: inputs.network,
      accountUuid: accountUuid,
      status: status,
    );
  }

  if (status.phase == kIronwoodMigrationCompletePhase ||
      inputs.hasIronwoodSpendableFunds) {
    return IronwoodPostMigrationState.complete(
      network: inputs.network,
      accountUuid: accountUuid,
      status: status,
    );
  }

  if (status.phase == kIronwoodMigrationWaitingForIronwoodSpendabilityPhase ||
      inputs.hasIronwoodPendingFunds) {
    return IronwoodPostMigrationState.pendingIronwoodSpendability(
      network: inputs.network,
      accountUuid: accountUuid,
      status: status,
    );
  }

  return IronwoodPostMigrationState.notNeeded(
    network: inputs.network,
    accountUuid: accountUuid,
    status: status,
  );
}

bool _shouldStartIronwoodMigration(String phase) {
  return kIronwoodMigrationStartPhases.contains(phase);
}

bool _shouldResumeIronwoodMigration(rust_sync.MigrationStatus status) {
  if (status.activeRunId != null) return true;
  return isIronwoodMigrationInProgressPhase(status.phase);
}
