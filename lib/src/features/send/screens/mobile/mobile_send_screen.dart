import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart'
    show InputDecoration, Scaffold, TextField, Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/navigation/payment_uri_busy_surface_provider.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/amount_price_loading_bar.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../../../../core/widgets/mobile/mobile_review_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../core/widgets/mobile/mobile_tx_fee_info_sheet.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../../address_book/widgets/contact_name_inline.dart';
import '../../../../providers/payment_request_flow_provider.dart';
import '../../../migration/providers/ironwood_migration_announcement_provider.dart';
import '../../models/send_scan_result.dart';
import '../../services/send_flow.dart';
import '../../services/send_amount_conversion.dart';
import '../../services/send_proving_key_warmup.dart';
import '../../widgets/send_recipient_resolver.dart';
import '../../widgets/send_review_layout.dart' show SendReviewContactRecipient;
import 'mobile_send_scan_screen.dart';

enum _SendStep { recipient, amount, review }

enum _SendPhase { compose, failed }

enum MobileSendAmountInputMode { zec, usd }

final _mobileSendSpendableStateProvider = Provider.autoDispose
    .family<({BigInt balance, SpendableBalanceFreshness freshness}), String?>((
      ref,
      accountUuid,
    ) {
      final freshness = ref.watch(
        syncProvider.select(
          (value) => (value.value ?? SyncState())
              .scopedToAccount(accountUuid)
              .displaySpendableFreshness,
        ),
      );
      return (
        balance: ref.watch(
          ironwoodMigrationAwareDisplaySpendableProvider(accountUuid),
        ),
        freshness: freshness,
      );
    });

class _ReviewRecipientPresentation {
  const _ReviewRecipientPresentation({
    required this.headline,
    required this.verifyTitle,
    this.profilePictureId,
    this.useZecIcon = false,
  });

  final String headline;
  final String verifyTitle;
  final String? profilePictureId;
  final bool useZecIcon;

  Widget buildReviewLeading() {
    return KeyedSubtree(
      key: const ValueKey('mobile_send_review_recipient_picture'),
      child: useZecIcon
          ? const _ReviewWalletIcon()
          : AppProfilePicture(
              profilePictureId: profilePictureId ?? '',
              size: AppProfilePictureSize.navLarge,
            ),
    );
  }

  Widget? buildVerifyLeading() {
    if (useZecIcon) return const _ReviewWalletIcon();
    return AppProfilePicture(
      profilePictureId: profilePictureId ?? '',
      size: AppProfilePictureSize.large,
    );
  }
}

typedef MobileSendAddressValidator =
    Future<rust_sync.AddressValidationResult> Function({
      required String address,
      required String network,
    });

typedef MobileSendFeeEstimator =
    Future<BigInt> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
      required String toAddress,
      required BigInt amountZatoshi,
      String? memo,
    });

/// [networkName] is the network the wallet is actually on, not the build
/// default: the scanner refuses an address that does not belong to it.
typedef MobileSendScanner =
    Future<SendScanResult?> Function(
      BuildContext context, {
      required String networkName,
    });

class _MobileSendMaxQuote {
  const _MobileSendMaxQuote({
    required this.accountUuid,
    required this.address,
    required this.memo,
    required this.amountZatoshi,
    required this.feeZatoshi,
  });

  final String accountUuid;
  final String address;
  final String memo;
  final BigInt amountZatoshi;
  final BigInt feeZatoshi;
}

class _MobileSendFeeQuote {
  const _MobileSendFeeQuote({
    required this.accountUuid,
    required this.address,
    required this.memo,
    required this.amountZatoshi,
    required this.feeZatoshi,
  });

  final String accountUuid;
  final String address;
  final String memo;
  final BigInt amountZatoshi;
  final BigInt feeZatoshi;

  bool matches({
    required String? accountUuid,
    required String address,
    required String memo,
    required BigInt? amountZatoshi,
    required BigInt? feeZatoshi,
  }) {
    return this.accountUuid == accountUuid &&
        this.address == address &&
        this.memo == memo &&
        this.amountZatoshi == amountZatoshi &&
        this.feeZatoshi == feeZatoshi;
  }
}

class MobileSendAmountArgs {
  const MobileSendAmountArgs({
    required this.sendFlowId,
    required this.recipient,
    required this.addressType,
    this.amountText,
    this.fiatAmountText,
    this.amountInputMode = MobileSendAmountInputMode.zec,
    this.memo,
    this.preserveMemoWhitespace = false,
    this.contactLabel,
    this.contactPictureId,
    this.isPaymentRequest = false,
    this.requestedBy,
    this.requestedAmountZatoshi,
  });

  final String sendFlowId;
  final String recipient;
  final String addressType;

  /// Any amount already composed on the recipient step — a ZIP-321 payment URI
  /// prefills one and can step back in place, so the pushed amount page has to
  /// carry it forward or the payee-requested amount is silently dropped.
  final String? amountText;
  final String? fiatAmountText;
  final MobileSendAmountInputMode amountInputMode;
  final String? memo;
  final bool preserveMemoWhitespace;
  final String? contactLabel;
  final String? contactPictureId;

  /// Payment-request framing carried from the recipient step, already gated
  /// on the recipient still being the one the request named (see
  /// `_isAnsweringPaymentRequest`); the amount and review pages cannot change
  /// the recipient, so passing it on is safe.
  final bool isPaymentRequest;
  final String? requestedBy;
  final BigInt? requestedAmountZatoshi;
}

/// What the pushed `/send/amount` page hands back when it pops.
///
/// The recipient page below it keeps its own copy of the amount so it can seed
/// the next push (a ZIP-321 link prefills one). That copy goes stale the moment
/// the pushed page is edited, so the pushed page returns the amount it actually
/// holds and the recipient page adopts it.
class MobileSendAmountResult {
  const MobileSendAmountResult({
    required this.amountText,
    required this.fiatAmountText,
    required this.amountInputMode,
  });

  /// Canonical ZEC text, whichever input mode composed it.
  final String amountText;
  final String fiatAmountText;
  final MobileSendAmountInputMode amountInputMode;
}

/// Reports a memo the pushed review page saved, so the page that pushed it
/// keeps the same memo and a second review does not restore the copy it was
/// handed before the edit.
typedef MobileSendMemoEditedCallback =
    void Function(String memo, bool preserveWhitespace);

class MobileSendReviewDraftArgs {
  const MobileSendReviewDraftArgs({
    required this.sendFlowId,
    required this.recipient,
    required this.addressType,
    required this.amountText,
    this.feeZatoshi,
    this.isMaxMode = false,
    this.memo,
    this.preserveMemoWhitespace = false,
    this.contactLabel,
    this.contactPictureId,
    this.isPaymentRequest = false,
    this.requestedBy,
    this.requestedAmountZatoshi,
    this.onMemoEdited,
  });

  /// Set by the amount step that pushes the review as a page: the memo it
  /// hands over is a copy, and Back pops through the framework without a
  /// result (system back, the iOS edge swipe), so edits travel back through
  /// this callback instead. Null when the review is the whole stack.
  final MobileSendMemoEditedCallback? onMemoEdited;

  /// Retitles the step "Review payment request".
  final bool isPaymentRequest;

  /// Sanitised requester label from the request, when it carried one.
  final String? requestedBy;

  /// The amount the request asked for; shown only when the reviewed amount
  /// differs from it.
  final BigInt? requestedAmountZatoshi;

  final String sendFlowId;
  final String recipient;
  final String addressType;
  final String amountText;
  final BigInt? feeZatoshi;
  final bool isMaxMode;
  final String? memo;
  final bool preserveMemoWhitespace;
  final String? contactLabel;
  final String? contactPictureId;
}

class MobileSendAmountScreen extends StatelessWidget {
  const MobileSendAmountScreen({required this.args, super.key});

  final MobileSendAmountArgs args;

  @override
  Widget build(BuildContext context) {
    return MobileSendScreen(
      useRouteSteps: true,
      initialAmountStep: true,
      initialSendFlowId: args.sendFlowId,
      initialRecipient: args.recipient,
      initialAddressType: args.addressType,
      initialAmount: args.amountText,
      initialFiatAmount: args.fiatAmountText,
      initialAmountInputMode: args.amountInputMode,
      initialMemo: args.memo,
      preserveInitialMemoWhitespace: args.preserveMemoWhitespace,
      initialContactLabel: args.contactLabel,
      initialContactPictureId: args.contactPictureId,
      isPaymentRequest: args.isPaymentRequest,
      paymentRequestLabel: args.requestedBy,
      requestedAmountZatoshi: args.requestedAmountZatoshi,
    );
  }
}

class MobileSendReviewScreen extends StatelessWidget {
  const MobileSendReviewScreen({required this.args, super.key});

  final MobileSendReviewDraftArgs args;

  @override
  Widget build(BuildContext context) {
    return MobileSendScreen(
      useRouteSteps: true,
      initialReview: true,
      initialAmountReady: true,
      initialSendFlowId: args.sendFlowId,
      initialRecipient: args.recipient,
      initialAddressType: args.addressType,
      initialAmount: args.amountText,
      initialFeeZatoshi: args.feeZatoshi,
      refreshReviewFeeOnInit: true,
      initialMaxMode: args.isMaxMode,
      initialMemo: args.memo,
      preserveInitialMemoWhitespace: args.preserveMemoWhitespace,
      initialContactLabel: args.contactLabel,
      initialContactPictureId: args.contactPictureId,
      isPaymentRequest: args.isPaymentRequest,
      paymentRequestLabel: args.requestedBy,
      requestedAmountZatoshi: args.requestedAmountZatoshi,
      onMemoEdited: args.onMemoEdited,
    );
  }
}

const _kMobileSendRecipientLineHeight = 17.0;
const _kMobileSendAddressActionHeight = 36.0;
const _kMobileSendAddressActionSlotWidth = 96.0;
const _kMobileSendAddressPasteWidth = 76.0;
const _kMobileSendAddressClearWidth = 73.0;
const _kMobileSendAddressErrorGap = AppSpacing.xxs;
const _kMobileSendAddressFieldGroupHeight =
    AppInputSizing.height +
    _kMobileSendAddressErrorGap +
    _kMobileSendRecipientLineHeight;
const _kMobileSendAmountFieldHeight = 164.0;
const _kMobileSendAmountBalanceRowHeight = 44.0;
const _kMobileSendAmountInputHeight = 64.0;
const _kMobileSendAmountMetaHeight = 20.0;
const _kMobileSendAmountZecHintEndInset = 3.7;
const _kMobileSendAmountInputMinWidth = 32.0;
const _kMobileSendAmountInputFallbackMaxWidth = 220.0;
const _kMobileSendAmountCursorBlinkHalfPeriod = Duration(milliseconds: 500);
const _kMobileSendAmountFontSize = 48.0;
const _kMobileSendAmountLineHeightPx = 40.0;
const _kMobileSendAmountUnitFontSize = 38.0;
const _kMobileSendAmountUsdPrefixFontSize = 40.0;
const _kMobileSendAmountUsdPrefixOpticalOffsetY = -2.0;
const _kMobileSendAmountTopContentHeight = 285.0;
const _kMobileSendAmountRecipientBlockHeight = 97.0;
const _kMobileSendAmountRecipientLabelHeight = 25.0;
const _kMobileSendAmountRecipientRowHeight = 68.0;
const _kMobileSendReviewInfoHeight = 268.0;
const _kMobileSendReviewInfoRowHeight = 90.0;
const _kMobileSendReviewInfoDetailsHeight = 89.0;
const _kMobileSendReviewIconRowHeight = 24.0;
const _kMobileSendReviewWrapHeight = 161.0;
const _kMobileSendReviewRowHeight = 32.0;
const _kMobileSendReviewDividerHeight = 1.0;

/// The mobile send wizard — Figma `Send to` → `Enter Amount` →
/// `Review Send` (4423:119950, 4479:47503, 4481:51525) plus the memo
/// modal (4484:62917). This screen owns proposal creation and hands
/// the proposal to the mobile status route for broadcast.
class MobileSendScreen extends ConsumerStatefulWidget {
  const MobileSendScreen({
    this.loadWalletDbPath = getWalletDbPath,
    this.validateAddress,
    this.estimateFee,
    this.openScanner = showMobileSendScanSheet,
    this.useRouteSteps = false,
    this.initialSendFlowId,
    this.initialRecipient,
    this.initialAddressType,
    this.initialAmount,
    this.initialFiatAmount,
    this.initialAmountInputMode = MobileSendAmountInputMode.zec,
    this.initialAmountError,
    this.initialAmountReady = false,
    this.initialAmountStep = false,
    this.initialReview = false,
    this.initialFeeZatoshi,
    this.initialMaxMode = false,
    this.refreshReviewFeeOnInit = false,
    this.initialMemo,
    this.preserveInitialMemoWhitespace = false,
    this.initialContactLabel,
    this.initialContactPictureId,
    this.initialRecipientFocused = false,
    this.isPaymentRequest = false,
    this.paymentRequestLabel,
    this.requestedAmountZatoshi,
    this.onMemoEdited,
    super.key,
  });

  /// Test seam: widget tests cannot complete the real file IO behind
  /// [getWalletDbPath] inside the fake-async zone.
  final Future<String> Function() loadWalletDbPath;

  /// Pre-fills the recipient step (e.g. the accounts row menu's
  /// "Send ZEC" action passes that account's shielded address).
  final String? initialRecipient;
  final String? initialAddressType;

  /// Preview/test seam for opening the amount step with a preset value.
  final bool initialAmountStep;
  final String? initialAmount;
  final String? initialFiatAmount;
  final MobileSendAmountInputMode initialAmountInputMode;
  final String? initialAmountError;
  final bool initialAmountReady;
  final bool initialReview;
  final BigInt? initialFeeZatoshi;
  final bool initialMaxMode;
  final bool refreshReviewFeeOnInit;
  final String? initialMemo;
  final bool preserveInitialMemoWhitespace;
  final String? initialSendFlowId;
  final bool useRouteSteps;

