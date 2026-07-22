/// Shared driver for the mobile regtest E2E tests: pump/tap/enter
/// helpers, regtest-guarded wallet-state cleanup, and flow primitives
/// for the mobile UI (passcode onboarding, paste import, accounts
/// sheet, send wizard). The desktop regtest tests keep their own
/// per-file copies; this file is the mobile counterpart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

const mobileE2ePasscode = '111111';
const mobileIronwoodE2eMnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';

/// 'TAZ' on regtest; activity amounts and the balance card follow it.
final mobileE2eTicker = kZcashDefaultCurrencyTicker;
const mobileE2eNetwork = String.fromEnvironment(
  'ZCASH_E2E_NETWORK',
  defaultValue: 'regtest',
);
const mobileE2eLightwalletdUrl = String.fromEnvironment(
  'ZCASH_E2E_LIGHTWALLETD_URL',
  defaultValue: 'http://127.0.0.1:9067',
);
const mobileE2eZcashdRpcUrl = String.fromEnvironment(
  'ZCASH_E2E_ZCASHD_RPC_URL',
  defaultValue: 'http://127.0.0.1:18232',
);
const _zcashdRpcUser = 'zcash';
const _zcashdRpcPassword = 'zcash';
const _accountsKey = 'zcash_accounts';

void logE2e(String message) {
  debugPrint('[mobile-$mobileE2eNetwork-e2e] $message');
}

/// Keeps cosmetic RenderFlex overflows (a few px on the 393pt frame
/// with device fonts) from failing functional E2E runs. Everything
/// else still fails the test. MUST be called INSIDE the testWidgets
/// body — the test framework installs its own FlutterError.onError per
/// test, so wrapping any earlier handler has no effect.
void tolerateRenderOverflows() {
  final defaultHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final exception = details.exception;
    if (exception is FlutterError &&
        exception.message.contains('RenderFlex overflowed')) {
      logE2e('tolerated overflow: ${exception.message}');
      return;
    }
    defaultHandler?.call(details);
  };
}

// ── Generic pump/tap/enter helpers ───────────────────────────────────

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  Object? lastError;
  var polls = 0;
  while (DateTime.now().isBefore(end)) {
    try {
      if (condition()) return;
    } catch (e) {
      lastError = e;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    polls++;
    if (polls % 25 == 0) {
      logE2e('still waiting for $description');
    }
  }

  final error = lastError == null ? '' : ' Last error: $lastError';
  fail('Timed out waiting for $description.$error');
}

Future<void> tapAppButton(
  WidgetTester tester,
  Key key, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final keyed = find.byKey(key);
  final finder = find.descendant(
    of: keyed,
    matching: find.byType(AppButton),
    matchRoot: true,
  );
  await pumpUntil(
    tester,
    () =>
        tester.any(finder) &&
        tester.widget<AppButton>(finder).onPressed != null,
    description: '$key button to be enabled',
    timeout: timeout,
  );
  await tester.ensureVisible(keyed);
  await tester.pump(const Duration(milliseconds: 100));
  final hitTestable = finder.hitTestable();
  await pumpUntil(
    tester,
    () =>
        tester.any(hitTestable) &&
        tester.widget<AppButton>(finder).onPressed != null,
    description: '$key button to be tappable',
    timeout: timeout,
  );
  await tester.tap(hitTestable);
  await tester.pump(const Duration(milliseconds: 250));
  logE2e('tapped $key');
}

