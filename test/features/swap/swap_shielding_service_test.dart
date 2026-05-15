import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_shielding_service.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  group('classifySwapShieldTransaction', () {
    test('returns mined when the shield tx is confirmed', () {
      final state = classifySwapShieldTransaction(
        transactions: [_tx(txidHex: 'abc123', minedHeight: BigInt.from(42))],
        txHash: 'ABC123',
      );

      expect(state.status, SwapShieldTxStatus.mined);
    });

    test('matches display-order broadcast txids to protocol-order history', () {
      const displayOrder =
          '1d488e20539811f0dfd353273916e7547e40b9bf18e14c0f7a64c132eb99da02';
      const protocolOrder =
          '02da99eb32c1647a0f4ce118bfb9407e54e716392753d3dff0119853208e481d';

      final state = classifySwapShieldTransaction(
        transactions: [
          _tx(txidHex: protocolOrder, minedHeight: BigInt.from(42)),
        ],
        txHash: displayOrder,
      );

      expect(state.status, SwapShieldTxStatus.mined);
    });

    test('returns pending when the shield tx exists but is unmined', () {
      final state = classifySwapShieldTransaction(
        transactions: [_tx(txidHex: 'shield-tx', minedHeight: BigInt.zero)],
        txHash: 'shield-tx',
      );

      expect(state.status, SwapShieldTxStatus.pending);
    });

    test('returns expired when the shield tx expired unmined', () {
      final state = classifySwapShieldTransaction(
        transactions: [
          _tx(
            txidHex: 'shield-expired',
            minedHeight: BigInt.zero,
            expiredUnmined: true,
          ),
        ],
        txHash: 'shield-expired',
      );

      expect(state.status, SwapShieldTxStatus.expired);
    });

    test('returns unknown when the tx is missing or blank', () {
      expect(
        classifySwapShieldTransaction(
          transactions: [_tx(txidHex: 'other')],
          txHash: 'missing',
        ).status,
        SwapShieldTxStatus.unknown,
      );
      expect(
        classifySwapShieldTransaction(
          transactions: [_tx(txidHex: 'other')],
          txHash: '   ',
        ).status,
        SwapShieldTxStatus.unknown,
      );
    });
  });
}

rust_sync.TransactionInfo _tx({
  required String txidHex,
  BigInt? minedHeight,
  bool expiredUnmined = false,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: minedHeight ?? BigInt.one,
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'sent',
    displayAmount: BigInt.one,
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}
