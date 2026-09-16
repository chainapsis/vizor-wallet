import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/home/providers/ledger_shielding_capacity_provider.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

void main() {
  test('reports the device input budget and approval count', () async {
    final reads = <String>[];
    final container = _container(
      ledger: true,
      canShield: true,
      status: _status(inputCount: 41, limit: 32),
      reads: reads,
    );
    addTearDown(container.dispose);

    final capacity = await _capacity(container);

    expect(capacity?.inputCount, 41);
    expect(capacity?.inputLimit, 32);
    expect(capacity?.approvalCount, 2);
    expect(reads, ['account-1']);
  });

  test('returns no capacity warning when inputs fit one approval', () async {
    final container = _container(
      ledger: true,
      canShield: true,
      status: _status(inputCount: 3, limit: 32),
    );
    addTearDown(container.dispose);

    expect(await _capacity(container), isNull);
  });

  test(
    'does not read status for software accounts or unavailable shielding',
    () async {
      final reads = <String>[];
      final software = _container(
        ledger: false,
        canShield: true,
        status: _status(inputCount: 41, limit: 32),
        reads: reads,
      );
      addTearDown(software.dispose);
      expect(await _capacity(software), isNull);

      final unavailable = _container(
        ledger: true,
        canShield: false,
        status: _status(inputCount: 41, limit: 32),
        reads: reads,
      );
      addTearDown(unavailable.dispose);
      expect(await _capacity(unavailable), isNull);
      expect(reads, isEmpty);
    },
  );
}

Future<LedgerShieldingCapacity?> _capacity(ProviderContainer container) {
  container.listen(ledgerShieldingCapacityProvider, (_, _) {});
  return container.read(ledgerShieldingCapacityProvider.future);
}

rust_sync.ShieldTransparentStatus _status({
  required int inputCount,
  required int limit,
}) {
  return rust_sync.ShieldTransparentStatus(
    canShield: true,
    feeZatoshi: BigInt.from(10_000),
    shieldedZatoshi: BigInt.from(90_000),
    reason: '',
    transparentInputCount: inputCount,
    ledgerInputLimit: limit,
  );
}

ProviderContainer _container({
  required bool ledger,
  required bool canShield,
  required rust_sync.ShieldTransparentStatus status,
  List<String>? reads,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(ledger: ledger)),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            transparentBalance: BigInt.from(500_000),
            canShieldTransparentBalance: canShield,
          ),
        ),
      ),
      ledgerWalletDbPathProvider.overrideWithValue(
        () async => '/tmp/wallet.db',
      ),
      ledgerShieldStatusReaderProvider.overrideWithValue(({
        required dbPath,
        required network,
        required accountUuid,
      }) async {
        reads?.add(accountUuid);
        return status;
      }),
    ],
  );
}

AppBootstrapState _bootstrap({required bool ledger}) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: 'account-1',
          name: ledger ? 'Ledger' : 'Software',
          order: 0,
          isHardware: ledger,
          hardwareSignerKind: ledger ? HardwareSignerKind.ledger : null,
        ),
      ],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1active',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}
