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
import '../src/features/address_book/models/address_format_validator.dart';
import '../src/features/pay/models/pay_recent_recipients.dart';
import '../src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_add_contact_card.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_amount_step.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_recipient_step.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_review_content.dart';
import '../src/features/swap/models/swap_deposit_broadcast_result.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/providers/swap_state_provider.dart';
import 'pay_use_cases.dart'
    show payAmountFixtureFieldText, payAmountFixtureState, payFixtureKey;
import 'support/wb_layout.dart';

const _mikeAddress = '0x52908400098527886E0F7030069857D2E4169EE7';
const _newAddress = '0x1111111111111111111111111111111111111111';

/// Addresses the mobile recipient-step knobs pick between.
const String mobilePayFixtureKnownAddress = _mikeAddress;
const String mobilePayFixtureUnknownAddress = _newAddress;
const String mobilePayFixtureInvalidAddress = '0x1234';

/// Contact preselected when the typed address is
/// [mobilePayFixtureKnownAddress]; both preview contacts share it, so the row
/// shows the duplicate selection indicator.
const String mobilePayFixtureSelectedContactId = 'widgetbook-pay-mike';

const _mobilePayRecipientQuoteError =
    'This route or address was rejected.\n'
    'Edit the details and request a new quote.';
const _mobilePayBlockedReason =
    "You don't have enough ZEC for this payment. Try a smaller amount.";

/// Spendable ZEC the amount step compares the quote against. The starved
/// balance is what drives the step's own 'Not enough ZEC' line.
final _mobilePayZecAvailable = BigInt.from(12800000000);
final _mobilePayZecStarved = BigInt.one;

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
    address: _mikeAddress,
    profilePictureId: 'pfp-02',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
];

final _payRecents = [
  PayRecentRecipient(
    address: _mikeAddress,
    contactId: 'widgetbook-pay-mike',
    amountText: '990 USDC',
    lastUsedAt: DateTime(2026, 7, 8),
  ),
  PayRecentRecipient(
    address: _mikeAddress,
    contactId: 'widgetbook-pay-alice',
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

const _paySubmittingIntent = SwapIntent(
  id: 'widgetbook-pay-intent',
  pair: 'ZEC -> USDC',
  sellAmount: '2.251 ZEC',
  receiveEstimate: '990 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Submitting payment',
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  payMode: true,
);

const _payStatusUncertainIntent = SwapIntent(
  id: 'widgetbook-pay-intent',
  pair: 'ZEC -> USDC',
  sellAmount: '2.251 ZEC',
  receiveEstimate: '990 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Check Activity',
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositTxHash: 'widgetbook-pay-deposit-txid',
  broadcastStatus: SwapDepositBroadcastStatus.pendingBroadcast,
  broadcastNotice:
      'The network did not acknowledge this payment yet. '
      'Check Activity before trying again.',
  payMode: true,
);

const _payFailedIntent = SwapIntent(
  id: 'widgetbook-pay-intent',
  pair: 'ZEC -> USDC',
  sellAmount: '2.251 ZEC',
  receiveEstimate: '990 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Try again',
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  statusError: 'The payment could not be submitted. Try again.',
  payMode: true,
);

/// Base composer state every Pay-submitted phase varies from; only the intent
/// list and the submission flags change between them.
const _payHandoffState = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  selectedIntentId: 'widgetbook-pay-intent',
  payMode: true,
);

const _paySubmittingState = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [_paySubmittingIntent],
  selectedIntentId: 'widgetbook-pay-intent',
  depositSubmitting: true,
  payMode: true,
);

const _payStatusUncertainState = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [_payStatusUncertainIntent],
  selectedIntentId: 'widgetbook-pay-intent',
  payMode: true,
);

const _payFailedState = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [_payFailedIntent],
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
    ),
  );
}

Widget buildMobilePayRecipientNewAddressUseCase(BuildContext context) {
  return const _MobilePayFrame(
    child: _MobilePayRecipientPreview(
      key: ValueKey('mobile_pay_recipient_new_preview'),
      initialAddress: _newAddress,
    ),
  );
}

