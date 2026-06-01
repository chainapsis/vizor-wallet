import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  test('wallet db cleanup paths include main db and voting sidecar files', () {
    const dbPath = '/tmp/zcash_wallet.db';

    final cleanupPaths = walletDbCleanupPaths(dbPath);

    expect(cleanupPaths, [
      '/tmp/zcash_wallet.db',
      '/tmp/zcash_wallet.db-journal',
      '/tmp/zcash_wallet.db-wal',
      '/tmp/zcash_wallet.db-shm',
      '/tmp/zcash_wallet.db.voting',
      '/tmp/zcash_wallet.db.voting-journal',
      '/tmp/zcash_wallet.db.voting-wal',
      '/tmp/zcash_wallet.db.voting-shm',
    ]);
  });

  test('wallet db cleanup paths are stable for empty db path', () {
    final cleanupPaths = walletDbCleanupPaths('');

    expect(cleanupPaths, [
      '',
      '-journal',
      '-wal',
      '-shm',
      '.voting',
      '.voting-journal',
      '.voting-wal',
      '.voting-shm',
    ]);
  });

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
}
