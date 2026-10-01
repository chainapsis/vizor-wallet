import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/home/providers/backup_reminder_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

const _accounts = AccountState(
  accounts: [
    AccountInfo(uuid: 'a', name: 'First', order: 0, setupPending: true),
    AccountInfo(uuid: 'b', name: 'Second', order: 1, setupPending: true),
  ],
  activeAccountUuid: 'a',
  activeAddress: 'u1address',
);

AppBootstrapState _bootstrap(AccountState accounts) => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: accounts,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _ControlledStorage extends FlutterSecureStorage {
  bool fail = false;
  Completer<void>? writeGate;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    if (fail) throw StateError('storage unavailable');
    await writeGate?.future;
    return super.write(key: key, value: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ControlledStorage storage;
  late ProviderContainer container;
  late AccountNotifier notifier;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    storage = _ControlledStorage();
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(_accounts)),
        accountProvider.overrideWith(
          () => AccountNotifier.testing(
            store: AppSecureStore.testing(
              storage: storage,
              enforceSessionGeneration: true,
            ),
          ),
        ),
      ],
    );
    await container.read(accountProvider.future);
    notifier = container.read(accountProvider.notifier);
  });
  tearDown(() => container.dispose());

  test(
    'reminders persist 2 days, 14 days, then 30 days without completing backup',
    () async {
      final now = DateTime.utc(2026, 10, 1);
      for (final days in [2, 14, 30, 30]) {
        await notifier.snoozeBackupReminder('a', now: now);
        final account = container
            .read(accountProvider)
            .requireValue
            .accounts
            .first;
        expect(account.setupPending, isTrue);
        expect(
          account.backupReminderSnoozedUntilUtc,
          now.add(Duration(days: days)),
        );
        expect(shouldShowBackupReminder(account, now), isFalse);
        expect(
          shouldShowBackupReminder(
            account,
            account.backupReminderSnoozedUntilUtc!,
          ),
          isTrue,
        );
        final json =
            jsonDecode((await storage.read(key: 'zcash_accounts'))!) as List;
        final restored = AccountInfo.fromJson(
          json.first as Map<String, dynamic>,
        );
        expect(
          restored.backupReminderSnoozedUntilUtc,
          account.backupReminderSnoozedUntilUtc,
        );
        expect(
          restored.backupReminderSnoozeCount,
          account.backupReminderSnoozeCount,
        );
        expect(
          container
              .read(accountProvider)
              .requireValue
              .accounts
              .last
              .backupReminderSnoozeCount,
          0,
        );
      }
    },
  );

  test(
    'completion persists and clears only the target account reminder',
    () async {
      await notifier.snoozeBackupReminder('a');
      await notifier.markBackedUp('a');
      final accounts = container.read(accountProvider).requireValue.accounts;
      expect(accounts.first.setupPending, isFalse);
      expect(accounts.first.backupReminderSnoozedUntilUtc, isNull);
      expect(accounts.first.backupReminderSnoozeCount, 0);
      expect(accounts.last.setupPending, isTrue);
      final json =
          jsonDecode((await storage.read(key: 'zcash_accounts'))!) as List;
      expect(
        AccountInfo.fromJson(json.first as Map<String, dynamic>).setupPending,
        isFalse,
      );
      expect(notifier.snoozeBackupReminder('a'), throwsStateError);
      expect(notifier.markBackedUp('missing'), throwsStateError);
    },
  );

  test(
    'failed persistence leaves completion and snooze state unchanged',
    () async {
      storage.fail = true;
      await expectLater(notifier.markBackedUp('a'), throwsA(anything));
      await expectLater(notifier.snoozeBackupReminder('a'), throwsA(anything));
      expect(
        container
            .read(accountProvider)
            .requireValue
            .accounts
            .first
            .setupPending,
        isTrue,
      );
      expect(
        container
            .read(accountProvider)
            .requireValue
            .accounts
            .first
            .backupReminderSnoozeCount,
        0,
      );
    },
  );

  test('a delayed metadata write does not restore a locked address', () async {
    storage.writeGate = Completer<void>();
    final saving = notifier.markBackedUp('a');
    await Future<void>.delayed(Duration.zero);
    notifier.clearSensitiveStateForLock();
    storage.writeGate!.complete();
    await saving;
    final current = container.read(accountProvider).requireValue;
    expect(current.activeAddress, isNull);
    expect(current.accounts.first.setupPending, isFalse);
  });

  test(
    'old metadata has no new Home prompt and corrupt counters are bounded',
    () {
      final account = AccountInfo.fromJson({
        'uuid': 'old',
        'name': 'Existing',
        'order': 0,
      });
      expect(shouldShowBackupReminder(account, DateTime.now()), isFalse);
      expect(
        AccountInfo.fromJson({
          ...account.toJson(),
          'backupReminderSnoozeCount': 99,
        }).backupReminderSnoozeCount,
        3,
      );
    },
  );

  testWidgets(
    'Home reminder expires while mounted and disappears after completion',
    (tester) async {
      var now = DateTime.utc(2026, 10, 1);
      await notifier.snoozeBackupReminder(
        'a',
        now: now
            .subtract(const Duration(days: 2))
            .add(const Duration(seconds: 1)),
      );
      final scope = ProviderContainer(
        parent: container,
        overrides: [backupReminderClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(scope.dispose);
      final subscription = scope.listen(showBackupReminderProvider, (_, _) {});
      addTearDown(subscription.close);
      expect(scope.read(showBackupReminderProvider), isFalse);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(scope.read(showBackupReminderProvider), isTrue);
      await notifier.markBackedUp('a');
      expect(scope.read(showBackupReminderProvider), isFalse);
      subscription.close();
      scope.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