Future<void> tapWidget(
  WidgetTester tester,
  Key key, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final finder = find.byKey(key);
  await pumpUntil(
    tester,
    () => tester.any(finder),
    description: '$key widget to render',
    timeout: timeout,
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
  logE2e('tapped $key');
}

/// Taps [trigger] until [outcome] renders — route pushes and sheet
/// opens can swallow a tap that lands mid-transition, so drive by
/// outcome with retries throttled past the transition.
Future<void> tapUntilVisible(
  WidgetTester tester, {
  required Finder trigger,
  required Finder outcome,
  required String description,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  while (!tester.any(outcome)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    if (tester.any(trigger) &&
        DateTime.now().difference(lastTap) > const Duration(seconds: 2)) {
      lastTap = DateTime.now();
      await tester.tap(trigger.first, warnIfMissed: false);
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  logE2e('reached $description');
}

Future<void> enterText(WidgetTester tester, Key key, String text) async {
  // matchRoot covers keys that sit on the EditableText itself.
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
    matchRoot: true,
  );
  await pumpUntil(
    tester,
    () => tester.any(editable),
    description: '$key editable text field',
  );
  await tester.tap(editable);
  await tester.enterText(editable, text);
  await tester.pump(const Duration(milliseconds: 100));
  logE2e('entered text into $key');
}

/// Passcode/numpad keys are semantics-labeled, not keyed.
Future<void> enterPasscode(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    final finder = find.bySemanticsLabel('Digit $digit');
    await pumpUntil(
      tester,
      () => tester.any(finder),
      description: 'digit $digit key',
    );
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 150));
  }
  logE2e('entered passcode');
}

bool keyedTextEquals(WidgetTester tester, Key key, String expected) {
  return textForKey(tester, key) == expected;
}

/// Reads the plain text behind [key]; supports both Text and Text.rich.
String? textForKey(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  if (!tester.any(finder)) return null;
  final widget = tester.widget(finder);
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  return null;
}

Set<String> textSetIn(WidgetTester tester, Finder finder) {
  if (!tester.any(finder)) return const {};
  final texts = find.descendant(of: finder, matching: find.byType(Text));
  return tester
      .widgetList<Text>(texts)
      .map((text) => text.data ?? text.textSpan?.toPlainText())
      .whereType<String>()
      .toSet();
}

// ── Wallet state cleanup (regtest-guarded) ───────────────────────────

Future<void> cleanupE2eWalletState() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError(
      'Refusing to clean wallet state without ZCASH_DEFAULT_NETWORK=regtest.',
    );
  }

  final storage = AppSecureStore.instance;
  final dbName = await getWalletDbName();

  logE2e('cleaning regtest wallet state');
  await stopRustWorkForCleanup();

  await storage.deleteAll();

  final preferences = await SharedPreferences.getInstance();
  await preferences.remove(ironwoodActiveSeenStorageKey(mobileE2eNetwork));
  for (final key in preferences.getKeys()) {
    if (key.startsWith(
      'zcash_ironwood_migration_announcement_seen_${mobileE2eNetwork}_',
    )) {
      await preferences.remove(key);
    }
  }

  final supportDir = await getWalletSupportDirectory();
  if (!supportDir.existsSync()) return;

  for (final name in [dbName, '$dbName-shm', '$dbName-wal']) {
    final file = File('${supportDir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) file.deleteSync();
  }
}

