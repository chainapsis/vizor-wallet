import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

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

      // ── Add a second account through the create flow ─────────────
      await openAddAccountFlow(tester);
      await tapAppButton(tester, const ValueKey('mobile_welcome_create'));
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
      // Second tap creates the account directly (passcode exists).
      await tapAppButton(
        tester,
        const ValueKey('mobile_secret_passphrase_primary'),
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
          outcome: find.text('Enter Passcode'),
          description: 'change-passcode screen',
        );
        await enterPasscode(tester, current);
        await pumpUntil(
          tester,
          () => tester.any(find.text('Update Passcode')),
          description: 'new-passcode phase',
        );
        await enterPasscode(tester, next);
        await pumpUntil(
          tester,
          () => tester.any(find.text('Confirm Passcode')),
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
