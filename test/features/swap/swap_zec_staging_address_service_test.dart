import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';

void main() {
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