Future<void> stopRustWorkForCleanup() async {
  rust_sync.setSyncMode(mode: 0);
  rust_sync.cancelFullSync();
  rust_sync.stopMempoolObserver();

  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while ((rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  if (rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) {
    logE2e(
      'timed out waiting for Rust work to stop; continuing E2E storage cleanup',
    );
  }
}

Future<void> snapshotWalletDbToDriver() async {
  await stopRustWorkForCleanup();
  final supportDir = await getWalletSupportDirectory();
  final dbName = await getWalletDbName();
  final snapshot = <String, Object?>{};
  for (final entry in {
    'db': dbName,
    'wal': '$dbName-wal',
    'shm': '$dbName-shm',
  }.entries) {
    final file = File(
      '${supportDir.path}${Platform.pathSeparator}${entry.value}',
    );
    if (file.existsSync()) {
      snapshot[entry.key] = base64Encode(await file.readAsBytes());
    }
  }
  if (!snapshot.containsKey('db')) {
    fail('Wallet database was missing before the process-restart snapshot.');
  }
  await postDriver('/wallet-snapshot', {'files': snapshot});
  logE2e('saved wallet DB snapshot for process restart');
}

Future<void> restoreWalletDbFromDriver() async {
  await stopRustWorkForCleanup();
  final response = await getDriver('/wallet-snapshot');
  final encodedFiles = response['files'];
  if (encodedFiles is! Map) {
    fail('E2E driver returned an invalid wallet DB snapshot.');
  }

  final supportDir = await getWalletSupportDirectory();
  final dbName = await getWalletDbName();
  final names = {'db': dbName, 'wal': '$dbName-wal', 'shm': '$dbName-shm'};
  for (final name in names.values) {
    final file = File('${supportDir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) file.deleteSync();
  }
  for (final entry in encodedFiles.entries) {
    final name = names[entry.key];
    if (name == null || entry.value is! String) {
      fail('E2E driver returned an unsupported wallet DB snapshot file.');
    }
    final file = File('${supportDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(base64Decode(entry.value as String), flush: true);
  }
  logE2e('restored wallet DB snapshot after test-runner reinstall');
}

// ── Mobile flow primitives ───────────────────────────────────────────

/// Welcome → create flow → passcode ×2 → biometrics → home.
Future<void> createWalletWithPasscode(WidgetTester tester) async {
  logE2e('creating wallet');
  await tapWidget(tester, const ValueKey('mobile_welcome_get_started'));
  await tapWidget(tester, const ValueKey('mobile_welcome_create'));
  await tapAppButton(tester, const ValueKey('mobile_intro_continue'));
  await tapAppButton(tester, const ValueKey('mobile_address_types_continue'));
  await tapAppButton(tester, const ValueKey('mobile_things_to_know_continue'));
  await tapAppButton(
    tester,
    const ValueKey('mobile_secret_passphrase_primary'),
  );
  await tapAppButton(
    tester,
    const ValueKey('mobile_secret_passphrase_primary'),
  );
  await enterPasscode(tester, mobileE2ePasscode);
  await enterPasscode(tester, mobileE2ePasscode);
  await tapWidget(
    tester,
    const ValueKey('mobile_biometrics_not_now'),
    timeout: const Duration(seconds: 90),
  );
  await waitForHome(tester);
  logE2e('wallet created');
}

/// Welcome → import (clipboard paste) → review → birthday height → passcode
/// (first wallet only) → home.
Future<void> importWalletViaPaste(
  WidgetTester tester, {
  required String mnemonic,
  required int birthdayHeight,
  required bool isFirstWallet,
}) async {
  logE2e('importing wallet (first=$isFirstWallet)');
  await tapWidget(tester, const ValueKey('mobile_welcome_get_started'));
  await tapWidget(tester, const ValueKey('mobile_welcome_import'));
  await Clipboard.setData(ClipboardData(text: mnemonic));
  await tapAppButton(tester, const ValueKey('mobile_import_paste'));
  await tapAppButton(tester, const ValueKey('mobile_import_review_continue'));
  // Block height is a real text field on the system keyboard.
  await tapWidget(tester, const ValueKey('mobile_import_birthday_mode_height'));
  await tester.enterText(
    find.byKey(const ValueKey('mobile_import_birthday_height')),
    '$birthdayHeight',
  );
  await tester.pump();
  await tapAppButton(
    tester,
    const ValueKey('mobile_import_birthday_continue'),
    timeout: const Duration(minutes: 1),
  );
  if (isFirstWallet) {
    await enterPasscode(tester, mobileE2ePasscode);
    await enterPasscode(tester, mobileE2ePasscode);
    await tapWidget(
      tester,
      const ValueKey('mobile_biometrics_not_now'),
      timeout: const Duration(seconds: 90),
    );
  }
  await waitForHome(tester);
  logE2e('wallet imported');
}

Future<void> waitForHome(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('mobile_home_shielded_balance'))),
    description: 'home balance card to render',
    timeout: const Duration(minutes: 1),
  );
}

Future<void> openMobilePrivateMigrationReview(WidgetTester tester) async {
  await openMobileMigrationOptions(tester);
  await tapAppButton(
    tester,
    const ValueKey('mobile_ironwood_options_continue_button'),
    timeout: const Duration(minutes: 2),
  );
  await pumpUntil(
    tester,
    () {
      final keyed = find.byKey(
        const ValueKey('mobile_ironwood_authorize_start_button'),
      );
      final button = find.descendant(
        of: keyed,
        matching: find.byType(AppButton),
        matchRoot: true,
      );
      return tester.any(button) &&
          tester.widget<AppButton>(button).onPressed != null;
    },
    description: 'mobile private migration review plan',
    timeout: const Duration(minutes: 3),
  );
}

/// Opens the choice screen after the migration announcement, intro, and
/// explanation steps. Callers choose either Private or Immediate from here.
Future<void> openMobileMigrationOptions(WidgetTester tester) async {
  final announcementSheet = find.byKey(
    const ValueKey('mobile_ironwood_announcement_sheet'),
  );
  final announcementStart = find.byKey(
    const ValueKey('mobile_ironwood_start_migration_button'),
  );
  final homeCta = find.byKey(
    const ValueKey('mobile_home_ironwood_migration_required_pill'),
  );
  final intro = find.byKey(
    const ValueKey('mobile_ironwood_intro_continue_button'),
  );
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  var lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  while (tester.any(announcementSheet) || !tester.any(intro.hitTestable())) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out entering the mobile Ironwood migration flow.');
    }
    if (DateTime.now().difference(lastTap) > const Duration(seconds: 1)) {
      final tappableAnnouncementStart = announcementStart.hitTestable();
      final tappableHomeCta = homeCta.hitTestable();
      if (tester.any(tappableAnnouncementStart)) {
        lastTap = DateTime.now();
        await tester.tap(tappableAnnouncementStart);
      } else if (!tester.any(announcementSheet) &&
          tester.any(tappableHomeCta)) {
        lastTap = DateTime.now();
        await tester.tap(tappableHomeCta);
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  logE2e('entered mobile Ironwood migration flow');

  await tapAppButton(
    tester,
    const ValueKey('mobile_ironwood_intro_continue_button'),
  );
  await tapAppButton(
    tester,
    const ValueKey('mobile_ironwood_steps_continue_button'),
    timeout: const Duration(minutes: 2),
  );
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('mobile_ironwood_immediate_option')),
    ),
    description: 'mobile migration options',
    timeout: const Duration(minutes: 2),
  );
}