Widget buildMobilePayRecipientMatchedUseCase(BuildContext context) {
  return const _MobilePayFrame(
    child: _MobilePayRecipientPreview(
      key: ValueKey('mobile_pay_recipient_matched_preview'),
      initialAddress: _mikeAddress,
    ),
  );
}

/// Mobile amount step across its knob axes; the composer state is shared with
/// the desktop fixture so both lanes render the same case.
Widget mobilePayAmountStepFixture({
  bool fiatMode = false,
  bool emptyAmount = false,
  bool pricingLoading = false,
  bool priceUnavailable = false,
  bool tooManyDecimals = false,
  bool assetUnavailable = false,
  bool quoteFailed = false,
  bool notEnoughZec = false,
}) {
  return _MobilePayFrame(
    child: _MobilePayAmountPreview(
      key: payFixtureKey('mobile_pay_amount_gallery_', [
        fiatMode,
        emptyAmount,
        pricingLoading,
        priceUnavailable,
        tooManyDecimals,
        assetUnavailable,
        quoteFailed,
        notEnoughZec,
      ]),
      initialState: payAmountFixtureState(
        fiatMode: fiatMode,
        emptyAmount: emptyAmount,
        pricingLoading: pricingLoading,
        priceUnavailable: priceUnavailable,
        tooManyDecimals: tooManyDecimals,
        assetUnavailable: assetUnavailable,
        quoteFailed: quoteFailed,
      ),
      zecAvailableZatoshi: notEnoughZec ? _mobilePayZecStarved : null,
    ),
  );
}

/// Mobile recipient step across its knob axes. [address] selects between the
/// `mobilePayFixture*Address` constants; the format error derives from it.
Widget mobilePayRecipientStepFixture({
  String address = '',
  bool showContacts = true,
  bool showRecents = true,
  bool busy = false,
  bool enabled = true,
  bool routeRejected = false,
}) {
  return _MobilePayFrame(
    child: _MobilePayRecipientPreview(
      key: payFixtureKey('mobile_pay_recipient_gallery_', [
        address,
        showContacts,
        showRecents,
        busy,
        enabled,
        routeRejected,
      ]),
      initialAddress: address,
      quoteError: routeRejected ? _mobilePayRecipientQuoteError : null,
      contacts: showContacts ? _payContacts : const [],
      recents: showRecents ? _payRecents : const [],
      busy: busy,
      enabled: enabled,
      selectedContactId: address == mobilePayFixtureKnownAddress
          ? mobilePayFixtureSelectedContactId
          : null,
    ),
  );
}

