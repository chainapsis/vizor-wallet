// ignore_for_file: depend_on_referenced_packages
// Dev-only entry point for inspecting the swap prototype without touching
// wallet bootstrap, secure storage, Rust sync, or a real 1Click provider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'src/app_bootstrap.dart';
import 'src/core/config/rpc_endpoint_config.dart';
import 'src/core/theme/app_theme.dart';
import 'src/features/receive/models/receive_prefill_args.dart';
import 'src/features/send/models/send_prefill_args.dart';
import 'src/features/swap/models/swap_prototype_models.dart';
import 'src/features/swap/providers/swap_prototype_provider.dart';
import 'src/features/swap/providers/swap_deposit_sender.dart';
import 'src/features/swap/providers/swap_max_amount_estimator.dart';
import 'src/features/swap/providers/swap_session_store.dart';
import 'src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'src/features/swap/screens/swap_screen.dart';
import 'src/providers/account_models.dart';
import 'src/providers/receive_address_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final params = Uri.base.queryParameters;
  final initialTab = _previewInitialTab(params);
  final scenario = _previewScenario(params);
  final router = GoRouter(
    initialLocation: '/swap',
    routes: [
      GoRoute(
        path: '/swap',
        builder: (_, _) => SwapScreen(initialTab: initialTab),
      ),
      GoRoute(
        path: '/send',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is! SendPrefillArgs) {
            return const Center(child: Text('Send preview'));
          }
          return Center(
            child: Text(
              'Send prefill: ${extra.address} / ${extra.amountText ?? 'no amount'}',
            ),
          );
        },
      ),
      GoRoute(
        path: '/receive',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is! ReceivePrefillArgs) {
            return const Center(child: Text('Receive preview'));
          }
          return Center(
            child: Text(
              'Receive prefill: ${extra.title} / ${extra.addressType.name}',
            ),
          );
        },
      ),
    ],
  );

  runApp(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_previewBootstrap),
        receiveAddressServiceProvider.overrideWith(
          _PreviewReceiveAddressService.new,
        ),
        swapZecStagingAddressServiceProvider.overrideWith(
          (ref) => SwapZecStagingAddressService(
            loadShieldedAddress: ({required accountUuid}) async {
              return 'u1preview-shielded-recipient';
            },
          ),
        ),
        swapIntentProvider.overrideWithValue(_PreviewSwapProvider()),
        swapDepositSenderProvider.overrideWithValue(_PreviewDepositSender()),
        swapMaxAmountEstimatorProvider.overrideWithValue(
          _PreviewMaxAmountEstimator(),
        ),
        swapSessionStoreProvider.overrideWithValue(
          _PreviewSwapSessionStore(initialIntents: _previewIntents(scenario)),
        ),
        swapStatusPollIntervalProvider.overrideWithValue(
          const Duration(minutes: 10),
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
}

SwapScreenInitialTab _previewInitialTab(Map<String, String> params) {
  const tabOverride = String.fromEnvironment('ZCASH_SWAP_PREVIEW_TAB');
  final tab = tabOverride.isNotEmpty ? tabOverride : params['tab'];
  return switch (tab) {
    'activity' => SwapScreenInitialTab.activity,
    'requests' => SwapScreenInitialTab.requests,
    _ => SwapScreenInitialTab.swap,
  };
}

String _previewScenario(Map<String, String> params) {
  const scenarioOverride = String.fromEnvironment(
    'ZCASH_SWAP_PREVIEW_SCENARIO',
  );
  return scenarioOverride.isNotEmpty
      ? scenarioOverride
      : params['scenario'] ?? 'default';
}

List<SwapPrototypeIntent> _previewIntents(String scenario) {
  if (scenario != 'long') return const [];
  return [
    SwapPrototypeIntent(
      id: 'swap-long-provider-data',
      title: 'USDC to ZEC',
      pair: 'USDC -> ZEC',
      sellAmount: '12345.678901 USDC',
      receiveEstimate: '~175.9421 ZEC',
      provider: 'NEAR Intents',
      status: SwapIntentStatus.awaitingExternalDeposit,
      nextAction:
          'Send the external deposit, then submit the source-chain transaction hash after confirmation.',
      steps: const [
        SwapPrototypeStep(
          label: 'Quote locked',
          state: SwapPrototypeStepState.done,
          evidence: 'Stored locally',
        ),
        SwapPrototypeStep(
          label: 'Awaiting external deposit',
          state: SwapPrototypeStepState.active,
          evidence: 'Waiting for source-chain confirmation',
        ),
      ],
      exposure: const [
        SwapPrototypeField(
          label: 'Deposit address',
          value:
              'one-time USDC address with source-chain routing metadata visible',
        ),
        SwapPrototypeField(
          label: 'Refund path',
          value:
              'USDC refunds return to the long source-chain address entered during review',
        ),
      ],
      receipt: const [
        SwapPrototypeField(label: 'Swap id', value: 'swap-long-provider-data'),
        SwapPrototypeField(
          label: 'Deposit',
          value:
              '0xone-time-usdc-deposit-address-with-a-long-provider-suffix-abcdef1234567890',
        ),
        SwapPrototypeField(
          label: 'Memo',
          value:
              'memo-with-a-long-routing-tag-and-provider-reference-9876543210',
        ),
      ],
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      depositAddress:
          '0xone-time-usdc-deposit-address-with-a-long-provider-suffix-abcdef1234567890',
      depositMemo:
          'memo-with-a-long-routing-tag-and-provider-reference-9876543210',
      oneClickRefundTo:
          '0xrefund-address-with-a-very-long-source-chain-suffix-abcdef1234567890',
    ),
  ];
}

