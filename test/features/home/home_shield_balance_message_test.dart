import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/network_upgrade_hold.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import '../../support/test_l10n.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  group('shieldBalanceBroadcastStatusMessage', () {
    test('returns null after completed broadcast', () {
      expect(
        shieldBalanceBroadcastStatusMessage(
          testL10n,
          _shieldResult(status: 'broadcasted'),
        ),
        isNull,
      );
    });

    test('describes pending broadcast as automatic retry, not failure', () {
      final message = shieldBalanceBroadcastStatusMessage(
        testL10n,
        _shieldResult(status: 'pending_broadcast'),
      );

      expect(message, testL10n.homeShieldQueuedForRetry);
      expect(message, isNot(contains('failed')));
      expect(message, isNot(contains('Try again')));
      expect(message, contains('queued for retry'));
      expect(message, contains('Check Activity'));
    });

    test('describes partial broadcast the same as pending broadcast', () {
      final message = shieldBalanceBroadcastStatusMessage(
        testL10n,
        _shieldResult(status: 'partial_broadcast'),
      );

      expect(message, testL10n.homeShieldQueuedForRetry);
      expect(message, isNot(contains('Try again')));
      expect(message, contains('Check Activity'));
    });
  });

  test('a Keystone shield the upgrade expired shows the hold copy', () {
    expect(
      shieldPcztBroadcastStatusMessage(
        testL10n,
        const rust_sync.ExtractAndBroadcastPcztResult(
          notices: [],
          txid: 'txid',
          status: 'expired',
          message:
              "Transactions can't be sent this close to the network upgrade. "
              'Try again after it activates.',
        ),
      ),
      networkUpgradeHoldText(testL10n),
    );
  });
}

rust_sync.ShieldTransparentResult _shieldResult({required String status}) {
  return rust_sync.ShieldTransparentResult(
    txids: 'txid',
    status: status,
    broadcastedCount: status == 'broadcasted' ? 1 : 0,
    totalCount: 1,
    feeZatoshi: BigInt.from(10_000),
    shieldedZatoshi: BigInt.from(90_000),
  );
}
