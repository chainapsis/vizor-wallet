import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import '../src/core/layout/app_form_factor.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/payments/cross_chain_payment_request.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_modal_card.dart';
import '../src/core/widgets/app_modal_overlay_scope.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/features/pay/models/payment_request_resolution.dart';
import '../src/features/pay/widgets/cross_chain_payment_request_card.dart';
import '../src/features/swap/domain/swap_asset.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';
import '../src/features/swap/widgets/swap_slippage_modal.dart';

const _evmRecipient = '0x52908400098527886E0F7030069857D2E4169EE7';
const _bitcoinRecipient = '1FsSia9rv4NeEwvJ2GvXrX7LyxYspbN2mo';
const _litecoinRecipient = 'LT2KVaAy1ppRuxRgrS5RNU3vBsy7RibPeA';
const _solanaRecipient = 'mvines9iiHiQTysrwkJjGf2gb9Ex9jXJX8ns3qwf2kN';
const _baseUsdc = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _ethereumUsdc = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
const _solanaUsdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

/// Offline request and asset metadata. The production resolver and card render
/// these examples without wallet storage, a Rust runtime, or pricing requests.
class CrossChainPaymentRequestExample {
  const CrossChainPaymentRequestExample({
    required this.id,
    required this.name,
    required this.request,
    required this.assets,
  });

  final String id;
  final String name;
  final CrossChainPaymentRequest request;
  final List<SwapAsset> assets;
}

final crossChainPaymentRequestExamples = <CrossChainPaymentRequestExample>[
  _evmExample(chainId: '8453', contract: _baseUsdc),
  _evmExample(chainId: '1', contract: _ethereumUsdc),
  _displayExample(
    id: 'bitcoin',
    name: 'Bitcoin - BTC',
    scheme: 'bitcoin',
    chain: 'btc',
    symbol: 'BTC',
    decimals: 8,
    address: _bitcoinRecipient,
    amount: '0.00123456',
  ),
  _displayExample(
    id: 'litecoin',
    name: 'Litecoin - LTC',
    scheme: 'litecoin',
    chain: 'ltc',
    symbol: 'LTC',
    decimals: 8,
    address: _litecoinRecipient,
    amount: '1.23456789',
  ),
  _displayExample(
    id: 'solana-usdc',
    name: 'Solana - USDC',
    scheme: 'solana',
    chain: 'sol',
    symbol: 'USDC',
    decimals: 6,
    address: _solanaRecipient,
    amount: '25',
    contract: _solanaUsdc,
  ),
  _displayExample(
    id: 'solana',
    name: 'Solana - SOL',
    scheme: 'solana',
    chain: 'sol',
    symbol: 'SOL',
    decimals: 9,
    address: _solanaRecipient,
    amount: '0.125',
  ),
  for (final chainId in evmPaymentNetworks.keys) _evmExample(chainId: chainId),
  _evmExample(chainId: '8453', includeAmount: false),
  _evmExample(),
  _evmExample(includeAmount: false),
  _displayExample(
    id: 'requester-details',
    name: 'Requester details',
    scheme: 'bitcoin',
    chain: 'btc',
    symbol: 'BTC',
    decimals: 8,
    address: _bitcoinRecipient,
    amount: '0.000125',
    label: 'Coffee corner',
    message: 'Order 1042: two coffees and a pastry.',
  ),
  _displayExample(
    id: 'requester-details-long',
    name: 'Requester details - long message',
    scheme: 'bitcoin',
    chain: 'btc',
    symbol: 'BTC',
    decimals: 8,
    address: _bitcoinRecipient,
    amount: '0.00125',
    label: 'Coffee corner catering - invoice 1042',
    message:
        'Invoice 1042 covers coffee, tea, pastries, and lunch for the team. '
        'Delivery is scheduled for the morning of the event at the address '
        'provided when the order was placed. The order includes vegetarian '
        'options and individually packed desserts. '
        'If the delivery time or the number of guests has changed, please '
        'contact the shop before paying so the order can be updated. '
        'Keep this invoice number when contacting us about the order.',
  ),
];