final _previewBootstrap = AppBootstrapState(
  initialLocation: '/swap',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1swapprototypeaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _PreviewReceiveAddressService extends ReceiveAddressService {
  _PreviewReceiveAddressService(super.ref);

  @override
  Future<String> loadTransparentAddress({required String accountUuid}) async {
    return 't1preview-shield-prompt-staging';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return 'u1preview-shielded-recipient';
  }
}

class _PreviewSwapProvider implements SwapProvider {
  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return swapExternalAssets;
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    final estimate = SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      sellAmount: request.sellAmount,
      providerLabel: providerLabel,
    );
    return SwapQuote(
      direction: estimate.direction,
      sellAsset: estimate.sellAsset,
      receiveAsset: estimate.receiveAsset,
      externalAsset: estimate.externalAsset,
      sellAmount: estimate.sellAmount,
      receiveAmount: estimate.receiveAmount,
      minimumReceiveAmount: estimate.minimumReceiveAmount,
      providerLabel: estimate.providerLabel,
      feeLabel: estimate.feeLabel,
      expiryLabel: estimate.expiryLabel,
      providerQuoteId: 'quote-preview',
      providerSignature: 'sig-preview',
      depositInstruction: SwapDepositInstruction(
        asset: estimate.sellAsset,
        address: estimate.direction.sendsZec
            ? 't1preview-deposit'
            : '0xpreview-usdc-deposit',
        expiresInLabel: estimate.expiryLabel,
        reuseWarning: 'Do not reuse this address',
        memo: 'memo-preview',
      ),
    );
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    return SwapIntentSnapshot.fromQuote(
      quote,
      id: quote.depositInstruction.address,
    );
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    return SwapIntentSnapshot(
      id: intentId,
      providerLabel: providerLabel,
      pairText: 'USDC -> ZEC',
      sellAmountText: '12345.678901 USDC',
      receiveEstimateText: '~175.9421 ZEC',
      status: SwapIntentStatus.awaitingExternalDeposit,
      nextAction:
          'Send the external deposit, then submit the source-chain transaction hash after confirmation.',
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.usdc,
        address: intentId,
        expiresInLabel: '07:12',
        reuseWarning: 'Do not reuse this address',
        memo: depositMemo ?? 'memo-preview',
      ),
    );
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    return SwapIntentSnapshot(
      id: depositAddress,
      providerLabel: providerLabel,
      pairText: 'USDC -> ZEC',
      sellAmountText: '12345.678901 USDC',
      receiveEstimateText: '~175.9421 ZEC',
      status: SwapIntentStatus.depositObserved,
      nextAction: 'Deposit detected by 1Click',
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.usdc,
        address: depositAddress,
        expiresInLabel: '07:12',
        reuseWarning: 'Do not reuse this address',
        memo: depositMemo,
      ),
    );
  }
}

class _PreviewDepositSender implements SwapDepositSender {
  @override
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    return BigInt.from(10000);
  }

  @override
  Future<String> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    return 'zec-preview-txid';
  }
}

class _PreviewMaxAmountEstimator implements SwapMaxAmountEstimator {
  @override
  Future<BigInt> estimateMaxZecSellAmount({required String accountUuid}) async {
    return BigInt.from(1247900000);
  }
}

class _PreviewSwapSessionStore implements SwapSessionStore {
  _PreviewSwapSessionStore({required List<SwapPrototypeIntent> initialIntents})
    : _intents = [...initialIntents];

  List<SwapPrototypeIntent> _intents;
  SwapDraftSnapshot? _draft;

  @override
  Future<List<SwapPrototypeIntent>> loadIntents({
    required String accountUuid,
  }) async {
    return _intents;
  }

  @override
  Future<void> saveIntents({
    required String accountUuid,
    required List<SwapPrototypeIntent> intents,
  }) async {
    _intents = [...intents];
  }

  @override
  Future<SwapDraftSnapshot?> loadDraft() async {
    return _draft;
  }

  @override
  Future<void> saveDraft(SwapDraftSnapshot draft) async {
    _draft = draft;
  }
}
