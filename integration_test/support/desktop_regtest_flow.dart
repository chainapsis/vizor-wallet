import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

const desktopRegtestMnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const secondDesktopRegtestMnemonic =
    'return try reason flat civil wolf dwarf announce toddler uphold equip '
    'range neck proof gauge east rifle swim tray twin venue fossil will '
    'version';
const desktopRegtestPassword = 'Vizor123!';
var _nextE2ePointer = 1000;

int _takeE2ePointer() => _nextE2ePointer++;

Future<void> importDesktopRegtestWallet(WidgetTester tester) async {
  await tapAppButton(tester, const ValueKey('welcome_import_wallet_button'));
  await enterAppText(
    tester,
    const ValueKey('import_mnemonic_first_word_field'),
    desktopRegtestMnemonic,
  );
  await tapAppButton(tester, const ValueKey('import_secret_submit_button'));
  await tapAppButton(tester, const ValueKey('import_birthday_skip_button'));
  await tapAppButton(tester, const ValueKey('unknown_birthday_confirm_button'));
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
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'desktop home to render',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> importAdditionalDesktopRegtestWallet(WidgetTester tester) async {
  await tapAppWidget(tester, const ValueKey('sidebar_accounts_button'));
  await tapAppWidget(tester, const ValueKey('sidebar_accounts_add'));
  await pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('welcome_import_wallet_button'))),
    description: 'add-account import option',
  );
  await tapAppButton(tester, const ValueKey('welcome_import_wallet_button'));
  await enterAppText(
    tester,
    const ValueKey('import_mnemonic_first_word_field'),
    secondDesktopRegtestMnemonic,
  );
  await tapAppButton(tester, const ValueKey('import_secret_submit_button'));
  await tapAppButton(tester, const ValueKey('import_birthday_skip_button'));
  await tapAppButton(tester, const ValueKey('unknown_birthday_confirm_button'));
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'home after importing an additional account',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> switchDesktopRegtestAccount(
  WidgetTester tester,
  String accountUuid,
) async {
  await tapAppWidget(tester, const ValueKey('sidebar_accounts_button'));
  await tapAppWidget(
    tester,
    ValueKey('sidebar_account_popover_row_$accountUuid'),
  );
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'home after account switch',
    timeout: const Duration(minutes: 2),
  );
}

Future<List<rust_wallet.AccountInfo>> desktopRegtestAccounts() {
  return getWalletDbPath().then(
    (dbPath) => rust_wallet.listAccounts(dbPath: dbPath, network: 'regtest'),
  );
}

Future<void> unlockDesktopRegtestWallet(WidgetTester tester) async {
  await enterAppText(
    tester,
    const ValueKey('unlock_password_field'),
    desktopRegtestPassword,
  );
  await tapAppButton(tester, const ValueKey('unlock_submit_button'));
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'desktop home after unlock',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> dismissIronwoodAnnouncement(WidgetTester tester) async {
  final overlay = find.byKey(
    const ValueKey('ironwood_migration_announcement_overlay'),
  );
  final origin = tester.getTopLeft(overlay);
  await tester.tapAt(origin + const Offset(16, 16), pointer: _takeE2ePointer());
  await tester.pump(const Duration(milliseconds: 250));
  await pumpUntil(
    tester,
    () => !tester.any(
      find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
    ),
    description: 'dismissed Ironwood announcement',
  );
}

Future<void> openPrivateMigrationReview(WidgetTester tester) async {
  await tapAppButton(
    tester,
    const ValueKey('home_desktop_ironwood_migration_cta_button'),
  );
  await tapAppButton(
    tester,
    const ValueKey('ironwood_migration_intro_continue_button'),
  );
  await tapAppButton(
    tester,
    const ValueKey('ironwood_migration_how_it_works_continue_button'),
  );
  await tapAppWidget(
    tester,
    const ValueKey('ironwood_migration_private_option'),
  );
  await tapAppButton(
    tester,
    const ValueKey('ironwood_migration_select_review_button'),
  );
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('ironwood_migration_review_screen')),
    ),
    description: 'private migration review',
  );
}

