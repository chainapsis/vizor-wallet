import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';

const _initial = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'ledger',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
    ),
  ],
  activeAccountUuid: 'ledger',
  activeAddress: 'u-initial',
);

class _Accounts extends AccountNotifier {
  @override
  AccountState build() => _initial;
  void publish(AsyncValue<AccountState> next) {
    state = next;
  }
}

void main() {
  for (final transition in [
    'address',
    'account',
    'delete',
    'lock',
    'error',
    'loading',
  ]) {
    test('Ledger metadata filtering preserves $transition updates', () async {
      final accounts = _Accounts();
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(() => accounts),
          appBootstrapProvider.overrideWithValue(
            AppBootstrapState(
              initialLocation: '/home',
              initialAccountState: _initial,
              initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('ledger'),
              network: 'main',
              rpcEndpointConfig: defaultRpcEndpointConfig('main'),
              themeMode: ThemeMode.system,
              privacyModeEnabled: false,
              isPasswordConfigured: true,
              isUnlocked: true,
              passwordRotationRecoveryFailed: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(walletProvider.future);
      var updates = 0;
      final sub = container.listen(walletProvider, (_, _) => updates++);
      addTearDown(sub.close);
      // All Ledger consumers share this wallet boundary, including desktop USB.
      for (final transport in LedgerConnectionTransport.values) {
        accounts.publish(
          AsyncData(
            _initial.copyWith(
              accounts: [
                _initial.accounts.single.copyWith(
                  ledgerDeviceId: 'new',
                  ledgerDeviceName: 'New Ledger',
                  ledgerLastTransport: transport,
                ),
              ],
            ),
          ),
        );
        await container.pump();
        expect(updates, 0);
      }
      switch (transition) {
        case 'address':
          accounts.publish(
            AsyncData(_initial.copyWith(activeAddress: 'u-new')),
          );
        case 'account':
          accounts.publish(
            const AsyncData(
              AccountState(
                accounts: [AccountInfo(uuid: 'other', name: 'Other', order: 0)],
                activeAccountUuid: 'other',
                activeAddress: 'u-other',
              ),
            ),
          );
        case 'delete':
          accounts.publish(const AsyncData(AccountState()));
        case 'lock':
          accounts.clearSensitiveStateForLock();
        case 'error':
          accounts.publish(
            AsyncError(StateError('Storage failed'), StackTrace.current),
          );
        case 'loading':
          accounts.publish(const AsyncLoading());
      }
      await container.pump();
      expect(updates, greaterThan(0));
      final wallet = container.read(walletProvider);
      switch (transition) {
        case 'address':
          expect(wallet.requireValue.unifiedAddress, 'u-new');
        case 'account':
          expect(wallet.requireValue.activeAccountUuid, 'other');
        case 'delete':
          expect(wallet.requireValue.hasWallet, isFalse);
        case 'lock':
          expect(wallet.requireValue.unifiedAddress, isNull);
        case 'error':
          expect(wallet.hasError, isTrue);
          accounts.publish(const AsyncData(_initial));
          await container.pump();
          expect(container.read(walletProvider).hasError, isFalse);
        case 'loading':
          expect(wallet.requireValue.hasWallet, isTrue);
      }
    });
  }
}