  /// Preview/test seam for recipient summary states.
  final String? initialContactLabel;
  final String? initialContactPictureId;
  final bool initialRecipientFocused;

  /// This send answers a ZIP-321 payment request: the review step is retitled
  /// and its recipient row says who asked. Nothing about the proposal, the
  /// broadcast or the receipt changes.
  final bool isPaymentRequest;

  /// Sanitised `label=` from the request. Carried through to the proposal
  /// and the status receipt; the review UI never renders it.
  final String? paymentRequestLabel;

  /// The amount the request asked for. Rendered under the review info block
  /// only when the reviewed amount differs from it.
  final BigInt? requestedAmountZatoshi;

  /// Preview/test seam for the direct Rust validation call.
  final MobileSendAddressValidator? validateAddress;

  /// Preview/test seam for the direct Rust fee-estimation call.
  final MobileSendFeeEstimator? estimateFee;

  /// Preview/test seam for the mobile scanner sheet.
  final MobileSendScanner openScanner;

  /// Told about every memo this screen saves; see
  /// [MobileSendReviewDraftArgs.onMemoEdited].
  final MobileSendMemoEditedCallback? onMemoEdited;

  @override
  ConsumerState<MobileSendScreen> createState() => _MobileSendScreenState();
}

class _MobileSendScreenState extends ConsumerState<MobileSendScreen> {
  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();
  late final String _sendFlowId = widget.initialSendFlowId ?? newSendFlowId();

  var _step = _SendStep.recipient;
  // True when a ZIP-321 prefill jumped straight to the amount step while the
  // address is still validating; lets us bounce back to the recipient step if
  // the prefilled address turns out invalid (see _maybeFallBackToRecipientStep).
  var _amountJumpPendingAddressCheck = false;
  var _phase = _SendPhase.compose;
  var _isConfirmingSend = false;

  /// Captured in [initState] so the hold can be given back from [dispose]
  /// and from an async continuation that outlives the element.
  late final PaymentUriBusySurfaceNotifier _paymentUriBusySurface;

  /// Whether this screen holds the `paymentUriBusySurfaceProvider` hold it
  /// takes for the confirmation window — see [_confirmAndSend].
  var _holdsConfirmBusySurface = false;

  // Recipient state.
  String _addressType = '';

  /// True when the last validation refused the address only because it belongs
  /// to another Zcash network. `_addressType` stays `'invalid'` so every gate
  /// that already refuses bad addresses keeps refusing this one; the flag only
  /// changes the sentence under the field.
  bool _addressWrongNetwork = false;
  String? _contactLabel;
  String? _contactPictureId;
  int _addressSeq = 0;

  // Amount state. `_amountText` stays canonical ZEC text for Rust/review.
  String _amountText = '';
  String _fiatAmountText = '';
  MobileSendAmountInputMode _amountInputMode = MobileSendAmountInputMode.zec;
  String? _amountError = ''; // null = valid, '' = silently incomplete
  int _validateSeq = 0;
  bool _isMaxMode = false;
  bool _isResolvingMax = false;
  int _maxSeq = 0;
  _MobileSendMaxQuote? _maxQuote;

  // Review state.
  String _memo = '';
  bool _preserveMemoWhitespace = false;
  BigInt? _feeZatoshi;
  _MobileSendFeeQuote? _reviewFeeQuote;
  bool _isRefreshingReviewFee = false;
  bool _reviewFeeRetryAvailable = false;
  String? _reviewFeeNotice;
  int _feeSeq = 0;

  // Failure state.
  String? _error;