CrossChainPaymentRequestExample _displayExample({
  required String id,
  required String name,
  required String scheme,
  required String chain,
  required String symbol,
  required int decimals,
  required String address,
  required String amount,
  String? contract,
  String? label,
  String? message,
}) => CrossChainPaymentRequestExample(
  id: id,
  name: name,
  request: CrossChainPaymentRequest(
    id: 'widgetbook-$id',
    rawUri:
        '$scheme:$address?amount=$amount'
        '${contract == null ? '' : '&spl-token=$contract'}'
        '${label == null ? '' : '&label=${Uri.encodeComponent(label)}'}'
        '${message == null ? '' : '&message=${Uri.encodeComponent(message)}'}',
    address: address,
    isEvm: false,
    chain: chain,
    contractAddress: contract,
    amount: PaymentRequestAmount.display(amount),
    label: label,
    message: message,
  ),
  assets: [
    SwapAsset.live(
      assetId: 'widgetbook:$id',
      symbol: symbol,
      blockchain: chain,
      decimals: decimals,
      contractAddress: contract,
    ),
  ],
);

CrossChainPaymentRequestExample _evmExample({
  String? chainId,
  String? contract,
  bool includeAmount = true,
}) {
  final network = evmPaymentNetworks[chainId];
  final symbol = contract == null ? network?.nativeSymbol ?? 'ETH' : 'USDC';
  final id = network == null
      ? 'choose-network${includeAmount ? '' : '-no-amount'}'
      : '${network.chain}-${symbol.toLowerCase()}'
            '${includeAmount ? '' : '-no-amount'}';
  final atomicAmount = contract == null ? '10000000000000000' : '25000000';
  final target = contract ?? _evmRecipient;
  final suffix = contract == null ? '' : '/transfer?address=$_evmRecipient';
  final amountQuery = !includeAmount
      ? ''
      : contract == null
      ? '?value=$atomicAmount'
      : '&uint256=$atomicAmount';
  return CrossChainPaymentRequestExample(
    id: id,
    name: network == null
        ? 'EVM - choose a network${includeAmount ? '' : ' - no amount'}'
        : '${network.label} - $symbol'
              '${includeAmount ? '' : ' - no amount'}',
    request: CrossChainPaymentRequest(
      id: 'widgetbook-$id',
      rawUri:
          'ethereum:$target${chainId == null ? '' : '@$chainId'}'
          '$suffix$amountQuery',
      address: _evmRecipient,
      isEvm: true,
      chainId: chainId,
      contractAddress: contract,
      amount: includeAmount
          ? PaymentRequestAmount.atomicHex(
              '0x${BigInt.parse(atomicAmount).toRadixString(16)}',
            )
          : null,
    ),
    assets: [
      if (network != null)
        SwapAsset.live(
          assetId: 'widgetbook:$id',
          symbol: symbol,
          blockchain: network.chain,
          decimals: contract == null ? 18 : 6,
          contractAddress: contract,
        )
      else
        for (final network in evmPaymentNetworks.values)
          SwapAsset.live(
            assetId: 'widgetbook:${network.chain}-native',
            symbol: network.nativeSymbol,
            blockchain: network.chain,
            decimals: 18,
          ),
    ],
  );
}

Widget buildCrossChainPaymentRequestUseCase(
  BuildContext context,
  CrossChainPaymentRequestExample example, {
  required bool isMobile,
  bool showSlippageSettings = false,
}) => _RequestPreview(
  key: ValueKey('${example.id}-$isMobile-$showSlippageSettings'),
  example: example,
  isMobile: isMobile,
  initialSlippageOpen: showSlippageSettings,
);

Widget buildPaymentRequestSlippageUseCase(BuildContext context) =>
    _capturePreview(context, 'base-usdc', showSlippageSettings: true);

Widget buildPaymentRequestRequesterDetailsUseCase(BuildContext context) =>
    _capturePreview(context, 'requester-details');

Widget buildPaymentRequestLongRequesterDetailsUseCase(BuildContext context) =>
    _capturePreview(context, 'requester-details-long');

// Shared capture entry points select the tokens and shell of the compiled lane.
Widget buildBaseUsdcPaymentRequestUseCase(BuildContext context) =>
    _capturePreview(context, 'base-usdc');

Widget buildBitcoinPaymentRequestUseCase(BuildContext context) =>
    _capturePreview(context, 'bitcoin');

Widget buildLitecoinPaymentRequestUseCase(BuildContext context) =>
    _capturePreview(context, 'litecoin');

Widget buildSolanaUsdcPaymentRequestUseCase(BuildContext context) =>
    _capturePreview(context, 'solana-usdc');

Widget _capturePreview(
  BuildContext context,
  String id, {
  bool showSlippageSettings = false,
}) => buildCrossChainPaymentRequestUseCase(
  context,
  crossChainPaymentRequestExamples.singleWhere((example) => example.id == id),
  isMobile: kAppFormFactor == AppFormFactor.mobile,
  showSlippageSettings: showSlippageSettings,
);

