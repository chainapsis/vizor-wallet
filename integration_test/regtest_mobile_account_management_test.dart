import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/mobile_regtest_flow.dart';

/// Mobile regtest E2E for Track B account management + passcode change,
/// the regtest counterpart of the old mainnet dogfood:
///
///   create wallet → add second account → manage accounts (rename →
///   reject/cancel removal → authenticate removal → change passcode
///   111111→222222 → authenticate last-account reset with the new passcode.
///
/// Run via scripts/e2e/flutter-ios-regtest-mobile-account-management.sh.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'authenticates account removal and last-account reset on regtest',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      logE2e('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await createWalletWithPasscode(tester);
      final originalUuid = await accountUuidAtOrder(0);
      final dbPath = await getWalletDbPath();
      Future<List<String>> databaseAccountUuids() async => [
        for (final account in await rust_wallet.listAccounts(
          dbPath: dbPath,
          network: mobileE2eNetwork,
        ))
          account.uuid,
      ];

      // ── Add a second account through the create flow ─────────────
      await openAddAccountFlow(tester);
      await tapWidget(tester, const ValueKey('mobile_welcome_get_started'));
      await tapAppButton(tester, const ValueKey('mobile_intro_continue'));
      await tapAppButton(
        tester,
        const ValueKey('mobile_address_types_continue'),
      );
      await tapAppButton(
        tester,
        const ValueKey('mobile_things_to_know_continue'),
      );
      await tapAppButton(
        tester,
        const ValueKey('mobile_secret_passphrase_primary'),
      );
      // The second tap advances to account customisation (passcode exists).
      await tapAppButton(
        tester,
        const ValueKey('mobile_secret_passphrase_primary'),
      );
      await tapAppButton(
        tester,
        const ValueKey('mobile_customise_account_continue'),
        timeout: const Duration(minutes: 2),
      );
      await waitForHome(tester);
      final addedUuid = await accountUuidAtOrder(1);
      logE2e('second account added: $addedUuid');

      // ── Manage accounts: rename, then remove ─────────────────────
      await openAccountsSheet(tester);
      await tapUntilVisible(
        tester,
        trigger: find.text('Manage accounts'),
        outcome: find.byKey(ValueKey('mobile_accounts_menu_$addedUuid')),
        description: 'accounts management screen',
      );
      await tapWidget(tester, ValueKey('mobile_accounts_menu_$addedUuid'));
      await tapWidget(tester, const ValueKey('mobile_account_menu_edit'));
      await pumpUntil(
        tester,
        () => tester.any(
          find
              .descendant(
                of: find.byKey(const ValueKey('mobile_account_edit_name')),
                matching: find.byType(EditableText),
                matchRoot: true,
              )
              .hitTestable(),
        ),
        description: 'account name field after the edit sheet transition',
      );
      await enterText(
        tester,
        const ValueKey('mobile_account_edit_name'),
        'Dogfood',
      );
      await tapAppButton(tester, const ValueKey('mobile_account_edit_save'));
      await pumpUntil(
        tester,
        () => tester.any(find.text('Dogfood')),
        description: 'renamed account row',
      );
      logE2e('account renamed');

      Future<void> confirmRemoval(String uuid) async {
        await tapWidget(tester, ValueKey('mobile_accounts_menu_$uuid'));
        await tapWidget(tester, const ValueKey('mobile_account_menu_remove'));
        await tapAppButton(
          tester,
          const ValueKey('mobile_account_remove_confirm'),
        );
        await pumpUntil(
          tester,
          () => tester.any(
            find.byKey(const ValueKey('mobile_account_removal_passcode')),
          ),
          description: 'account removal passcode',
        );
        expect(find.bySemanticsLabel('Passcode help'), findsNothing);
      }

      await confirmRemoval(addedUuid);
      await enterPasscode(tester, '000000');
      await pumpUntil(
        tester,
        () => tester.any(find.text('Incorrect passcode')),
        description: 'incorrect removal passcode error',
      );
      expect(
        await databaseAccountUuids(),
        unorderedEquals([originalUuid, addedUuid]),
      );
      expect(await accountUuidAtOrder(1), addedUuid);
      logE2e('incorrect passcode preserved both database accounts');
      await tapBack(tester);
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(ValueKey('mobile_accounts_menu_$addedUuid'))),
        description: 'accounts after cancelling removal authentication',
      );
      expect(
        await databaseAccountUuids(),
        unorderedEquals([originalUuid, addedUuid]),
      );
      logE2e('cancelled authentication preserved both database accounts');

      await confirmRemoval(addedUuid);
      await enterPasscode(tester, mobileE2ePasscode);
      await pumpUntil(
        tester,
        () =>
            !tester.any(
              find.byKey(const ValueKey('mobile_account_removal_passcode')),
            ) &&
            tester.any(
              find
                  .byKey(ValueKey('mobile_accounts_row_$originalUuid'))
                  .hitTestable(),
            ) &&
            !tester.any(find.byKey(ValueKey('mobile_accounts_row_$addedUuid'))),
        description: 'account screen after authenticated removal',
        timeout: const Duration(seconds: 30),
      );
      expect(await databaseAccountUuids(), [originalUuid]);
      expect(await accountUuidAtOrder(0), originalUuid);
      logE2e('account removed');
      await tapBack(tester);

      // ── Passcode change, then last-account reset ─────────────────
      Future<void> changePasscode(String current, String next) async {
        logE2e('changing passcode');
        await tapUntilVisible(
          tester,
          trigger: find.text('Password'),
          outcome: find.byKey(const ValueKey('mobile_change_passcode_verify')),
          description: 'change-passcode screen',
        );
        await enterPasscode(tester, current);
        await pumpUntil(
          tester,
          () => tester.any(
            find.byKey(const ValueKey('mobile_change_passcode_create')),
          ),
          description: 'new-passcode phase',
        );
        await enterPasscode(tester, next);
        await pumpUntil(
          tester,
          () => tester.any(
            find.byKey(const ValueKey('mobile_change_passcode_confirm')),
          ),
          description: 'confirm-passcode phase',
        );
        await enterPasscode(tester, next);
        await pumpUntil(
          tester,
          () => tester.any(find.text('Passcode updated')),
          description: 'passcode updated toast',
          timeout: const Duration(seconds: 30),
        );
        await pumpUntil(
          tester,
          () => !tester.any(find.text('Passcode updated')),
          description: 'toast to clear',
          timeout: const Duration(seconds: 30),
        );
        logE2e('passcode changed');
      }

      await tapUntilVisible(
        tester,
        trigger: find.bySemanticsLabel('Settings'),
        outcome: find.text('Password'),
        description: 'settings tab',
      );
      await changePasscode(mobileE2ePasscode, '222222');

      await tapUntilVisible(
        tester,
        trigger: find.bySemanticsLabel('Home'),
        outcome: find.byKey(const ValueKey('mobile_home_shielded_balance')),
        description: 'home tab before last-account reset',
      );
      await openAccountsSheet(tester);
      await tapUntilVisible(
        tester,
        trigger: find.text('Manage accounts'),
        outcome: find.byKey(ValueKey('mobile_accounts_menu_$originalUuid')),
        description: 'last account management screen',
      );
      await confirmRemoval(originalUuid);
      expect(find.text('Enter your passcode to reset Vizor.'), findsOneWidget);
      await enterPasscode(tester, mobileE2ePasscode);
      await pumpUntil(
        tester,
        () => tester.any(find.text('Incorrect passcode')),
        description: 'old passcode rejected before reset',
      );
      expect(await databaseAccountUuids(), [originalUuid]);
      logE2e('old passcode rejected; last account remains');
      await tapBack(tester);
      await pumpUntil(
        tester,
        () => tester.any(
          find
              .byKey(ValueKey('mobile_accounts_menu_$originalUuid'))
              .hitTestable(),
        ),
        description: 'last account after cancelling reset authentication',
      );
      expect(await databaseAccountUuids(), [originalUuid]);
      logE2e(
        'cancelled reset authentication preserved the last database account',
      );
      await confirmRemoval(originalUuid);
      await enterPasscode(tester, '222222');
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_welcome_get_started')),
        ),
        description: 'welcome after authenticated last-account reset',
        timeout: const Duration(seconds: 30),
      );
      expect(await File(dbPath).exists(), isFalse);
      expect(await getExistingWalletDbPath(), isNull);
      expect(
        await AppSecureStore.instance.readString('zcash_accounts'),
        isNull,
      );
      expect(await AppSecureStore.instance.isPasswordConfigured(), isFalse);
      logE2e(
        'new passcode authorized last-account reset; wallet state cleared',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
