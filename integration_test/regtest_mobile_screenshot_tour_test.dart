import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/services/native_date_picker.dart';

import 'support/mobile_regtest_flow.dart';

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _screenshotDriverUrl = String.fromEnvironment(
  'ZCASH_E2E_SCREENSHOT_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39070',
);

/// Design-fidelity capture tour — NOT part of the e2e runner. Walks
/// every mobile screen/state on a funded regtest wallet and asks the
/// host screenshot driver to grab the simulator screen at each stop.
/// Run via scripts/e2e/flutter-ios-regtest-mobile-screenshot-tour.sh;
/// PNGs land in .regtest-logs/screens/.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'captures every mobile screen for the design comparison',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      Future<void> shot(String name) async {
        // Let animations/toasts settle so frames are representative.
        await settle(tester, const Duration(milliseconds: 700));
        await postDriver('/screenshot', {'name': name}, baseUrl: _screenshotDriverUrl);
        logE2e('shot $name');
      }

      logE2e('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(const ValueKey('mobile_welcome_create'))),
        description: 'welcome screen',
        timeout: const Duration(minutes: 1),
      );
      await shot('01_welcome');

      // ── Import flow (funded wallet) ────────────────────────────────
      await tapAppButton(tester, const ValueKey('mobile_welcome_import'));
      await shot('02_import_entry');
      await tapWidget(
        tester,
        const ValueKey('mobile_import_enter_manually'),
      );
      await pumpUntil(
        tester,
        () => tester.any(find.text('Next word')),
        description: 'manual entry screen',
      );
      await shot('02m_import_manual');
      await tester.enterText(find.byType(EditableText).first, 'winter');
      await settle(tester, const Duration(milliseconds: 400));
      await shot('02n_import_manual_typed');
      await tapBack(tester);
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(const ValueKey('mobile_import_paste'))),
        description: 'back on import entry',
      );
      await Clipboard.setData(const ClipboardData(text: _mnemonic));
      await tapAppButton(tester, const ValueKey('mobile_import_paste'));
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey('mobile_import_confirm'))),
        description: 'import slots filled',
      );
      await shot('02b_import_entry_filled');
      await tapAppButton(tester, const ValueKey('mobile_import_confirm'));
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_import_review_continue')),
        ),
        description: 'import review',
      );
      await shot('03_import_review');
      await tapAppButton(
        tester,
        const ValueKey('mobile_import_review_continue'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_import_birthday_continue')),
        ),
        description: 'import birthday',
      );
      await shot('04_import_birthday');
      // The date "field" opens the OS-native UICalendarView sheet on
      // iOS (the tour only runs on the iOS simulator). There are no
      // Flutter widgets to wait on — give the present animation real
      // time, capture, then dismiss through the picker channel since
      // flutter_test cannot tap native UIKit views.
      await tapWidget(tester, const ValueKey('mobile_import_birthday_date'));
      await settle(tester, const Duration(milliseconds: 1500));
      await shot('04c_import_birthday_calendar');
      await NativeDatePicker.cancel();
      await settle(tester, const Duration(milliseconds: 800));
      await tapWidget(
        tester,
        const ValueKey('mobile_import_birthday_mode_height'),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mobile_import_birthday_height')),
        '1',
      );
      await settle(tester, const Duration(milliseconds: 400));
      await shot('04b_import_birthday_height');
      await tapAppButton(
        tester,
        const ValueKey('mobile_import_birthday_continue'),
        timeout: const Duration(minutes: 1),
      );

      // ── Passcode setup ─────────────────────────────────────────────
      await pumpUntil(
        tester,
        () => tester.any(find.text('Create Passcode')),
        description: 'passcode create',
      );
      await shot('05_passcode_create');
      await enterPasscode(tester, '111');
      await shot('06_passcode_create_partial');
      await enterPasscode(tester, '111');
      await pumpUntil(
        tester,
        () => tester.any(find.text('Confirm Passcode')),
        description: 'passcode confirm',
      );
      await shot('07_passcode_confirm');
      await enterPasscode(tester, mobileE2ePasscode);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_biometrics_not_now')),
        ),
        description: 'biometrics screen',
        timeout: const Duration(seconds: 90),
      );
      await shot('08_biometrics');
      await tapWidget(tester, const ValueKey('mobile_biometrics_not_now'));
      await waitForHome(tester);
      await shot('08b_home_syncing');

      // ── Home (funded, synced) ──────────────────────────────────────
      await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');
      await pumpUntil(
        tester,
        () => tester.any(find.text('Vizor is synced')),
        description: 'sync to complete',
        timeout: const Duration(minutes: 2),
      );
      await shot('09_home_funded');

      // ── Accounts sheet + management ────────────────────────────────
      await openAccountsSheet(tester);
      await shot('10_accounts_sheet');
      await tapUntilVisible(
        tester,
        trigger: find.text('Manage accounts'),
        outcome: find.text('Accounts'),
        description: 'accounts management screen',
      );
      await shot('11_accounts_manage');
      final accountUuid = await accountUuidAtOrder(0);
      await tapWidget(tester, ValueKey('mobile_accounts_menu_$accountUuid'));
      await shot('12_accounts_row_menu');
      await tapWidget(tester, const ValueKey('mobile_account_menu_edit'));
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey('mobile_account_edit_name'))),
        description: 'edit sheet',
      );
      await shot('13_account_edit_sheet');
      await tapWidget(tester, const ValueKey('mobile_account_edit_avatar'));
      await pumpUntil(
        tester,
        () => tester.any(find.text('Select profile picture')),
        description: 'pfp sheet',
      );
      await shot('14_pfp_sheet');
      await tapWidget(tester, const ValueKey('mobile_account_pfp_update'));
      await settle(tester, const Duration(milliseconds: 400));
      await escapeToHome(tester);

      // ── Receive ────────────────────────────────────────────────────
      await tapWidget(tester, const ValueKey('mobile_home_receive'));
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(const ValueKey('mobile_receive_copy'))),
        description: 'receive screen',
        timeout: const Duration(minutes: 1),
      );
      await shot('15_receive_shielded');
      await tapWidget(tester, const ValueKey('receive_address_type_tab_transparent'));
      await shot('16_receive_transparent');
      // Info sheets per pool.
      final help = find.bySemanticsLabel('About this address type');
      await tester.tap(help.first, warnIfMissed: false);
      await shot('17_receive_transparent_info');
      await tapWidget(tester, const ValueKey('receive_address_info_close'));
      await tapWidget(
        tester,
        const ValueKey('receive_address_type_tab_shielded'),
      );
      await tester.tap(help.first, warnIfMissed: false);
      await shot('18_receive_shielded_info');
      await tapWidget(tester, const ValueKey('receive_address_info_close'));
      await tapBack(tester);
      await waitForHome(tester);

      // ── Send wizard ────────────────────────────────────────────────
      final ownAddress = await copyShieldedAddress(tester);
      await tapWidget(tester, const ValueKey('mobile_home_send'));
      await pumpUntil(
        tester,
        () => tester.any(find.text('Select Recipient')),
        description: 'send recipient step',
      );
      await shot('19_send_recipient');
      await enterText(
        tester,
        const ValueKey('mobile_send_address_field'),
        ownAddress,
      );
      await shot('20_send_recipient_filled');
      await tapAppButton(
        tester,
        const ValueKey('mobile_send_continue'),
        timeout: const Duration(minutes: 1),
      );
      await pumpUntil(
        tester,
        () => tester.any(find.text('Enter amount')),
        description: 'send amount step',
      );
      await shot('21_send_amount_empty');
      for (final ch in '0.25'.split('')) {
        final label = ch == '.' ? 'Decimal point' : 'Digit $ch';
        await tester.tap(find.bySemanticsLabel(label));
        await tester.pump(const Duration(milliseconds: 150));
      }
      await pumpUntil(
        tester,
        () => tester.any(find.text('Finish & Review')),
        description: 'amount ready',
        timeout: const Duration(minutes: 1),
      );
      await shot('22_send_amount_ready');
      await tapAppButton(
        tester,
        const ValueKey('mobile_send_review_button'),
        timeout: const Duration(minutes: 1),
      );
      await pumpUntil(
        tester,
        () => tester.any(find.text('Review Send')),
        description: 'send review step',
      );
      await shot('23_send_review');
      await tapWidget(tester, const ValueKey('mobile_send_memo_row'));
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey('mobile_send_memo_field'))),
        description: 'memo sheet',
      );
      await shot('24_send_memo_sheet');
      await enterText(
        tester,
        const ValueKey('mobile_send_memo_field'),
        'Zcash is a privacy-focused cryptocurrency',
      );
      await tapAppButton(tester, const ValueKey('mobile_send_memo_save'));
      await settle(tester, const Duration(milliseconds: 400));
      await shot('25_send_review_with_memo');
      // Inline full-address toggle on the recipient row.
      await tapWidget(tester, const ValueKey('mobile_send_full_address'));
      await settle(tester, const Duration(milliseconds: 400));
      await shot('25b_send_full_address');
      await tapWidget(tester, const ValueKey('mobile_send_full_address'));
      await settle(tester, const Duration(milliseconds: 400));
      // Actually send so the in-flight and success states are captured.
      await tapAppButton(
        tester,
        const ValueKey('mobile_send_confirm'),
        timeout: const Duration(minutes: 1),
      );
      await shot('25c_send_sending');
      await pumpUntil(
        tester,
        () => tester
            .any(find.byKey(const ValueKey('mobile_send_status_succeeded'))),
        description: 'send status to succeed',
        timeout: const Duration(minutes: 4),
      );
      await shot('25d_send_success');
      await tapAppButton(tester, const ValueKey('mobile_send_done'));
      await waitForHome(tester);

      // ── Activity tab ───────────────────────────────────────────────
      await openActivityTab(tester);
      await shot('26_activity');

      // ── Transaction status (Figma ACTIVITY & STATUS frames) ────────
      // The just-sent memo tx: sending (unmined) or sent state.
      await tapUntilVisible(
        tester,
        trigger: find.text('Sent').first,
        outcome: find.text('Status'),
        description: 'sent tx status screen',
      );
      await shot('26b_tx_status_sent');
      await tapWidget(
        tester,
        const ValueKey('mobile_tx_status_toggle_address'),
      );
      await settle(tester, const Duration(milliseconds: 400));
      await shot('26c_tx_status_full_address');
      await tapWidget(
        tester,
        const ValueKey('mobile_tx_status_toggle_address'),
      );
      await settle(tester, const Duration(milliseconds: 400));
      await tapWidget(
        tester,
        const ValueKey('mobile_tx_status_message_toggle'),
      );
      await settle(tester, const Duration(milliseconds: 400));
      await shot('26d_tx_status_message');
      await tapUntilVisible(
        tester,
        trigger: find.bySemanticsLabel('Back'),
        outcome: find.byKey(const ValueKey('mobile_activity_row_0')),
        description: 'back to activity',
      );
      // A mined funding tx: the received completed state.
      await tapUntilVisible(
        tester,
        trigger: find.text('Received').first,
        outcome: find.text('Completed'),
        description: 'received tx status screen',
      );
      await shot('26e_tx_status_received');
      await tapUntilVisible(
        tester,
        trigger: find.bySemanticsLabel('Back'),
        outcome: find.byKey(const ValueKey('mobile_activity_row_0')),
        description: 'back to activity again',
      );

      // ── Settings + change passcode ─────────────────────────────────
      await tapUntilVisible(
        tester,
        trigger: find.bySemanticsLabel('Settings'),
        outcome: find.text('Password'),
        description: 'settings tab',
      );
      await shot('27_settings');
      await tapWidget(tester, const ValueKey('mobile_settings_theme_row'));
      await shot('28_theme_sheet');
      await tapUntilVisible(
        tester,
        trigger: find.text('Cancel'),
        outcome: find.text('Password'),
        description: 'theme sheet closed',
      );
      await tapUntilVisible(
        tester,
        trigger: find.text('Password'),
        outcome: find.text('Enter Passcode'),
        description: 'change passcode verify',
      );
      await shot('29_change_passcode_verify');
      await enterPasscode(tester, mobileE2ePasscode);
      await pumpUntil(
        tester,
        () => tester.any(find.text('Update Passcode')),
        description: 'change passcode new',
      );
      await shot('30_change_passcode_new');
      await tapBack(tester);

      // ── Settings: secret passphrase (gate + reveal) ────────────────
      await tapWidget(tester, const ValueKey('mobile_settings_seed_row'));
      await pumpUntil(
        tester,
        () => tester.any(find.text('Enter your passcode')),
        description: 'seed confirm access gate',
      );
      await shot('30b_seed_confirm_access');
      await enterPasscode(tester, mobileE2ePasscode);
      await pumpUntil(
        tester,
        () => tester.any(find.text('Birthday block height')),
        description: 'seed reveal',
        timeout: const Duration(minutes: 1),
      );
      await shot('30c_seed_reveal');
      await tapBack(tester);

      // ── Settings: endpoint (list + custom) ─────────────────────────
      await tapWidget(tester, const ValueKey('mobile_settings_endpoint_row'));
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_endpoint_tab_custom')),
        ),
        description: 'endpoint screen',
      );
      // The regtest endpoint is custom, so the screen opens on the
      // custom tab — switch to the preset list for its shot first.
      await tapWidget(tester, const ValueKey('mobile_endpoint_tab_list'));
      await settle(tester, const Duration(milliseconds: 400));
      await shot('30d_endpoint_list');
      await tapWidget(tester, const ValueKey('mobile_endpoint_tab_custom'));
      await settle(tester, const Duration(milliseconds: 400));
      await shot('30e_endpoint_custom');
      await tapBack(tester);

      // ── Settings: address book (empty → add → list) ────────────────
      await tapWidget(
        tester,
        const ValueKey('mobile_settings_address_book_row'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_address_book_add_empty')),
        ),
        description: 'address book empty state',
      );
      await shot('30f_address_book_empty');
      await tapAppButton(
        tester,
        const ValueKey('mobile_address_book_add_empty'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_address_book_save')),
        ),
        description: 'add contact sheet',
      );
      await tester.enterText(
        find.byKey(const ValueKey('mobile_address_book_label')),
        'Tea house',
      );
      await tester.enterText(
        find.byKey(const ValueKey('mobile_address_book_address')),
        // Regtest transparent prefix passes the format validator.
        'tmEEzy3GZ8bQyaQXAbtnoVHBjDPSDfWPSkE',
      );
      await settle(tester, const Duration(milliseconds: 300));
      // Drop the keyboard so the whole form is in the shot and the save
      // button cannot be obscured regardless of the simulator's active
      // keyboard (a Korean layout with candidate bar is taller).
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester, const Duration(milliseconds: 400));
      await shot('30g_address_book_add');
      await tapAppButton(tester, const ValueKey('mobile_address_book_save'));
      // 'Tea house' alone is satisfied by the form field itself — wait
      // for the sheet to actually close.
      await pumpUntil(
        tester,
        () =>
            !tester.any(
              find.byKey(const ValueKey('mobile_address_book_save')),
            ) &&
            tester.any(find.text('Tea house')),
        description: 'contact saved and sheet closed',
      );
      await settle(tester, const Duration(milliseconds: 300));
      await shot('30h_address_book_list');
      await tapBack(tester);

      // ── Add-account create onboarding (static screens) ────────────
      await openHomeTab(tester);
      await openAddAccountFlow(tester);
      await shot('31_welcome_add_account');
      await tapAppButton(tester, const ValueKey('mobile_welcome_keystone'));
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_keystone_intro_continue')),
        ),
        description: 'keystone intro',
      );
      await shot('31b_keystone_intro');
      await tapBack(tester);
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey('mobile_welcome_create'))),
        description: 'back on add-account welcome',
      );
      await tapAppButton(tester, const ValueKey('mobile_welcome_create'));
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey('mobile_intro_continue'))),
        description: 'intro screen',
      );
      await shot('32_intro');
      await tapAppButton(tester, const ValueKey('mobile_intro_continue'));
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_address_types_continue')),
        ),
        description: 'address types screen',
      );
      await shot('33_address_types');
      await tapAppButton(
        tester,
        const ValueKey('mobile_address_types_continue'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_things_to_know_continue')),
        ),
        description: 'things to know screen',
      );
      await shot('34_things_to_know');
      await tapAppButton(
        tester,
        const ValueKey('mobile_things_to_know_continue'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_secret_passphrase_primary')),
        ),
        description: 'secret passphrase screen',
      );
      await shot('35_passphrase_hidden');
      await tapAppButton(
        tester,
        const ValueKey('mobile_secret_passphrase_primary'),
      );
      await shot('36_passphrase_revealed');

      logE2e('tour complete');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}


/// Dismisses any open sheets/pushed screens until the home balance
/// card is visible again.
Future<void> escapeToHome(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  final home = find.byKey(const ValueKey('mobile_home_shielded_balance'));
  while (!tester.any(home)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out escaping back to home');
    }
    final cancel = find.text('Cancel');
    final back = find.bySemanticsLabel('Back');
    if (tester.any(cancel)) {
      await tester.tap(cancel.first, warnIfMissed: false);
    } else if (tester.any(back)) {
      await tester.tap(back.first, warnIfMissed: false);
    }
    await settle(tester, const Duration(milliseconds: 600));
  }
  logE2e('escaped to home');
}
