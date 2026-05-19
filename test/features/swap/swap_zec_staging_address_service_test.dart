import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_address_plan.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';

void main() {
  test(
    'blocks quote preparation when shielded wallet address is unavailable',
    () {
      final service = SwapZecStagingAddressService(
        loadShieldedAddress: ({required accountUuid}) async {
          throw Exception('address unavailable');
        },
      );

      expect(
        () => service.prepareForQuote(accountUuid: 'account-1'),
        throwsA(isA<SwapZecStagingAddressUnavailableException>()),
      );
    },
  );

  test('uses shielded unified address for the ZEC refund path', () async {
    var shieldedLoads = 0;
    final service = SwapZecStagingAddressService(
      loadShieldedAddress: ({required accountUuid}) async {
        shieldedLoads++;
        expect(accountUuid, 'account-1');
        return 'u1fresh-shielded-refund';
      },
    );

    final staging = await service.prepareForQuote(accountUuid: 'account-1');

    expect(shieldedLoads, 1);
    expect(staging.address, 'u1fresh-shielded-refund');
    expect(
      staging.stagingAddressPolicy,
      SwapZecStagingAddressPolicy.rotatingWalletUnifiedAddress,
    );
    expect(staging.shieldingPolicy, SwapZecShieldingPolicy.notRequired);

    final plan = staging.toAddressPlan(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      userExternalAddress: '0xrecipient',
    );
    expect(plan.oneClickRecipient, '0xrecipient');
    expect(plan.oneClickRefundTo, 'u1fresh-shielded-refund');
    expect(plan.reviewDeliveryValue, '0xrecipient');
  });

  test('uses shielded unified address for external to ZEC delivery', () async {
    var shieldedLoads = 0;
    final service = SwapZecStagingAddressService(
      loadShieldedAddress: ({required accountUuid}) async {
        shieldedLoads++;
        expect(accountUuid, 'account-1');
        return 'u1fresh-shielded-recipient';
      },
    );

    final staging = await service.prepareForQuote(accountUuid: 'account-1');

    expect(shieldedLoads, 1);
    expect(staging.address, 'u1fresh-shielded-recipient');
    expect(
      staging.stagingAddressPolicy,
      SwapZecStagingAddressPolicy.rotatingWalletUnifiedAddress,
    );
    expect(staging.shieldingPolicy, SwapZecShieldingPolicy.notRequired);

    final plan = staging.toAddressPlan(
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      userExternalAddress: '0xrefund',
    );
    expect(plan.oneClickRecipient, 'u1fresh-shielded-recipient');
    expect(plan.oneClickRefundTo, '0xrefund');
    expect(plan.zecDeliveryIsDirectShielded, isTrue);
  });
}
