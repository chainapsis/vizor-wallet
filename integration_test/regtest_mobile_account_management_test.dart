import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';

import 'support/mobile_regtest_flow.dart';

/// Mobile regtest E2E for Track B account management + passcode change,
/// the regtest counterpart of the old mainnet dogfood:
///
///   create wallet → add second account → manage accounts (rename →
///   remove) → change passcode 111111→222222 → change back (the verify
///   step proves the rotated credential against the real store).
///
/// Run via scripts/e2e/flutter-ios-regtest-mobile-account-management.sh.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'manages accounts and rotates the passcode on regtest',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      logE2e('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await createWalletWithPasscode(tester);

      final sourceBefore = await accountInfoAtOrder(0);
      final sourceSecret = await AppSecureStore.instance
          .readAccountSoftwareWalletSecret(sourceBefore.uuid);
      expect(sourceSecret, isNotNull);
      final sourceAddress = await unifiedAddressForAccount(sourceBefore.uuid);

      // Add a second ZIP-32 account from the existing software secret.
      await openAddAccountFlow(tester);
      await tapWidget(tester, const ValueKey('mobile_welcome_get_started'));
      await tapWidget(tester, const ValueKey('mobile_welcome_derive_account'));
      await tapAppButton(
        tester,
        const ValueKey('mobile_customise_account_continue'),
      );
      await waitForHome(tester);

      final source = await accountInfoAtOrder(0);
      final added = await accountInfoAtOrder(1);
      final addedSecret = await AppSecureStore.instance
          .readAccountSoftwareWalletSecret(added.uuid);
      final addedAddress = await unifiedAddressForAccount(added.uuid);

      expect(added.uuid, isNot(source.uuid));
      expect(addedAddress, isNot(sourceAddress));
      expect(source.seedFamilyId, isNotEmpty);
      expect(added.seedFamilyId, source.seedFamilyId);
      expect(addedSecret?.mnemonic, sourceSecret?.mnemonic);
      expect(addedSecret?.bip39Passphrase, sourceSecret?.bip39Passphrase);
      final addedUuid = added.uuid;
      logE2e('same-seed account added: $addedUuid');

      // ── Manage accounts: rename, then remove ─────────────────────
      await openAccountsSheet(tester);
      await tapUntilVisible(
        tester,
        trigger: find.text('Manage accounts'),
        outcome: find.byKey(ValueKey('mobile_accounts_menu_$addedUuid')),
        description: 'accounts management screen',
      );

      final familyCard = find.byKey(
        ValueKey('mobile_accounts_family_${source.uuid}'),
      );
      expect(familyCard, findsOneWidget);
      expect(
        find.descendant(
          of: familyCard,
          matching: find.byKey(ValueKey('mobile_accounts_row_${source.uuid}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: familyCard,
          matching: find.byKey(ValueKey('mobile_accounts_row_$addedUuid')),
        ),
        findsOneWidget,
      );

      await tapWidget(
        tester,
        ValueKey('mobile_accounts_edit_group_${source.uuid}'),
      );
      await enterText(
        tester,
        const ValueKey('mobile_account_group_edit_name'),
        'Everyday wallet',
      );
      await tapAppButton(
        tester,
        const ValueKey('mobile_account_group_edit_save'),
      );
      await pumpUntil(
        tester,
        () => tester.any(find.text('Everyday wallet')),
        description: 'renamed account group',
      );

      final groupedAccounts = await storedAccountsByOrder();
      expect(groupedAccounts[0].accountGroupName, 'Everyday wallet');
      expect(groupedAccounts[1].accountGroupName, 'Everyday wallet');

      await tapWidget(tester, ValueKey('mobile_accounts_menu_$addedUuid'));
      await tapWidget(tester, const ValueKey('mobile_account_menu_edit'));
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

      await tapWidget(tester, ValueKey('mobile_accounts_menu_$addedUuid'));
      await tapWidget(tester, const ValueKey('mobile_account_menu_remove'));
      await tapAppButton(
        tester,
        const ValueKey('mobile_account_remove_confirm'),
      );
      await pumpUntil(
        tester,
        () =>
            !tester.any(find.byKey(ValueKey('mobile_accounts_row_$addedUuid'))),
        description: 'removed account row to disappear',
        timeout: const Duration(seconds: 30),
      );
      logE2e('account removed');
      await tapBack(tester);

      // ── Passcode change round-trip ───────────────────────────────
      Future<void> changePasscode(String current, String next) async {
        logE2e('changing passcode $current -> $next');
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
      await changePasscode('222222', mobileE2ePasscode);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