/// Mobile review content and its bottom actions across their knob axes.
Widget mobilePayReviewFixture({
  bool expired = false,
  String? expiresInText = '1:30',
  bool knownRecipient = true,
  bool showFiat = true,
  bool starting = false,
  bool notEnoughZec = false,
  bool inactive = false,
}) {
  return _MobilePayFrame(
    child: _MobilePayReviewPreview(
      expired: expired,
      expiresInText: expiresInText,
      knownRecipient: knownRecipient,
      showFiat: showFiat,
      starting: starting,
      notEnoughZec: notEnoughZec,
      inactive: inactive,
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

/// The real `MobilePaySubmittedScreen`; [state] is the only input its
/// presentation reads, so every deposit phase is one composer state.
Widget mobilePaySubmittedFixture({SwapState state = _paySubmittedState}) {
  return ProviderScope(
    overrides: [
      swapStateProvider.overrideWith(
        () => _WidgetbookPaySubmittedNotifier(state),
      ),
    ],
    child: const _MobilePayFrame(
      child: MobilePaySubmittedScreen(intentId: 'widgetbook-pay-intent'),
    ),
  );
}

Widget buildMobilePaySubmittedUseCase(BuildContext context) =>
    mobilePaySubmittedFixture();

Widget buildMobilePaySubmittingUseCase(BuildContext context) =>
    mobilePaySubmittedFixture(state: _paySubmittingState);

Widget buildMobilePayStatusUncertainUseCase(BuildContext context) =>
    mobilePaySubmittedFixture(state: _payStatusUncertainState);

Widget buildMobilePayFailedUseCase(BuildContext context) =>
    mobilePaySubmittedFixture(state: _payFailedState);

/// Intent gone after the restore grace: the screen can only point at Activity.
Widget buildMobilePayUnavailableUseCase(BuildContext context) =>
    mobilePaySubmittedFixture(state: _payHandoffState);

/// Intent restored but nothing is submitting it any more.
Widget buildMobilePaySubmissionInterruptedUseCase(BuildContext context) =>
    mobilePaySubmittedFixture(
      state: _payHandoffState.copyWith(intents: const [_paySubmittingIntent]),
    );

class _WidgetbookPaySubmittedNotifier extends SwapNotifier {
  _WidgetbookPaySubmittedNotifier(this.initialState);

  final SwapState initialState;

  @override
  SwapState build() => initialState;
}

class _MobilePayFrame extends StatelessWidget {
  const _MobilePayFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WbScaleDownBox(
      size: const Size(393, 852),
      child: SizedBox(
        key: const ValueKey('mobile_pay_preview_frame'),
        width: 393,
        height: 852,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(size: const Size(393, 852)),
          child: child,
        ),
      ),
    );
  }
}

class _MobilePayAmountPreview extends StatefulWidget {
  const _MobilePayAmountPreview({
    this.initialState = _payAmountState,
    this.zecAvailableZatoshi,
    super.key,
  });

  final SwapState initialState;

  /// Spendable balance the step's 'Not enough ZEC' guard reads.
  final BigInt? zecAvailableZatoshi;

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
    _controller = TextEditingController(
      text: payAmountFixtureFieldText(_state),
    );
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
                zecAvailableZatoshi:
                    widget.zecAvailableZatoshi ?? _mobilePayZecAvailable,
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

class _MobilePayRecipientPreview extends StatefulWidget {
  const _MobilePayRecipientPreview({
    this.initialAddress = '',
    this.quoteError,
    this.contacts,
    this.recents,
    this.busy = false,
    this.enabled = true,
    this.selectedContactId,
    super.key,
  });

  final String initialAddress;
  final String? quoteError;
  final List<AddressBookContact>? contacts;
  final List<PayRecentRecipient>? recents;
  final bool busy;
  final bool enabled;
  final String? selectedContactId;

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
    _typedAddress = widget.initialAddress;
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
    final issue = _typedAddress.trim().isEmpty
        ? null
        : addressFormatIssue(AddressBookNetwork.ethereum, _typedAddress);
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
                addressError: issue,
                quoteError: widget.quoteError,
                contacts: widget.contacts ?? _payContacts,
                recents: widget.recents ?? _payRecents,
                busy: widget.busy,
                enabled: widget.enabled,
                selectedContactId: widget.selectedContactId,
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

  void _selectRecipient(PayRecipientSelection selection) {
    final address = selection.address;
    setState(() {
      _typedAddress = address;
      _controller.text = address;
    });
  }
}

class _MobilePayReviewPreview extends StatelessWidget {
  const _MobilePayReviewPreview({
    this.expired = false,
    this.expiresInText = '1:30',
    this.knownRecipient = true,
    this.showFiat = true,
    this.starting = false,
    this.notEnoughZec = false,
    this.inactive = false,
  });

  final bool expired;

  /// Ticking remainder; null falls back to the quote's static label.
  final String? expiresInText;
  final bool knownRecipient;
  final bool showFiat;
  final bool starting;
  final bool notEnoughZec;
  final bool inactive;

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
                  recipientAddress: knownRecipient ? _mikeAddress : _newAddress,
                  recipientContact: knownRecipient ? _payContacts.first : null,
                  payingFiatText: showFiat ? r'$250.12' : null,
                  convertedFiatText: showFiat ? r'$250.12' : null,
                  expiresInText: expiresInText,
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
                  starting: starting,
                  inactive: inactive,
                  startBlockedReason: notEnoughZec
                      ? _mobilePayBlockedReason
                      : null,
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
