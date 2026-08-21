import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_onboarding_flow.dart';

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _password = 'Vizor123!';
const _fallbackToast =
    'Selected endpoint is unstable. Switched to fallback endpoint.';
const _networkFailure =
    "Network connection lost. We'll keep trying automatically.";
const _endpointFailure =
    'Cannot reach the configured Zcash endpoint. Check your endpoint settings.';
const _genericFailure = 'Sync failed. Retry sync to continue.';
const _unavailableCustomEndpoint = 'http://127.0.0.1:19067';
var _nextE2ePointer = 1000;

int _takeE2ePointer() => _nextE2ePointer++;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'does not fallback from an unavailable custom endpoint',
    (tester) async {
      addTearDown(() async {
        await _cleanupE2eWalletState();
      });

      await _cleanupE2eWalletState();
      await _configureUnavailableCustomPrimary();

      _log('pumping app with intentionally unavailable custom endpoint');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      _log('opening import flow');
      await _tapButton(tester, const ValueKey('welcome_import_wallet_button'));

      _log('entering mnemonic');
      await _enterText(
        tester,
        const ValueKey('import_mnemonic_first_word_field'),
        _mnemonic,
      );
      await _tapButton(tester, const ValueKey('import_secret_submit_button'));

      _log('skipping birthday');
      await _tapButton(tester, const ValueKey('import_birthday_skip_button'));
      await _tapButton(
        tester,
        const ValueKey('unknown_birthday_confirm_button'),
      );

      _log('setting password');
      await _enterText(
        tester,
        const ValueKey('set_password_password_field'),
        _password,
      );
      await _enterText(
        tester,
        const ValueKey('set_password_confirm_field'),
        _password,
      );
      await _tapButton(tester, const ValueKey('set_password_submit_button'));
      await finishDesktopAccountCustomisation(tester);

      await _pumpUntil(
        tester,
        () =>
            tester.any(find.text(_networkFailure)) ||
            tester.any(find.text(_endpointFailure)) ||
            tester.any(find.text(_genericFailure)),
        description: 'sync failure notice without fallback',
        timeout: const Duration(seconds: 60),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ZcashWalletApp)),
      );
      final failoverState = container.read(rpcEndpointFailoverProvider);
      expect(tester.any(find.text(_fallbackToast)), isFalse);
      expect(failoverState.isUsingFallback, isFalse);
      expect(
        failoverState.current.effectivePresetId,
        kCustomRpcEndpointPresetId,
      );
      expect(
        failoverState.current.normalizedLightwalletdUrl,
        _unavailableCustomEndpoint,
      );
      _log('custom endpoint failed without fallback toast');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _configureUnavailableCustomPrimary() async {
  final storage = AppSecureStore.instance;
  await storage.writePlain(kRpcEndpointUrlKey, _unavailableCustomEndpoint);
  await storage.writePlain(kRpcEndpointPresetKey, kCustomRpcEndpointPresetId);
}

Future<void> _cleanupE2eWalletState() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError(
      'Refusing to clean wallet state without ZCASH_DEFAULT_NETWORK=regtest.',
    );
  }

  final storage = AppSecureStore.instance;
  final dbName = await getWalletDbName();

  _log('cleaning regtest wallet state');
  await _stopRustWorkForCleanup();

  await storage.deleteAll();

  final supportDir = await getWalletSupportDirectory();
  if (!supportDir.existsSync()) return;

  for (final name in [dbName, '$dbName-shm', '$dbName-wal']) {
    final file = File('${supportDir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) file.deleteSync();
  }
}

Future<void> _stopRustWorkForCleanup() async {
  rust_sync.setSyncMode(mode: 0);
  rust_sync.cancelFullSync();
  rust_sync.stopMempoolObserver();

  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while ((rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  if (rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) {
    _log(
      'timed out waiting for Rust work to stop; continuing E2E storage cleanup',
    );
  }
}

Future<void> _tapButton(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await _pumpUntil(tester, () {
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
  _log('tapped $key');
}

Future<void> _enterText(WidgetTester tester, Key key, String text) async {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  await _pumpUntil(
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
  // A pasted mnemonic is distributed across multiple controllers. Notify the
  // field using the word it retained so integration-test platform timing
  // cannot leave the submit state stale after that programmatic distribution.
  editableText.onChanged?.call(actualText);
  await tester.pump(const Duration(milliseconds: 100));
  _log('entered text into $key');
}

Future<void> _pumpUntil(
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
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    polls++;
    if (polls % 25 == 0) {
      _log('still waiting for $description');
    }
  }

  final error = lastError == null ? '' : ' Last error: $lastError';
  fail('Timed out waiting for $description.$error');
}

void _log(String message) {
  debugPrint('[custom-no-fallback-e2e] $message');
}
