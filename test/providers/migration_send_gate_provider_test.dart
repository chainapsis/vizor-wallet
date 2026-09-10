import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../fakes/fake_sync_notifier.dart';

/// The gate is the product's send gate, and only mobile Home has one — see the
/// doc comment on [migrationSendGateProvider]. So the expected "gated" answer
/// is lane-dependent: true in the mobile lane, false in the desktop lane.
/// Everything that makes the gate *not* fire must hold in both.
const _gatedInThisLane = kAppFormFactor == AppFormFactor.mobile;

void main() {
  test(
    'gates sending while a migration holds the whole spendable balance',
    () async {
      expect(
        await _gateFor(
          migrationCta: _resumeCta(),
          ironwoodBalance: BigInt.zero,
        ),
        _gatedInThisLane,
      );
    },
  );

  test(
    'does not gate once the migration produced a spendable Ironwood note',
    () async {
      expect(
        await _gateFor(
          migrationCta: _resumeCta(),
          ironwoodBalance: BigInt.from(100000000),
        ),
        isFalse,
      );
    },
  );

  test('does not gate when no migration is running', () async {
    expect(
      await _gateFor(
        migrationCta: const IronwoodHomeMigrationCtaState.hidden(),
        ironwoodBalance: BigInt.zero,
      ),
      isFalse,
    );
  });

  test('does not gate when a migration is only offered, not resumed', () async {
    expect(
      await _gateFor(
        migrationCta: const IronwoodHomeMigrationCtaState.start(
          network: 'main',
          accountUuid: 'account-1',
        ),
        ironwoodBalance: BigInt.zero,
      ),
      isFalse,
    );
  });

  test("ignores another account's Ironwood balance", () async {
    expect(
      await _gateFor(
        migrationCta: _resumeCta(),
        ironwoodBalance: BigInt.from(100000000),
        syncAccountUuid: 'account-2',
      ),
      _gatedInThisLane,
      reason:
          'sync state scoped to a different account carries no balance for the '
          'active one',
    );
  });
}

Future<bool> _gateFor({
  required IronwoodHomeMigrationCtaState migrationCta,
  required BigInt ironwoodBalance,
  String syncAccountUuid = 'account-1',
}) async {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(migrationCta),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: syncAccountUuid,
            hasAccountScopedData: true,
            ironwoodBalance: ironwoodBalance,
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // `syncProvider` is an AsyncNotifier: read it out before asking for the
  // gate, or every case answers from the empty `SyncState()` fallback and the
  // balance rows pass for the wrong reason.
  await container.read(syncProvider.future);
  return container.read(migrationSendGateProvider);
}

IronwoodHomeMigrationCtaState _resumeCta() =>
    IronwoodHomeMigrationCtaState.resume(
      network: 'main',
      accountUuid: 'account-1',
      status: _status(),
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

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'Account1', order: 0)],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1migrationgate',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
