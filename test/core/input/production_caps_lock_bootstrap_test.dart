import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/input/caps_lock_monitor.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/core/widgets/linux_keyring_gate.dart';

void main() {
  testWidgets(
    'Linux startup keeps production monitoring after delayed bootstrap',
    (tester) async {
      final coordinator = LinuxKeyringCoordinator.testing();
      addTearDown(coordinator.dispose);
      final bootstrap = Completer<AppBootstrapState>();
      var queries = 0;
      final policyApplied = Completer<void>();
      var policyCalls = 0;
      CapsLockMonitor? monitor;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(CapsLockMonitor.channel, (call) async {
        expect(call.method, 'getCapsLockState');
        queries++;
        return true;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(CapsLockMonitor.channel, null),
      );

      await tester.pumpWidget(
        LinuxKeyringStartupHost(
          coordinator: coordinator,
          loadApp: () async {
            final app = await buildProductionZcashWalletApp(
              loadBootstrap: () => bootstrap.future,
              applyPrivacyPolicy: (state) async {
                expect(state, same(AppBootstrapState.empty));
                policyCalls++;
                await policyApplied.future;
              },
            );
            // Exercise the actual production overrides without starting wallet,
            // storage, or Rust providers belonging to the full application shell.
            return ProviderScope(
              overrides: app.overrides,
              child: Consumer(
                builder: (context, ref, _) {
                  expect(ref.watch(capsLockMonitoringEnabledProvider), isTrue);
                  monitor = ref.watch(capsLockMonitorProvider);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      );
      await tester.pump();
      expect(queries, 0);
      expect(monitor, isNull);
      bootstrap.complete(AppBootstrapState.empty);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(policyCalls, 1);
      expect(monitor, isNull);
      policyApplied.complete();
      await tester.pump();
      await tester.pump();
      expect(monitor?.enabled, isTrue);
      expect(queries, 1);
      expect(monitor?.value, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  test('preview defaults do not enable native monitoring', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(capsLockMonitoringEnabledProvider), isFalse);
  });
}
