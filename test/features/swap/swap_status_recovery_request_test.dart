import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_tracker.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_receive_reservation_service.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart' as api;

import '../../fakes/fake_sync_notifier.dart';

/// A wallet whose record of each status is [record].
class _Store extends Fake implements ReceiveReservationStore {
  api.SwapStatusRecord record = const api.SwapStatusRecord(
    tracked: true,
    receiptExpected: false,
  );

  @override
  Future<api.SwapStatusRecord> observe({
    required bool incoming,
    required String depositAddress,
    required String? memo,
    required SwapIntentSnapshot snapshot,
    required DateTime checkedAt,
  }) async => record;
}

/// A private swap in `direction`.
SwapIntent _swap(String id, SwapDirection direction) => SwapIntent(
  id: id,
  pair: 'pair',
  sellAmount: '1',
  receiveEstimate: '1',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.processing,
  nextAction: 'Wait',
  direction: direction,
  externalAsset: SwapAsset.usdc,
  depositAddress: id,
  accountUuid: 'account-1',
  privateAddress: true,
);

/// NEAR's status for swap `id`.
SwapIntentSnapshot _status(String id, SwapIntentStatus status) =>
    SwapIntentSnapshot(
      id: id,
      providerLabel: 'NEAR Intents',
      pairText: 'pair',
      sellAmountText: '1',
      receiveEstimateText: '1',
      status: status,
      nextAction: 'Wait',
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: id,
        expiresInLabel: '01:30',
        reuseWarning: 'Do not reuse this address',
      ),
    );

void main() {
  test('a status the wallet says promises ZEC to a tracked private address '
      'owes one recovery round per swap', () async {
    final sync = FakeSyncNotifier();
    final store = _Store();
    final container = ProviderContainer(
      overrides: [
        syncProvider.overrideWith(() => sync),
        swapReceiveReservationServiceProvider.overrideWithValue(
          SwapReceiveReservationService(store: (_) async => store),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(syncProvider.future);
    final tracker = container.read(swapActivityTrackerProvider);
    final now = DateTime.utc(2026, 10, 27);
    // The wallet's normalizer, not the app's status mapping, decides what
    // promises ZEC: a FAILED swap's refund maps to `failed` here.
    final refund = _swap('refund', SwapDirection.zecToExternal);
    final failed = _status('refund', SwapIntentStatus.failed);

    expect(await tracker.recordProviderSnapshot(refund, failed, now), isTrue);
    expect(sync.swapRecoveryRequests, 0, reason: 'no ZEC promised');

    store.record = const api.SwapStatusRecord(
      tracked: false,
      receiptExpected: true,
    );
    expect(await tracker.recordProviderSnapshot(refund, failed, now), isFalse);
    expect(sync.swapRecoveryRequests, 0, reason: 'an address no longer held');

    store.record = const api.SwapStatusRecord(
      tracked: true,
      receiptExpected: true,
    );
    await tracker.recordProviderSnapshot(refund, failed, now);
    expect(sync.swapRecoveryRequests, 1);
    await tracker.recordProviderSnapshot(refund, failed, now);
    expect(sync.swapRecoveryRequests, 1, reason: 'once per swap');

    final payout = _swap('payout', SwapDirection.externalToZec);
    await tracker.recordProviderSnapshot(
      payout,
      _status('payout', SwapIntentStatus.complete),
      now,
    );
    expect(sync.swapRecoveryRequests, 2);
  });
}
