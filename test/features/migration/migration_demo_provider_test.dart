import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/features/migration/providers/migration_demo_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('provider yields null when there is no active account', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = await container.read(migrationDemoProvider.future);
    expect(value, isNull);
  });

  test(
    'startDemoForAccount writes original account without publishing it',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(
            () => _FakeAccountNotifier(
              const AccountState(
                accounts: [
                  AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
                  AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
                ],
                activeAccountUuid: 'account-1',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(migrationDemoProvider.future), isNull);

      await container.read(accountProvider.notifier).switchAccount('account-2');
      expect(await container.read(migrationDemoProvider.future), isNull);

      await container
          .read(migrationDemoProvider.notifier)
          .startDemoForAccount(
            accountUuid: 'account-1',
            displayAmountZatoshi: BigInt.from(125_000),
            txids: const ['tx-1'],
          );

      expect(container.read(migrationDemoProvider).value, isNull);

      await container.read(accountProvider.notifier).switchAccount('account-1');
      final restored = await container.read(migrationDemoProvider.future);
      expect(restored?.accountUuid, 'account-1');
      expect(restored?.displayAmountZatoshi, BigInt.from(125_000));
      expect(restored?.txids, ['tx-1']);
    },
  );
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }
}
