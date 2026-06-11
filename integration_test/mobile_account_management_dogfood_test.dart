import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav_account.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

/// Manual dogfood runner for mobile account management + passcode
/// change (Track B).
///
/// Self-contained in a single invocation because `flutter test
/// integration_test` reinstalls the app per run: the wallet DB lives in
/// the app container and is wiped with it, while the iOS Keychain
/// persists — a wallet created by an earlier invocation would come back
/// as keychain entries without DB rows. So this test creates its own
/// wallet first (real Rust mnemonic, mainnet birthday fetch, keychain
/// commit; passcode 111111) and then drives Track B end to end:
///
///   create wallet → add account (real mainnet account creation) →
///   manage accounts → rename → remove → change passcode
///   111111→222222 → change back 222222→111111 (the verify step
///   doubles as proof the new passcode unlocks the rotated verifier).
///
/// It therefore CREATES A MAINNET WALLET on the target device: run it
/// on a disposable simulator with NO existing wallet (`./clear-app.sh`
/// resets one — required, or the leftover keychain breaks bootstrap),
/// with the mobile token lane:
///
///   fvm flutter test integration_test/mobile_account_management_dogfood_test.dart \
///     -d SIMULATOR --dart-define=VIZOR_FORM_FACTOR=mobile
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('account management and passcode change round-trip', (
    tester,
  ) async {
    final app = await buildBootstrappedZcashWalletApp();
    await tester.pumpWidget(app);

    Future<void> waitFor(
      Finder finder, {
      Duration timeout = const Duration(seconds: 20),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (finder.evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          final onstage = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? '')
              .where((s) => s.isNotEmpty)
              .toSet();
          final pages = tester
              .widgetList<Navigator>(find.byType(Navigator, skipOffstage: false))
              .expand((n) => n.pages)
              .map((p) => '${p.name ?? p.runtimeType}#${p.key}')
              .toList();
          fail(
            'Timed out waiting for $finder\n'
            'Onstage texts: $onstage\n'
            'Navigator pages: $pages',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> waitUntilGone(
      Finder finder, {
      Duration timeout = const Duration(seconds: 20),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (finder.evaluate().isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Timed out waiting for $finder to go away');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> tapWhenVisible(
      Finder finder, {
      Duration timeout = const Duration(seconds: 20),
    }) async {
      await waitFor(finder, timeout: timeout);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> enterPasscode(String digits) async {
      for (final digit in digits.split('')) {
        await tapWhenVisible(find.bySemanticsLabel('Digit $digit'));
      }
    }

    AccountState readAccounts() {
      // skipOffstage: false — the home screen sits offstage in the tab
      // shell while onboarding/management routes cover it.
      final context = tester.element(
        find.byType(MobileHomeScreen, skipOffstage: false).first,
      );
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(accountProvider).value!;
    }

    // The home shell stays mounted under pushed routes and sheets, so
    // a bare avatar tap can land mid-transition and miss. Retry the
    // tap until the sheet content is actually up.
    Future<void> openAccountsSheet() async {
      final avatar = find.descendant(
        of: find.byType(MobileTopNavAccount),
        matching: find.byType(AppProfilePicture),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (find.text('Manage accounts').evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Timed out opening the accounts sheet');
        }
        if (avatar.evaluate().isNotEmpty) {
          await tester.tap(avatar.first, warnIfMissed: false);
        }
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    Future<void> walkCreateFlowToPasscode() async {
      await tapWhenVisible(find.byKey(const ValueKey('mobile_welcome_create')));
      await tapWhenVisible(find.byKey(const ValueKey('mobile_intro_continue')));
      await tapWhenVisible(
        find.byKey(const ValueKey('mobile_address_types_continue')),
      );
      await tapWhenVisible(
        find.byKey(const ValueKey('mobile_things_to_know_continue')),
      );
      await tapWhenVisible(
        find.byKey(const ValueKey('mobile_secret_passphrase_primary')),
      );
      // Second tap leaves the (revealed) passphrase step; on the first
      // account it opens passcode setup, on later accounts it creates
      // the account directly.
      await tapWhenVisible(
        find.byKey(const ValueKey('mobile_secret_passphrase_primary')),
      );
    }

    // ── Create the wallet (first account, passcode 111111) ─────────
    await walkCreateFlowToPasscode();
    await enterPasscode('111111');
    await enterPasscode('111111');
    // Account creation fetches the birthday over the network.
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_biometrics_not_now')),
      timeout: const Duration(seconds: 90),
    );
    await waitFor(
      find.byType(MobileHomeScreen),
      timeout: const Duration(seconds: 20),
    );
    await tester.pump(const Duration(seconds: 1));

    final baseline = readAccounts();
    expect(baseline.accounts.length, 1);
    final baselineUuids = {for (final a in baseline.accounts) a.uuid};

    // ── Add a second account (real mainnet account creation) ───────
    await openAccountsSheet();
    await tapWhenVisible(find.bySemanticsLabel('Add account'));
    await walkCreateFlowToPasscode();
    // Wait for the creation to land AND the onboarding stack to fully
    // unwind back to home (the home screen alone is no signal — it
    // stays mounted in the tab shell underneath pushed routes).
    final addDeadline = DateTime.now().add(const Duration(seconds: 90));
    while (readAccounts().accounts.length != baseline.accounts.length + 1) {
      if (DateTime.now().isAfter(addDeadline)) {
        fail('Timed out waiting for the added account');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await waitUntilGone(
      find.byKey(const ValueKey('mobile_secret_passphrase_primary')),
    );
    await tester.pump(const Duration(seconds: 1));
    final added = readAccounts().accounts.firstWhere(
      (a) => !baselineUuids.contains(a.uuid),
    );

    // ── Manage accounts: rename the new account ─────────────────────
    await openAccountsSheet();
    await tapWhenVisible(find.text('Manage accounts'));
    await tapWhenVisible(
      find.byKey(ValueKey('mobile_accounts_menu_${added.uuid}')),
    );
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_account_menu_edit')),
    );
    await waitFor(find.byKey(const ValueKey('mobile_account_edit_name')));
    await tester.enterText(
      find.byKey(const ValueKey('mobile_account_edit_name')),
      'Dogfood',
    );
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_account_edit_save')),
    );
    await waitFor(find.text('Dogfood'));
    expect(
      readAccounts().accounts.firstWhere((a) => a.uuid == added.uuid).name,
      'Dogfood',
    );

    // ── Remove it again ─────────────────────────────────────────────
    await tapWhenVisible(
      find.byKey(ValueKey('mobile_accounts_menu_${added.uuid}')),
    );
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_account_menu_remove')),
    );
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_account_remove_confirm')),
    );
    await waitUntilGone(
      find.byKey(ValueKey('mobile_accounts_row_${added.uuid}')),
      timeout: const Duration(seconds: 30),
    );
    expect(readAccounts().accounts.length, baseline.accounts.length);
    await tapWhenVisible(find.bySemanticsLabel('Back'));

    // ── Change the passcode, then change it back ────────────────────
    Future<void> changePasscode(String current, String next) async {
      debugPrint('[dogfood] changePasscode $current -> $next: open');
      // Open the change screen by outcome, not by a single tap: while
      // the previous round's pop/toast animations are settling, one
      // tap on the row can be swallowed by the exiting route. Throttle
      // retries well past the push transition, or a second tap lands
      // on the still-visible row underneath and stacks a second copy
      // of the screen.
      final openDeadline = DateTime.now().add(const Duration(seconds: 20));
      var lastTap = DateTime.fromMillisecondsSinceEpoch(0);
      while (find.text('Enter Passcode').evaluate().isEmpty) {
        if (DateTime.now().isAfter(openDeadline)) {
          fail('Timed out opening the change-passcode screen');
        }
        final row = find.text('Password');
        if (row.evaluate().isNotEmpty &&
            DateTime.now().difference(lastTap) >
                const Duration(seconds: 3)) {
          lastTap = DateTime.now();
          await tester.tap(row, warnIfMissed: false);
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      debugPrint('[dogfood] verify phase');
      await enterPasscode(current);
      await waitFor(find.text('Update Passcode'));
      debugPrint('[dogfood] create phase');
      await enterPasscode(next);
      await waitFor(find.text('Confirm Passcode'));
      debugPrint('[dogfood] confirm phase');
      await enterPasscode(next);
      // The rotation pops back to settings and raises the toast.
      await waitFor(
        find.text('Passcode updated'),
        timeout: const Duration(seconds: 30),
      );
      debugPrint('[dogfood] toast seen');
      await waitUntilGone(
        find.text('Passcode updated'),
        timeout: const Duration(seconds: 30),
      );
      debugPrint('[dogfood] changePasscode done');
    }

    await tapWhenVisible(find.bySemanticsLabel('Settings'));
    await changePasscode('111111', '222222');
    // Verifying 222222 here proves the rotated passcode is the one the
    // store now accepts; finishing the change restores 111111.
    await changePasscode('222222', '111111');
  });
}
