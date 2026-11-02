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
import 'package:zcash_wallet/src/rust/api/network_privacy.dart'
    as rust_network_privacy;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'desktop_onboarding_flow.dart';

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
  await tapAppButton(
    tester,
    const ValueKey('welcome_import_wallet_button'),
  );
  await tapAppWidget(
    tester,
    const ValueKey('desktop_import_secret_passphrase_card'),
  );
  await enterAppText(
    tester,
    const ValueKey('import_mnemonic_first_word_field'),
    desktopRegtestMnemonic,
  );
  await tapAppButton(tester, const ValueKey('import_secret_submit_button'));
  await tapAppButton(tester, const ValueKey('import_birthday_skip_button'));
  await tapAppButton(tester, const ValueKey('unknown_birthday_confirm_button'));
  await finishDesktopAccountCustomisation(tester);
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
  await tapAppButton(
    tester,
    const ValueKey('welcome_import_wallet_button'),
  );
  await tapAppWidget(
    tester,
    const ValueKey('desktop_import_secret_passphrase_card'),
  );
  await enterAppText(
    tester,
    const ValueKey('import_mnemonic_first_word_field'),
    secondDesktopRegtestMnemonic,
  );
  await tapAppButton(tester, const ValueKey('import_secret_submit_button'));
  await tapAppButton(tester, const ValueKey('import_birthday_skip_button'));
  await tapAppButton(tester, const ValueKey('unknown_birthday_confirm_button'));
  await finishDesktopAccountCustomisation(tester);
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

/// Home's migration CTA through the intro, How it works and What to expect to
/// the migration options.
Future<void> openMigrationOptions(WidgetTester tester) async {
  await tapAppButton(
    tester,
    const ValueKey('home_desktop_ironwood_migration_cta_button'),
  );
  await tapAppButton(
    tester,
    const ValueKey('ironwood_migration_intro_continue_button'),
  );
  const next = ValueKey('ironwood_migration_how_it_works_continue_button');
  const whatToExpect = ValueKey(
    'ironwood_migration_what_to_expect_continue_button',
  );
  // How it works is a carousel, and a Next tapped before its page animation
  // settles does not advance it, so tap until What to expect opens.
  for (var tap = 0; tap < 6; tap++) {
    await pumpUntil(
      tester,
      () =>
          tester.any(find.byKey(whatToExpect)) || tester.any(find.byKey(next)),
      description: 'How it works or What to expect',
    );
    if (tester.any(find.byKey(whatToExpect))) break;
    await tapAppButton(tester, next);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  await tapAppButton(tester, whatToExpect);
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('ironwood_migration_private_option')),
    ),
    description: 'migration options',
  );
}

Future<void> openPrivateMigrationReview(WidgetTester tester) async {
  await openMigrationOptions(tester);
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

Future<void> openImmediateMigrationReview(WidgetTester tester) async {
  await openMigrationOptions(tester);
  await tapAppWidget(tester, const ValueKey('ironwood_migration_fast_option'));
  await tapAppButton(
    tester,
    const ValueKey('ironwood_migration_select_review_button'),
  );
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('ironwood_migration_immediate_review_screen')),
    ),
    description: 'Immediate migration review',
  );
}

