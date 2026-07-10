// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/layout/mobile/mobile_bottom_safe_area.dart';
import '../src/core/layout/mobile/mobile_top_nav.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/pay/models/pay_recent_recipients.dart';
import '../src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_add_contact_card.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_amount_step.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_recipient_step.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_review_content.dart';
import '../src/features/swap/models/swap_deposit_broadcast_result.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/providers/swap_state_provider.dart';

const _mikeAddress = '0x52908400098527886E0F7030069857D2E4169EE7';
const _aliceAddress = '0xde709f2102306220921060314715629080e2fb77';
const _newAddress = '0x1111111111111111111111111111111111111111';

const _payContacts = [
  AddressBookContact(
    id: 'widgetbook-pay-mike',
    label: 'Mike',
    network: AddressBookNetwork.ethereum,
    address: _mikeAddress,
    profilePictureId: 'pfp-01',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
  AddressBookContact(
    id: 'widgetbook-pay-alice',
    label: 'Alice',
    network: AddressBookNetwork.ethereum,
    address: _aliceAddress,
    profilePictureId: 'pfp-02',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
];

final _payRecents = [
  PayRecentRecipient(
    address: _mikeAddress,
    amountText: '990 USDC',
    lastUsedAt: DateTime(2026, 7, 8),
  ),
  PayRecentRecipient(
    address: _aliceAddress,
    amountText: '125 USDC',
    lastUsedAt: DateTime(2026, 4, 27),
  ),
];

const _payAmountState = SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '2.251',
  receiveAmountText: '990',
  receiveFiatText: '990.00',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  payMode: true,
);

const _payAmountEmptyState = SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '',
  receiveAmountText: '',
  receiveFiatText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  pricingLoading: true,
  payMode: true,
);

const _payAmountRefreshingState = SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '2.251',
  receiveAmountText: '990',
  receiveFiatText: '990.00',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  pricingLoading: true,
  payMode: true,
);

const _paySubmittedIntent = SwapIntent(
  id: 'widgetbook-pay-intent',
  pair: 'ZEC -> USDC',
  sellAmount: '2.251 ZEC',
  receiveEstimate: '990 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Payment submitted',
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositTxHash: 'widgetbook-pay-deposit-txid',
  broadcastStatus: SwapDepositBroadcastStatus.broadcasted,
  payMode: true,
);

const _paySubmittedState = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [_paySubmittedIntent],
  selectedIntentId: 'widgetbook-pay-intent',
  payMode: true,
);

const _payQuote = SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: SwapAsset.usdc,
  externalAsset: SwapAsset.usdc,
  mode: SwapQuoteMode.exactOutput,
  sellAmount: 2.251,
  receiveAmount: 990,
  minimumReceiveAmount: 990,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '1:30',
  depositInstruction: SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 'u1widgetbookpaydeposit',
    expiresInLabel: '1:30',
    reuseWarning: 'Do not reuse this address',
  ),
  sellAmountTextOverride: '2.251 ZEC',
  receiveEstimateTextOverride: '990 USDC',
);

Widget buildMobilePayAmountUseCase(BuildContext context) {
  return const _MobilePayFrame(
    child: _MobilePayAmountPreview(
      key: ValueKey('mobile_pay_amount_loaded_preview'),
    ),
  );
}

Widget buildMobilePayAmountEmptyUseCase(BuildContext context) {
  return const _MobilePayFrame(
    child: _MobilePayAmountPreview(
      key: ValueKey('mobile_pay_amount_empty_preview'),
      initialState: _payAmountEmptyState,
    ),
  );
}

Widget buildMobilePayAmountRefreshingUseCase(BuildContext context) {
  return const _MobilePayFrame(
    child: _MobilePayAmountPreview(
      key: ValueKey('mobile_pay_amount_refreshing_preview'),
      initialState: _payAmountRefreshingState,
    ),
  );
}

Widget buildMobilePayRecipientUseCase(BuildContext context) {
  return const _MobilePayFrame(
    child: _MobilePayRecipientPreview(
      key: ValueKey('mobile_pay_recipient_initial_preview'),
      state: _MobilePayRecipientPreviewState.initial,
    ),
  );
}

Widget buildMobilePayRecipientNewAddressUseCase(BuildContext context) {
  return const _MobilePayFrame(
    child: _MobilePayRecipientPreview(
      key: ValueKey('mobile_pay_recipient_new_preview'),
      state: _MobilePayRecipientPreviewState.newAddress,
    ),
  );
}

Widget buildMobilePayRecipientMatchedUseCase(BuildContext context) {
  return const _MobilePayFrame(
    child: _MobilePayRecipientPreview(
      key: ValueKey('mobile_pay_recipient_matched_preview'),
      state: _MobilePayRecipientPreviewState.matchedContact,
    ),
  );
}