Future<String> firstDesktopRegtestAccountUuid() async {
  final accounts = await rust_wallet.listAccounts(
    dbPath: await getWalletDbPath(),
    network: 'regtest',
  );
  if (accounts.length != 1) {
    throw StateError('Expected one regtest account, found ${accounts.length}.');
  }
  return accounts.single.uuid;
}

Future<rust_sync.MigrationStatus> desktopRegtestMigrationStatus(
  String accountUuid,
) {
  return getWalletDbPath().then(
    (dbPath) => rust_sync.getOrchardMigrationStatus(
      dbPath: dbPath,
      network: 'regtest',
      accountUuid: accountUuid,
    ),
  );
}

Future<void> cleanupDesktopRegtestWallet() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError(
      'Refusing to clean wallet state without ZCASH_DEFAULT_NETWORK=regtest.',
    );
  }

  await stopRustWorkForCleanup();
  final storage = AppSecureStore.instance;
  final dbName = await getWalletDbName();
  await storage.deleteAll();

  final preferences = await SharedPreferences.getInstance();
  await preferences.remove(ironwoodActiveSeenStorageKey('regtest'));
  for (final key in preferences.getKeys()) {
    if (key.startsWith('zcash_ironwood_migration_announcement_seen_regtest_')) {
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
}

Future<void> tapAppButton(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await pumpUntil(
    tester,
    () =>
        tester.any(finder) &&
        tester.widget<AppButton>(finder).onPressed != null,
    description: '$key button to be enabled',
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder, pointer: _takeE2ePointer());
  await tester.pump(const Duration(milliseconds: 250));
  e2eLog('tapped $key');
}

Future<void> tapAppWidget(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await pumpUntil(
    tester,
    () => tester.any(finder),
    description: '$key widget to render',
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder, pointer: _takeE2ePointer());
  await tester.pump(const Duration(milliseconds: 250));
  e2eLog('tapped $key');
}

Future<void> enterAppText(WidgetTester tester, Key key, String text) async {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  await pumpUntil(
    tester,
    () => tester.any(editable),
    description: '$key editable text field',
  );
  await tester.tap(editable, pointer: _takeE2ePointer());
  await tester.enterText(editable, text);
  await tester.pump(const Duration(milliseconds: 100));
  final editableText = tester.widget<EditableText>(editable);
  final actualText = editableText.controller.text;
  if (actualText.isEmpty) {
    fail('$key did not receive text input.');
  }
  // Pasted mnemonics distribute across multiple controllers, so notify with
  // the value retained by this field rather than the original input string.
  editableText.onChanged?.call(actualText);
  await tester.pump(const Duration(milliseconds: 100));
}

String? textForKey(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  if (!tester.any(finder)) return null;
  return tester.widget<Text>(finder).data;
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  Object? lastError;
  var polls = 0;
  while (DateTime.now().isBefore(end)) {
    try {
      if (condition()) return;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    polls++;
    if (polls % 50 == 0) e2eLog('still waiting for $description');
  }
  final detail = lastError == null ? '' : ' Last error: $lastError';
  fail('Timed out waiting for $description.$detail');
}

Future<Map<String, Object?>> ironwoodDriverGet(
  String driverUrl,
  String path, {
  Duration timeout = const Duration(minutes: 5),
}) {
  return _ironwoodDriverRequest(driverUrl, 'GET', path, const {}, timeout);
}

Future<Map<String, Object?>> ironwoodDriverPost(
  String driverUrl,
  String path, {
  Map<String, Object?> payload = const {},
  Duration timeout = const Duration(minutes: 5),
}) {
  return _ironwoodDriverRequest(driverUrl, 'POST', path, payload, timeout);
}

Future<Map<String, Object?>> _ironwoodDriverRequest(
  String driverUrl,
  String method,
  String path,
  Map<String, Object?> payload,
  Duration timeout,
) async {
  final client = HttpClient();
  try {
    final request = await client
        .openUrl(method, Uri.parse('$driverUrl$path'))
        .timeout(timeout);
    if (method == 'POST') {
      final body = utf8.encode(jsonEncode(payload));
      request.headers.contentType = ContentType.json;
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Ironwood E2E driver $path failed: HTTP ${response.statusCode}\n$body',
      );
    }
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

void e2eLog(String message) {
  debugPrint('[ironwood-flutter-e2e] $message');
}