Future<void> startPrivateMigrationFromReview(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('ironwood_migration_authorize_start_button')),
    ),
    description: 'migration review start button',
  );
  await tapAppButton(
    tester,
    const ValueKey('ironwood_migration_authorize_start_button'),
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

Future<rust_sync.MigrationStatus> waitForDesktopRegtestMigrationStatus(
  WidgetTester tester,
  String accountUuid,
  bool Function(rust_sync.MigrationStatus status) condition, {
  required String description,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final end = DateTime.now().add(timeout);
  Object? lastError;
  rust_sync.MigrationStatus? lastStatus;
  var polls = 0;
  while (DateTime.now().isBefore(end)) {
    try {
      lastStatus = await desktopRegtestMigrationStatus(accountUuid);
      lastError = null;
      if (condition(lastStatus)) return lastStatus;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    polls++;
    if (polls % 20 == 0) e2eLog('still waiting for $description');
  }
  final statusDetail = lastStatus == null
      ? ''
      : ' Last phase: ${lastStatus.phase}, run: ${lastStatus.activeRunId}.';
  final errorDetail = lastError == null ? '' : ' Last error: $lastError';
  fail('Timed out waiting for $description.$statusDetail$errorDetail');
}

Future<rust_sync.MigrationStatus> advanceDesktopRegtestMigrationSchedule(
  WidgetTester tester,
  String driverUrl,
  String accountUuid, {
  int? submittedTarget,
  Duration timeout = const Duration(minutes: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = await desktopRegtestMigrationStatus(accountUuid);
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

    final chain = await ironwoodDriverGet(driverUrl, '/status');
    final currentHeight = (chain['zcashdHeight'] as num).toInt();
    final nextHeight = scheduled.first.scheduledHeight;
    if (nextHeight > currentHeight) {
      final blocks = nextHeight - currentHeight;
      e2eLog(
        'mining $blocks block(s) to migration broadcast height $nextHeight',
      );
      await ironwoodDriverPost(driverUrl, '/mine', payload: {'blocks': blocks});
    }

    await waitForDesktopRegtestMigrationStatus(
      tester,
      accountUuid,
      (next) => next.broadcastedTxCount + next.confirmedTxCount > submitted,
      description: 'migration transaction at block $nextHeight',
      timeout: const Duration(minutes: 2),
    );
  }
  fail('Timed out advancing the regtest migration broadcast schedule.');
}

/// Mines a desktop run through its denomination preparation until its
/// migration broadcasts are scheduled, or with [untilScheduled] false until
/// the preparation is confirmed. Desktop spaces the preparation: each split is
/// broadcast only once the tip reaches its scheduled height, and a later layer
/// waits for its inputs to confirm. So mine to the next scheduled height, or
/// one block while a split is unconfirmed, and let the app observe each block
/// before mining again.
Future<rust_sync.MigrationStatus> prepareDesktopRegtestMigrationSchedule(
  WidgetTester tester,
  String driverUrl,
  String accountUuid, {
  bool untilScheduled = true,
  Duration timeout = const Duration(minutes: 12),
}) async {
  final deadline = DateTime.now().add(timeout);
  rust_sync.MigrationStatus? status;
  while (DateTime.now().isBefore(deadline)) {
    status = await desktopRegtestMigrationStatus(accountUuid);
    final preparing = status.phase == 'waiting_denom_confirmations';
    if (!preparing &&
        (!untilScheduled || status.scheduledBroadcasts.isNotEmpty)) {
      return status;
    }
    final chain = await ironwoodDriverGet(driverUrl, '/status');
    final tip = (chain['zcashdHeight'] as num).toInt();
    final target = preparing
        ? _nextDesktopPreparationBlock(status, tip)
        : _aboveTip(status.nextProofWindowHeight, tip);
    if (target != null) {
      e2eLog('mining ${target - tip} block(s) of migration preparation');
      await ironwoodDriverPost(
        driverUrl,
        '/mine',
        payload: {'blocks': target - tip},
      );
    }
    // Without a block to mine, the app is sending a due split or proving.
    await _waitForDesktopPreparationProgress(
      tester,
      accountUuid,
      status,
      Duration(seconds: target == null ? 30 : 60),
    );
  }
  fail(
    'Timed out preparing the regtest migration broadcast schedule. Last: '
    '${status == null ? 'no status' : _desktopPreparationProgress(status)}',
  );
}

int? _nextDesktopPreparationBlock(rust_sync.MigrationStatus status, int tip) {
  final stages = _preparationStages(status);
  if (stages.any(
    (stage) =>
        stage.state ==
            rust_sync.MigrationPreparationTransactionState.broadcasted ||
        stage.state ==
            rust_sync.MigrationPreparationTransactionState.confirming,
  )) {
    return tip + 1;
  }
  int? next;
  for (final stage in stages) {
    if (stage.state !=
        rust_sync.MigrationPreparationTransactionState.scheduled) {
      continue;
    }
    final height = stage.scheduledHeight ?? stage.plannedHeight;
    if (next == null || height < next) next = height;
  }
  // A layer waiting on confirmed inputs is built on a later scan.
  final awaitingInputs = stages.any(
    (stage) =>
        stage.state ==
        rust_sync.MigrationPreparationTransactionState.awaitingInputs,
  );
  return _aboveTip(next, tip) ?? (awaitingInputs ? tip + 1 : null);
}

int? _aboveTip(int? height, int tip) =>
    height != null && height > tip ? height : null;

List<rust_sync.MigrationPreparationTransactionStatus> _preparationStages(
  rust_sync.MigrationStatus status,
) => status.preparationTransactions ?? const [];

/// Preparation transactions per layer. Stage rounds count layers from 1.
List<int> desktopPreparationLayers(rust_sync.MigrationStatus status) {
  final layers = <int>[];
  for (final stage in _preparationStages(status)) {
    while (layers.length < stage.round) {
      layers.add(0);
    }
    layers[stage.round - 1]++;
  }
  return layers;
}

String _desktopPreparationProgress(rust_sync.MigrationStatus status) => [
  status.phase,
  '${status.scheduledBroadcasts.length} scheduled',
  for (final stage in _preparationStages(status))
    '#${stage.stageIndex} ${stage.state.name} '
        '${stage.confirmationCount}/${stage.confirmationTarget}',
].join(', ');

Future<void> _waitForDesktopPreparationProgress(
  WidgetTester tester,
  String accountUuid,
  rust_sync.MigrationStatus before,
  Duration timeout,
) async {
  final previous = _desktopPreparationProgress(before);
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final status = await desktopRegtestMigrationStatus(accountUuid);
    if (_desktopPreparationProgress(status) != previous) return;
  }
}

/// Waits for the private migration status screen of a live run. A software
/// account's run has no action button there. While the run prepares its
/// denominations, the screen offers the preparation schedule.
Future<void> waitForDesktopActiveMigrationStatus(
  WidgetTester tester, {
  bool preparing = false,
  Duration timeout = const Duration(minutes: 2),
}) {
  return pumpUntil(
    tester,
    () =>
        tester.any(
          find.byKey(const ValueKey('ironwood_migration_active_status')),
        ) &&
        (!preparing ||
            tester.any(
              find.byKey(
                const ValueKey(
                  'ironwood_migration_view_preparation_schedule_button',
                ),
              ),
            )),
    description: preparing
        ? 'migration preparation status'
        : 'active migration status',
    timeout: timeout,
  );
}

/// Returns Home from the migration status through the sidebar while the run
/// continues.
Future<void> leaveDesktopMigrationStatusForHome(WidgetTester tester) async {
  await tapAppWidget(tester, const ValueKey('sidebar_home_button'));
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'home while migration continues',
  );
}

Future<void> cleanupDesktopRegtestWallet() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError(
      'Refusing to clean wallet state without ZCASH_DEFAULT_NETWORK=regtest.',
    );
  }

  await stopRustWorkForCleanup();
  await rust_network_privacy.configureNetworkPrivacy(
    enabled: false,
    torDirectory: '',
  );
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
  for (final name in [
    dbName,
    '$dbName-shm',
    '$dbName-wal',
    '$dbName.voting',
    '$dbName.voting-journal',
    '$dbName.voting-shm',
    '$dbName.voting-wal',
  ]) {
    final file = File('${supportDir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) file.deleteSync();
  }
}

/// Regtest-guarded Gift Card claim-wallet sweep. Claim wallets from every
/// network share one support directory, so the sweep is scoped to regtest
/// names; a developer's unfinished mainnet claim keeps its retained DB.
Future<void> cleanupRegtestPaymentLinkClaimWallets() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError(
      'Refusing to delete Gift Card claim wallets without '
      'ZCASH_DEFAULT_NETWORK=regtest.',
    );
  }
  await deletePaymentLinkClaimWalletDirectories(
    network: ZcashNetwork.regtest.name,
  );
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
  await pumpUntil(tester, () {
    final elements = finder.evaluate();
    if (elements.isEmpty) return false;
    final buttons = [
      for (final element in elements)
        if (element.widget case final AppButton button) button,
    ];
    if (buttons.isEmpty) return true;
    return buttons.any((button) => button.onPressed != null);
  }, description: '$key button to be enabled');
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
  final keyedWidget = find.byKey(key);
  await pumpUntil(
    tester,
    () => tester.any(keyedWidget),
    description: '$key input widget',
  );
  final editable = tester.widget(keyedWidget) is EditableText
      ? keyedWidget
      : find.descendant(of: keyedWidget, matching: find.byType(EditableText));
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
  final keyedWidget = tester.widget(finder);
  if (keyedWidget is Text) {
    return keyedWidget.data ?? keyedWidget.textSpan?.toPlainText();
  }
  final descendants = tester.widgetList<Text>(
    find.descendant(of: finder, matching: find.byType(Text)),
  );
  for (final descendant in descendants) {
    final text = descendant.data ?? descendant.textSpan?.toPlainText();
    if (text != null) return text;
  }
  return null;
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