/// The mobile balance card renders e.g. `1.25 ZEC` (rich text).
Future<void> waitForShieldedBalance(
  WidgetTester tester,
  String expected, {
  Duration timeout = const Duration(minutes: 4),
}) async {
  await pumpUntil(
    tester,
    () => keyedTextEquals(
      tester,
      const ValueKey('mobile_home_shielded_balance'),
      expected,
    ),
    description: 'shielded balance to show "$expected"',
    timeout: timeout,
  );
  logE2e('shielded balance matched: $expected');
}

Future<void> openAccountsSheet(WidgetTester tester) async {
  await tapUntilVisible(
    tester,
    trigger: find.byKey(const ValueKey('mobile_top_nav_account')),
    outcome: find.text('Manage accounts'),
    description: 'accounts sheet to open',
  );
  // Let the sheet's entrance animation finish — a tap dispatched while
  // the sheet is still sliding up uses the in-flight coordinates and
  // can land on the tab bar underneath.
  await settle(tester, const Duration(milliseconds: 600));
}

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Accounts sheet → add account → welcome (back variant). Re-opens the
/// sheet when a stray tap dismissed it.
Future<void> openAddAccountFlow(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  final welcome = find.byKey(const ValueKey('mobile_welcome_get_started'));
  final addButton = find.byKey(const ValueKey('mobile_accounts_add'));
  while (!tester.any(welcome)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for add-account welcome screen');
    }
    if (!tester.any(addButton)) {
      await openAccountsSheet(tester);
    }
    if (tester.any(addButton)) {
      await tester.tap(addButton, warnIfMissed: false);
      await settle(tester, const Duration(milliseconds: 600));
    }
  }
  logE2e('reached add-account welcome screen');
}