Widget buildMobilePayAddContactUseCase(BuildContext context) {
  return _MobilePayFrame(
    child: ColoredBox(
      color: context.colors.background.window,
      child: ColoredBox(
        color: context.colors.background.neutralScrim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            MobileModalCard(
              child: MobilePayAddContactCard(
                network: AddressBookNetwork.ethereum,
                address: _newAddress,
                onCancel: _noop,
                onSave: (_, _) async {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildMobilePayReviewUseCase(BuildContext context) {
  return const _MobilePayFrame(child: _MobilePayReviewPreview());
}

Widget buildMobilePayReviewExpiredUseCase(BuildContext context) {
  return const _MobilePayFrame(child: _MobilePayReviewPreview(expired: true));
}

Widget buildMobilePaySubmittedUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      swapStateProvider.overrideWith(() => _WidgetbookPaySubmittedNotifier()),
    ],
    child: const _MobilePayFrame(
      child: MobilePaySubmittedScreen(intentId: 'widgetbook-pay-intent'),
    ),
  );
}

class _WidgetbookPaySubmittedNotifier extends SwapNotifier {
  @override
  SwapState build() => _paySubmittedState;
}

class _MobilePayFrame extends StatelessWidget {
  const _MobilePayFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('mobile_pay_preview_frame'),
      width: 393,
      height: 852,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(size: const Size(393, 852)),
        child: child,
      ),
    );
  }
}

class _MobilePayAmountPreview extends StatefulWidget {
  const _MobilePayAmountPreview({
    this.initialState = _payAmountState,
    super.key,
  });

  final SwapState initialState;

  @override
  State<_MobilePayAmountPreview> createState() =>
      _MobilePayAmountPreviewState();
}

class _MobilePayAmountPreviewState extends State<_MobilePayAmountPreview> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late SwapState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _controller = TextEditingController(text: _state.receiveAmountText);
    _focusNode = FocusNode(
      canRequestFocus: false,
      debugLabel: 'WidgetbookMobilePayAmount',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.s),
            MobileTopNav.back(title: 'Pay in USDC', onBack: _noop),
            Expanded(
              child: MobilePayAmountStep(
                state: _state,
                controller: _controller,
                focusNode: _focusNode,
                zecAvailableZatoshi: BigInt.from(12800000000),
                onAmountChanged: (value) => setState(
                  () => _state = _state.copyWith(receiveAmountText: value),
                ),
                onFiatAmountChanged: (value) => setState(
                  () => _state = _state.copyWith(receiveFiatText: value),
                ),
                onToggleFiatInputMode: _toggleAmountMode,
                onOpenAssetSelector: _noop,
                slippageLabel: '0.5%',
                onOpenSlippage: _noop,
                onContinue: _noop,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleAmountMode() {
    final nextMode = _state.receiveAmountInputMode == SwapAmountInputMode.token
        ? SwapAmountInputMode.fiat
        : SwapAmountInputMode.token;
    setState(() {
      _state = _state.copyWith(receiveAmountInputMode: nextMode);
      _controller.text = nextMode == SwapAmountInputMode.fiat
          ? _state.receiveFiatText
          : _state.receiveAmountText;
    });
  }
}

enum _MobilePayRecipientPreviewState { initial, newAddress, matchedContact }

class _MobilePayRecipientPreview extends StatefulWidget {
  const _MobilePayRecipientPreview({required this.state, super.key});

  final _MobilePayRecipientPreviewState state;

  @override
  State<_MobilePayRecipientPreview> createState() =>
      _MobilePayRecipientPreviewViewState();
}

class _MobilePayRecipientPreviewViewState
    extends State<_MobilePayRecipientPreview> {
  late final TextEditingController _controller;
  late String _typedAddress;

  @override
  void initState() {
    super.initState();
    _typedAddress = switch (widget.state) {
      _MobilePayRecipientPreviewState.initial => '',
      _MobilePayRecipientPreviewState.newAddress => _newAddress,
      _MobilePayRecipientPreviewState.matchedContact => _mikeAddress,
    };
    _controller = TextEditingController(text: _typedAddress);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(title: 'Select Recipient', onBack: _noop),
            Expanded(
              child: MobilePayRecipientStep(
                controller: _controller,
                typedAddress: _typedAddress,
                addressError: null,
                contacts: _payContacts,
                recents: _payRecents,
                busy: false,
                externalAsset: SwapAsset.usdc,
                onAddressChanged: (value) =>
                    setState(() => _typedAddress = value),
                onOpenScanner: _noop,
                onChooseRecipient: _selectRecipient,
                onSelectRecipient: _noop,
                onAddToContacts: _noop,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectRecipient(String address) {
    setState(() {
      _typedAddress = address;
      _controller.text = address;
    });
  }
}

class _MobilePayReviewPreview extends StatelessWidget {
  const _MobilePayReviewPreview({this.expired = false});

  final bool expired;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(title: 'Review Payment', onBack: _noop),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.s,
                ),
                child: MobilePayReviewContent(
                  quote: _payQuote,
                  recipientAddress: _mikeAddress,
                  recipientContact: _payContacts.first,
                  payingFiatText: r'$250.12',
                  convertedFiatText: r'$250.12',
                  expiresInText: '1:30',
                  expired: expired,
                ),
              ),
            ),
            MobileBottomSafeArea(
              bottomPadding: AppSpacing.md,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: MobilePayReviewActions(
                  expired: expired,
                  starting: false,
                  startBlockedReason: null,
                  onConfirm: _noop,
                  onRefreshQuote: _noop,
                  onCancel: _noop,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}
