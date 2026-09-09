import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';

void main() {
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