Future<void> switchAccountTo(WidgetTester tester, String accountUuid) async {
  logE2e('switching account to $accountUuid');
  await openAccountsSheet(tester);
  await tapWidget(tester, ValueKey('account_row_$accountUuid'));
  await settle(tester, const Duration(milliseconds: 400));
  await waitForHome(tester);
}

/// Home → receive screen → copy → back. Returns the copied address.
Future<String> copyShieldedAddress(WidgetTester tester) async {
  await tapWidget(tester, const ValueKey('mobile_home_receive'));
  await tapWidget(
    tester,
    const ValueKey('mobile_receive_copy'),
    timeout: const Duration(minutes: 1),
  );
  // The copy button only enables once the address loads; the tap above
  // is plain, so wait for the toast as the copy signal.
  await pumpUntil(
    tester,
    () => tester.any(find.text('Address copied')),
    description: 'address copied toast',
  );
  final data = await Clipboard.getData('text/plain');
  final address = data?.text?.trim() ?? '';
  if (address.isEmpty) {
    fail('Shielded address was not copied to the clipboard.');
  }
  await tapBack(tester);
  await waitForHome(tester);
  return address;
}

/// Taps the top-nav back chevron (semantics label 'Back').
Future<void> tapBack(WidgetTester tester) async {
  final finder = find.bySemanticsLabel('Back');
  await pumpUntil(tester, () => tester.any(finder), description: 'back button');
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 350));
  logE2e('tapped back');
}

/// Home → send wizard → recipient → amount → review → confirm →
/// succeeded status → done (back to home).
Future<void> sendViaWizard(
  WidgetTester tester, {
  required String address,
  required String amountDigits,
}) async {
  logE2e('sending $amountDigits via wizard');
  await tapWidget(tester, const ValueKey('mobile_home_send'));
  await enterText(tester, const ValueKey('mobile_send_address_field'), address);
  await tapAppButton(
    tester,
    const ValueKey('mobile_send_continue'),
    timeout: const Duration(minutes: 1),
  );
  await enterText(
    tester,
    const ValueKey('mobile_send_amount_input'),
    amountDigits,
  );
  await tapAppButton(
    tester,
    const ValueKey('mobile_send_review_button'),
    timeout: const Duration(minutes: 1),
  );
  await tapAppButton(
    tester,
    const ValueKey('mobile_send_confirm'),
    timeout: const Duration(minutes: 1),
  );
  await pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('mobile_send_status_succeeded'))),
    description: 'send status to succeed',
    timeout: const Duration(minutes: 4),
  );
  logE2e('send succeeded');
  await tapAppButton(tester, const ValueKey('mobile_send_status_button'));
  await waitForHome(tester);
}

/// Switches the tab shell to the Activity tab and waits for rows.
Future<void> openActivityTab(WidgetTester tester) async {
  await tapUntilVisible(
    tester,
    trigger: find.bySemanticsLabel('Activity'),
    outcome: _mobileActivityTransactionRows(),
    description: 'activity rows to render',
    timeout: const Duration(minutes: 1),
  );
}

Future<void> openHomeTab(WidgetTester tester) async {
  await tapUntilVisible(
    tester,
    trigger: find.bySemanticsLabel('Home'),
    outcome: find.byKey(const ValueKey('mobile_home_shielded_balance')),
    description: 'home tab to render',
    timeout: const Duration(minutes: 1),
  );
}

