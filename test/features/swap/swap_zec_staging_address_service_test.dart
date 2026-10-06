import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:zcash_wallet/src/rust/wallet/swap_receiving/receive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_receive_reservation_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';

void main() {
  test('typed allocation failures preserve the display message', () {
    const cause = ReceiveError(message: 'Choose another quote.');
    expect(
      const SwapZecStagingAddressUnavailableException(cause).toString(),
      'Choose another quote.',
    );
  });
  test('POC uses separate refund and incoming reservations', () async {
    final purposes = <SwapDirection>[];
    final service = SwapZecStagingAddressService(
      reserveFreshOrchardAddress: ({required accountUuid}) async =>
          throw StateError('ordinary address must not be exposed'),
      reserveSwapAddress: ({required accountUuid, required direction}) async {
        purposes.add(direction);
        return SwapZecStagingAddress(
          address: 'derived-${direction.name}',
          receivingIndex: BigInt.from(7),
        );
      },
    );
    for (final direction in SwapDirection.values) {
      final staging = await service.prepareForQuote(
        accountUuid: 'software',
        direction: direction,
      );
      expect(staging.receivingIndex, BigInt.from(7));
      final plan = staging.toAddressPlan(
        direction: direction,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: 'external',
      );
      expect(
        direction.sendsZec ? plan.oneClickRefundTo : plan.oneClickRecipient,
        staging.address,
      );
    }
    expect(purposes, SwapDirection.values);
  });

  test('records refund quotes for reserved refund keys only', () async {
    final recorded = <String>[];
    final reservations = _Reservations();
    final service = SwapZecStagingAddressService(
      reserveFreshOrchardAddress: ({required accountUuid}) async => 'ordinary',
      reservations: reservations,
      recordRefundQuote: (account, index, quote) async {
        recorded.add('$account:$index:${quote.depositInstruction.address}');
      },
    );
    final quote = SwapQuote(
      direction: SwapDirection.zecToExternal,
      sellAsset: SwapAsset.zec,
      receiveAsset: SwapAsset.usdc,
      externalAsset: SwapAsset.usdc,
      sellAmount: 1,
      receiveAmount: 70,
      minimumReceiveAmount: 69,
      providerLabel: 'NEAR Intents',
      feeLabel: 'Included',
      expiryLabel: '10:00',
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: 't1deposit',
        expiresInLabel: '10:00',
        reuseWarning: '',
        deadline: DateTime.utc(2026, 10),
      ),
    );
    final refund = await service.quote(
      'software',
      SwapZecStagingAddress(address: 'refund', receivingIndex: BigInt.from(7)),
      (_) async => quote,
    );
    expect(refund.swapRefundIndex, BigInt.from(7));
    for (final address in [
      const SwapZecStagingAddress(address: 'incoming', reservationId: 1),
      const SwapZecStagingAddress(address: 'ordinary'),
    ]) {
      expect(
        await service.quote('software', address, (_) async => quote),
        same(quote),
      );
    }
    expect(reservations.quoted, [1]);
    expect(recorded, ['software:7:t1deposit']);
    // The funding transaction cannot carry a deposit memo.
    final withMemo = SwapQuote(
      direction: quote.direction,
      sellAsset: quote.sellAsset,
      receiveAsset: quote.receiveAsset,
      externalAsset: quote.externalAsset,
      sellAmount: quote.sellAmount,
      receiveAmount: quote.receiveAmount,
      minimumReceiveAmount: quote.minimumReceiveAmount,
      providerLabel: quote.providerLabel,
      feeLabel: quote.feeLabel,
      expiryLabel: quote.expiryLabel,
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: 't1deposit',
        expiresInLabel: '10:00',
        reuseWarning: '',
        memo: 'memo',
        deadline: DateTime.utc(2026, 10),
      ),
    );
    await expectLater(
      service.quote(
        'software',
        SwapZecStagingAddress(
          address: 'refund',
          receivingIndex: BigInt.from(8),
        ),
        (_) async => withMemo,
      ),
      throwsStateError,
    );
    expect(recorded, ['software:7:t1deposit']);
  });

  test(
    'failed POC reservation never falls back to the account address',
    () async {
      var ordinaryCalls = 0;
      final service = SwapZecStagingAddressService(
        reserveFreshOrchardAddress: ({required accountUuid}) async {
          ordinaryCalls++;
          return 'ordinary';
        },
        reserveSwapAddress:
            ({required accountUuid, required direction}) async =>
                throw StateError('hardware wallet unsupported'),
      );
      await expectLater(
        service.prepareForQuote(accountUuid: 'hardware'),
        throwsA(isA<SwapZecStagingAddressUnavailableException>()),
      );
      expect(ordinaryCalls, 0);
    },
  );

  test(
    'blocks quote preparation when Orchard wallet address is unavailable',
    () {
      final service = SwapZecStagingAddressService(
        reserveFreshOrchardAddress: ({required accountUuid}) async {
          throw Exception('address unavailable');
        },
      );

      expect(
        () => service.prepareForQuote(accountUuid: 'account-1'),
        throwsA(isA<SwapZecStagingAddressUnavailableException>()),
      );
    },
  );

  test('uses Orchard-only unified address for the ZEC refund path', () async {
    var orchardLoads = 0;
    final service = SwapZecStagingAddressService(
      reserveFreshOrchardAddress: ({required accountUuid}) async {
        orchardLoads++;
        expect(accountUuid, 'account-1');
        return 'u1fresh-orchard-refund';
      },
    );

    final staging = await service.prepareForQuote(accountUuid: 'account-1');

    expect(orchardLoads, 1);
    expect(staging.address, 'u1fresh-orchard-refund');
    final plan = staging.toAddressPlan(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      userExternalAddress: '0xrecipient',
    );
    expect(plan.oneClickRecipient, '0xrecipient');
    expect(plan.oneClickRefundTo, 'u1fresh-orchard-refund');
  });

  test(
    'uses Orchard-only unified address for external to ZEC deposit',
    () async {
      var orchardLoads = 0;
      final service = SwapZecStagingAddressService(
        reserveFreshOrchardAddress: ({required accountUuid}) async {
          orchardLoads++;
          expect(accountUuid, 'account-1');
          return 'u1fresh-orchard-deposit';
        },
      );

      final staging = await service.prepareForQuote(accountUuid: 'account-1');

      expect(orchardLoads, 1);
      expect(staging.address, 'u1fresh-orchard-deposit');
      final plan = staging.toAddressPlan(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: '0xrefund',
      );
      expect(plan.oneClickRecipient, 'u1fresh-orchard-deposit');
      expect(plan.oneClickRefundTo, '0xrefund');
    },
  );
}

/// Quotes an incoming reservation without a wallet, recording which it quoted.
class _Reservations extends Fake implements SwapReceiveReservationService {
  final quoted = <PlatformInt64>[];

  @override
  Future<SwapQuote> quote(
    String account,
    PlatformInt64 reservation,
    Future<SwapQuote> Function(SwapQuoteSendHook beforeSend) fetch,
  ) {
    quoted.add(reservation);
    return fetch((_) async {});
  }
}
