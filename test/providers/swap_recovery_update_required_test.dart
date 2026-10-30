import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart';

/// The wallet's saved recovery state, with `upgradeRequired` as given.
SwapRecoveryStatus _saved(bool upgradeRequired) => SwapRecoveryStatus(
  roundDue: false,
  awaitingAdmission: false,
  checkingHistory: false,
  manualCheckActive: false,
  upgradeRequired: upgradeRequired,
);

void main() {
  /// A container whose wallet answers each read with `saved`.
  ProviderContainer container(Future<SwapRecoveryStatus?> Function() saved) {
    final container = ProviderContainer(
      overrides: [swapRecoveryStatusReaderProvider.overrideWithValue(saved)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the saved update request shows before any round, and each round '
      'reads it again', () async {
    var saved = _saved(true);
    final c = container(() async => saved);
    expect(await c.read(swapRecoveryUpdateRequiredProvider.future), isTrue);

    saved = _saved(false);
    c.read(swapRecoveryRoundsProvider.notifier).ended();
    expect(await c.read(swapRecoveryUpdateRequiredProvider.future), isFalse);
  });

  test(
    'no wallet leaves it off, and a failed read keeps the last answer',
    () async {
      final none = container(() async => null);
      expect(
        await none.read(swapRecoveryUpdateRequiredProvider.future),
        isFalse,
      );

      var fail = false;
      final failing = container(
        () async => fail ? throw StateError('wallet busy') : _saved(true),
      );
      expect(
        await failing.read(swapRecoveryUpdateRequiredProvider.future),
        isTrue,
      );
      fail = true;
      failing.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(failing.read(swapRecoveryUpdateRequiredProvider).value, isTrue);
    },
  );
}