Future<void> expectActivityRow(
  WidgetTester tester,
  Key key, {
  required String title,
  required String amount,
  String? status,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var polls = 0;
  while (DateTime.now().isBefore(deadline)) {
    for (final row in _activityRowFinders(tester, key)) {
      final texts = textSetIn(tester, row);
      if (texts.contains(title) &&
          texts.contains(amount) &&
          (status == null || texts.contains(status))) {
        logE2e('activity row matched: $title $amount ${status ?? ''}');
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    polls++;
    if (polls % 50 == 0) {
      final observed = _activityRowFinders(
        tester,
        key,
      ).map((row) => textSetIn(tester, row)).toList();
      logE2e('waiting for $key row: $title $amount; seeing $observed');
    }
  }
  final observed = _activityRowFinders(
    tester,
    key,
  ).map((row) => textSetIn(tester, row)).toList();
  fail(
    'Timed out waiting for $key activity row to show $title $amount '
    '${status ?? ''}. Observed texts: $observed',
  );
}

void expectNoActivityRow(
  WidgetTester tester, {
  required String rowKeyPrefix,
  required String title,
  required String amount,
  String? status,
}) {
  final rows = rowKeyPrefix == 'mobile_activity'
      ? _findersFor(_mobileActivityRows())
      : [
          for (var i = 0; i < 10; i++)
            find.byKey(ValueKey('${rowKeyPrefix}_row_$i')),
        ];
  for (final row in rows) {
    final texts = textSetIn(tester, row);
    if (texts.contains(title) &&
        texts.contains(amount) &&
        (status == null || texts.contains(status))) {
      fail('Unexpected stale activity row: $title $amount $status');
    }
  }
  logE2e('no stale activity row matched: $title $amount ${status ?? ''}');
}

List<Finder> _activityRowFinders(WidgetTester tester, Key key) {
  if (key is ValueKey<String> && key.value.startsWith('mobile_activity_row_')) {
    return _findersFor(_mobileActivityRows());
  }
  return [find.byKey(key)];
}

List<Finder> _findersFor(Finder finder) => [
  for (var index = 0; index < finder.evaluate().length; index++)
    finder.at(index),
];

Finder _mobileActivityRows() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      (key.value.startsWith('tx:') ||
          key.value.startsWith('mobile_activity_row_'));
});

Finder _mobileActivityTransactionRows() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('tx:');
});

// ── Account/state inspection and chain control ──────────────────────

Future<String> accountUuidAtOrder(int order) async {
  final rawAccounts = await AppSecureStore.instance.readString(_accountsKey);
  if (rawAccounts == null || rawAccounts.trim().isEmpty) {
    fail('Expected stored accounts before reading account order $order.');
  }

  final decoded = jsonDecode(rawAccounts);
  if (decoded is! List) {
    fail('Expected stored accounts to be a JSON list.');
  }

  final accounts = <AccountInfo>[];
  for (final entry in decoded) {
    if (entry is! Map) {
      fail('Expected stored account entry to be a JSON object.');
    }
    accounts.add(AccountInfo.fromJson(Map<String, dynamic>.from(entry)));
  }
  accounts.sort((a, b) => a.order.compareTo(b.order));

  if (order >= accounts.length) {
    fail('Expected account order $order, got ${accounts.length} accounts.');
  }
  return accounts[order].uuid;
}

Future<rust_sync.MigrationStatus> mobileRegtestMigrationStatus(
  String accountUuid,
) async {
  return rust_sync.getOrchardMigrationStatus(
    dbPath: await getWalletDbPath(),
    network: mobileE2eNetwork,
    accountUuid: accountUuid,
  );
}

