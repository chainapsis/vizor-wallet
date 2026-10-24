import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart';

void main() {
  /// A container whose wallet answers the startup read with `saved`.
  ProviderContainer container(Future<SwapRecoveryStatus?> Function() saved) {
    final container = ProviderContainer(
      overrides: [swapRecoveryStatusReaderProvider.overrideWithValue(saved)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a saved update request shows before any recovery round', () async {
    final c = container(
      () async => const SwapRecoveryStatus(
        checkingHistory: false,
        manualCheckActive: false,
        upgradeRequired: true,
      ),
    );
    expect(c.read(swapRecoveryUpdateRequiredProvider), isFalse);
    await pumpEventQueue();
    expect(c.read(swapRecoveryUpdateRequiredProvider), isTrue);
  });

  test(
    'a round that answers first is not overwritten by the saved state',
    () async {
      final saved = Completer<SwapRecoveryStatus?>();
      final c = container(() => saved.future);
      c.read(swapRecoveryUpdateRequiredProvider);
      c.read(swapRecoveryUpdateRequiredProvider.notifier).set(false);
      saved.complete(
        const SwapRecoveryStatus(
          checkingHistory: false,
          manualCheckActive: false,
          upgradeRequired: true,
        ),
      );
      await pumpEventQueue();
      expect(c.read(swapRecoveryUpdateRequiredProvider), isFalse);
    },
  );

  test('no wallet or a failed read leaves the flag off', () async {
    final none = container(() async => null);
    none.read(swapRecoveryUpdateRequiredProvider);
    await pumpEventQueue();
    expect(none.read(swapRecoveryUpdateRequiredProvider), isFalse);

    final failing = container(() async => throw StateError('wallet busy'));
    failing.read(swapRecoveryUpdateRequiredProvider);
    await pumpEventQueue();
    expect(failing.read(swapRecoveryUpdateRequiredProvider), isFalse);
  });
}