  @override
  void initState() {
    super.initState();
    _paymentUriBusySurface = ref.read(paymentUriBusySurfaceProvider.notifier);
    try {
      ref.read(sendProvingKeyWarmupProvider).call();
    } catch (error) {
      log('Send: Orchard proving-key warmup failed to start: $error');
    }
    _addressFocus.addListener(_handleAddressFocusChanged);
    _amountFocus.addListener(_handleAmountFocusChanged);
    final initial = widget.initialRecipient;
    var hasInitialAddressType = false;
    if (initial != null && initial.trim().isNotEmpty) {
      _addressController.text = initial.trim();
      final initialAddressType = widget.initialAddressType?.trim();
      if (initialAddressType != null && initialAddressType.isNotEmpty) {
        _addressType = initialAddressType;
        hasInitialAddressType = true;
      } else {
        unawaited(_validateAddress());
      }
    }
    final initialContactLabel = widget.initialContactLabel;
    if (initialContactLabel != null && initialContactLabel.trim().isNotEmpty) {
      _contactLabel = initialContactLabel.trim();
    }
    _contactPictureId = widget.initialContactPictureId;
    final initialMemo = widget.initialMemo;
    if (initialMemo != null) {
      final memo = widget.preserveInitialMemoWhitespace
          ? initialMemo
          : initialMemo.trim();
      if (memo.isNotEmpty) {
        _memo = memo;
        _preserveMemoWhitespace = widget.preserveInitialMemoWhitespace;
      }
    }
    if (widget.initialAmountStep || widget.initialAmount != null) {
      _step = widget.initialReview ? _SendStep.review : _SendStep.amount;
      // A ZIP-321 payment URI can prefill the amount and skip to the amount
      // step; if the prefilled address validates as invalid, bounce back to the
      // recipient step instead of letting the user continue past the error.
      _amountJumpPendingAddressCheck =
          !widget.initialReview &&
          widget.initialRecipient != null &&
          !hasInitialAddressType;
      _amountText = widget.initialAmount?.trim() ?? '';
      _amountInputMode = widget.initialAmountInputMode;
      _fiatAmountText = widget.initialFiatAmount?.trim() ?? '';
      _amountController.text = _amountInputMode == MobileSendAmountInputMode.usd
          ? _fiatAmountText
          : _amountText;
      _isMaxMode = widget.initialMaxMode;
      if (widget.initialAmountError != null) {
        _amountError = widget.initialAmountError;
      } else if (widget.initialAmountReady || widget.initialReview) {
        _amountError = null;
        _feeZatoshi = widget.initialFeeZatoshi;
        if (_feeZatoshi == null && !widget.refreshReviewFeeOnInit) {
          _feeZatoshi = BigInt.from(10000);
        }
        _seedInitialMaxQuote();
        _seedInitialReviewFeeQuote();
      } else if (_amountText.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_validateAmount());
        });
      }
    }
    if (widget.initialReview && widget.refreshReviewFeeOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshReviewQuote());
      });
    }
    if (widget.initialRecipientFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addressFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    if (_holdsConfirmBusySurface) {
      _holdsConfirmBusySurface = false;
      _paymentUriBusySurface.releaseAfterNavigation();
    }
    _addressFocus.removeListener(_handleAddressFocusChanged);
    _amountFocus.removeListener(_handleAmountFocusChanged);
    _addressController.dispose();
    _addressFocus.dispose();
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  // ── Recipient step ─────────────────────────────────────────────────

  bool get _hasValidAddress =>
      _addressController.text.trim().isNotEmpty &&
      _addressType.isNotEmpty &&
      _addressType != 'invalid' &&
      _addressType != 'error';

  static const _notEnoughZecText = 'Not enough ZEC';

  bool get _activeAccountIsHardware {
    final uuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (uuid == null) return false;
    return ref.read(accountProvider.notifier).isHardwareAccount(uuid);
  }

  bool get _showRecipientContinue =>
      _addressController.text.trim().isNotEmpty || _addressFocus.hasFocus;

  bool get _showRecipientFocusOverlay =>
      _phase == _SendPhase.compose &&
      _step == _SendStep.recipient &&
      _addressFocus.hasFocus;

  // Whether this screen's own page has anything under it.
  //
  // Asks the route this screen sits in, not the navigator: `GoRouter.canPop()`
  // answers "is there more than one page on the stack", which a modal bottom
  // sheet pushed *above* a rootless /send (scanner, memo editor, fee info,
  // full-address sheet) flips to true — and, because that read happens at
  // build time, the true survives the sheet closing and sends the system back
  // out of the app again. `ModalRoute.isFirst` is a fact about this route's
  // position and no sheet can move it.
  //
  // Null means no enclosing route at all (bare widgetbook hosts): the two
  // callers keep their existing defaults for that case, which differ.
  ModalRoute<Object?>? get _enclosingRoute => ModalRoute.of(context);

  // Null (no route) keeps today's `?? false`: fall back to /home rather than
  // calling `context.pop()` where there may be nothing to pop.
  bool get _canPopRoute {
    final route = _enclosingRoute;
    return route != null && !route.isFirst;
  }

  // Drives `PopScope.canPop`, so it decides whether the Android system back /
  // gesture is handled by the framework or handed to [_handleBack]. It has to
  // agree with the toolbar arrow: a payment-URI deep link enters through `go`,
  // which makes `/send` the whole stack, and leaving `canPop` true there lets
  // the press bubble out of the app (backgrounding it) while the arrow lands
  // on /home. Reporting `false` when nothing can be popped routes the press
  // into `onPopInvokedWithResult` → [_handleBack] instead.
  bool get _routePopAllowed {
    if (_phase != _SendPhase.compose) return false;
    if (_isConfirmingSend) return false;
    if (!widget.useRouteSteps && _step != _SendStep.recipient) return false;
    // Without an enclosing route (bare widgetbook renders) there is no way to
    // tell whether a pop would go anywhere, so keep the framework default.
    final route = _enclosingRoute;
    return route == null || !route.isFirst;
  }

  bool get _isShieldedAddress =>
      _addressType == 'unified' || _addressType == 'sapling';

  void _handleAddressFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleAmountFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _validateAddress() async {
    final seq = ++_addressSeq;
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      if (mounted && seq == _addressSeq) {
        setState(() {
          _addressType = '';
          _addressWrongNetwork = false;
        });
      }
      return;
    }
    try {
      final result =
          await (widget.validateAddress ?? rust_sync.validateAddress)(
            address: address,
            network: ref.read(rpcEndpointProvider).networkName,
          );
      if (!mounted || seq != _addressSeq) return;
      setState(() {
        _addressType = result.isValid ? result.addressType : 'invalid';
        _addressWrongNetwork = result.wrongNetwork;
        _maybeFallBackToRecipientStep();
      });
    } catch (e) {
      log('MobileSend: address validation error: $e');
      if (!mounted || seq != _addressSeq) return;
      setState(() {
        _addressType = 'error';
        _addressWrongNetwork = false;
        _maybeFallBackToRecipientStep();
      });
    }
  }

  /// A ZIP-321 payment URI can jump straight to the amount step with the
  /// address + amount prefilled. If the prefilled address does not come back
  /// usable, fall back to the recipient step so the address error is shown
  /// instead of letting the user continue past it.
  ///
  /// Both outcomes bounce: `'invalid'` (validation ran and rejected the
  /// address, shown as "Invalid address") and `'error'` (validation itself
  /// failed, e.g. offline, shown as "Address validation failed"). The amount
  /// step gates its CTA on [_hasValidAddress], which excludes both, so leaving
  /// the user on the amount step after an `'error'` strands them behind a
  /// disabled "Enter amount to continue" button with no way to re-validate.
  /// The recipient step re-runs validation whenever the address changes.
  /// Runs once, for the initial prefill.
  void _maybeFallBackToRecipientStep() {
    if (!_amountJumpPendingAddressCheck) return;
    _amountJumpPendingAddressCheck = false;
    if (_step == _SendStep.amount && !_hasValidAddress) {
      _step = _SendStep.recipient;
    }
  }

  void _handleAddressChanged({bool clearContact = true}) {
    setState(() {
      if (clearContact) {
        _contactLabel = null;
        _contactPictureId = null;
      }
      _addressType = '';
      _addressWrongNetwork = false;
      _invalidateReviewFeeQuote();
      _clearMaxMode();
    });
    unawaited(_validateAddress());
  }

  void _selectContact(AddressBookContact contact) {
    final address = contact.address.trim();
    _addressController.value = TextEditingValue(
      text: address,
      selection: TextSelection.collapsed(offset: address.length),
    );
    setState(() {
      _contactLabel = contact.label.trim().isEmpty
          ? null
          : contact.label.trim();
      _contactPictureId = contact.profilePictureId;
    });
    _handleAddressChanged(clearContact: false);
  }

  Future<void> _openScanner() async {
    final scanned = await widget.openScanner(
      context,
      networkName: ref.read(rpcEndpointProvider).networkName,
    );
    if (scanned == null || !mounted) return;
    switch (scanned) {
      case SendScanPaymentRequest(:final prefill):
        // A QR that already names an amount is the same object a `zcash:`
        // link is, so it gets the same answer: the card, over whatever is on
        // screen — not a half-filled composer.
        ref
            .read(paymentRequestFlowProvider.notifier)
            .present(prefill, source: PaymentRequestSource.qrCode);
      case SendScanAddress(:final address, :final downgrade):
        final recipient = address.trim();
        if (recipient.isEmpty) return;
        _addressController.value = TextEditingValue(
          text: recipient,
          selection: TextSelection.collapsed(offset: recipient.length),
        );
        _handleAddressChanged();
        // A request the scan refused still surrendered its address, and the
        // composer just took it. Say what was left behind — otherwise the
        // payer answers a request they never saw the terms of.
        final downgradeMessage = sendScanDowngradeMessage(downgrade);
        if (downgradeMessage != null) {
          showAppToast(
            context,
            downgradeMessage,
            iconName: AppIcons.warning,
            tone: AppToastTone.destructive,
          );
        }
    }
  }

  Future<void> _pasteAddress() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text?.trim() ?? '';
    if (pasted.isEmpty || !mounted) return;
    _addressController.value = TextEditingValue(
      text: pasted,
      selection: TextSelection.collapsed(offset: pasted.length),
    );
    _handleAddressChanged();
  }

  void _clearAddress() {
    _addressController.clear();
    _handleAddressChanged();
  }

  Future<void> _showFullAddressSheet(
    String address,
    _ReviewRecipientPresentation recipient,
  ) {
    return showMobileAddressVerifySheet(
      context,
      title: recipient.verifyTitle,
      address: address,
      leading: recipient.buildVerifyLeading(),
    );
  }

  void _continueToAmount() {
    if (!_hasValidAddress) return;
    _addressFocus.unfocus();
    if (widget.useRouteSteps) {
      unawaited(_pushAmountStep());
      return;
    }
    setState(() => _step = _SendStep.amount);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
    unawaited(_validateAmount());
  }

  Future<void> _pushAmountStep() async {
    final amountText = _amountText.trim();
    final fiatAmountText = _fiatAmountText.trim();
    final result = await context.push<MobileSendAmountResult>(
      '/send/amount',
      extra: MobileSendAmountArgs(
        sendFlowId: _sendFlowId,
        recipient: _addressController.text.trim(),
        addressType: _addressType,
        // A ZIP-321 deep link prefills the amount on this same screen and
        // can step back to the recipient in place (there is no amount page
        // to pop). Carrying the amount forward keeps the payee-requested
        // value instead of stranding it in the hidden root state.
        amountText: amountText.isEmpty ? null : amountText,
        fiatAmountText: fiatAmountText.isEmpty ? null : fiatAmountText,
        amountInputMode: _amountInputMode,
        memo: _memo,
        preserveMemoWhitespace: _preserveMemoWhitespace,
        contactLabel: _contactLabel,
        contactPictureId: _contactPictureId,
        isPaymentRequest: _isAnsweringPaymentRequest,
        requestedBy: _activePaymentRequestLabel,
        requestedAmountZatoshi: _isAnsweringPaymentRequest
            ? widget.requestedAmountZatoshi
            : null,
      ),
    );
    if (!mounted) return;
    _adoptAmountStepResult(result);
  }

  /// The amount this screen would hand back to the page below if it popped now.
  MobileSendAmountResult get _amountStepResult => MobileSendAmountResult(
    amountText: _amountText.trim(),
    fiatAmountText: _fiatAmountText.trim(),
    amountInputMode: _amountInputMode,
  );

  /// Takes over whatever the pushed amount page composed.
  ///
  /// A null result means the page popped without one — the Android system back
  /// and the iOS edge swipe pop through the framework and cannot carry a
  /// value. Dropping the carried amount there is deliberate: re-seeding the
  /// next push from this screen's copy would resurrect a number the user has
  /// already edited past, which is the bug this hand-back exists to remove.
  void _adoptAmountStepResult(MobileSendAmountResult? result) {
    final amountText = result?.amountText ?? '';
    final fiatAmountText = result?.fiatAmountText ?? '';
    final amountInputMode = result?.amountInputMode ?? _amountInputMode;
    if (amountText == _amountText &&
        fiatAmountText == _fiatAmountText &&
        amountInputMode == _amountInputMode) {
      return;
    }
    setState(() {
      _amountText = amountText;
      _fiatAmountText = fiatAmountText;
      _amountInputMode = amountInputMode;
    });
    _setAmountControllerText(
      amountInputMode == MobileSendAmountInputMode.usd
          ? fiatAmountText
          : amountText,
    );
  }

  // ── Amount step ────────────────────────────────────────────────────

  BigInt get _spendable {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    return ref.read(_mobileSendSpendableStateProvider(accountUuid)).balance;
  }

  bool get _isUsingCompletedSpendableSnapshot {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    return ref.read(_mobileSendSpendableStateProvider(accountUuid)).freshness ==
        SpendableBalanceFreshness.lastCompletedSync;
  }

  String? get _activeAccountUuid =>
      ref.read(accountProvider).value?.activeAccountUuid;

  bool get _amountInputIsUsd =>
      _amountInputMode == MobileSendAmountInputMode.usd;

  void _setAmountControllerText(String text) {
    _amountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _toggleAmountInputMode() {
    final nextMode = _amountInputIsUsd
        ? MobileSendAmountInputMode.zec
        : MobileSendAmountInputMode.usd;
    final zecUsdUnitPrice = ref.read(zecLiveUsdUnitPriceProvider);
    if (nextMode == MobileSendAmountInputMode.usd && zecUsdUnitPrice == null) {
      return;
    }

    setState(() {
      _amountInputMode = nextMode;
      if (_amountInputIsUsd) {
        final zatoshi = parseZecAmount(_amountText.trim());
        _fiatAmountText = zatoshi == null || zatoshi <= BigInt.zero
            ? ''
            : sendSendableUsdInputTextForZatoshi(zatoshi, zecUsdUnitPrice!);
        if (_fiatAmountText.isEmpty) {
          _amountText = '';
          _amountError = '';
          _invalidateReviewFeeQuote();
          _clearMaxMode();
        }
        _setAmountControllerText(_fiatAmountText);
      } else {
        _setAmountControllerText(_amountText);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
  }

  bool get _hasCurrentMaxQuote {
    final quote = _maxQuote;
    if (quote == null) return false;
    return quote.accountUuid == _activeAccountUuid &&
        quote.address == _addressController.text.trim() &&
        quote.memo == _effectiveMemo &&
        parseZecAmount(_amountText.trim()) == quote.amountZatoshi &&
        _feeZatoshi == quote.feeZatoshi;
  }

  void _seedInitialMaxQuote() {
    if (!_isMaxMode) return;
    final accountUuid = _activeAccountUuid;
    final amountZatoshi = parseZecAmount(_amountText.trim());
    final feeZatoshi = _feeZatoshi;
    if (accountUuid == null || amountZatoshi == null || feeZatoshi == null) {
      return;
    }
    _maxQuote = _MobileSendMaxQuote(
      accountUuid: accountUuid,
      address: _addressController.text.trim(),
      memo: _effectiveMemo,
      amountZatoshi: amountZatoshi,
      feeZatoshi: feeZatoshi,
    );
  }

  void _seedInitialReviewFeeQuote() {
    if (_isMaxMode) return;
    final accountUuid = _activeAccountUuid;
    final amountZatoshi = parseZecAmount(_amountText.trim());
    final feeZatoshi = _feeZatoshi;
    if (accountUuid == null || amountZatoshi == null || feeZatoshi == null) {
      return;
    }
    _reviewFeeQuote = _MobileSendFeeQuote(
      accountUuid: accountUuid,
      address: _addressController.text.trim(),
      memo: _effectiveMemo,
      amountZatoshi: amountZatoshi,
      feeZatoshi: feeZatoshi,
    );
  }

  void _invalidateReviewFeeQuote() {
    _feeSeq++;
    _reviewFeeQuote = null;
    _feeZatoshi = null;
    _isRefreshingReviewFee = false;
    _reviewFeeRetryAvailable = false;
    _reviewFeeNotice = null;
  }

  bool get _hasCurrentReviewFeeQuote {
    if (_isUsingCompletedSpendableSnapshot) return false;
    if (_isMaxMode) return _hasCurrentMaxQuote;
    final quote = _reviewFeeQuote;
    if (quote == null || _isRefreshingReviewFee) return false;
    return quote.matches(
      accountUuid: _activeAccountUuid,
      address: _addressController.text.trim(),
      memo: _effectiveMemo,
      amountZatoshi: parseZecAmount(_amountText.trim()),
      feeZatoshi: _feeZatoshi,
    );
  }

  void _clearMaxMode() {
    _maxSeq++;
    _isMaxMode = false;
    _isResolvingMax = false;
    _maxQuote = null;
  }

  void _invalidateMaxQuoteForSync() {
    _validateSeq++;
    _maxSeq++;
    setState(() {
      _isResolvingMax = false;
      _maxQuote = null;
      _reviewFeeQuote = null;
      _feeZatoshi = null;
      _reviewFeeRetryAvailable = false;
      _reviewFeeNotice = null;
    });
  }

  void _handleAmountChanged(String value) {
    if (_amountInputIsUsd) {
      _handleFiatAmountChanged(value);
      return;
    }
    setState(() {
      _amountText = value.trim();
      _invalidateReviewFeeQuote();
      if (_isMaxMode) {
        _clearMaxMode();
      }
    });
    unawaited(_validateAmount());
  }

  void _handleFiatAmountChanged(String value) {
    final zecUsdUnitPrice = ref.read(zecLiveUsdUnitPriceProvider);
    final zatoshi = sendZatoshiFromUsdText(value, zecUsdUnitPrice);
    setState(() {
      _fiatAmountText = value.trim();
      _amountText = zatoshi == null
          ? ''
          : ZecAmount.fromZatoshi(zatoshi).pretty().amountText;
      _invalidateReviewFeeQuote();
      if (_isMaxMode) {
        _clearMaxMode();
      }
    });
    unawaited(_validateAmount());
  }

  void _handleZecUsdPriceChanged(double? zecUsdUnitPrice) {
    if (!_amountInputIsUsd) return;

    if (_isMaxMode) {
      _refreshMaxFiatAmountText(zecUsdUnitPrice);
      return;
    }

    final fiatText = _fiatAmountText.trim();
    if (fiatText.isEmpty) return;

    final zatoshi = sendZatoshiFromUsdText(fiatText, zecUsdUnitPrice);
    final nextAmountText = zatoshi == null
        ? ''
        : ZecAmount.fromZatoshi(zatoshi).pretty().amountText;
    if (nextAmountText == _amountText) return;

    setState(() {
      _amountText = nextAmountText;
      _invalidateReviewFeeQuote();
      if (nextAmountText.isEmpty) {
        _amountError = '';
      }
    });
    unawaited(_validateAmount());
  }

  void _refreshMaxFiatAmountText(double? zecUsdUnitPrice) {
    final zatoshi = parseZecAmount(_amountText.trim());
    if (zatoshi == null ||
        zatoshi <= BigInt.zero ||
        zecUsdUnitPrice == null ||
        !zecUsdUnitPrice.isFinite ||
        zecUsdUnitPrice <= 0) {
      return;
    }

    final fiatText = sendSendableUsdInputTextForZatoshi(
      zatoshi,
      zecUsdUnitPrice,
    );
    if (fiatText.isEmpty || fiatText == _fiatAmountText) return;

    setState(() => _fiatAmountText = fiatText);
    _setAmountControllerText(fiatText);
  }

  void _activateMaxMode() {
    if (_isResolvingMax) return;
    _amountFocus.unfocus();
    setState(() {
      _isMaxMode = true;
      _maxQuote = null;
      _amountError = '';
      _error = null;
    });
    unawaited(_resolveMaxEstimate());
  }

  String? _maxEstimatePreconditionError() {
    if (_activeAccountUuid == null) return 'Max amount unavailable';
    if (!_hasValidAddress) return 'Max amount unavailable';
    if (utf8.encode(_effectiveMemo).length > 512) {
      return 'Message is too long';
    }
    return null;
  }

  Future<void> _resolveMaxEstimate() async {
    _validateSeq++;
    final seq = ++_maxSeq;
    final accountUuid = _activeAccountUuid;
    final address = _addressController.text.trim();
    final memo = _effectiveMemo;
    final preconditionError = _maxEstimatePreconditionError();
    setState(() {
      _isMaxMode = true;
      _isResolvingMax = preconditionError == null;
      _maxQuote = null;
      _reviewFeeQuote = null;
      _reviewFeeRetryAvailable = false;
      _reviewFeeNotice = null;
      _amountError = preconditionError ?? '';
      if (preconditionError != null) {
        _feeZatoshi = null;
      }
    });
    if (preconditionError != null || accountUuid == null) return;

    try {
      final estimate = await ref
          .read(syncProvider.notifier)
          .runWithAuthoritativeSpendable<rust_sync.SendMaxEstimateResult?>(
            accountUuid: accountUuid,
            operation: () async {
              if (!_isCurrentMaxRequest(seq, accountUuid, address, memo)) {
                return null;
              }
              final dbPath = await widget.loadWalletDbPath();
              final endpoint = ref.read(rpcEndpointProvider);
              if (!_isCurrentMaxRequest(seq, accountUuid, address, memo)) {
                return null;
              }
              return rust_sync.estimateSendMax(
                dbPath: dbPath,
                network: endpoint.networkName,
                accountUuid: accountUuid,
                toAddress: address,
                memo: memo.isNotEmpty ? memo : null,
              );
            },
          );
      if (estimate == null) return;
      if (!_isCurrentMaxRequest(seq, accountUuid, address, memo)) return;

      if (estimate.amountZatoshi <= BigInt.zero) {
        _applyMaxEstimateError(_notEnoughZecText);
        return;
      }

      final amountText = ZecAmount.fromZatoshi(
        estimate.amountZatoshi,
      ).pretty().amountText;
      final zecUsdUnitPrice = ref.read(zecLiveUsdUnitPriceProvider);
      final fiatText = zecUsdUnitPrice == null
          ? ''
          : sendSendableUsdInputTextForZatoshi(
              estimate.amountZatoshi,
              zecUsdUnitPrice,
            );
      if (_amountInputIsUsd && fiatText.isEmpty) {
        _setAmountControllerText('');
        setState(() {
          _amountText = '';
          _fiatAmountText = '';
          _amountError = '';
          _feeZatoshi = null;
          _isResolvingMax = false;
          _isMaxMode = false;
          _maxQuote = null;
        });
        return;
      }
      _setAmountControllerText(_amountInputIsUsd ? fiatText : amountText);

      setState(() {
        _amountText = amountText;
        _fiatAmountText = fiatText;
        _amountError = null;
        _feeZatoshi = estimate.feeZatoshi;
        _reviewFeeNotice = null;
        _isResolvingMax = false;
        _maxQuote = _MobileSendMaxQuote(
          accountUuid: accountUuid,
          address: address,
          memo: memo,
          amountZatoshi: estimate.amountZatoshi,
          feeZatoshi: estimate.feeZatoshi,
        );
      });
    } catch (e) {
      if (!_isCurrentMaxRequest(seq, accountUuid, address, memo)) return;
      final msg = e.toString().toLowerCase();
      _applyMaxEstimateError(
        msg.contains('insufficient')
            ? _notEnoughZecText
            : 'Max amount unavailable',
      );
    }
  }

  bool _isCurrentMaxRequest(
    int seq,
    String accountUuid,
    String address,
    String memo,
  ) {
    return mounted &&
        _isMaxMode &&
        seq == _maxSeq &&
        _activeAccountUuid == accountUuid &&
        _addressController.text.trim() == address &&
        _effectiveMemo == memo;
  }

  void _applyMaxEstimateError(String message) {
    setState(() {
      _isResolvingMax = false;
      _maxQuote = null;
      _feeZatoshi = null;
      _amountError = message;
    });
    if (_step == _SendStep.review) {
      showAppToast(context, message, iconName: AppIcons.warning);
    }
  }

  /// Same shape as the desktop validator — quick spendable pre-check,
  /// then a seq-guarded fee estimate so the total is covered. The
  /// mobile copy is the design's "Not enough ZEC".
  Future<void> _validateAmount() async {
    final seq = ++_validateSeq;
    final text = _amountText.trim();
    if (text.isEmpty || text == '.' || text == '0.') {
      setState(() => _amountError = '');
      return;
    }
    final zatoshi = parseZecAmount(text);
    if (zatoshi == null || zatoshi <= BigInt.zero) {
      setState(() => _amountError = '');
      return;
    }
    if (zatoshi > _spendable) {
      setState(() => _amountError = _notEnoughZecText);
      return;
    }
    if (_isUsingCompletedSpendableSnapshot) {
      setState(() {
        _amountError = null;
        _feeZatoshi = null;
        _reviewFeeQuote = null;
        _reviewFeeRetryAvailable = false;
        _reviewFeeNotice = null;
      });
      return;
    }
    // Block Continue until the fee estimate confirms the total fits —
    // otherwise a quick Continue tap right after typing rides on the
    // previous amount's validation result.
    setState(() => _amountError = '');

    try {
      final dbPath = await widget.loadWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (!mounted || seq != _validateSeq || accountUuid == null) return;
      final fee = await (widget.estimateFee ?? rust_sync.estimateFee)(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        toAddress: _addressController.text.trim(),
        amountZatoshi: zatoshi,
        memo: _effectiveMemo.isNotEmpty ? _effectiveMemo : null,
      );
      if (!mounted || seq != _validateSeq) return;
      if (zatoshi + fee > _spendable) {
        setState(() => _amountError = _notEnoughZecText);
      } else {
        setState(() {
          _amountError = null;
          _feeZatoshi = fee;
          _reviewFeeQuote = _MobileSendFeeQuote(
            accountUuid: accountUuid,
            address: _addressController.text.trim(),
            memo: _effectiveMemo,
            amountZatoshi: zatoshi,
            feeZatoshi: fee,
          );
          _reviewFeeRetryAvailable = false;
          _reviewFeeNotice = null;
        });
      }
    } catch (e) {
      if (!mounted || seq != _validateSeq) return;
      // Lowercase first, like the max and review estimates in this file: what
      // Rust actually sends up is "Propose failed: Insufficient balance (have
      // …, need … including fee)", so a case-sensitive match on either literal
      // never fired and this warning could not reach the composer at all.
      final msg = e.toString().toLowerCase();
      if (msg.contains('insufficientfunds') || msg.contains('insufficient')) {
        setState(() => _amountError = _notEnoughZecText);
      } else {
        log('MobileSend: fee estimation failed (non-blocking): $e');
        setState(() => _amountError = null);
      }
    }
  }

  bool get _amountReady =>
      !_isResolvingMax &&
      _hasValidAddress &&
      !_amountJumpPendingAddressCheck &&
      _amountError == null &&
      (!_amountInputIsUsd || ref.read(zecLiveUsdUnitPriceProvider) != null) &&
      (parseZecAmount(_amountText.trim()) ?? BigInt.zero) > BigInt.zero &&
      (!_isMaxMode || _hasCurrentMaxQuote);

  String get _amountCtaLabel {
    if (_isResolvingMax) return 'Calculating max amount';
    if (_amountReady) return 'Finish & review';

    final error = _amountError;
    if (error != null && error.isNotEmpty) {
      return error;
    }
    return 'Enter amount to continue';
  }

  void _continueToReview() {
    if (!_amountReady) return;
    _amountFocus.unfocus();
    if (widget.useRouteSteps) {
      unawaited(
        context.push<void>(
          '/send/review',
          extra: MobileSendReviewDraftArgs(
            sendFlowId: _sendFlowId,
            recipient: _addressController.text.trim(),
            addressType: _addressType,
            amountText: _amountText,
            feeZatoshi: _feeZatoshi,
            isMaxMode: _isMaxMode && _hasCurrentMaxQuote,
            memo: _memo,
            preserveMemoWhitespace: _preserveMemoWhitespace,
            contactLabel: _contactLabel,
            contactPictureId: _contactPictureId,
            // The pushed review page decides the "Review payment request"
            // framing from these; without them it reads as an ordinary send.
            isPaymentRequest: _isAnsweringPaymentRequest,
            requestedBy: _activePaymentRequestLabel,
            requestedAmountZatoshi: _isAnsweringPaymentRequest
                ? widget.requestedAmountZatoshi
                : null,
            // The memo above is a copy. Keep this page's in step with edits
            // made on the review, or a second review after Back would send
            // the memo from before the edit.
            onMemoEdited: (memo, preserveWhitespace) {
              if (!mounted) return;
              setState(() {
                _memo = memo;
                _preserveMemoWhitespace = preserveWhitespace;
              });
            },
          ),
        ),
      );
      return;
    }
    setState(() => _step = _SendStep.review);
    // Refresh the fee for the review card (the memo may change it).
    unawaited(_refreshReviewQuote());
  }

  // ── Review step ────────────────────────────────────────────────────

  String get _effectiveMemo {
    if (!_isShieldedAddress) return '';
    return _preserveMemoWhitespace ? _memo : _memo.trim();
  }

  Future<void> _refreshReviewQuote() {
    if (_isMaxMode) return _resolveMaxEstimate();
    return _estimateReviewFee();
  }

  bool _isCurrentReviewFeeRequest({
    required int seq,
    required String accountUuid,
    required String address,
    required String memo,
    required BigInt amountZatoshi,
  }) {
    return mounted &&
        seq == _feeSeq &&
        accountUuid == _activeAccountUuid &&
        address == _addressController.text.trim() &&
        memo == _effectiveMemo &&
        amountZatoshi == parseZecAmount(_amountText.trim());
  }

  Future<void> _estimateReviewFee() async {
    final seq = ++_feeSeq;
    final zatoshi = parseZecAmount(_amountText.trim());
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final address = _addressController.text.trim();
    final memo = _effectiveMemo;
    if (zatoshi == null || accountUuid == null) {
      if (mounted) {
        setState(() {
          _feeZatoshi = null;
          _reviewFeeQuote = null;
          _isRefreshingReviewFee = false;
          _reviewFeeRetryAvailable = false;
        });
      }
      return;
    }
    setState(() {
      _feeZatoshi = null;
      _reviewFeeQuote = null;
      _isRefreshingReviewFee = true;
      _reviewFeeRetryAvailable = false;
      _reviewFeeNotice = _isUsingCompletedSpendableSnapshot
          ? 'Finishing wallet sync.'
          : null;
    });
    try {
      final fee = await ref
          .read(syncProvider.notifier)
          .runWithAuthoritativeSpendable<BigInt?>(
            accountUuid: accountUuid,
            operation: () async {
              if (!_isCurrentReviewFeeRequest(
                seq: seq,
                accountUuid: accountUuid,
                address: address,
                memo: memo,
                amountZatoshi: zatoshi,
              )) {
                return null;
              }
              final dbPath = await widget.loadWalletDbPath();
              final endpoint = ref.read(rpcEndpointProvider);
              if (!_isCurrentReviewFeeRequest(
                seq: seq,
                accountUuid: accountUuid,
                address: address,
                memo: memo,
                amountZatoshi: zatoshi,
              )) {
                return null;
              }
              return (widget.estimateFee ?? rust_sync.estimateFee)(
                dbPath: dbPath,
                network: endpoint.networkName,
                accountUuid: accountUuid,
                toAddress: address,
                amountZatoshi: zatoshi,
                memo: memo.isNotEmpty ? memo : null,
              );
            },
          );
      if (fee == null) return;
      if (!_isCurrentReviewFeeRequest(
        seq: seq,
        accountUuid: accountUuid,
        address: address,
        memo: memo,
        amountZatoshi: zatoshi,
      )) {
        return;
      }
      if (zatoshi + fee > _spendable) {
        setState(() {
          _amountError = _notEnoughZecText;
          _isRefreshingReviewFee = false;
          _reviewFeeRetryAvailable = false;
          _reviewFeeNotice = _notEnoughZecText;
        });
        return;
      }
      setState(() {
        _feeZatoshi = fee;
        _reviewFeeQuote = _MobileSendFeeQuote(
          accountUuid: accountUuid,
          address: address,
          memo: memo,
          amountZatoshi: zatoshi,
          feeZatoshi: fee,
        );
        _isRefreshingReviewFee = false;
        _reviewFeeRetryAvailable = false;
        _reviewFeeNotice = null;
      });
    } catch (e) {
      log('MobileSend: review fee estimate failed (non-blocking): $e');
      if (!_isCurrentReviewFeeRequest(
        seq: seq,
        accountUuid: accountUuid,
        address: address,
        memo: memo,
        amountZatoshi: zatoshi,
      )) {
        return;
      }
      final lower = e.toString().toLowerCase();
      final insufficientFunds =
          lower.contains('insufficientfunds') || lower.contains('insufficient');
      setState(() {
        _feeZatoshi = null;
        _reviewFeeQuote = null;
        _isRefreshingReviewFee = false;
        _reviewFeeRetryAvailable = !insufficientFunds;
        if (insufficientFunds) {
          _amountError = _notEnoughZecText;
          _reviewFeeNotice = _notEnoughZecText;
        } else {
          _reviewFeeNotice = lower.contains('sync')
              ? 'Finishing wallet sync. Try again shortly.'
              : 'Fee unavailable. Try again.';
        }
      });
    }
  }

  Future<void> _editMemo() async {
    // A bottom sheet, not a top-pinned card: the modal rises from the
    // bottom and the sheet frame floats it 16px above the software
    // keyboard (Figma `Review Add Memo`, 4638:74505).
    final next = await showAppMobileSheet<String>(
      context: context,
      builder: (_) => _MemoSheet(initial: _memo),
    );
    if (next == null || !mounted) return;
    setState(() {
      _memo = next;
      _preserveMemoWhitespace = false;
    });
    widget.onMemoEdited?.call(_memo, _preserveMemoWhitespace);
    unawaited(_refreshReviewQuote());
  }

  Future<void> _showFeeInfo() => showMobileTxFeeInfoSheet(context);

  /// Whether this send is still answering the payment request it opened from.
  ///
  /// The request's framing is a claim about who the money is going to, so it
  /// only holds while the recipient is the one the request named. Retype the
  /// address and this is an ordinary send again — the same rule
  /// `_activePaymentRequest` applies on desktop, and the reason an
  /// attacker-supplied label can never be shown over an address the request
  /// did not ask for.
  bool get _isAnsweringPaymentRequest =>
      widget.isPaymentRequest &&
      (widget.initialRecipient?.trim() ?? '') == _addressController.text.trim();

  /// The request's label, or null once the recipient no longer matches.
  String? get _activePaymentRequestLabel =>
      _isAnsweringPaymentRequest ? widget.paymentRequestLabel : null;

  /// The requested amount, but only while the reviewed amount is a different
  /// number. The info block above already states what is being sent; repeating
  /// the same figure as "Requested" would be noise.
  String? get _requestedAmountNotice {
    if (!_isAnsweringPaymentRequest) return null;
    final requested = widget.requestedAmountZatoshi;
    if (requested == null) return null;
    if (requested == parseZecAmount(_amountText.trim())) return null;
    return ZecAmount.fromZatoshi(requested).activityDetail.toString();
  }

  void _openStatusRoute(Object extra) {
    if (widget.useRouteSteps) {
      final router = GoRouter.of(context);
      router.go('/home');
      unawaited(router.push<void>('/send/status', extra: extra));
      return;
    }
    context.pushReplacement('/send/status', extra: extra);
  }

  /// Confirm & send, under a `paymentUriBusySurfaceProvider` hold.
  ///
  /// Between the tap on Confirm and the status route being on screen, a
  /// `zcash:` link would otherwise be delivered as a card over the review —
  /// the drain policy's "a broadcast is running on `/send/status`" row
  /// cannot see a send that has not reached that route yet. The card then
  /// outlives the route change (it is hosted above the router), and its
  /// Review or Edit would dispose the status screen mid-broadcast: the
  /// transaction is on the network with no receipt, or the proposal leaks
  /// if the broadcast had not started. The hold parks the link for the
  /// window; when it lifts, the app re-runs the drain against `/send/status`,
  /// which waits for the receipt.
  Future<void> _confirmAndSend() async {
    if (_phase != _SendPhase.compose || _isConfirmingSend) return;
    _acquireConfirmBusySurface();
    try {
      await _confirmAndSendHeld();
    } finally {
      _releaseConfirmBusySurface();
    }
  }

  void _acquireConfirmBusySurface() {
    if (_holdsConfirmBusySurface) return;
    _holdsConfirmBusySurface = true;
    _paymentUriBusySurface.acquire();
  }

  /// Safe after the element is gone: the notifier is app-scoped, and this
  /// runs from an async continuation, never from `dispose` (which has its
  /// own release).
  void _releaseConfirmBusySurface() {
    if (!_holdsConfirmBusySurface) return;
    _holdsConfirmBusySurface = false;
    _paymentUriBusySurface.release();
  }

  Future<void> _confirmAndSendHeld() async {
    if (_isResolvingMax || (_isMaxMode && !_hasCurrentMaxQuote)) return;
    if (!_hasCurrentReviewFeeQuote) {
      unawaited(_refreshReviewQuote());
      return;
    }
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    final isHardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(accountUuid);
    final amountZatoshi = parseZecAmount(_amountText.trim());
    if (amountZatoshi == null || amountZatoshi <= BigInt.zero) return;
    final reviewedFeeZatoshi = _feeZatoshi!;
    final address = _addressController.text.trim();
    final memo = _effectiveMemo;

    setState(() {
      _isConfirmingSend = true;
      _error = null;
    });

    SendReviewArgs args;
    try {
      args = await proposeSendTransfer(
        ref: ref,
        loadDbPath: widget.loadWalletDbPath,
        accountUuid: accountUuid,
        sendFlowId: _sendFlowId,
        address: address,
        addressType: _addressType,
        amountZatoshi: amountZatoshi,
        memo: memo.isNotEmpty ? memo : null,
      );
    } catch (e) {
      log('MobileSend: propose error: $e');
      if (!mounted) return;
      setState(() {
        _isConfirmingSend = false;
        _phase = _SendPhase.failed;
        _error = friendlyProposeSendError(e.toString());
      });
      return;
    }
    if (!mounted) {
      // Awaited: `_confirmAndSend`'s hold on the payment-URI latch lifts when
      // this returns, and a link parked behind it would otherwise be
      // pre-checked against inputs this proposal still holds.
      await discardSendProposal(
        proposalId: args.proposalId,
        sendFlowId: _sendFlowId,
        logContext: 'MobileSend(unmounted)',
      );
      return;
    }
    if (args.feeZatoshi != reviewedFeeZatoshi) {
      await discardSendProposal(
        proposalId: args.proposalId,
        sendFlowId: _sendFlowId,
        logContext: 'MobileSend(fee changed after review)',
      );
      if (!mounted) return;
      setState(() {
        _isConfirmingSend = false;
        _feeZatoshi = args.feeZatoshi;
        _reviewFeeQuote = _MobileSendFeeQuote(
          accountUuid: accountUuid,
          address: address,
          memo: memo,
          amountZatoshi: amountZatoshi,
          feeZatoshi: args.feeZatoshi,
        );
        _reviewFeeRetryAvailable = false;
        _reviewFeeNotice = 'Fee updated after sync. Review and confirm again.';
      });
      return;
    }
    setState(() {
      _feeZatoshi = args.feeZatoshi;
      _reviewFeeRetryAvailable = false;
      _reviewFeeNotice = null;
    });

    KeystoneBroadcastArgs? keystone;
    if (isHardware) {
      // Hand the PCZT to the device for the spend-auth signature; the
      // signing screen owns the QR display/scan round trip.
      keystone = await context.push<KeystoneBroadcastArgs>(
        '/send/keystone-sign',
        extra: args,
      );
      if (keystone == null) {
        if (mounted) {
          setState(() {
            _isConfirmingSend = false;
            _phase = _SendPhase.compose;
          });
        }
        // Cancelled (or failed before signing). The signing screen may
        // already have consumed the proposal — discard is idempotent. Awaited
        // so the payment-URI hold `_confirmAndSend` took outlives the release:
        // a link parked behind it would otherwise be pre-checked against
        // inputs this proposal still holds.
        await discardSendProposal(
          proposalId: args.proposalId,
          sendFlowId: _sendFlowId,
          logContext: 'MobileSend(keystone cancelled)',
        );
        return;
      }
      if (!mounted) return;
      _openStatusRoute(keystone);
      return;
    }

    if (!mounted) return;
    _openStatusRoute(args);
  }

  // ── Navigation ─────────────────────────────────────────────────────

  void _cancelSend() {
    if (widget.useRouteSteps) {
      context.go('/home');
      return;
    }
    context.pop();
  }

  void _handleBack() {
    if (_isConfirmingSend) return;
    switch (_phase) {
      case _SendPhase.failed:
        setState(() => _phase = _SendPhase.compose);
        return;
      case _SendPhase.compose:
        break;
    }
    switch (_step) {
      case _SendStep.recipient:
        // First compose step: pop to wherever we came from, or fall back to
        // /home when there's nothing to pop. A payment-URI deep link can make
        // /send the navigation root, leaving the back button with nowhere to go.
        if (_canPopRoute) {
          context.pop();
        } else {
          context.go('/home');
        }
      case _SendStep.amount:
        _amountFocus.unfocus();
        if (widget.useRouteSteps) {
          if (_canPopRoute) {
            // Normal flow: amount is a pushed /send/amount page — pop it back
            // to the recipient page, handing up the amount composed here so
            // the page below does not re-push its stale copy.
            context.pop(_amountStepResult);
          } else {
            // A prefilled-amount deep link landed on the amount step of the
            // root /send route (no page to pop), so popping is a dead end.
            // Step back to recipient in place; the address is already filled.
            setState(() => _step = _SendStep.recipient);
          }
          return;
        }
        setState(() => _step = _SendStep.recipient);
      case _SendStep.review:
        if (widget.useRouteSteps && _canPopRoute) {
          context.pop();
          return;
        }
        // A review opened from the payment-request card enters through `go`,
        // which makes /send/review the whole stack: there is no page under it
        // to pop to. Step back in place instead, the way the deep-linked
        // amount step does; from there the recipient step's own fallback
        // still leads home.
        setState(() => _step = _SendStep.amount);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _amountFocus.requestFocus();
        });
    }
  }

  String _truncateAddress(String address) {
    final value = address.trim();
    if (value.length <= 28) return value;
    return '${value.substring(0, 13)} ... '
        '${value.substring(value.length - 11)}';
  }

  String _compactReviewAddress(String address) {
    final value = address.trim();
    if (value.length <= 18) return value;
    return '${value.substring(0, 7)} .... '
        '${value.substring(value.length - 7)}';
  }

  _ReviewRecipientPresentation _reviewRecipientPresentation({
    required String address,
    required Iterable<AddressBookContact> contacts,
    required Map<String, AccountInfo> ownAccounts,
  }) {
    final contact = sendRecipientContactFor(
      contacts: contacts,
      address: address,
    );
    if (contact != null) {
      final label = contact.label.trim();
      return _ReviewRecipientPresentation(
        headline: label,
        verifyTitle: label,
        profilePictureId: contact.profilePictureId,
      );
    }

    final account = _ownAccountForAddress(ownAccounts, address);
    if (account != null) {
      return _ReviewRecipientPresentation(
        headline: account.name,
        verifyTitle: account.name,
        profilePictureId: account.profilePictureId,
      );
    }

    final rememberedContactLabel = _contactLabel?.trim();
    if (rememberedContactLabel != null && rememberedContactLabel.isNotEmpty) {
      return _ReviewRecipientPresentation(
        headline: rememberedContactLabel,
        verifyTitle: rememberedContactLabel,
        profilePictureId: _contactPictureId,
      );
    }

    final fallbackLabel = _fallbackAddressTypeLabel();
    return _ReviewRecipientPresentation(
      headline: fallbackLabel,
      verifyTitle: fallbackLabel,
      useZecIcon: true,
    );
  }

  String _fallbackAddressTypeLabel() {
    return switch (_addressType) {
      'unified' => 'Shielded address',
      'sapling' => 'Shielded address',
      'transparent' => 'Transparent address',
      'tex' => 'TEX address',
      _ => 'Zcash address',
    };
  }

  AccountInfo? _ownAccountForAddress(
    Map<String, AccountInfo> ownAccounts,
    String address,
  ) {
    final target = address.trim();
    if (target.isEmpty) return null;
    final account = ownAccounts[target];
    if (account == null || account.name.trim().isEmpty) return null;
    return account;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<double?>(zecLiveUsdUnitPriceProvider, (previous, next) {
      if (previous == next || !mounted) return;
      _handleZecUsdPriceChanged(next);
    });

    final accountUuid = ref.watch(
      accountProvider.select((value) => value.value?.activeAccountUuid),
    );
    ref.watch(_mobileSendSpendableStateProvider(accountUuid));
    ref.listen(_mobileSendSpendableStateProvider(accountUuid), (
      previous,
      next,
    ) {
      if (previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_isMaxMode) {
          if (next.freshness == SpendableBalanceFreshness.lastCompletedSync) {
            _invalidateMaxQuoteForSync();
          } else {
            unawaited(_resolveMaxEstimate());
          }
        } else if (_step == _SendStep.amount && _amountText.trim().isNotEmpty) {
          unawaited(_validateAmount());
        } else if (_step == _SendStep.review &&
            !_isRefreshingReviewFee &&
            !_hasCurrentReviewFeeQuote) {
          unawaited(_refreshReviewQuote());
        }
      });
    });
    final colors = context.colors;
    final showRecipientFocusOverlay = _showRecipientFocusOverlay;
    final showRecipientFieldLayer =
        _phase == _SendPhase.compose && _step == _SendStep.recipient;

    final title = switch (_phase) {
      _SendPhase.compose => switch (_step) {
        _SendStep.recipient => 'Select Recipient',
        _SendStep.amount => 'Enter Amount',
        _SendStep.review =>
          _isAnsweringPaymentRequest ? 'Review payment request' : 'Review Send',
      },
      _SendPhase.failed => 'Send failed',
    };

    final body = switch (_phase) {
      _SendPhase.compose => switch (_step) {
        _SendStep.recipient => _buildRecipientStep(
          context,
          hasFocusedRecipient: showRecipientFocusOverlay,
        ),
        _SendStep.amount => _buildAmountStep(context),
        _SendStep.review => _buildReviewStep(context),
      },
      _ => _buildStatus(context),
    };

    return PopScope<void>(
      canPop: _routePopAllowed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        resizeToAvoidBottomInset: true,
        body: AppToastHost(
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    MobileTopNav.back(
                      title: title,
                      onBack: _isConfirmingSend ? null : _handleBack,
                    ),
                    Expanded(child: body),
                  ],
                ),
              ),
              if (showRecipientFocusOverlay) ...[
                Positioned.fill(
                  key: const ValueKey(
                    'mobile_send_recipient_focus_scrim_layer',
                  ),
                  child: GestureDetector(
                    key: const ValueKey('mobile_send_recipient_focus_scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _addressFocus.unfocus,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
              if (showRecipientFieldLayer)
                Positioned(
                  key: const ValueKey('mobile_send_recipient_field_layer'),
                  top:
                      MediaQuery.paddingOf(context).top +
                      kMobileTopNavHeight +
                      AppSpacing.s,
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: _buildAddressFieldGroup(context),
                ),
              if (showRecipientFocusOverlay) ...[
                if (_showRecipientContinue)
                  Positioned(
                    key: const ValueKey(
                      'mobile_send_recipient_focus_continue_layer',
                    ),
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.s,
                    child: _buildRecipientContinueButton(
                      context,
                      useBackdropColors: true,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Step bodies ────────────────────────────────────────────────────

  Widget _buildRecipientStep(
    BuildContext context, {
    required bool hasFocusedRecipient,
  }) {
    final colors = context.colors;
    final contacts = filterAddressBookContacts(
      ref.watch(addressBookProvider).value?.contacts ??
          const <AddressBookContact>[],
      query: _addressController.text,
      networks: const {AddressBookNetwork.zcash},
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.s +
                  _kMobileSendAddressFieldGroupHeight +
                  AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            children: [
              Semantics(
                button: true,
                child: GestureDetector(
                  key: const ValueKey('mobile_send_scan_row'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_openScanner()),
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppAssetSize.padding,
                      ),
                      child: Row(
                        children: [
                          Container(
                            key: const ValueKey('mobile_send_scan_icon_frame'),
                            width: AppAssetSize.size,
                            height: AppAssetSize.size,
                            decoration: BoxDecoration(
                              color: colors.background.neutralSubtleOpacity,
                              borderRadius: BorderRadius.circular(
                                AppRadii.full,
                              ),
                            ),
                            child: Center(
                              child: AppIcon(
                                AppIcons.qr,
                                size: AppAssetSize.icon,
                                color: colors.icon.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _RecipientLineText(
                                  'Scan a QR Code',
                                  color: colors.text.accent,
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                _RecipientLineText(
                                  'Scan an address using camera',
                                  color: colors.text.secondary,
                                  fontWeight: FontWeight.w400,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (contacts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxs),
                        child: Row(
                          children: [
                            AppIcon(
                              AppIcons.users,
                              size: 20,
                              color: colors.icon.muted,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Text(
                              '${contacts.length} '
                              'contact${contacts.length == 1 ? '' : 's'}',
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (var i = 0; i < contacts.length; i++) ...[
                        Semantics(
                          button: true,
                          child: GestureDetector(
                            key: ValueKey(
                              'mobile_send_contact_${contacts[i].id}',
                            ),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _selectContact(contacts[i]),
                            child: SizedBox(
                              height: 44,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    height: 32,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: AppProfilePicture(
                                        profilePictureId:
                                            contacts[i].profilePictureId,
                                        size: AppProfilePictureSize.large,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.s),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _RecipientLineText(
                                          contacts[i].label,
                                          color: colors.text.accent,
                                        ),
                                        const SizedBox(height: AppSpacing.xxs),
                                        _RecipientLineText(
                                          _truncateAddress(contacts[i].address),
                                          color: colors.text.secondary,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (i != contacts.length - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_showRecipientContinue && !hasFocusedRecipient)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.s,
            ),
            child: _buildRecipientContinueButton(context),
          ),
      ],
    );
  }

  Widget _buildAddressFieldGroup(BuildContext context) {
    return Column(
      key: const ValueKey('mobile_send_address_field_group'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_buildAddressField(context), _buildAddressErrorSpace(context)],
    );
  }

  Widget _buildAddressField(BuildContext context) {
    final colors = context.colors;
    final showAction = _addressFocus.hasFocus;
    final hasAddressError =
        _addressType == 'invalid' || _addressType == 'error';
    return MobileTextField(
      key: const ValueKey('mobile_send_address_field'),
      fieldKey: const ValueKey('mobile_send_address_input'),
      controller: _addressController,
      focusNode: _addressFocus,
      hintText: 'Zcash Address',
      leading: SizedBox(
        width: AppInputSizing.iconWrapWidth,
        height: AppInputSizing.height,
        child: Align(
          alignment: Alignment.centerRight,
          child: AppIcon(
            AppIcons.plane,
            size: 20,
            color: _addressController.text.trim().isEmpty
                ? colors.icon.regular
                : colors.icon.accent,
          ),
        ),
      ),
      restingBorderColor: hasAddressError
          ? colors.border.utilityDestructive
          : null,
      focusedBorderColor: hasAddressError
          ? colors.border.utilityDestructive
          : const Color(0x00000000),
      focusedBoxShadow: showAction
          ? [
              BoxShadow(
                color: colors.background.neutralScrim,
                offset: const Offset(0, 4),
                blurRadius: 4,
                spreadRadius: 1000,
              ),
            ]
          : null,
      trailing: showAction
          ? SizedBox(
              key: const ValueKey('mobile_send_address_action_slot'),
              width: _kMobileSendAddressActionSlotWidth,
              height: AppInputSizing.height,
              child: Center(
                child: _AddressFieldActionButton(
                  label: _addressController.text.trim().isEmpty
                      ? 'Paste'
                      : 'Clear',
                  onTap: _addressController.text.trim().isEmpty
                      ? () => unawaited(_pasteAddress())
                      : _clearAddress,
                ),
              ),
            )
          : null,
      onChanged: (_) => _handleAddressChanged(),
      keyboardType: TextInputType.text,
    );
  }

  Widget _buildAddressErrorSpace(BuildContext context) {
    final colors = context.colors;
    final showError = _addressType == 'invalid' || _addressType == 'error';
    // The reserved line shows the validation error, or — when the address is
    // valid and matches a saved contact / own account — the resolved name so
    // the user knows the pasted/typed address is the intended one.
    Widget? line;
    if (showError) {
      line = Text(
        _addressType == 'invalid'
            // A wrong-network address is well-formed, so "Invalid address"
            // would send the user hunting for a typo that is not there.
            ? (_addressWrongNetwork
                  ? kWrongNetworkAddressMessage
                  : 'Invalid address')
            : 'Address validation failed',
        style: AppTypography.labelLarge.copyWith(
          color: colors.text.destructive,
        ),
      );
    } else if (_hasValidAddress) {
      final recipient = sendReviewRecipientFor(
        contacts:
            ref.watch(addressBookProvider).value?.contacts ??
            const <AddressBookContact>[],
        address: _addressController.text.trim(),
        ownAccounts: ref.watch(ownAccountAddressesProvider).value ?? const {},
      );
      if (recipient is SendReviewContactRecipient) {
        line = ContactNameInline(
          key: const ValueKey('mobile_send_address_contact_match'),
          name: recipient.name,
          textStyle: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
          iconSize: 16,
        );
      }
    }
    return SizedBox(
      height: _kMobileSendAddressErrorGap + _kMobileSendRecipientLineHeight,
      child: line == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: _kMobileSendAddressErrorGap),
              child: Align(alignment: Alignment.topLeft, child: line),
            ),
    );
  }

  Widget _buildRecipientContinueButton(
    BuildContext context, {
    bool useBackdropColors = false,
  }) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: AppButton(
        key: const ValueKey('mobile_send_continue'),
        expand: true,
        constrainContent: true,
        disabledBackgroundColor: useBackdropColors
            ? Color.alphaBlend(
                colors.button.disabled.bg,
                colors.surface.input.primary,
              )
            : null,
        enabledBorderColor: useBackdropColors
            ? colors.border.subtleOpacity
            : null,
        onPressed: _hasValidAddress ? _continueToAmount : null,
        child: Text(
          _addressController.text.trim().isEmpty
              ? 'Enter address to continue'
              : 'Continue',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildAmountStep(BuildContext context) {
    final colors = context.colors;
    final zecUsdUnitPrice = ref.watch(zecLiveUsdUnitPriceProvider);
    final spendableText = ZecAmount.fromZatoshi(
      _spendable,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final showError = _amountError != null && _amountError!.isNotEmpty;
    final amountStyle = AppTypography.displayLarge.copyWith(
      color: showError ? colors.text.destructive : colors.text.accent,
      fontSize: _kMobileSendAmountFontSize,
      height: _kMobileSendAmountLineHeightPx / _kMobileSendAmountFontSize,
      fontWeight: FontWeight.w500,
    );
    final amountUnitStyle = amountStyle.copyWith(
      color: amountStyle.color?.withValues(alpha: 0.5),
      fontSize: _kMobileSendAmountUnitFontSize,
      height: _kMobileSendAmountLineHeightPx / _kMobileSendAmountUnitFontSize,
    );

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: const ValueKey('mobile_send_amount_top_content'),
                height: _kMobileSendAmountTopContentHeight,
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAmountField(
                      context,
                      showError: showError,
                      spendableText: spendableText,
                      zecUsdUnitPrice: zecUsdUnitPrice,
                      amountStyle: amountStyle,
                      amountUnitStyle: amountUnitStyle,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      key: const ValueKey('mobile_send_amount_recipient_block'),
                      height: _kMobileSendAmountRecipientBlockHeight,
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: _kMobileSendAmountRecipientLabelHeight,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Sending to',
                                style: AppTypography.labelLarge.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          SizedBox(
                            key: const ValueKey(
                              'mobile_send_amount_recipient_row',
                            ),
                            height: _kMobileSendAmountRecipientRowHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s,
                              ),
                              child: Row(
                                children: [
                                  AppProfilePicture(
                                    key: const ValueKey(
                                      'mobile_send_amount_recipient_picture',
                                    ),
                                    profilePictureId: _contactPictureId ?? '',
                                    size: AppProfilePictureSize.navLarge,
                                  ),
                                  const SizedBox(width: AppSpacing.s),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: _contactLabel == null
                                          ? [
                                              _RecipientLineText(
                                                _truncateAddress(
                                                  _addressController.text,
                                                ),
                                                color: colors.text.accent,
                                              ),
                                            ]
                                          : [
                                              _RecipientLineText(
                                                _contactLabel!,
                                                color: colors.text.accent,
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.xxs,
                                              ),
                                              _RecipientLineText(
                                                _truncateAddress(
                                                  _addressController.text,
                                                ),
                                                color: colors.text.secondary,
                                              ),
                                            ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            AppSpacing.s,
          ),
          child: SizedBox(
            width: double.infinity,
            child: AppButton(
              key: const ValueKey('mobile_send_review_button'),
              expand: true,
              constrainContent: true,
              onPressed: _amountReady ? _continueToReview : null,
              child: Text(
                _amountCtaLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountField(
    BuildContext context, {
    required bool showError,
    required String spendableText,
    required double? zecUsdUnitPrice,
    required TextStyle amountStyle,
    required TextStyle amountUnitStyle,
  }) {
    return SizedBox(
      key: const ValueKey('mobile_send_amount_field'),
      height: _kMobileSendAmountFieldHeight,
      width: double.infinity,
      child: Column(
        children: [
          _buildAmountBalanceRow(
            context,
            showError: showError,
            spendableText: spendableText,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildAmountInputPanel(
            context,
            zecUsdUnitPrice: zecUsdUnitPrice,
            amountStyle: amountStyle,
            amountUnitStyle: amountUnitStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildAmountBalanceRow(
    BuildContext context, {
    required bool showError,
    required String spendableText,
  }) {
    final colors = context.colors;
    final textColor = showError ? colors.text.destructive : colors.text.accent;
    return SizedBox(
      key: const ValueKey('mobile_send_amount_balance_row'),
      height: _kMobileSendAmountBalanceRowHeight,
      child: Row(
        children: [
          const _ReviewZecIcon(),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              spendableText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Semantics(
            button: true,
            label: 'Use maximum spendable balance',
            child: GestureDetector(
              key: const ValueKey('mobile_send_max_button'),
              behavior: HitTestBehavior.opaque,
              onTap: _isResolvingMax ? null : _activateMaxMode,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                decoration: BoxDecoration(
                  color: colors.button.secondary.bg,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Max',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.button.secondary.label,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountInputPanel(
    BuildContext context, {
    required double? zecUsdUnitPrice,
    required TextStyle amountStyle,
    required TextStyle amountUnitStyle,
  }) {
    return SizedBox(
      key: const ValueKey('mobile_send_amount_input_panel'),
      height:
          _kMobileSendAmountInputHeight +
          AppSpacing.s +
          _kMobileSendAmountMetaHeight,
      child: Column(
        children: [
          _buildAmountInputRow(
            context,
            amountStyle: amountStyle,
            amountUnitStyle: amountUnitStyle,
          ),
          const SizedBox(height: AppSpacing.s),
          _buildAmountConversionRow(context, zecUsdUnitPrice: zecUsdUnitPrice),
        ],
      ),
    );
  }

  Widget _buildAmountInputRow(
    BuildContext context, {
    required TextStyle amountStyle,
    required TextStyle amountUnitStyle,
  }) {
    final colors = context.colors;
    final activeText = _amountInputIsUsd ? _fiatAmountText : _amountText;
    final textScaler = MediaQuery.textScalerOf(context);
    final showAmountCursor = _amountInputIsUsd || activeText.trim().isNotEmpty;
    final showEmptyZecCursor =
        !_amountInputIsUsd &&
        activeText.trim().isEmpty &&
        _amountFocus.hasFocus;
    final hintStyle = amountStyle.copyWith(color: colors.text.disabled);
    final usdPrefixStyle = amountUnitStyle.copyWith(
      fontSize: _kMobileSendAmountUsdPrefixFontSize,
      height:
          _kMobileSendAmountLineHeightPx / _kMobileSendAmountUsdPrefixFontSize,
    );
    final inputFormatters = [
      const CommaToDotInputFormatter(),
      _DecimalAmountInputFormatter(
        maxFractionDigits: _amountInputIsUsd ? 2 : 8,
        maxLength: _amountInputIsUsd ? 12 : 17,
      ),
    ];

    return SizedBox(
      height: _kMobileSendAmountInputHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final affixWidth = _amountInputIsUsd
              ? _textWidth(r'$', usdPrefixStyle, textScaler: textScaler) +
                    AppSpacing.xs
              : _textWidth('ZEC', amountUnitStyle, textScaler: textScaler) +
                    AppSpacing.xs;
          final inputWidth = _amountInputWidth(
            activeText,
            amountStyle,
            maxWidth: constraints.maxWidth - affixWidth,
            textScaler: textScaler,
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (_amountInputIsUsd) ...[
                Transform.translate(
                  offset: const Offset(
                    0,
                    _kMobileSendAmountUsdPrefixOpticalOffsetY,
                  ),
                  child: Text(r'$', style: usdPrefixStyle),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              SizedBox(
                width: inputWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    TextField(
                      key: const ValueKey('mobile_send_amount_input'),
                      controller: _amountController,
                      focusNode: _amountFocus,
                      autofocus: true,
                      onChanged: _handleAmountChanged,
                      onSubmitted: (_) => _amountFocus.unfocus(),
                      onTapOutside: (_) => _amountFocus.unfocus(),
                      textAlign: _amountInputIsUsd
                          ? TextAlign.left
                          : TextAlign.right,
                      textAlignVertical: TextAlignVertical.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      inputFormatters: inputFormatters,
                      maxLines: 1,
                      style: amountStyle,
                      showCursor: showAmountCursor,
                      cursorColor: colors.text.accent,
                      decoration: _amountInputDecoration(hintStyle),
                    ),
                    if (showEmptyZecCursor)
                      Positioned.fill(
                        child: _MobileSendAmountEmptyCursor(
                          style: amountStyle,
                          color: colors.text.accent,
                        ),
                      ),
                  ],
                ),
              ),
              if (!_amountInputIsUsd) ...[
                const SizedBox(width: AppSpacing.xs),
                Text('ZEC', style: amountUnitStyle),
              ],
            ],
          );
        },
      ),
    );
  }

  InputDecoration _amountInputDecoration(TextStyle hintStyle) {
    if (_amountInputIsUsd) {
      return InputDecoration.collapsed(hintText: '0', hintStyle: hintStyle);
    }

    return InputDecoration.collapsed(
      hintText: null,
      hint: Padding(
        padding: const EdgeInsetsDirectional.only(
          end: _kMobileSendAmountZecHintEndInset,
        ),
        child: Text('0', style: hintStyle, textAlign: TextAlign.right),
      ),
    );
  }

  double _amountInputWidth(
    String text,
    TextStyle style, {
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    final sample = text.trim().isEmpty ? '0' : text.trim();
    final measuredWidth = _textWidth(sample, style, textScaler: textScaler);
    final resolvedMaxWidth = maxWidth.isFinite
        ? maxWidth.clamp(_kMobileSendAmountInputMinWidth, double.infinity)
        : _kMobileSendAmountInputFallbackMaxWidth;
    return (measuredWidth + 10)
        .clamp(_kMobileSendAmountInputMinWidth, resolvedMaxWidth)
        .toDouble();
  }

  double _textWidth(
    String text,
    TextStyle style, {
    required TextScaler textScaler,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return painter.width;
  }

  Widget _buildAmountConversionRow(
    BuildContext context, {
    required double? zecUsdUnitPrice,
  }) {
    final colors = context.colors;
    final amountZatoshi = parseZecAmount(_amountText.trim());
    final canToggle = _amountInputIsUsd || zecUsdUnitPrice != null;
    final metaText = _amountInputIsUsd
        ? '${amountZatoshi == null ? '0' : ZecAmount.fromZatoshi(amountZatoshi).pretty().amountText} ZEC'
        : zecUsdUnitPrice == null
        ? null
        : r'$ ' +
              (amountZatoshi == null || amountZatoshi <= BigInt.zero
                  ? '0.00'
                  : sendUsdDisplayTextForZatoshi(
                      amountZatoshi,
                      zecUsdUnitPrice,
                    ));

    return SizedBox(
      height: _kMobileSendAmountMetaHeight,
      child: Center(
        child: Semantics(
          button: true,
          label: _amountInputIsUsd
              ? 'Enter amount in ZEC'
              : 'Enter amount in USD',
          enabled: canToggle,
          child: GestureDetector(
            key: const ValueKey('mobile_send_amount_mode_toggle'),
            behavior: HitTestBehavior.opaque,
            onTap: canToggle ? _toggleAmountInputMode : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.doubleArrowVertical,
                  size: 20,
                  color: colors.text.secondary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                if (metaText == null) ...[
                  Text(
                    r'$',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  const AmountPriceLoadingBar(
                    key: ValueKey('mobile_send_amount_price_loading'),
                    animated: true,
                  ),
                ] else
                  Text(
                    metaText,
                    key: const ValueKey('mobile_send_amount_conversion_text'),
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    // Uppercase ticker per the mobile review frame ("123.12 ZEC").
    final amountText =
        ZecAmount.tryParse(_amountText)?.activityDetail.toString() ??
        '$_amountText ZEC';
    final amountZatoshi = parseZecAmount(_amountText.trim());
    final amountFiatText = amountZatoshi == null
        ? null
        : fiatTextForZatoshi(
            amountZatoshi,
            zecUsdUnitPrice: ref.watch(zecLiveUsdUnitPriceProvider),
          );
    final feeText = _feeZatoshi == null
        ? '—'
        : ZecAmount.fromZatoshi(_feeZatoshi!).fee.toString();
    final address = _addressController.text.trim();
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final recipient = _reviewRecipientPresentation(
      address: address,
      contacts: addressBookContacts,
      ownAccounts: ownAccounts,
    );
    final isHardware = _activeAccountIsHardware;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.s,
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    key: const ValueKey('mobile_send_review_info'),
                    height: _kMobileSendReviewInfoHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        children: [
                          _ReviewInfoRow(
                            leading: const _ReviewZecIcon(),
                            title: 'Amount',
                            headline: amountText,
                            headlineKey: const ValueKey(
                              'mobile_send_review_amount',
                            ),
                            detail: amountFiatText,
                            detailKey: const ValueKey(
                              'mobile_send_review_amount_fiat',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const SizedBox(
                            width: 40,
                            height: _kMobileSendReviewIconRowHeight,
                            child: Center(
                              child: AppIcon(AppIcons.arrowDownward, size: 24),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _ReviewInfoRow(
                            // A request only retitles the row. The headline
                            // stays the recipient the wallet resolved, so an
                            // unverified link label never stands in for the
                            // identity being paid.
                            leading: recipient.buildReviewLeading(),
                            title: _isAnsweringPaymentRequest
                                ? 'Requested by'
                                : 'To',
                            headline: recipient.headline,
                            bottom: _ReviewAddressLine(
                              address: _compactReviewAddress(address),
                              addressType: _addressType,
                              isShielded: _isShieldedAddress,
                              onFullAddress: () => unawaited(
                                _showFullAddressSheet(address, recipient),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_requestedAmountNotice != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Requested $_requestedAmountNotice',
                      key: const ValueKey('mobile_send_review_requested'),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.base),
                  _ReviewWrap(
                    isShielded: _isShieldedAddress,
                    memo: _effectiveMemo,
                    feeText: feeText,
                    onMemoTap: () => unawaited(_editMemo()),
                    onFeeInfoTap: () => unawaited(_showFeeInfo()),
                  ),
                  if (_reviewFeeNotice != null) ...[
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      _reviewFeeNotice!,
                      key: const ValueKey('mobile_send_review_fee_notice'),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            key: const ValueKey('mobile_send_review_buttons'),
            height: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: const ValueKey('mobile_send_confirm'),
                  expand: true,
                  onPressed:
                      _isConfirmingSend ||
                          _isResolvingMax ||
                          (_isMaxMode && !_hasCurrentMaxQuote) ||
                          (!_hasCurrentReviewFeeQuote &&
                              !_reviewFeeRetryAvailable)
                      ? null
                      : () => unawaited(
                          _reviewFeeRetryAvailable
                              ? _refreshReviewQuote()
                              : _confirmAndSend(),
                        ),
                  leading: AppIcon(
                    isHardware ? AppIcons.qr : AppIcons.plane,
                    size: 20,
                  ),
                  child: Text(
                    _isConfirmingSend
                        ? 'Preparing...'
                        : _reviewFeeRetryAvailable
                        ? 'Try again'
                        : _isUsingCompletedSpendableSnapshot
                        ? 'Finishing wallet sync...'
                        : _isRefreshingReviewFee
                        ? 'Calculating fee...'
                        : !_hasCurrentReviewFeeQuote
                        ? 'Fee unavailable'
                        : isHardware
                        ? 'Confirm with Keystone'
                        : 'Confirm & Send',
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  key: const ValueKey('mobile_send_cancel'),
                  expand: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: _cancelSend,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colors = context.colors;
    final amountText =
        ZecAmount.tryParse(_amountText)?.receipt.toString() ??
        '$_amountText ZEC';
    final toLabel =
        _contactLabel ?? _truncateAddress(_addressController.text.trim());

    return Padding(
      key: ValueKey('mobile_send_status_${_phase.name}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  AppIcons.warning,
                  size: 48,
                  color: colors.text.destructive,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Send failed',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  '$amountText to $toLabel',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              key: const ValueKey('mobile_send_try_again'),
              onPressed: () => setState(() => _phase = _SendPhase.compose),
              child: const Text('Try again'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go('/home'),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Back to wallet',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _MobileSendAmountEmptyCursor extends StatefulWidget {
  const _MobileSendAmountEmptyCursor({
    required this.style,
    required this.color,
  });

  final TextStyle style;
  final Color color;

  @override
  State<_MobileSendAmountEmptyCursor> createState() =>
      _MobileSendAmountEmptyCursorState();
}

class _MobileSendAmountEmptyCursorState
    extends State<_MobileSendAmountEmptyCursor> {
  static const _iosCursorOpacityKeyFrames = <_CursorOpacityKeyFrame>[
    _CursorOpacityKeyFrame(Duration.zero, 1),
    _CursorOpacityKeyFrame(Duration(milliseconds: 500), 1),
    _CursorOpacityKeyFrame(Duration(microseconds: 537500), 0.75),
    _CursorOpacityKeyFrame(Duration(milliseconds: 575), 0.5),
    _CursorOpacityKeyFrame(Duration(microseconds: 612500), 0.25),
    _CursorOpacityKeyFrame(Duration(milliseconds: 650), 0),
    _CursorOpacityKeyFrame(Duration(milliseconds: 850), 0),
    _CursorOpacityKeyFrame(Duration(microseconds: 887500), 0.25),
    _CursorOpacityKeyFrame(Duration(milliseconds: 925), 0.5),
    _CursorOpacityKeyFrame(Duration(microseconds: 962500), 0.75),
    _CursorOpacityKeyFrame(Duration(seconds: 1), 1),
  ];

  final _editableKey = GlobalKey();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _blinkTimer;
  Rect? _cursorRect;
  TargetPlatform? _blinkPlatform;
  bool? _blinkTickersEnabled;
  double _cursorOpacity = 1;
  bool _measurementScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '0')
      ..selection = const TextSelection.collapsed(offset: 1);
    _focusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  }

  @override
  void didUpdateWidget(covariant _MobileSendAmountEmptyCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasurement();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final platform = Theme.of(context).platform;
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    if (_blinkPlatform != platform || _blinkTickersEnabled != tickersEnabled) {
      _blinkPlatform = platform;
      _blinkTickersEnabled = tickersEnabled;
      _restartBlink(platform, tickersEnabled: tickersEnabled);
    }
    _scheduleMeasurement();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final cursorOffset = _usesCupertinoCursor(platform)
        ? Offset(-2.0 / MediaQuery.devicePixelRatioOf(context), 0)
        : Offset.zero;
    _scheduleMeasurement();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ExcludeSemantics(
          child: IgnorePointer(
            child: Offstage(
              child: EditableText(
                key: _editableKey,
                controller: _controller,
                focusNode: _focusNode,
                readOnly: true,
                showCursor: false,
                enableInteractiveSelection: false,
                style: widget.style,
                textAlign: TextAlign.right,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                cursorColor: widget.color,
                backgroundCursorColor: widget.color,
                cursorWidth: 2,
                cursorOffset: cursorOffset,
              ),
            ),
          ),
        ),
        if (_cursorRect != null)
          Positioned.fromRect(
            rect: _cursorRect!,
            child: IgnorePointer(
              child: Opacity(
                key: const ValueKey('mobile_send_amount_empty_cursor'),
                opacity: _cursorOpacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: _usesCupertinoCursor(platform)
                        ? BorderRadius.circular(2)
                        : BorderRadius.zero,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _restartBlink(TargetPlatform platform, {required bool tickersEnabled}) {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _cursorOpacity = tickersEnabled ? 1 : 0;
    if (!tickersEnabled || EditableText.debugDeterministicCursor) return;

    if (platform == TargetPlatform.iOS) {
      _scheduleIosBlinkKeyFrame(1);
      return;
    }

    _blinkTimer = Timer.periodic(_kMobileSendAmountCursorBlinkHalfPeriod, (_) {
      _setCursorOpacity(_cursorOpacity == 0 ? 1 : 0);
    });
  }

  void _scheduleIosBlinkKeyFrame(int index) {
    final next = _iosCursorOpacityKeyFrames[index];
    final previous = _iosCursorOpacityKeyFrames[index - 1];
    _blinkTimer = Timer(next.time - previous.time, () {
      if (!mounted ||
          _blinkPlatform != TargetPlatform.iOS ||
          _blinkTickersEnabled != true ||
          EditableText.debugDeterministicCursor) {
        return;
      }

      _setCursorOpacity(next.opacity);
      final nextIndex = index + 1;
      _scheduleIosBlinkKeyFrame(
        nextIndex < _iosCursorOpacityKeyFrames.length ? nextIndex : 1,
      );
    });
  }

  void _setCursorOpacity(double opacity) {
    if (_cursorOpacity == opacity) return;
    setState(() => _cursorOpacity = opacity);
  }

  void _scheduleMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;

      final renderObject = context.findRenderObject();
      final editableRenderObject = _editableKey.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox || editableRenderObject == null) return;

      final editable = _findRenderEditable(editableRenderObject);
      if (editable == null || !editable.hasSize) return;

      final caretLocal = editable.getLocalRectForCaret(
        const TextPosition(offset: 1),
      );
      final caretTopLeft = renderObject.globalToLocal(
        editable.localToGlobal(caretLocal.topLeft),
      );
      final nextRect = caretTopLeft & caretLocal.size;
      if (!_rectNearlyEquals(_cursorRect, nextRect)) {
        setState(() => _cursorRect = nextRect);
      }
    });
  }

  bool _usesCupertinoCursor(TargetPlatform platform) {
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  bool _rectNearlyEquals(Rect? a, Rect b) {
    if (a == null) return false;
    const tolerance = 0.01;
    return (a.left - b.left).abs() < tolerance &&
        (a.top - b.top).abs() < tolerance &&
        (a.width - b.width).abs() < tolerance &&
        (a.height - b.height).abs() < tolerance;
  }
}

class _CursorOpacityKeyFrame {
  const _CursorOpacityKeyFrame(this.time, this.opacity);

  final Duration time;
  final double opacity;
}

RenderEditable? _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= _findRenderEditable(child);
  });
  return found;
}

class _DecimalAmountInputFormatter extends TextInputFormatter {
  const _DecimalAmountInputFormatter({
    required this.maxFractionDigits,
    required this.maxLength,
  });

  final int maxFractionDigits;
  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    var hasDecimal = false;
    for (final codeUnit in text.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      if (ch == '.') {
        if (hasDecimal) continue;
        hasDecimal = true;
        buffer.write(ch);
        continue;
      }
      if (codeUnit >= 0x30 && codeUnit <= 0x39) {
        buffer.write(ch);
      }
    }

    text = buffer.toString();
    if (text.startsWith('.')) text = '0$text';
    if (text.length > maxLength) text = text.substring(0, maxLength);
    final decimalIndex = text.indexOf('.');
    if (decimalIndex >= 0) {
      final maxEnd = decimalIndex + 1 + maxFractionDigits;
      if (text.length > maxEnd) text = text.substring(0, maxEnd);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _ReviewZecIcon extends StatelessWidget {
  const _ReviewZecIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        // Zcash brand yellow — fixed brand color like the crimson shield,
        // not a theme token.
        color: Color(0xFFF4B728),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: AppIcon(
          AppIcons.zcashCurrency,
          size: 22,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

class _ReviewWalletIcon extends StatelessWidget {
  const _ReviewWalletIcon();

  @override
  Widget build(BuildContext context) {
    // Neutral circular wallet badge for a raw (no-contact) recipient —
    // reuses the shared status badge instead of the Amount row's brand ZEC
    // coin, so the recipient leading matches the status receipts.
    return MobileReviewIconBadge(
      child: AppIcon(
        AppIcons.wallet,
        size: 18,
        color: context.colors.icon.regular,
      ),
    );
  }
}

class _ReviewInfoRow extends StatelessWidget {
  const _ReviewInfoRow({
    required this.leading,
    required this.title,
    required this.headline,
    this.headlineKey,
    this.detail,
    this.detailKey,
    this.bottom,
  }) : assert(detail == null || bottom == null);

  final Widget leading;
  final String title;
  final String headline;
  final Key? headlineKey;
  final String? detail;
  final Key? detailKey;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detailText = detail;
    return SizedBox(
      height: _kMobileSendReviewInfoRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SizedBox(
              height: _kMobileSendReviewInfoDetailsHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: _kMobileSendReviewIconRowHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SizedBox(
                    height: 33,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        headline,
                        key: headlineKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.headlineLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SizedBox(
                    height: _kMobileSendReviewIconRowHeight,
                    child:
                        bottom ??
                        Align(
                          alignment: Alignment.centerLeft,
                          child: detailText == null
                              ? const SizedBox.shrink()
                              : Text(
                                  detailText,
                                  key: detailKey,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewAddressLine extends StatelessWidget {
  const _ReviewAddressLine({
    required this.address,
    required this.addressType,
    required this.isShielded,
    required this.onFullAddress,
  });

  final String address;
  final String addressType;
  final bool isShielded;
  final VoidCallback onFullAddress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isTex = _isTexAddressType(addressType);
    final label = isTex ? 'TEX - $address' : address;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              AppIcon(
                isShielded
                    ? AppIcons.shieldKeyhole
                    : AppIcons.transparentBalance,
                size: 16,
                color: isShielded
                    ? colors.icon.brandCrimson
                    : colors.icon.muted,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        _ReviewSmallButton(
          key: const ValueKey('mobile_send_full_address'),
          icon: AppIcons.eye,
          label: 'Full address',
          onTap: onFullAddress,
        ),
      ],
    );
  }
}

bool _isTexAddressType(String addressType) =>
    addressType.trim().toLowerCase() == 'tex';

class _ReviewSmallButton extends StatelessWidget {
  const _ReviewSmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 16, color: colors.button.ghost.label),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.button.ghost.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewWrap extends StatelessWidget {
  const _ReviewWrap({
    required this.isShielded,
    required this.memo,
    required this.feeText,
    required this.onMemoTap,
    required this.onFeeInfoTap,
  });

  final bool isShielded;
  final String memo;
  final String feeText;
  final VoidCallback onMemoTap;
  final VoidCallback onFeeInfoTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('mobile_send_review_wrap'),
      height: isShielded ? _kMobileSendReviewWrapHeight : 96,
      child: MobileSurfaceCard(
        cornerRadius: AppRadii.xLarge - AppSpacing.xs,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.base,
        ),
        child: Column(
          children: [
            if (isShielded) ...[
              _ReviewListRow(
                key: const ValueKey('mobile_send_memo_row'),
                onTap: onMemoTap,
                leftLabel: memo.isEmpty ? null : 'Message',
                rightLabel: memo.isEmpty ? 'Add short encrypted message' : memo,
                rightIcon: memo.isEmpty
                    ? AppIcons.edit
                    : AppIcons.doubleArrowVertical,
                centered: memo.isEmpty,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                height: _kMobileSendReviewDividerHeight,
                color: colors.border.regular,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _ReviewListRow(
              leftLabel: 'Tx fee',
              rightLabel: feeText,
              rightIcon: AppIcons.help,
              rightKey: const ValueKey('mobile_send_fee'),
              onTap: onFeeInfoTap,
              semanticLabel: 'About the transaction fee',
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewListRow extends StatelessWidget {
  const _ReviewListRow({
    required this.rightLabel,
    this.leftLabel,
    this.rightIcon,
    this.rightKey,
    this.onTap,
    this.semanticLabel,
    this.centered = false,
    super.key,
  });

  final String? leftLabel;
  final String rightLabel;
  final String? rightIcon;
  final Key? rightKey;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final right = Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.end,
      children: [
        if (rightIcon != null && centered) ...[
          AppIcon(rightIcon!, size: 20, color: colors.icon.muted),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Flexible(
          fit: centered ? FlexFit.loose : FlexFit.tight,
          child: Text(
            rightLabel,
            key: rightKey,
            textAlign: centered ? TextAlign.left : TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: centered && leftLabel == null
                  ? colors.text.secondary
                  : colors.text.accent,
            ),
          ),
        ),
        if (rightIcon != null && !centered) ...[
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(rightIcon!, size: 20, color: colors.icon.muted),
        ],
      ],
    );

    final content = SizedBox(
      height: _kMobileSendReviewRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: centered
            ? Center(child: right)
            : Row(
                children: [
                  if (leftLabel != null)
                    Text(
                      leftLabel!,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: right),
                ],
              ),
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Memo entry sheet — Figma `Review Add Memo` (4484:62917). Pops the
/// new memo text; popping an empty string clears it.
class _MemoSheet extends StatefulWidget {
  const _MemoSheet({required this.initial});

  final String initial;

  @override
  State<_MemoSheet> createState() => _MemoSheetState();
}

class _MemoSheetState extends State<_MemoSheet> {
  static const _memoByteLimit = 512;
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  late final FocusNode _focusNode = FocusNode()..addListener(_handleFocus);

  String get _initialMemo => widget.initial.trim();

  String get _currentMemo => _controller.text.trim();

  bool get _showClearMemo =>
      _initialMemo.isNotEmpty && _currentMemo == _initialMemo;

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (mounted) setState(() {});
  }

  int get _usedBytes => utf8.encode(_currentMemo).length;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overLimit = _usedBytes > _memoByteLimit;
    final labelStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.secondary,
      fontWeight: FontWeight.w400,
    );
    final primaryIsClear = _showClearMemo;
    final primaryDisabled = overLimit && !primaryIsClear;

    return MobileModalScaffold(
      title: 'Add Memo',
      onClose: () => Navigator.of(context).pop(),
      bodyGap: AppSpacing.s,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const ValueKey('mobile_send_memo_text_area'),
            height: 222,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                children: [
                  SizedBox(
                    height: _kMobileSendRecipientLineHeight,
                    child: Row(
                      children: [
                        Text('Message', style: labelStyle),
                        const Spacer(),
                        Text(
                          // Used/total bytes, like the Add Memo frame's
                          // "51/512".
                          '$_usedBytes/$_memoByteLimit',
                          style: labelStyle.copyWith(
                            color: overLimit
                                ? colors.text.destructive
                                : colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _MemoTextArea(
                    key: const ValueKey('mobile_send_memo_field'),
                    controller: _controller,
                    focusNode: _focusNode,
                    hintText: 'Only the recipient can read this',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: _kMobileSendRecipientLineHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: overLimit
                          ? Text(
                              'Message is too long',
                              style: labelStyle.copyWith(
                                color: colors.text.destructive,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            key: const ValueKey('mobile_send_memo_buttons'),
            height: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: ValueKey(
                    primaryIsClear
                        ? 'mobile_send_memo_clear'
                        : 'mobile_send_memo_save',
                  ),
                  expand: true,
                  leading: primaryIsClear
                      ? const AppIcon(AppIcons.trash)
                      : null,
                  onPressed: primaryDisabled
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(primaryIsClear ? '' : _currentMemo),
                  child: Text(primaryIsClear ? 'Clear memo' : 'Add Memo'),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  key: const ValueKey('mobile_send_memo_cancel'),
                  expand: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoTextArea extends StatefulWidget {
  const _MemoTextArea({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  State<_MemoTextArea> createState() => _MemoTextAreaState();
}

class _MemoTextAreaState extends State<_MemoTextArea> {
  late final ScrollController _scrollController = ScrollController();
  bool _canScroll = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleCanScrollUpdate);
    _scrollController.addListener(_scheduleCanScrollUpdate);
    _scheduleCanScrollUpdate();
  }

  @override
  void didUpdateWidget(covariant _MemoTextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleCanScrollUpdate);
      widget.controller.addListener(_scheduleCanScrollUpdate);
      _scheduleCanScrollUpdate();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleCanScrollUpdate);
    _scrollController.removeListener(_scheduleCanScrollUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleCanScrollUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nextCanScroll =
          _scrollController.hasClients &&
          _scrollController.position.hasContentDimensions &&
          _scrollController.position.maxScrollExtent > 0.5;
      if (_canScroll == nextCanScroll) return;
      setState(() {
        _canScroll = nextCanScroll;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final focused = widget.focusNode.hasFocus;

    return Container(
      height: 148,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(
          color: focused
              ? colors.background.inverse
              : colors.background.ground.withValues(alpha: 0),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _scheduleCanScrollUpdate();
                return false;
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 40, 12),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: TextField(
                    key: const ValueKey('mobile_send_memo_editable'),
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    scrollController: _scrollController,
                    autofocus: true,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                    cursorColor: colors.text.accent,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hintText,
                      hintStyle: AppTypography.bodyMedium.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 12,
            child: _MemoTextAreaScrollbar(
              visible: _canScroll,
              controller: _scrollController,
              thumbColor: colors.background.overlay,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoTextAreaScrollbar extends StatefulWidget {
  const _MemoTextAreaScrollbar({
    required this.visible,
    required this.controller,
    required this.thumbColor,
  });

  final bool visible;
  final ScrollController controller;
  final Color thumbColor;

  @override
  State<_MemoTextAreaScrollbar> createState() => _MemoTextAreaScrollbarState();
}

class _MemoTextAreaScrollbarState extends State<_MemoTextAreaScrollbar> {
  static const _horizontalInset = 3.0;
  static const _topInset = 8.0;
  static const _bottomInset = 8.0;
  static const _minThumbHeight = 24.0;
  static const _maxThumbHeight = 62.0;
  static const _thumbWidth = 6.0;

  double? _dragThumbOffset;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _MemoTextAreaScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleScrollChanged);
      widget.controller.addListener(_handleScrollChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScrollChanged);
    super.dispose();
  }

  void _handleScrollChanged() {
    if (mounted) setState(() {});
  }

  _MemoScrollbarGeometry? _geometry(double height) {
    if (!widget.visible) return null;
    if (height <= 0) return null;
    if (!widget.controller.hasClients) return null;
    final position = widget.controller.position;
    if (!position.hasContentDimensions) return null;
    final maxScrollExtent = position.maxScrollExtent;
    if (maxScrollExtent <= 0) return null;

    final trackHeight = height - _topInset - _bottomInset;
    final viewportExtent = position.viewportDimension;
    final contentExtent = viewportExtent + maxScrollExtent;
    if (trackHeight <= 0 || viewportExtent <= 0 || contentExtent <= 0) {
      return null;
    }

    final maxThumbHeight = trackHeight < _maxThumbHeight
        ? trackHeight
        : _maxThumbHeight;
    if (maxThumbHeight <= 0) return null;
    final thumbHeight = (trackHeight * viewportExtent / contentExtent)
        .clamp(_minThumbHeight, maxThumbHeight)
        .toDouble();
    final thumbTravel = trackHeight - thumbHeight;
    final scrollFraction = thumbTravel <= 0
        ? 0.0
        : (position.pixels / maxScrollExtent).clamp(0.0, 1.0).toDouble();
    final thumbTop = _topInset + scrollFraction * thumbTravel;

    return _MemoScrollbarGeometry(
      trackHeight: trackHeight,
      thumbTop: thumbTop,
      thumbHeight: thumbHeight,
      thumbTravel: thumbTravel,
      maxScrollExtent: maxScrollExtent,
    );
  }

  void _jumpToLocalY(double localY, _MemoScrollbarGeometry geometry) {
    if (geometry.thumbTravel <= 0) return;
    final dragOffset = _dragThumbOffset ?? geometry.thumbHeight / 2;
    final targetThumbTop = localY - dragOffset;
    final scrollFraction = ((targetThumbTop - _topInset) / geometry.thumbTravel)
        .clamp(0.0, 1.0)
        .toDouble();
    widget.controller.jumpTo(scrollFraction * geometry.maxScrollExtent);
  }

  void _handlePointerDown(PointerDownEvent event, double height) {
    final geometry = _geometry(height);
    if (geometry == null) return;
    final localY = event.localPosition.dy;
    final hitThumb =
        localY >= geometry.thumbTop &&
        localY <= geometry.thumbTop + geometry.thumbHeight;
    _dragThumbOffset = hitThumb
        ? localY - geometry.thumbTop
        : geometry.thumbHeight / 2;
    _jumpToLocalY(localY, geometry);
  }

  void _handlePointerMove(PointerMoveEvent event, double height) {
    final geometry = _geometry(height);
    if (geometry == null) return;
    _jumpToLocalY(event.localPosition.dy, geometry);
  }

  void _clearDrag() {
    _dragThumbOffset = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final geometry = _geometry(height);
        if (geometry == null) return const SizedBox.shrink();

        return Listener(
          key: const ValueKey('mobile_send_memo_scrollbar'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _handlePointerDown(event, height),
          onPointerMove: (event) => _handlePointerMove(event, height),
          onPointerUp: (_) => _clearDrag(),
          onPointerCancel: (_) => _clearDrag(),
          child: Stack(
            children: [
              Positioned(
                key: const ValueKey('mobile_send_memo_scrollbar_thumb'),
                left: _horizontalInset,
                top: geometry.thumbTop,
                width: _thumbWidth,
                height: geometry.thumbHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.thumbColor,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemoScrollbarGeometry {
  const _MemoScrollbarGeometry({
    required this.trackHeight,
    required this.thumbTop,
    required this.thumbHeight,
    required this.thumbTravel,
    required this.maxScrollExtent,
  });

  final double trackHeight;
  final double thumbTop;
  final double thumbHeight;
  final double thumbTravel;
  final double maxScrollExtent;
}

/// Mobile counterpart of the desktop Sapling params prompt — same copy,
/// presented as a sheet. Pops true to download.
/// Shared with the Keystone signing screen, which needs the same
/// proving-parameters consent before preparing a Sapling-bound PCZT.
class MobileSaplingParamsSheet extends StatelessWidget {
  const MobileSaplingParamsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Download Required',
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'To create this private transaction, your wallet needs to '
            'download about 50MB of cryptographic parameters.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "This happens once, then it's done.\n"
            'Network data charges may apply.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_send_sapling_download'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(false),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Cancel',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientLineText extends StatelessWidget {
  const _RecipientLineText(
    this.text, {
    required this.color,
    this.fontWeight = FontWeight.w500,
  });

  final String text;
  final Color color;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kMobileSendRecipientLineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              color: color,
              fontWeight: fontWeight,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline action pill in the recipient field's trailing slot — Figma
/// `Send to Focus` variants switch it between Paste and Clear.
class _AddressFieldActionButton extends StatelessWidget {
  const _AddressFieldActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  double get _width => switch (label) {
    'Paste' => _kMobileSendAddressPasteWidth,
    'Clear' => _kMobileSendAddressClearWidth,
    _ => _kMobileSendAddressPasteWidth,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          key: ValueKey('mobile_send_address_${label.toLowerCase()}'),
          width: _width,
          height: _kMobileSendAddressActionHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.button.secondary.bg,
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.button.secondary.label,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