Future<rust_sync.MigrationStatus> waitForMobileRegtestMigrationStatus(
  WidgetTester tester,
  String accountUuid,
  bool Function(rust_sync.MigrationStatus status) condition, {
  required String description,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  rust_sync.MigrationStatus? lastStatus;
  var polls = 0;
  while (DateTime.now().isBefore(deadline)) {
    try {
      lastStatus = await mobileRegtestMigrationStatus(accountUuid);
      lastError = null;
      if (condition(lastStatus)) return lastStatus;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    polls++;
    if (polls % 20 == 0) logE2e('still waiting for $description');
  }

  final statusDetail = lastStatus == null
      ? ''
      : ' Last phase: ${lastStatus.phase}, run: ${lastStatus.activeRunId}, '
            'submitted: ${lastStatus.broadcastedTxCount + lastStatus.confirmedTxCount}/'
            '${lastStatus.totalCount}.';
  final errorDetail = lastError == null ? '' : ' Last error: $lastError';
  fail('Timed out waiting for $description.$statusDetail$errorDetail');
}

Future<rust_sync.MigrationStatus> advanceMobileRegtestMigrationSchedule(
  WidgetTester tester,
  String accountUuid, {
  int? submittedTarget,
  Duration timeout = const Duration(minutes: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = await mobileRegtestMigrationStatus(accountUuid);
    final submitted = status.broadcastedTxCount + status.confirmedTxCount;
    final target = submittedTarget ?? status.totalCount;
    if (target > 0 && submitted >= target) return status;

    final scheduled =
        status.scheduledBroadcasts
            .where((entry) => entry.status == 'scheduled')
            .toList()
          ..sort(
            (left, right) =>
                left.scheduledHeight.compareTo(right.scheduledHeight),
          );
    if (scheduled.isEmpty) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      continue;
    }

    final chain = await getDriver('/status');
    final currentHeight = (chain['zcashdHeight'] as num).toInt();
    final nextHeight = scheduled.first.scheduledHeight;
    if (nextHeight > currentHeight) {
      final blocks = nextHeight - currentHeight;
      logE2e(
        'mining $blocks block(s) to migration broadcast height $nextHeight',
      );
      await postDriver('/mine', {'blocks': blocks});
    }

    await waitForMobileRegtestMigrationStatus(
      tester,
      accountUuid,
      (next) => next.broadcastedTxCount + next.confirmedTxCount > submitted,
      description: 'migration transaction at block $nextHeight',
      timeout: const Duration(minutes: 2),
    );
  }
  fail('Timed out advancing the mobile regtest migration schedule.');
}

Future<Map<String, Object?>> waitForMobileRegtestMempoolSize(
  WidgetTester tester,
  int expected, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  Map<String, Object?>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await getDriver('/mempool');
    if (last['size'] == expected) return last;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for mempool size $expected. Last: $last');
}

Future<void> waitForHistoryEntry(
  WidgetTester tester, {
  required String accountUuid,
  required String txKind,
  required BigInt displayAmount,
  required bool pending,
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  Object? lastError;
  var lastHistorySummary = '<not read>';

  while (DateTime.now().isBefore(deadline)) {
    try {
      final history = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        limit: 20,
        accountUuid: accountUuid,
      );
      lastHistorySummary = history
          .map(
            (tx) =>
                '${tx.txidHex}:${tx.txKind}:${tx.displayAmount}:'
                'mined=${tx.minedHeight}:expired=${tx.expiredUnmined}',
          )
          .join(', ');
      if (history.any(
        (tx) =>
            tx.txKind == txKind &&
            tx.displayAmount == displayAmount &&
            (tx.minedHeight == BigInt.zero) == pending &&
            !tx.expiredUnmined,
      )) {
        logE2e('history matched $txKind tx amount=$displayAmount');
        return;
      }
    } catch (e) {
      lastError = e;
    }

    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  final error = lastError == null ? '' : ' Last error: $lastError';
  fail(
    'Timed out waiting for history $txKind amount=$displayAmount '
    'pending=$pending. Observed history: $lastHistorySummary.$error',
  );
}

Future<void> waitForMempoolObserver() async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    if (rust_sync.isMempoolObserverRunning()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for mempool observer to run.');
}

Future<void> mineRegtestBlocks(int blocks) async {
  logE2e('mining $blocks regtest blocks');

  final before = await zcashdRpc<int>('getblockcount');
  await zcashdRpc<List<Object?>>('generate', [blocks]);
  final targetHeight = before + blocks;
  final deadline = DateTime.now().add(const Duration(seconds: 30));

  while (DateTime.now().isBefore(deadline)) {
    final lightwalletdHeight = await rust_wallet.getLatestBlockHeight(
      lightwalletdUrl: mobileE2eLightwalletdUrl,
    );
    if (lightwalletdHeight.toInt() >= targetHeight) {
      logE2e('lightwalletd reached mined height $targetHeight');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  throw StateError('Timed out waiting for lightwalletd height $targetHeight.');
}

Future<T> zcashdRpc<T>(String method, [List<Object?> params = const []]) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(mobileE2eZcashdRpcUrl));
    final credentials = base64Encode(
      utf8.encode('$_zcashdRpcUser:$_zcashdRpcPassword'),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Basic $credentials')
      ..contentType = ContentType.json;
    request.write(
      jsonEncode({
        'jsonrpc': '1.0',
        'id': 'mobile-regtest-e2e',
        'method': method,
        'params': params,
      }),
    );

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'zcashd RPC $method failed: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(body) as Map<String, Object?>;
    final error = decoded['error'];
    if (error != null) {
      throw StateError('zcashd RPC $method failed: $error');
    }
    return decoded['result'] as T;
  } finally {
    client.close(force: true);
  }
}

// ── Host driver (python HTTP server started by the runner script) ────

const mobileE2eDriverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39067',
);

Future<Map<String, Object?>> postDriver(
  String path,
  Map<String, Object?> payload, {
  Duration timeout = const Duration(minutes: 2),
  String? baseUrl,
}) async {
  final client = HttpClient();
  try {
    final request = await client
        .postUrl(Uri.parse('${baseUrl ?? mobileE2eDriverUrl}$path'))
        .timeout(timeout);
    final bodyBytes = utf8.encode(jsonEncode(payload));
    request.headers.contentType = ContentType.json;
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);

    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'E2E driver $path failed: HTTP '
        '${response.statusCode}\n$body',
      );
    }
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> getDriver(
  String path, {
  Duration timeout = const Duration(minutes: 2),
  String? baseUrl,
}) async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(Uri.parse('${baseUrl ?? mobileE2eDriverUrl}$path'))
        .timeout(timeout);
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'E2E driver $path failed: HTTP ${response.statusCode}\n$body',
      );
    }
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

