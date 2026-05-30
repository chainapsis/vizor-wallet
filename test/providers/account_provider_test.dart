import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';

void main() {
  test(
    'next active account stays unchanged when removing a non-active account',
    () {
      const accounts = [
        AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Savings', order: 1),
        AccountInfo(uuid: 'account-3', name: 'Travel', order: 2),
      ];
      const previous = AccountState(
        accounts: accounts,
        activeAccountUuid: 'account-1',
      );

      final next = resolveNextActiveAccountUuidAfterRemoval(
        previousState: previous,
        removedAccount: accounts[1],
        remainingAccounts: [accounts[0], accounts[2].copyWith(order: 1)],
      );

      expect(next, 'account-1');
    },
  );

  test(
    'next active account clamps removed active index into remaining list',
    () {
      const removed = AccountInfo(uuid: 'account-3', name: 'Travel', order: 99);
      const remaining = [
        AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Savings', order: 1),
      ];
      const previous = AccountState(
        accounts: [...remaining, removed],
        activeAccountUuid: 'account-3',
      );

      final next = resolveNextActiveAccountUuidAfterRemoval(
        previousState: previous,
        removedAccount: removed,
        remainingAccounts: remaining,
      );

      expect(next, 'account-2');
    },
  );

  test(
    'destructive account mutations are rejected while voting submission is guarded',
    () async {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);
      final guard = container
          .read(votingSubmissionGuardProvider.notifier)
          .acquire(accountUuid: 'account-1', roundId: 'round-1');

      await expectLater(
        container.read(accountProvider.notifier).removeAccount('account-2'),
        throwsA(isA<VotingSubmissionInProgressException>()),
      );
      await expectLater(
        container.read(accountProvider.notifier).resetWallet(),
        throwsA(isA<VotingSubmissionInProgressException>()),
      );

      final state = container.read(accountProvider).value!;
      expect(state.activeAccountUuid, 'account-1');
      expect(state.accounts, hasLength(2));

      container.read(votingSubmissionGuardProvider.notifier).release(guard);
    },
  );

  test('voting submission guard tracks multiple active jobs', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(votingSubmissionGuardProvider.notifier);
    final first = notifier.acquire(
      accountUuid: 'account-1',
      roundId: 'round-1',
    );
    final second = notifier.acquire(
      accountUuid: 'account-2',
      roundId: 'round-2',
    );

    expect(container.read(votingSubmissionGuardProvider), [first, second]);
    expect(notifier.guardForAccount('account-2'), same(second));
  });
}

AppBootstrapState _bootstrapWithAccounts() {
  const accountState = AccountState(
    accounts: [
      AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Keystone', order: 1),
    ],
    activeAccountUuid: 'account-1',
  );
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('account-1'),
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}
