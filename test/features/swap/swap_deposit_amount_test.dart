import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_deposit_sender.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  late _RustApiFake rustApi;

  setUpAll(() {
    rustApi = _RustApiFake();
    RustLib.initMock(api: rustApi);
  });

  setUp(() {
    rustApi.reset();
  });

  tearDownAll(RustLib.dispose);

  test('software ZEC deposit uses quote base units, not display text', () {
    final quote = _quote(
      sellAmountTextOverride: '0.001 ZEC',
      sellAmountBaseUnits: BigInt.from(150000000),
    );

    expect(zecDepositAmountZatoshiForQuote(quote), BigInt.from(150000000));
  });

  test('software ZEC deposit rejects quotes without base units', () {
    final quote = _quote(sellAmountTextOverride: '1.5 ZEC');

    expect(
      () => zecDepositAmountZatoshiForQuote(quote),
      throwsA(isA<StateError>()),
    );
  });

  test('hardware ZEC deposit uses intent base units, not display text', () {
    final intent = _intent(
      sellAmount: '0.001 ZEC',
      sellAmountBaseUnits: BigInt.from(150000000),
    );

    expect(zecDepositAmountZatoshiForIntent(intent), BigInt.from(150000000));
  });

  test('hardware ZEC deposit rejects intents without base units', () {
    final intent = _intent(sellAmount: '1.5 ZEC');

    expect(
      () => zecDepositAmountZatoshiForIntent(intent),
      throwsA(isA<StateError>()),
    );
  });

  test('hardware ZEC deposit rejects TEX before proposal', () async {
    final container = ProviderContainer(
      // The TEX check validates against the wallet's own network, which it
      // reads off the persisted endpoint.
      overrides: [appBootstrapProvider.overrideWithValue(_bootstrap)],
    );
    addTearDown(container.dispose);

    final service = container.read(swapHardwareSigningServiceProvider);

    await expectLater(
      service.createZecDepositPczt(
        accountUuid: 'account-1',
        intent: _intent(
          sellAmount: '1.0 ZEC',
          sellAmountBaseUnits: BigInt.from(100000000),
          depositAddress: _texAddress,
        ),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'Keystone does not support TEX sends yet.',
        ),
      ),
    );
    expect(rustApi.proposeSendCalls, 0);
    expect(
      rustApi.lastValidatedNetwork,
      _bootstrap.rpcEndpointConfig.networkName,
      reason:
          'the deposit address is checked against the network the wallet '
          'would broadcast on',
    );
  });
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: kZcashDefaultNetworkName,
  rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

SwapQuote _quote({
  String? sellAmountTextOverride,
  BigInt? sellAmountBaseUnits,
}) {
  return SwapQuote(
    direction: SwapDirection.zecToExternal,
    sellAsset: SwapAsset.zec,
    receiveAsset: SwapAsset.usdc,
    externalAsset: SwapAsset.usdc,
    sellAmount: 0.001,
    receiveAmount: 0.07,
    minimumReceiveAmount: 0.069,
    providerLabel: 'NEAR Intents',
    feeLabel: 'Included in shown rate',
    expiryLabel: '07:12',
    depositInstruction: const SwapDepositInstruction(
      asset: SwapAsset.zec,
      address: 't1deposit',
      expiresInLabel: '07:12',
      reuseWarning: 'Do not reuse this address',
    ),
    sellAmountTextOverride: sellAmountTextOverride,
    sellAmountBaseUnits: sellAmountBaseUnits,
  );
}

SwapIntent _intent({
  required String sellAmount,
  BigInt? sellAmountBaseUnits,
  String depositAddress = 't1deposit',
}) {
  return SwapIntent(
    id: 't1deposit',
    pair: 'ZEC -> USDC',
    sellAmount: sellAmount,
    sellAmountBaseUnits: sellAmountBaseUnits,
    receiveEstimate: '0.07 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.awaitingDeposit,
    nextAction: 'Sign deposit',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: depositAddress,
  );
}

class _RustApiFake implements RustLibApi {
  int proposeSendCalls = 0;

  /// The network the last address validation was asked about.
  String? lastValidatedNetwork;

  void reset() {
    proposeSendCalls = 0;
    lastValidatedNetwork = null;
  }

  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
    required String network,
  }) async {
    lastValidatedNetwork = network;
    if (address == _texAddress) {
      return const AddressValidationResult(
        isValid: true,
        addressType: 'tex',
        wrongNetwork: false,
      );
    }
    return const AddressValidationResult(
      isValid: true,
      addressType: 'transparent',
      wrongNetwork: false,
    );
  }

  @override
  Future<ProposalResult> crateApiSyncProposeSend({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String sendFlowId,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async {
    proposeSendCalls++;
    return ProposalResult(
      proposalId: BigInt.one,
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';
