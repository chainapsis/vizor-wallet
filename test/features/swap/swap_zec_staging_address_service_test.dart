import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_address_plan.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  test('blocks quote preparation when rotating reservation fails', () async {
    final container = ProviderContainer(
      overrides: [
        swapZecStagingAddressServiceProvider.overrideWith(
          (ref) => SwapZecStagingAddressService(
            loadWalletDbPath: () async => 'wallet.db',
            readNetwork: () => 'main',
            reserveExchangeTransparentAddress:
                ({
                  required accountUuid,
                  required dbPath,
                  required network,
                }) async {
                  throw Exception('reservation unavailable');
                },
            releaseExchangeTransparentAddress:
                ({
                  required accountUuid,
                  required address,
                  required dbPath,
                }) async {
                  return false;
                },
            releaseUnusedExchangeTransparentAddresses:
                ({required accountUuid, required dbPath}) async {
                  return 0;
                },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      () => container
          .read(swapZecStagingAddressServiceProvider)
          .prepareForQuote(accountUuid: 'account-1'),
      throwsA(isA<SwapZecStagingAddressUnavailableException>()),
    );
  });

  test(
    'uses reserved exchange t-address when Rust reservation succeeds',
    () async {
      final container = ProviderContainer(
        overrides: [
          swapZecStagingAddressServiceProvider.overrideWith(
            (ref) => SwapZecStagingAddressService(
              loadWalletDbPath: () async => 'wallet.db',
              readNetwork: () => 'main',
              reserveExchangeTransparentAddress:
                  ({
                    required accountUuid,
                    required dbPath,
                    required network,
                  }) async {
                    expect(accountUuid, 'account-1');
                    expect(dbPath, 'wallet.db');
                    expect(network, 'main');
                    return rust_wallet.ExchangeTransparentAddressResult(
                      address: 't1rotating-exchange-staging',
                      transparentChildIndex: 7,
                      exposedAtHeight: BigInt.from(2500000),
                    );
                  },
              releaseExchangeTransparentAddress:
                  ({
                    required accountUuid,
                    required address,
                    required dbPath,
                  }) async {
                    return false;
                  },
              releaseUnusedExchangeTransparentAddresses:
                  ({required accountUuid, required dbPath}) async {
                    return 0;
                  },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final staging = await container
          .read(swapZecStagingAddressServiceProvider)
          .prepareForQuote(accountUuid: 'account-1');

      expect(staging.address, 't1rotating-exchange-staging');
      expect(
        staging.stagingAddressPolicy,
        SwapZecStagingAddressPolicy.rotatingWalletTransparentAddress,
      );
      expect(
        staging.shieldingPolicy,
        SwapZecShieldingPolicy.promptAfterArrival,
      );
      expect(staging.transparentChildIndex, 7);
      expect(staging.exposedAtHeight, BigInt.from(2500000));

      final plan = staging.toAddressPlan(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: '0xrefund',
      );
      expect(plan.oneClickRecipient, 't1rotating-exchange-staging');
      expect(
        plan.reviewDeliveryValue,
        'reserved wallet receive address; shield prompt follows',
      );
    },
  );

  test(
    'retries reservation after releasing unused stale reservations',
    () async {
      var reserveAttempts = 0;
      var releaseAttempts = 0;
      final container = ProviderContainer(
        overrides: [
          swapZecStagingAddressServiceProvider.overrideWith(
            (ref) => SwapZecStagingAddressService(
              loadWalletDbPath: () async => 'wallet.db',
              readNetwork: () => 'main',
              reserveExchangeTransparentAddress:
                  ({
                    required accountUuid,
                    required dbPath,
                    required network,
                  }) async {
                    reserveAttempts++;
                    if (reserveAttempts == 1) {
                      throw Exception('ephemeral gap exhausted');
                    }
                    return rust_wallet.ExchangeTransparentAddressResult(
                      address: 't1released-staging',
                      transparentChildIndex: 0,
                      exposedAtHeight: BigInt.from(2500000),
                    );
                  },
              releaseExchangeTransparentAddress:
                  ({
                    required accountUuid,
                    required address,
                    required dbPath,
                  }) async {
                    return false;
                  },
              releaseUnusedExchangeTransparentAddresses:
                  ({required accountUuid, required dbPath}) async {
                    releaseAttempts++;
                    expect(accountUuid, 'account-1');
                    expect(dbPath, 'wallet.db');
                    return 4;
                  },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final staging = await container
          .read(swapZecStagingAddressServiceProvider)
          .prepareForQuote(accountUuid: 'account-1');

      expect(staging.address, 't1released-staging');
      expect(reserveAttempts, 2);
      expect(releaseAttempts, 1);
    },
  );
}
