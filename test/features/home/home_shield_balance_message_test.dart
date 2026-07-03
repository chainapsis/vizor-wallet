import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations_en.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

final _l10n = AppLocalizationsEn();

void main() {
  group('shieldBalanceBroadcastStatusMessage', () {
    test('returns null after completed broadcast', () {
      expect(
        shieldBalanceBroadcastStatusMessage(
          _shieldResult(status: 'broadcasted'),
          _l10n,
        ),
        isNull,
      );
    });

    test('describes pending broadcast as automatic retry, not failure', () {
      final message = shieldBalanceBroadcastStatusMessage(
        _shieldResult(status: 'pending_broadcast'),
        _l10n,
      );

      expect(message, _l10n.shieldQueuedRetry);
      expect(message, isNot(contains('failed')));
      expect(message, isNot(contains('Try again')));
      expect(message, contains('queued for retry'));
      expect(message, contains('Check Activity'));
    });

    test('describes partial broadcast the same as pending broadcast', () {
      final message = shieldBalanceBroadcastStatusMessage(
        _shieldResult(status: 'partial_broadcast'),
        _l10n,
      );

      expect(message, _l10n.shieldQueuedRetry);
      expect(message, isNot(contains('Try again')));
      expect(message, contains('Check Activity'));
    });
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
