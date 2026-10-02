@Tags(['mobile'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_network_settings_sheet.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

// Live-network check for a disposable, fresh-install mobile simulator/device.
// Uses real Tor/Rust/storage and a mainnet lightwalletd server; creates no wallet.
// Run against a dedicated test device with --tags mobile --run-skipped and
// --dart-define=VIZOR_FORM_FACTOR=mobile (see the network settings spec).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'Welcome cancels real Tor and validates RPC without creating a wallet',
    (tester) async {
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await _wait(
        tester,
        () => find
            .byKey(const ValueKey('mobile_welcome_network_settings'))
            .evaluate()
            .isNotEmpty,
      );
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_welcome_network_settings')),
        ),
      );
      expect(
        container.read(accountProvider).value?.hasAccounts,
        isFalse,
        reason: 'Use a fresh disposable device for this test.',
      );
      final path = await getWalletDbPath();
      final hadDb = File(path).existsSync();

      await tester.tap(
        find.byKey(const ValueKey('mobile_welcome_network_settings')),
      );
      await _wait(
        tester,
        () => find.byType(MobileNetworkSettingsSheet).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('mobile_settings_tor_row')));
      await _wait(tester, () => container.read(networkPrivacyProvider).isBusy);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
        isFalse,
      );
      await tester.tapAt(const Offset(3, 3));
      await tester.drag(find.text('Network settings'), const Offset(0, 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MobileNetworkSettingsSheet), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mobile_settings_tor_row')));
      await _wait(
        tester,
        () =>
            container.read(networkPrivacyProvider).status ==
            NetworkPrivacyConnectionStatus.off,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
        isTrue,
      );

      final input = find.byKey(const ValueKey('welcome_endpoint_input'));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 500));
      final field = tester.widget<TextField>(input);
      // Keep the native IME active; enterText's test input would replace it.
      field.controller!.text = 'eu.zec.stardust.rest:443';
      field.onChanged?.call(field.controller!.text);
      await tester.pump(const Duration(milliseconds: 200));
      final update = find.byKey(const ValueKey('welcome_endpoint_update'));
      expect(update.hitTestable(), findsOneWidget);
      await tester.tap(update);
      await _wait(
        tester,
        () => find.byType(MobileNetworkSettingsSheet).evaluate().isEmpty,
        timeout: const Duration(seconds: 40),
      );
      expect(
        container.read(rpcEndpointProvider).hostPort,
        'eu.zec.stardust.rest:443',
      );
      expect(container.read(accountProvider).value?.hasAccounts, isFalse);
      expect(rust_sync.isSyncRunning(), isFalse);
      expect(File(path).existsSync(), hadDb);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the network settings flow.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
