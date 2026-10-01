// Transparent history qualification suite, app layer (desktop, public mode).
//
// Run through scripts/e2e/transparent-history-cases.sh --flutter desktop: the
// Rust layer builds H01-H13 on an isolated regtest chain, keeps it alive, and
// hands over runtime mnemonics and oracle expectations as --dart-defines.
// This test restores Alice's two seeds into the app (a fresh restore, variant
// N) and checks every expected activity row and its detail screen.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';

import 'support/desktop_activity_flow.dart';
import 'support/desktop_onboarding_flow.dart';
import 'support/desktop_regtest_flow.dart';
import 'support/transparent_history_cases_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('H01-H13 activity after a fresh restore (desktop, public mode)', (
    tester,
  ) async {
    final rows = thExpectedUiRows();
    addTearDown(cleanupDesktopRegtestWallet);
    await cleanupDesktopRegtestWallet();
    // Swap rows are mainnet-gated; H11 needs them to show retained records.
    await tester.pumpWidget(
      await buildBootstrappedZcashWalletApp(
        overrides: [swapFeatureEnabledProvider.overrideWithValue(true)],
      ),
    );

    await _importSeed(tester, thA0Mnemonic, first: true);
    await _importSeed(tester, thA1Mnemonic, first: false);
    final uuids = {
      'A0': await thAccountUuidAtOrder(0),
      'A1': await thAccountUuidAtOrder(1),
    };

    final failures = <String>[];
    for (final account in ['A0', 'A1']) {
      final expected = rows.where((r) => r.account == account).toList();
      if (expected.isEmpty) continue;
      await switchDesktopRegtestAccount(tester, uuids[account]!);
      await thWaitForHistory(
        tester,
        accountUuid: uuids[account]!,
        rows: expected,
      );
      await _openActivity(tester);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      failures.addAll(
        await thVerifyActivity(
          tester,
          account: account,
          rows: expected,
          ticker: kZcashDefaultCurrencyTicker,
          mobile: false,
          dragAt: Offset(size.width * 0.6, size.height * 0.5),
          returnToActivity: () => _openActivity(tester),
        ),
      );
      if (account == 'A0' && expected.any((r) => r.intent == 'swap_deposit')) {
        failures.addAll(
          await thVerifySwapRecord(
            tester,
            rows: expected,
            accountUuid: uuids[account]!,
            dragAt: Offset(size.width * 0.6, size.height * 0.5),
            reopenActivity: () => _openActivity(tester),
          ),
        );
      }
    }
    final checked = rows.length;
    e2eLog('checked $checked expected rows; ${failures.length} failures');
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 40)));
}

Future<void> _importSeed(
  WidgetTester tester,
  String mnemonic, {
  required bool first,
}) async {
  if (!first) {
    await tapAppWidget(tester, const ValueKey('sidebar_accounts_button'));
    await tapAppWidget(tester, const ValueKey('sidebar_accounts_add'));
  }
  await tapAppButton(tester, const ValueKey('welcome_import_wallet_button'));
  // The import screen can render its field before it accepts input; retry.
  for (var attempt = 0; ; attempt++) {
    await tester.pump(const Duration(milliseconds: 500));
    try {
      await enterAppText(
        tester,
        const ValueKey('import_mnemonic_first_word_field'),
        mnemonic,
      );
      break;
    } on TestFailure {
      if (attempt >= 3) rethrow;
    }
  }
  await tapAppButton(tester, const ValueKey('import_secret_submit_button'));
  await tapAppButton(tester, const ValueKey('import_birthday_skip_button'));
  await tapAppButton(tester, const ValueKey('unknown_birthday_confirm_button'));
  if (first) {
    await enterAppText(
      tester,
      const ValueKey('set_password_password_field'),
      desktopRegtestPassword,
    );
    await enterAppText(
      tester,
      const ValueKey('set_password_confirm_field'),
      desktopRegtestPassword,
    );
    await tapAppButton(tester, const ValueKey('set_password_submit_button'));
  }
  await finishDesktopAccountCustomisation(tester);
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'desktop home after import',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> _openActivity(WidgetTester tester) async {
  // The feed is a lazy sliver: once scrolled, its title row may not be built,
  // so any activity row also proves the screen is showing.
  bool showing() =>
      tester.any(find.byKey(const ValueKey('activity_screen_title_row'))) ||
      tester.any(desktopActivityRowsFinder());
  if (!showing()) {
    // From a transaction detail the sidebar's Activity item is a no-op (the
    // matched location is already /activity), so navigate explicitly.
    GoRouter.of(tester.element(find.byType(Navigator).first)).go('/activity');
    await tester.pump(const Duration(milliseconds: 400));
  }
  if (!showing()) {
    await tapAppWidget(tester, const ValueKey('sidebar_activity_button'));
  }
  await pumpUntil(
    tester,
    showing,
    description: 'activity screen',
    timeout: const Duration(minutes: 1),
  );
}
