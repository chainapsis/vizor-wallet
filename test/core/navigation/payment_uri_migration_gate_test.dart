@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

// Why the drain policy evaluates `sendGatedByMigration` only for an unlocked
// wallet.
//
// `migrationSendGateProvider` is `cta == resume && ironwoodBalance <= 0`, and
// locking the wallet resets `syncProvider` to a bare `SyncState()`
// (`SyncNotifier.clearSensitiveStateForLock`). That zeroes the balance half of
// the predicate unconditionally, so the whole gate collapses to "does the
// cached Home CTA still say resume" — and
// `ironwoodHomeMigrationPresentationProvider` is built to keep the last visible
// CTA across exactly this kind of gap.
//
// These tests pin what the gate answers on both sides of a lock, so the drain
// row's position in `decidePaymentUriDrain` is a decision about a measured
// value rather than an assumed one.
void main() {
  test('a resume migration reads gated while the wallet is unlocked', () async {
    final harness = await _MigrationGateHarness.create();

    expect(harness.gate, isTrue);
  });

  test(
    'the gate still reads gated after a lock zeroes the sync state',
    () async {
      final harness = await _MigrationGateHarness.create();
      expect(harness.gate, isTrue);

      harness.lock();

      expect(
        harness.cta.mode,
        IronwoodHomeMigrationCtaMode.resume,
        reason:
            'the Home presentation keeps the last visible CTA across a sync '
            'gap, and a lock is one',
      );
      expect(
        harness.gate,
        isTrue,
        reason:
            'a locked wallet still reads gated, on the strength of an '
            'Ironwood balance the lock itself zeroed — so the drain policy '
            'must not drop a parked link on this row before unlock',
      );
    },
  );

  test('an unlocked wallet with a spendable Ironwood note is not '
      'gated', () async {
    final harness = await _MigrationGateHarness.create(
      ironwoodBalance: BigInt.from(100000000),
    );

    expect(harness.gate, isFalse);
  });
}

/// A mobile wallet mid-migration, with a lock that reproduces what
/// `clearSensitiveStateForLock` leaves behind.
class _MigrationGateHarness {
  _MigrationGateHarness._(this._container);

  static Future<_MigrationGateHarness> create({BigInt? ironwoodBalance}) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        accountProvider.overrideWith(_FakeAccountNotifier.new),
        syncProvider.overrideWith(
          () =>
              FakeSyncNotifier(_migratingSync(ironwoodBalance ?? BigInt.zero)),
        ),
        // Ironwood is live on this chain; nothing about a lock changes that.
        chainUpgradeStatusProvider.overrideWith(
          _IronwoodActiveChainUpgrade.new,
        ),
        // The one async input, stubbed with the two values the real loader
        // produces for these two sync states: a run in progress while the
        // account has scoped data, and `unavailable` once it does not
        // (`_loadIronwoodPostMigrationState` returns that for
        // `!inputs.hasAccountScopedData`, which is what a lock leaves).
        ironwoodPostMigrationStateProvider.overrideWith(
          (ref) => ref.watch(_postMigrationStateProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Both async inputs are resolved before anything is read: an unresolved
    // `chainUpgradeStatusProvider` reads as "Ironwood not active", and an
    // unresolved `syncProvider` answers from the empty `SyncState()` fallback,
    // so either one would decide these cases for the wrong reason.
    await container.read(chainUpgradeStatusProvider.future);
    await container.read(syncProvider.future);
    final harness = _MigrationGateHarness._(container);
    // Reading the presentation while unlocked is what fills its cache — the
    // same thing Home does every build.
    expect(harness.cta.mode, IronwoodHomeMigrationCtaMode.resume);
    return harness;
  }

  final ProviderContainer _container;

  bool get gate => _container.read(migrationSendGateProvider);

  IronwoodHomeMigrationCtaState get cta =>
      _container.read(ironwoodHomeMigrationPresentationProvider);

  /// What locking the wallet does to everything this gate reads: the sync
  /// state is wiped, and the post-migration load can no longer answer.
  void lock() {
    (_container.read(syncProvider.notifier) as FakeSyncNotifier).emit(
      SyncState(),
    );
    _container
        .read(_postMigrationStateProvider.notifier)
        .set(const IronwoodPostMigrationState.unavailable());
  }
}

class _PostMigrationStateNotifier extends Notifier<IronwoodPostMigrationState> {
  @override
  IronwoodPostMigrationState build() => IronwoodPostMigrationState.inProgress(
    network: 'main',
    accountUuid: 'account-1',
    status: _status(),
  );

  void set(IronwoodPostMigrationState next) => state = next;
}

final _postMigrationStateProvider =
    NotifierProvider<_PostMigrationStateNotifier, IronwoodPostMigrationState>(
      _PostMigrationStateNotifier.new,
    );

class _IronwoodActiveChainUpgrade extends ChainUpgradeStatusNotifier {
  @override
  Future<ChainUpgradeStatusState> build() async =>
      ChainUpgradeStatusState.cachedActive(defaultRpcEndpointConfig('main'));
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1migrationgate',
  );
}

/// Mid-migration: the Orchard funds are already out, the Ironwood note is not
/// spendable yet.
SyncState _migratingSync(BigInt ironwoodBalance) => SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
  isSyncComplete: true,
  chainTipHeight: 3000000,
  scannedHeight: 3000000,
  ironwoodBalance: ironwoodBalance,
);

rust_sync.MigrationStatus _status() => rust_sync.MigrationStatus(
  phase: kIronwoodMigrationBroadcastScheduledPhase,
  activeRunId: 'run-1',
  targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
  preparedNoteCount: 1,
  denominationConfirmationCount: 3,
  denominationConfirmationTarget: 3,
  denominationSplitCompletedCount: 1,
  denominationSplitTotalCount: 1,
  pendingTxCount: 1,
  broadcastedTxCount: 1,
  confirmedTxCount: 0,
  totalCount: 1,
  signedChildPcztCount: 0,
  pendingSplitStageCount: 0,
  canAbandon: false,
  signingBatchLimit: 50,
  scheduleMeanDelayBlocks: 144,
  scheduleMaxDelayBlocks: 576,
  scheduledBroadcasts: const [],
  parts: const [],
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1migrationgate',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
