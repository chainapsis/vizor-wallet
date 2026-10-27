import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_address_wait_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart';

class _NearSwapPrivacy extends NearSwapPrivacyNotifier {
  @override
  bool build() => true;
}

class _Sync extends SyncNotifier {
  _Sync(this.initial);

  final SyncState initial;

  @override
  Future<SyncState> build() async => initial;
}

const _idle = SwapRecoveryStatus(
  roundDue: false,
  awaitingAdmission: false,
  checkingHistory: false,
  manualCheckActive: false,
  upgradeRequired: false,
);

const _restoring = SwapRecoveryStatus(
  roundDue: false,
  awaitingAdmission: false,
  checkingHistory: true,
  manualCheckActive: false,
  upgradeRequired: false,
);

void main() {
  group('swapRefundAddressNeedsSync', () {
    bool needsSync({required int tip, int scanned = 0, int? pendingStart}) =>
        swapRefundAddressNeedsSync(
          chainTipHeight: tip,
          scannedHeight: scanned,
          pendingScanStartHeight: pendingStart,
        );

    test('waits once the fully scanned height is over 10 blocks behind', () {
      expect(needsSync(tip: 1000, scanned: 990), isFalse);
      expect(needsSync(tip: 1000, scanned: 989), isTrue);
    });

    test('an unscanned range ends the fully scanned height before it', () {
      // Scanned to the tip, but an earlier range is still pending.
      expect(needsSync(tip: 1000, scanned: 1000, pendingStart: 900), isTrue);
      expect(needsSync(tip: 1000, scanned: 1000, pendingStart: 991), isFalse);
    });

    test('an unknown tip never waits', () {
      expect(needsSync(tip: 0, scanned: 0), isFalse);
    });
  });

  group('swapAddressHistoryPendingProvider', () {
    ProviderContainer container(Future<SwapRecoveryStatus?> Function() status) {
      final container = ProviderContainer(
        overrides: [
          swapRecoveryStatusReaderProvider.overrideWithValue(status),
          nearSwapPrivacyProvider.overrideWith(_NearSwapPrivacy.new),
        ],
      );
      addTearDown(container.dispose);
      container.listen(swapAddressHistoryPendingProvider, (_, _) {});
      return container;
    }

    test('holds quotes while the automatic history lookup runs', () async {
      var status = _restoring;
      final c = container(() async => status);
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);

      status = _idle;
      c.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
    });

    test('a history check the user started does not hold quotes', () async {
      final c = container(
        () async => const SwapRecoveryStatus(
          roundDue: false,
          awaitingAdmission: false,
          checkingHistory: true,
          manualCheckActive: true,
          upgradeRequired: false,
        ),
      );
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
    });

    test('a failed round lets a press show the reason', () async {
      final c = container(() async => _restoring);
      await pumpEventQueue();
      c.read(swapRecoveryRoundFailedProvider.notifier).set(true);
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);

      c.read(swapRecoveryRoundFailedProvider.notifier).set(false);
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);
    });

    test('a read the wallet refuses keeps the last answer', () async {
      var busy = false;
      final c = container(() async {
        if (busy) throw StateError('wallet busy');
        return _restoring;
      });
      await pumpEventQueue();
      busy = true;
      c.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);
    });

    test('a refused quote waits for the next round', () async {
      final c = container(() async => _idle);
      await pumpEventQueue();
      c.read(swapAddressHistoryPendingProvider.notifier).quoteRefused();
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);

      c.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
    });
  });

  group('swapAddressWaitProvider', () {
    ProviderContainer container({
      bool oneTime = true,
      SwapRecoveryStatus status = _restoring,
      SyncState? sync,
    }) {
      final container = ProviderContainer(
        overrides: [
          swapUsesOneTimeAddressProvider.overrideWithValue(oneTime),
          swapRecoveryStatusReaderProvider.overrideWithValue(
            () async => status,
          ),
          nearSwapPrivacyProvider.overrideWith(_NearSwapPrivacy.new),
          syncProvider.overrideWith(() => _Sync(sync ?? SyncState())),
        ],
      );
      addTearDown(container.dispose);
      container.listen(swapAddressWaitProvider(false), (_, _) {});
      container.listen(swapAddressWaitProvider(true), (_, _) {});
      return container;
    }

    test('a ZEC payout waits for its address to be prepared', () async {
      final c = container();
      await pumpEventQueue();
      expect(c.read(swapAddressWaitProvider(false)), SwapAddressWait.preparing);
    });

    test('a ZEC refund address waits for sync', () async {
      final c = container(
        sync: SyncState(chainTipHeight: 1000, scannedHeight: 900),
      );
      await pumpEventQueue();
      expect(c.read(swapAddressWaitProvider(true)), SwapAddressWait.sync);
    });

    test('a synced refund address does not wait', () async {
      final c = container(
        sync: SyncState(chainTipHeight: 1000, scannedHeight: 1000),
      );
      await pumpEventQueue();
      expect(c.read(swapAddressWaitProvider(true)), isNull);
    });

    test('regular addresses never wait', () async {
      final c = container(
        oneTime: false,
        sync: SyncState(chainTipHeight: 1000, scannedHeight: 900),
      );
      await pumpEventQueue();
      expect(c.read(swapAddressWaitProvider(false)), isNull);
      expect(c.read(swapAddressWaitProvider(true)), isNull);
    });
  });
}
