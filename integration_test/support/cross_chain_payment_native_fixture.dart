import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

const nativePaymentAccountId = '550e8400-e29b-41d4-a716-446655440000';
const nativePaymentPassword = 'PaymentE2E123!';
const nativePaymentRecipient = '0x52908400098527886E0F7030069857D2E4169EE7';
const nativePaymentContract = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const nativeBitcoinUri =
    'bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.00123456';
const nativeEthereumUri =
    'ethereum:$nativePaymentContract@8453/transfer'
    '?address=$nativePaymentRecipient&uint256=25000000';

final nativeBitcoinAsset = SwapAsset.live(
  assetId: 'e2e-bitcoin',
  symbol: 'BTC',
  blockchain: 'btc',
  decimals: 8,
);
final nativeUsdcAsset = SwapAsset.live(
  assetId: 'e2e-base-usdc',
  symbol: 'USDC',
  blockchain: 'base',
  decimals: 6,
  contractAddress: nativePaymentContract,
);

const _account = AccountState(
  accounts: [AccountInfo(uuid: nativePaymentAccountId, name: 'E2E', order: 0)],
  activeAccountUuid: nativePaymentAccountId,
  activeAddress: 'u1e2e-refund-address',
);

/// A funded account snapshot without keys or a live wallet. The actual app
/// router, unlock/password verification, request intake and Pay screens run.
AppBootstrapState nativePaymentBootstrap() => AppBootstrapState(
  initialLocation: '/unlock',
  initialAccountState: _account,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: false,
  passwordRotationRecoveryFailed: false,
);

class NativePaymentAccount extends AccountNotifier {
  @override
  Future<AccountState> build() async => _account;

  @override
  Future<void> restoreAfterUnlock() async {}
}

class NativePaymentSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: nativePaymentAccountId,
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(10000000000),
    totalBalance: BigInt.from(10000000000),
    orchardBalance: BigInt.from(10000000000),
  );

  @override
  void startSync({int? latestTipHeight}) {}

  @override
  Future<void> startSyncAnyway() async {}

  @override
  Future<void> refreshAfterUnlock() async {}

  @override
  Future<void> refreshAfterSend() async {}
}

/// Controls connection outcomes, not the Tor transport. Live Tor bootstrap is
/// deliberately outside this deterministic native UI test.
class NativePaymentPrivacy extends NetworkPrivacyNotifier {
  var retries = 0;

  @override
  NetworkPrivacyState build() => const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connecting,
  );

  void setStatus(NetworkPrivacyConnectionStatus status) {
    state = NetworkPrivacyState(torEnabled: true, status: status);
  }

  @override
  Future<void> retry() async {
    retries++;
    setStatus(NetworkPrivacyConnectionStatus.connecting);
  }
}

/// Deterministic external-service responses. SwapNotifier still performs real
/// asset resolution, amount conversion, quote preparation and navigation.
class NativePaymentPricing implements SwapProvider, SwapPricingProvider {
  final tokens = Completer<SwapPricingSnapshot>();
  final quotes = <SwapQuoteRequest>[];

  void releaseTokens() => tokens.complete(
    SwapPricingSnapshot(
      usdPrices: {
        SwapAsset.zec: 100,
        nativeBitcoinAsset: 60000,
        nativeUsdcAsset: 1,
      },
    ),
  );

  @override
  String get providerLabel => 'Native payment E2E fixture';

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({
    bool forceRefresh = false,
  }) => tokens.future;

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() =>
      throw StateError('Expected the token snapshot');

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    quotes.add(request);
    return SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      mode: request.mode,
      amount: request.amount,
      externalPerZec: request.externalAsset == nativeUsdcAsset ? 100 : 1 / 600,
      providerLabel: providerLabel,
    );
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) => throw StateError('This test must stop before creating a payment');

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) =>
      throw StateError('This test must never start a payment');

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) => throw StateError('This test must never broadcast a payment');
}
