import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_direction.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_state.dart';

SwapState _state({
  required SwapDirection direction,
  required SwapAsset externalAsset,
  String destinationText = '',
  String? destinationEnsName,
  SwapDestinationResolveStatus destinationResolveStatus =
      SwapDestinationResolveStatus.idle,
  String? destinationResolveError,
}) {
  return SwapState(
    direction: direction,
    amountText: '',
    receiveAmountText: '',
    destinationText: destinationText,
    externalAsset: externalAsset,
    reviewVisible: false,
    intents: const [],
    destinationEnsName: destinationEnsName,
    destinationResolveStatus: destinationResolveStatus,
    destinationResolveError: destinationResolveError,
  );
}

void main() {
  group('destinationFieldHint', () {
    test('shows or .eth for an EVM external asset when sending ZEC', () {
      final state = _state(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.eth,
      );

      expect(state.destinationFieldHint, 'Ethereum address or .eth');
    });

    test('shows or .eth for an EVM external asset when receiving ZEC', () {
      final state = _state(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.eth,
      );

      expect(state.destinationFieldHint, 'Ethereum address or .eth');
    });

    test(
      'stays "address or account" for a non-EVM asset when sending ZEC',
      () {
        final state = _state(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.near,
        );

        expect(state.destinationFieldHint, 'NEAR address or account');
      },
    );

    test('stays "address" for a non-EVM asset when receiving ZEC', () {
      final state = _state(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.near,
      );

      expect(state.destinationFieldHint, 'NEAR address');
    });
  });

  group('copyWith', () {
    test('round-trips the ENS resolution fields', () {
      final base = _state(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.eth,
      );

      final updated = base.copyWith(
        destinationEnsName: 'alice.eth',
        destinationResolveStatus: SwapDestinationResolveStatus.resolving,
        destinationResolveError: 'boom',
      );

      expect(updated.destinationEnsName, 'alice.eth');
      expect(
        updated.destinationResolveStatus,
        SwapDestinationResolveStatus.resolving,
      );
      expect(updated.destinationResolveError, 'boom');
    });

    test(
      'changing destinationText does not implicitly clear destinationEnsName',
      () {
        final base = _state(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.eth,
          destinationText: '0x0000000000000000000000000000000000dead',
          destinationEnsName: 'alice.eth',
        );

        final updated = base.copyWith(destinationText: '0xanotheraddress');

        expect(updated.destinationText, '0xanotheraddress');
        expect(updated.destinationEnsName, 'alice.eth');
      },
    );
  });
}