/// Sends an external unmined funding tx to [address]; returns the txid.
Future<String> fundUnmined(String address, String amount) async {
  logE2e('requesting external unmined funding of $amount to $address');
  final response = await postDriver('/fund-unmined', {
    'address': address,
    'amount': amount,
  }, timeout: const Duration(minutes: 5));
  final txid = response['txid'];
  if (txid is! String || txid.isEmpty) {
    throw StateError('E2E driver returned no txid: $response');
  }
  return txid;
}

/// Variant of [waitForHistoryEntry] that also matches the txid. zcashd
/// reports txids in display order while the wallet stores the internal
/// byte order, so both orientations are accepted.
Future<void> waitForHistoryTx(
  WidgetTester tester, {
  required String accountUuid,
  required String txidHex,
  required String txKind,
  required BigInt displayAmount,
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(const Duration(minutes: 4));
  Object? lastError;
  var lastHistorySummary = '<not read>';
  final acceptedTxids = {txidHex, reverseTxidHex(txidHex)};

  while (DateTime.now().isBefore(deadline)) {
    try {
      final history = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        limit: 20,
        accountUuid: accountUuid,
      );
      lastHistorySummary = history
          .map((tx) => '${tx.txidHex}:${tx.txKind}:${tx.displayAmount}')
          .join(', ');
      if (history.any(
        (tx) =>
            acceptedTxids.contains(tx.txidHex) &&
            tx.txKind == txKind &&
            tx.displayAmount == displayAmount &&
            !tx.expiredUnmined,
      )) {
        logE2e('history matched tx $txidHex');
        return;
      }
    } catch (e) {
      lastError = e;
    }

    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  final error = lastError == null ? '' : ' Last error: $lastError';
  fail(
    'Timed out waiting for history tx $txidHex ($txKind $displayAmount). '
    'Observed history: $lastHistorySummary.$error',
  );
}

/// Reverses a hex txid between display and internal byte order.
String reverseTxidHex(String txidHex) {
  final bytes = <String>[];
  for (var i = 0; i < txidHex.length; i += 2) {
    bytes.add(txidHex.substring(i, i + 2));
  }
  return bytes.reversed.join();
}