class _RequestPreview extends StatefulWidget {
  const _RequestPreview({
    required this.example,
    required this.isMobile,
    this.initialSlippageOpen = false,
    super.key,
  });

  final CrossChainPaymentRequestExample example;
  final bool isMobile;
  final bool initialSlippageOpen;

  @override
  State<_RequestPreview> createState() => _RequestPreviewState();
}

class _RequestPreviewState extends State<_RequestPreview> {
  String? _selectedChain;
  int _slippageBps = 50;
  late bool _editingSlippage = widget.initialSlippageOpen;
  bool _dismissed = false;
  bool _closingRequest = false;

  @override
  Widget build(BuildContext context) {
    final example = widget.example;
    final mobile = widget.isMobile;
    final size = mobile ? const Size(393, 852) : const Size(800, 720);
    final resolution = resolveCrossChainPaymentRequest(
      example.request,
      example.assets,
      selectedChain: _selectedChain,
    );
    void closeRequest() => setState(() => _dismissed = true);
    void beginClosingRequest() {
      if (!_closingRequest) setState(() => _closingRequest = true);
    }

    void dismissRequest() {
      if (mobile) {
        beginClosingRequest();
      } else {
        closeRequest();
      }
    }

    // Fixed preview rates in external tokens per ZEC, not live market prices.
    final rates = {
      for (final asset in example.assets)
        asset: switch (asset.symbol) {
          'USDC' => 100.0,
          'BTC' => 0.001,
          'LTC' => 1.25,
          'SOL' => 0.5,
          'ETH' => 0.025,
          'BNB' => 0.125,
          'POL' => 500.0,
          'OKB' => 1.0,
          'AVAX' => 5.0,
          _ => 0.0,
        },
    };
    final card = Material(
      type: MaterialType.transparency,
      child: CrossChainPaymentRequestCard(
        request: example.request,
        resolution: resolution,
        estimatedZecAmount: resolution.estimateZecAmount(rates),
        selectedChain: _selectedChain,
        isMobile: mobile,
        slippageBps: _slippageBps,
        onOpenSlippage: () => setState(() => _editingSlippage = true),
        onNetworkSelected: (chain) => setState(() => _selectedChain = chain),
        onContinue: () {},
        onEdit: () {},
        onCancel: dismissRequest,
        onRetry: () {},
      ),
    );
    void closeSlippage() => setState(() => _editingSlippage = false);
    void updateSlippage(int bps) => setState(() {
      _slippageBps = bps;
      _editingSlippage = false;
    });
    final editor = !_editingSlippage
        ? null
        : Material(
            type: MaterialType.transparency,
            child: mobile
                ? MobileSwapSlippageStepperModal(
                    slippageBps: _slippageBps,
                    paymentMode: true,
                    onSubmitted: updateSlippage,
                    onCancel: closeSlippage,
                  )
                : SwapSlippageModal(
                    slippageBps: _slippageBps,
                    paymentMode: true,
                    onSubmitted: updateSlippage,
                    onCancel: closeSlippage,
                    onBack: closeSlippage,
                  ),
          );
    final preview = SizedBox(
      key: const ValueKey('cross_chain_payment_request_preview_frame'),
      width: size.width,
      height: size.height,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(size: size),
        child: ColoredBox(
          color: context.colors.background.ground,
          child: Stack(
            children: [
              if (!_dismissed)
                AppModalOverlayScope(
                  child: AppPaneModalOverlay(
                    onDismiss: dismissRequest,
                    alignment: mobile
                        ? Alignment.bottomCenter
                        : Alignment.center,
                    child: mobile
                        ? SafeArea(
                            bottom: false,
                            minimum: const EdgeInsets.only(
                              top: AppSpacing.base,
                            ),
                            child: AppDraggableMobileSheet(
                              key: ValueKey((
                                example.request.id,
                                _editingSlippage,
                              )),
                              dismissRequested: _closingRequest,
                              onClosing: beginClosingRequest,
                              onDismiss: closeRequest,
                              child: MobileModalCard(
                                onBack: _editingSlippage ? closeSlippage : null,
                                child:
                                    editor ??
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.sm,
                                        AppSpacing.md,
                                        AppSpacing.sm,
                                        AppSpacing.base,
                                      ),
                                      child: card,
                                    ),
                              ),
                            ),
                          )
                        : editor == null
                        ? AppModalCard(width: 396, child: card)
                        : SizedBox(width: 396, child: editor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Center(
      // Keep the phone viewport intact when Widgetbook's canvas is shorter.
      child: mobile
          ? FittedBox(fit: BoxFit.scaleDown, child: preview)
          : preview,
    );
  }
}
