import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../models/vizor_payment_link.dart';
import '../providers/payment_link_cards_provider.dart';
import '../providers/payment_link_intake_provider.dart';
import '../services/payment_link_clipboard.dart';
import '../services/payment_link_received_store.dart';
import '../services/payment_link_recovery_store.dart';
import '../services/payment_link_service.dart';
import '../widgets/payment_link_card_flip.dart';
import '../widgets/payment_link_card_selector_rail.dart';
import '../widgets/payment_link_confetti.dart';
import '../widgets/payment_link_desktop_views.dart';
import '../widgets/payment_link_gift_card.dart';
import '../widgets/payment_link_keystone_signing_overlay.dart';
import '../widgets/mobile/payment_link_mobile_views.dart';

enum _PaymentLinksLocalPage {
  home,
  amount,
  message,
  review,
  ready,
  redeem,
  received,
}

/// Desktop Payment Link lifecycle.
///
/// The presentation remains local to this screen, while all secret creation,
/// recovery persistence, sync, and transaction work stays behind
/// [PaymentLinkOperations]. Artwork and message are carried by the v1
/// presentation payload.
class PaymentLinksDesktopScreen extends ConsumerStatefulWidget {
  const PaymentLinksDesktopScreen({this.initialCards, super.key});

  final PaymentLinkCardsSnapshot? initialCards;

  @override
  ConsumerState<PaymentLinksDesktopScreen> createState() =>
      _PaymentLinksDesktopScreenState();
}

class _PaymentLinksDesktopScreenState
    extends ConsumerState<PaymentLinksDesktopScreen> {
  static const _linkAvailableSoonRemainingConfirmations = 3;
  static const _syncingFeeEstimateMessage =
      'Card fee will be estimated when wallet sync completes.';

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static final _amountFormatter = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    final isNumericAmount = RegExp(
      r'^(?:\d+(?:\.\d{0,8})?|\.\d{0,8})?$',
    ).hasMatch(newValue.text);
    return isNumericAmount ? newValue : oldValue;
  });

  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  late final PaymentLinkOperations _paymentLinkOperations;
  Timer? _fundingQuoteDebounce;
  Timer? _fundingProgressTimer;

  _PaymentLinksLocalPage _page = _PaymentLinksLocalPage.home;
  PaymentLinkCardArtwork _selectedArtwork = PaymentLinkCardArtwork.gift;
  PaymentLinkRedeemVisualState _redeemState =
      PaymentLinkRedeemVisualState.paste;
  PaymentLinkCardsTab _activeCardsTab = PaymentLinkCardsTab.created;
  List<PaymentLinkRecoveryRecord> _recoveries = const [];
  Map<String, PaymentLinkFundingProgress> _fundingProgressByAddress = const {};
  List<PaymentLinkReceivedRecord> _receivedCards = const [];
  PaymentLinkFundingQuote? _fundingQuote;
  String? _fundingQuoteRequestedAccountUuid;
  final Map<String, PaymentLinkClaimSession> _receivedClaimSessions = {};
  final Set<String> _claimPreparations = {};
  final Set<String> _claimSubmissions = {};
  VizorPaymentLink? _readyLink;
  VizorPaymentLink? _receivedLink;
  _PaymentLinkKeystoneFundingRequest? _keystoneFundingRequest;
  bool _showHelp = false;
  bool _amountFocused = false;
  bool _fundingQuoteInProgress = false;
  String? _amountSupportingText;
  bool _amountSupportingTextIsError = false;
  int _fundingQuoteGeneration = 0;
  bool _fundingQuoteRetryScheduled = false;
  bool _reviewShowsBack = false;
  bool _readyShowsBack = false;
  bool _receivedShowsBack = false;
  bool _messageEditorRevealed = false;
  bool _operationInProgress = false;
  bool _receivedRefreshInProgress = false;
  bool _pendingIntakeScheduled = false;

  PaymentLinkClaimSession? get _receivedClaimSession {
    final address = _receivedLink?.address;
    return address == null ? null : _receivedClaimSessions[address];
  }

  bool get _activeClaimInProgress {
    final address = _receivedLink?.address;
    return address != null && _claimSubmissions.contains(address);
  }

  @override
  void initState() {
    super.initState();
    _paymentLinkOperations = ref.read(paymentLinkOperationsProvider);
    if (kAppFormFactor == AppFormFactor.mobile) {
      _page = _PaymentLinksLocalPage.redeem;
      if (ref.read(paymentLinkIntakeProvider).pendingLink != null) {
        _redeemState = PaymentLinkRedeemVisualState.loading;
      }
    }
    final initialCards = widget.initialCards;
    if (initialCards != null) {
      _recoveries = initialCards.created;
      _receivedCards = initialCards.received;
    }
    _amountFocusNode.addListener(_handleAmountFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kAppFormFactor == AppFormFactor.desktop) {
        ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      }
      if (initialCards == null) {
        unawaited(_loadRecoveries());
        unawaited(_loadReceivedCards());
      } else {
        unawaited(_refreshFundingProgress(records: initialCards.created));
        unawaited(_refreshReceivedClaims(records: initialCards.received));
      }
      unawaited(_consumePendingPaymentLink());
    });
    _fundingProgressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshFundingProgress());
      unawaited(_refreshReceivedClaims());
    });
  }

  @override
  void dispose() {
    _fundingQuoteDebounce?.cancel();
    _fundingProgressTimer?.cancel();
    for (final entry in _receivedClaimSessions.entries) {
      if (_claimSubmissions.contains(entry.key)) continue;
      final claimSession = entry.value;
      unawaited(_paymentLinkOperations.discardClaimSession(claimSession));
    }
    _amountFocusNode
      ..removeListener(_handleAmountFocus)
      ..dispose();
    _amountController.dispose();
    _messageFocusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleAmountFocus() {
    if (_amountFocused == _amountFocusNode.hasFocus) return;
    setState(() => _amountFocused = _amountFocusNode.hasFocus);
  }

  void _showPage(_PaymentLinksLocalPage page) {
    _amountFocusNode.unfocus();
    _messageFocusNode.unfocus();
    setState(() {
      if (page == _PaymentLinksLocalPage.message &&
          _page != _PaymentLinksLocalPage.message) {
        _messageEditorRevealed = _hasMessage;
      }
      if (page == _PaymentLinksLocalPage.review &&
          _page != _PaymentLinksLocalPage.review) {
        _reviewShowsBack = false;
      }
      _page = page;
      _showHelp = false;
    });
  }

  void _startCreate() {
    _fundingQuoteDebounce?.cancel();
    _fundingQuoteGeneration++;
    _amountController.clear();
    _messageController.clear();
    setState(() {
      _selectedArtwork = PaymentLinkCardArtwork.gift;
      _fundingQuote = null;
      _fundingQuoteInProgress = false;
      _amountSupportingText = null;
      _amountSupportingTextIsError = false;
      _readyLink = null;
      _reviewShowsBack = false;
      _readyShowsBack = false;
      _messageEditorRevealed = false;
      _page = _PaymentLinksLocalPage.amount;
      _showHelp = false;
    });
  }

  void _showHelpOverlay() => setState(() => _showHelp = true);

  void _hideHelpOverlay() => setState(() => _showHelp = false);

  void _schedulePendingPaymentLink() {
    if (_pendingIntakeScheduled) return;
    _pendingIntakeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingIntakeScheduled = false;
      if (mounted) _consumePendingPaymentLink();
    });
  }

  Future<void> _consumePendingPaymentLink() async {
    if (!mounted) return;
    final notifier = ref.read(paymentLinkIntakeProvider.notifier);
    while (mounted) {
      final link = notifier.takePending();
      if (link == null) return;
      unawaited(_checkPaymentLink(link));
    }
  }

  Future<void> _loadRecoveries({bool showError = true}) async {
    try {
      final records = await ref
          .read(paymentLinkOperationsProvider)
          .loadCreatedLinkRecoveries();
      if (!mounted) return;
      final visible = records.where((record) => !record.isArchived).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() => _recoveries = visible);
      unawaited(_refreshFundingProgress(records: visible));
    } catch (_) {
      if (mounted && showError) {
        _showError('Gift Cards could not be loaded.');
      }
    }
  }

  Future<void> _refreshFundingProgress({
    List<PaymentLinkRecoveryRecord>? records,
  }) async {
    final recoveries = records ?? _recoveries;
    final pending = recoveries
        .where(
          (record) =>
              !(_fundingProgressByAddress[record.link.address]?.isReady ??
                  false),
        )
        .toList();
    if (pending.isEmpty || _operationInProgress) return;
    try {
      final updates = await ref
          .read(paymentLinkOperationsProvider)
          .inspectCreatedLinkFundings(pending);
      if (!mounted) return;
      setState(
        () => _fundingProgressByAddress = {
          ..._fundingProgressByAddress,
          ...updates,
        },
      );
    } catch (_) {
      // Keep the last known progress. A later foreground sync or timer tick
      // retries this read without hiding an already-ready link.
    }
  }

  Future<void> _loadReceivedCards({bool showError = true}) async {
    try {
      final records = await ref
          .read(paymentLinkOperationsProvider)
          .loadReceivedLinkRecoveries();
      if (!mounted) return;
      final sorted = List<PaymentLinkReceivedRecord>.of(records)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() => _receivedCards = sorted);
      unawaited(_refreshReceivedClaims(records: sorted));
    } catch (_) {
      if (mounted && showError) {
        _showError('Received Gift Cards could not be loaded.');
      }
    }
  }

  Future<void> _refreshReceivedClaims({
    List<PaymentLinkReceivedRecord>? records,
  }) async {
    final receivedCards = records ?? _receivedCards;
    final hasReceiving = receivedCards.any(
      (record) => record.status == PaymentLinkReceivedStatus.receiving,
    );
    if (!hasReceiving ||
        _operationInProgress ||
        _claimSubmissions.isNotEmpty ||
        _receivedRefreshInProgress) {
      return;
    }
    _receivedRefreshInProgress = true;
    try {
      final updated = await ref
          .read(paymentLinkOperationsProvider)
          .inspectReceivedLinkClaims(receivedCards);
      if (!mounted) return;
      final sorted = List<PaymentLinkReceivedRecord>.of(updated)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() => _receivedCards = sorted);
    } catch (_) {
      // Keep the last persisted status. The main wallet sync and the next
      // timer tick will retry the mined-history check.
    } finally {
      _receivedRefreshInProgress = false;
    }
  }

  void _rememberReceivedLink(VizorPaymentLink link) {
    final existingIndex = _receivedCards.indexWhere(
      (record) => record.address == link.address,
    );
    if (existingIndex >= 0) return;
    _receivedCards = [
      PaymentLinkReceivedRecord.fromLink(link),
      ..._receivedCards,
    ];
  }

  void _setReceivedCardStatus(
    String address,
    PaymentLinkReceivedStatus status, {
    bool clearClaimLink = false,
  }) {
    _receivedCards = [
      for (final record in _receivedCards)
        if (record.address == address)
          record.copyWith(
            status: status,
            claimLink: clearClaimLink ? null : record.claimLink,
            updatedAt: DateTime.now(),
          )
        else
          record,
    ];
  }

  void _openReceivedCard(PaymentLinkReceivedRecord record) {
    final link = record.claimLink;
    if (link == null) return;
    final session = _receivedClaimSessions[link.address];
    if (session != null) {
      setState(() {
        _receivedLink = link;
        _receivedShowsBack = false;
        _page = _PaymentLinksLocalPage.received;
      });
      return;
    }
    unawaited(_checkPaymentLink(link));
  }

  bool get _hasPositiveAmount {
    final amount = parseZecAmount(_amountController.text);
    return amount != null && amount > BigInt.zero;
  }

  PaymentLinkAmountVisualState get _amountVisualState {
    if (_amountController.text.isEmpty) {
      return _amountFocused
          ? PaymentLinkAmountVisualState.focused
          : PaymentLinkAmountVisualState.empty;
    }
    return _hasPositiveAmount
        ? PaymentLinkAmountVisualState.amount
        : PaymentLinkAmountVisualState.focused;
  }

  bool get _canContinueAmount =>
      _hasPositiveAmount &&
      !_fundingQuoteInProgress &&
      _fundingQuote != null &&
      _amountSupportingText == null;

  bool _canEstimateCardFee(SyncState? sync, String accountUuid) {
    return sync != null &&
        sync.accountUuid == accountUuid &&
        sync.hasBalanceData &&
        sync.isSyncComplete &&
        !sync.isSyncing &&
        !sync.isBackgroundMode &&
        sync.failure == null &&
        sync.error == null;
  }

  void _handleFeeQuoteSyncGateChanged(
    ({String? accountUuid, bool ready})? previous,
    ({String? accountUuid, bool ready}) next,
  ) {
    if (!next.ready ||
        (previous?.ready == true &&
            previous?.accountUuid == next.accountUuid) ||
        _fundingQuoteRetryScheduled) {
      return;
    }
    if (_page != _PaymentLinksLocalPage.amount ||
        next.accountUuid == null ||
        _fundingQuoteRequestedAccountUuid != next.accountUuid ||
        !_hasPositiveAmount ||
        _fundingQuote != null ||
        _fundingQuoteInProgress) {
      return;
    }

    _fundingQuoteRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fundingQuoteRetryScheduled = false;
      if (!mounted || _page != _PaymentLinksLocalPage.amount) return;
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      final sync = ref.read(syncProvider).value;
      if (accountUuid != next.accountUuid ||
          !_canEstimateCardFee(sync, next.accountUuid!)) {
        return;
      }
      _handleAmountChanged(_amountController.text);
    });
  }

  void _handleAmountChanged(String value) {
    _fundingQuoteDebounce?.cancel();
    final generation = ++_fundingQuoteGeneration;
    final amount = parseZecAmount(value);
    setState(() {
      _fundingQuote = null;
      _fundingQuoteRequestedAccountUuid = null;
      _fundingQuoteInProgress = false;
      _amountSupportingText = null;
      _amountSupportingTextIsError = false;
    });
    if (amount == null || amount <= BigInt.zero) return;

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final sync = ref.read(syncProvider).value;
    if (accountUuid == null || accountUuid.isEmpty) return;
    setState(() => _fundingQuoteRequestedAccountUuid = accountUuid);
    if (!_canEstimateCardFee(sync, accountUuid)) {
      setState(() {
        _amountSupportingText = _syncingFeeEstimateMessage;
        _amountSupportingTextIsError = false;
      });
      return;
    }
    final readySync = sync!;
    final minimumFunding = paymentLinkFundingAmountZatoshi(amount);
    if (readySync.hasBalanceData &&
        readySync.spendableBalance < minimumFunding) {
      setState(() {
        _amountSupportingText =
            'Insufficient balance to cover the Card amount and fees.';
        _amountSupportingTextIsError = true;
      });
      return;
    }

    setState(() => _fundingQuoteInProgress = true);
    _fundingQuoteDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        _loadFundingQuote(
          generation: generation,
          amountZatoshi: amount,
          sourceAccountUuid: accountUuid,
        ),
      );
    });
  }

  void _handleActiveAccountChanged(String? previous, String? current) {
    final quotedAccount = _fundingQuote?.sourceAccountUuid;
    final priorAccount =
        previous ?? quotedAccount ?? _fundingQuoteRequestedAccountUuid;
    if (current == null || priorAccount == null || priorAccount == current) {
      return;
    }
    if (_page != _PaymentLinksLocalPage.amount &&
        _page != _PaymentLinksLocalPage.message &&
        _page != _PaymentLinksLocalPage.review) {
      return;
    }

    final wasPastAmountStep = _page != _PaymentLinksLocalPage.amount;
    _fundingQuoteDebounce?.cancel();
    _fundingQuoteGeneration += 1;
    setState(() {
      _fundingQuote = null;
      _fundingQuoteInProgress = false;
      _amountSupportingText = null;
      _amountSupportingTextIsError = false;
      _page = _PaymentLinksLocalPage.amount;
    });
    _handleAmountChanged(_amountController.text);
    if (wasPastAmountStep) {
      showAppToast(
        context,
        'Active account changed. Review the Gift Card amount and fees again.',
        iconName: AppIcons.warning,
      );
    }
  }

  Future<void> _loadFundingQuote({
    required int generation,
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    try {
      final quote = await ref
          .read(paymentLinkOperationsProvider)
          .quoteFunding(
            amountZatoshi: amountZatoshi,
            sourceAccountUuid: sourceAccountUuid,
          );
      if (!mounted || generation != _fundingQuoteGeneration) return;
      if (quote.sourceAccountUuid != sourceAccountUuid) {
        throw StateError('Gift Card quote was returned for another account.');
      }
      final sync = ref.read(syncProvider).value;
      final insufficient =
          sync?.hasBalanceData == true &&
          sync!.accountUuid == sourceAccountUuid &&
          sync.spendableBalance < quote.totalDeductedZatoshi;
      setState(() {
        _fundingQuoteInProgress = false;
        _fundingQuote = insufficient ? null : quote;
        _amountSupportingText = insufficient
            ? 'Insufficient balance to cover the Card amount and fees.'
            : null;
        _amountSupportingTextIsError = insufficient;
      });
    } catch (_) {
      if (!mounted || generation != _fundingQuoteGeneration) return;
      final sync = ref.read(syncProvider).value;
      final waitingForSync = !_canEstimateCardFee(sync, sourceAccountUuid);
      setState(() {
        _fundingQuoteInProgress = false;
        _fundingQuote = null;
        _amountSupportingText = waitingForSync
            ? _syncingFeeEstimateMessage
            : 'Card fee could not be estimated. Try again.';
        _amountSupportingTextIsError = !waitingForSync;
      });
    }
  }

  bool get _hasMessage => _messageController.text.trim().isNotEmpty;

  bool get _messageExceedsByteLimit =>
      !PaymentLinkPresentation.isMessageWithinUtf8ByteLimit(
        _messageController.text,
      );

  String? get _maxAmountText {
    final sync = ref.watch(syncProvider).value;
    final quote = _fundingQuote;
    if (sync == null ||
        !sync.hasBalanceData ||
        quote == null ||
        sync.spendableBalance <= quote.cardFeeZatoshi) {
      return null;
    }
    return formatZecAmount(sync.spendableBalance - quote.cardFeeZatoshi);
  }

  void _useMaxAmount() {
    final sync = ref.read(syncProvider).value;
    final quote = _fundingQuote;
    if (sync == null ||
        !sync.hasBalanceData ||
        quote == null ||
        sync.spendableBalance <= quote.cardFeeZatoshi) {
      return;
    }
    final text = formatZecAmount(sync.spendableBalance - quote.cardFeeZatoshi);
    _amountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _amountFocusNode.requestFocus();
    _handleAmountChanged(text);
  }

  void _handleMessageChanged(String _) => setState(() {});

  void _revealMessageEditor() {
    if (_messageEditorRevealed) {
      _messageFocusNode.requestFocus();
      return;
    }
    setState(() => _messageEditorRevealed = true);
    // Reduced-motion mode swaps the card face without running the flip, so
    // focus the editor as soon as that face is mounted. In the animated path
    // the editor is not mounted yet and onAnimationEnd handles the focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_messageEditorRevealed ||
          _page != _PaymentLinksLocalPage.message ||
          _messageFocusNode.context == null) {
        return;
      }
      _messageFocusNode.requestFocus();
    });
  }

  void _focusMessageEditorAfterFlip() {
    if (!mounted ||
        !_messageEditorRevealed ||
        _page != _PaymentLinksLocalPage.message) {
      return;
    }
    _messageFocusNode.requestFocus();
  }

  void _clearMessage() {
    _messageController.clear();
    _messageFocusNode.requestFocus();
    setState(() {});
  }

  void _skipMessage() {
    _messageController.clear();
    _showPage(_PaymentLinksLocalPage.review);
  }

  void _selectWizardStep(int step) {
    switch (step) {
      case 0:
        _showPage(_PaymentLinksLocalPage.amount);
      case 1:
        if (_canContinueAmount) {
          _showPage(_PaymentLinksLocalPage.message);
        }
    }
  }

  Future<void> _createFundedLink() async {
    if (_operationInProgress) return;
    final amount = parseZecAmount(_amountController.text.trim());
    final quote = _fundingQuote;
    final accountState = ref.read(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    if (amount == null || amount <= BigInt.zero || quote == null) {
      _showError('Enter a valid Gift Card amount.');
      return;
    }
    if (activeAccountUuid == null || activeAccountUuid.isEmpty) {
      _showError('No active account is available.');
      return;
    }
    if (activeAccountUuid != quote.sourceAccountUuid) {
      _handleActiveAccountChanged(quote.sourceAccountUuid, activeAccountUuid);
      _showError(
        'The active account changed. Review the amount and try again.',
      );
      return;
    }
    final sourceAccountUuid = quote.sourceAccountUuid;
    final presentation = PaymentLinkPresentation(
      artworkId: _selectedArtwork.protocolId,
      message: _messageController.text,
    );
    if (ref
        .read(accountProvider.notifier)
        .isHardwareAccount(sourceAccountUuid)) {
      setState(() {
        _operationInProgress = true;
        _keystoneFundingRequest = _PaymentLinkKeystoneFundingRequest(
          amountZatoshi: amount,
          sourceAccountUuid: sourceAccountUuid,
          presentation: presentation,
        );
      });
      return;
    }

    setState(() => _operationInProgress = true);
    try {
      final funding = await ref
          .read(paymentLinkOperationsProvider)
          .createFundedLink(
            amountZatoshi: amount,
            sourceAccountUuid: sourceAccountUuid,
            presentation: presentation,
          );
      final link = funding.link;
      await _loadRecoveries(showError: false);
      if (!mounted) return;
      setState(() {
        _readyLink = link;
        _fundingProgressByAddress = {
          ..._fundingProgressByAddress,
          link.address: const PaymentLinkFundingProgress(confirmationCount: 0),
        };
        _readyShowsBack = false;
        _page = _PaymentLinksLocalPage.ready;
      });
    } catch (_) {
      if (mounted) _showError('Gift Card creation failed. Try again.');
    } finally {
      if (mounted) {
        setState(() => _operationInProgress = false);
        unawaited(_refreshFundingProgress());
      }
    }
  }

  void _cancelKeystoneFunding() {
    setState(() {
      _keystoneFundingRequest = null;
      _operationInProgress = false;
    });
    unawaited(_loadRecoveries(showError: false));
  }

  Future<void> _completeKeystoneFunding(
    VizorPaymentLink link,
    String status,
    String? message,
  ) async {
    await _loadRecoveries(showError: false);
    if (!mounted) return;
    setState(() {
      _keystoneFundingRequest = null;
      _operationInProgress = false;
      _readyLink = link;
      _fundingProgressByAddress = {
        ..._fundingProgressByAddress,
        link.address: const PaymentLinkFundingProgress(confirmationCount: 0),
      };
      _readyShowsBack = false;
      _page = _PaymentLinksLocalPage.ready;
    });
    unawaited(_refreshFundingProgress());
    if (status == 'broadcasted_storage_failed' ||
        status == 'broadcast_unknown') {
      showAppToast(
        context,
        message ??
            (status == 'broadcast_unknown'
                ? 'Funding is still being verified. Vizor will keep checking it.'
                : 'Funding was sent, but local transaction storage needs to sync.'),
        iconName: AppIcons.warning,
      );
    }
  }

  Future<void> _copyPaymentLink(VizorPaymentLink link) async {
    if (_operationInProgress) return;
    setState(() => _operationInProgress = true);
    try {
      await ref
          .read(paymentLinkClipboardProvider)
          .copySecret(link.toUri().toString());
      try {
        await ref
            .read(paymentLinkOperationsProvider)
            .markCreatedLinkShared(link);
        await _loadRecoveries(showError: false);
        if (mounted) showAppToast(context, 'Gift link copied');
      } catch (_) {
        if (mounted) {
          _showError('Gift link copied, but its status could not be updated.');
        }
      }
    } catch (_) {
      if (mounted) _showError('Gift link could not be copied.');
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<void> _pastePaymentLink() async {
    if (_operationInProgress) return;
    setState(() {
      _operationInProgress = true;
      _redeemState = PaymentLinkRedeemVisualState.loading;
    });
    try {
      final rawLink = await ref.read(paymentLinkClipboardProvider).readText();
      if (rawLink == null || rawLink.trim().isEmpty) {
        if (mounted) {
          setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
        }
        return;
      }
      final notifier = ref.read(paymentLinkIntakeProvider.notifier);
      final result = notifier.receive(rawLink);
      if (result != PaymentLinkIntakeResult.accepted) {
        if (mounted) {
          setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
        }
        return;
      }
      final link = notifier.takePending();
      if (link == null || !mounted) return;
      await _prepareDecodedPaymentLink(link);
    } catch (_) {
      if (mounted) {
        setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
      }
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<void> _checkPaymentLink(VizorPaymentLink link) async {
    if (!_claimPreparations.add(link.address)) return;
    setState(() {
      _redeemState = PaymentLinkRedeemVisualState.loading;
      _page = _PaymentLinksLocalPage.redeem;
      _showHelp = false;
    });
    try {
      await _prepareDecodedPaymentLink(link);
    } finally {
      _claimPreparations.remove(link.address);
      if (mounted) setState(() {});
    }
  }

  Future<void> _prepareDecodedPaymentLink(VizorPaymentLink link) async {
    try {
      final session = await ref
          .read(paymentLinkOperationsProvider)
          .prepareClaim(link);
      if (!mounted) {
        await ref
            .read(paymentLinkOperationsProvider)
            .discardClaimSession(session);
        return;
      }
      if (!session.canClaim) {
        await ref
            .read(paymentLinkOperationsProvider)
            .discardClaimSession(session);
        setState(() {
          _receivedClaimSessions.remove(link.address);
          _redeemState = PaymentLinkRedeemVisualState.unavailable;
          _page = _PaymentLinksLocalPage.redeem;
        });
        return;
      }
      setState(() {
        _receivedClaimSessions[link.address] = session;
        _receivedLink = link;
        _receivedShowsBack = false;
        _rememberReceivedLink(link);
        _redeemState = PaymentLinkRedeemVisualState.paste;
        _page = _PaymentLinksLocalPage.received;
      });
    } on FormatException {
      if (mounted) {
        setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _redeemState = PaymentLinkRedeemVisualState.paste);
        _showError('Card balance could not be checked. Try again.');
      }
    }
  }

  Future<void> _clearClipboard() async {
    await ref.read(paymentLinkClipboardProvider).clear();
    final claimSession = _receivedClaimSession;
    if (claimSession != null) {
      await ref
          .read(paymentLinkOperationsProvider)
          .discardClaimSession(claimSession);
      _receivedClaimSessions.remove(claimSession.link.address);
    }
    ref.read(paymentLinkIntakeProvider.notifier).clearError();
    if (mounted) {
      setState(() {
        _redeemState = PaymentLinkRedeemVisualState.paste;
      });
    }
  }

  Future<void> _claimReceivedLink() async {
    final link = _receivedLink;
    final session = _receivedClaimSession;
    if (link == null ||
        session == null ||
        !_claimSubmissions.add(link.address)) {
      return;
    }
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    setState(() {
      _receivedShowsBack = false;
      _setReceivedCardStatus(link.address, PaymentLinkReceivedStatus.receiving);
      _activeCardsTab = PaymentLinkCardsTab.received;
      if (!mobile) {
        _receivedLink = null;
        _page = _PaymentLinksLocalPage.home;
      }
      _showHelp = false;
    });
    try {
      await ref.read(paymentLinkOperationsProvider).claimPreparedLink(session);
      if (!mounted) return;
      setState(() {
        // Broadcast acceptance is not receipt. The persisted receiver record
        // remains Receiving until claim history reaches six confirmations.
        _receivedClaimSessions.remove(link.address);
        if (mobile) _receivedLink = null;
      });
      showAppToast(context, 'Gift claim submitted');
      unawaited(_refreshReceivedClaims());
      if (mobile) context.go('/home');
    } catch (_) {
      if (mounted) {
        setState(() {
          _setReceivedCardStatus(
            link.address,
            PaymentLinkReceivedStatus.readyToClaim,
          );
        });
        _showError(
          'Gift Card claim failed. It may still be waiting for confirmation '
          'or may already be spent.',
        );
      }
    } finally {
      _claimSubmissions.remove(link.address);
      if (mounted) setState(() {});
    }
  }

  void _showError(String message) {
    showAppToast(
      context,
      message,
      iconName: AppIcons.warning,
      tone: AppToastTone.destructive,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      accountProvider.select((state) => state.value?.activeAccountUuid),
      _handleActiveAccountChanged,
    );
    ref.listen<({String? accountUuid, bool ready})>(
      syncProvider.select((state) {
        final sync = state.value;
        final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
        return (
          accountUuid: accountUuid,
          ready: accountUuid != null && _canEstimateCardFee(sync, accountUuid),
        );
      }),
      _handleFeeQuoteSyncGateChanged,
    );
    final pendingLink = ref.watch(
      paymentLinkIntakeProvider.select((state) => state.pendingLink),
    );
    if (pendingLink != null) _schedulePendingPaymentLink();

    if (kAppFormFactor == AppFormFactor.mobile) {
      return _buildMobileScreen();
    }

    final currentPage = _buildCurrentPage();
    final keystoneRequest = _keystoneFundingRequest;
    final pane = keystoneRequest != null
        ? Stack(
            fit: StackFit.expand,
            children: [
              currentPage,
              Positioned.fill(
                child: PaymentLinkKeystoneSigningOverlay(
                  amountZatoshi: keystoneRequest.amountZatoshi,
                  sourceAccountUuid: keystoneRequest.sourceAccountUuid,
                  presentation: keystoneRequest.presentation,
                  onCancel: _cancelKeystoneFunding,
                  onFundingBroadcast: _completeKeystoneFunding,
                ),
              ),
            ],
          )
        : _showHelp
        ? PaymentLinkHowItWorksDesktopView(
            background: _buildHome(),
            onClose: _hideHelpOverlay,
          )
        : currentPage;

    return AppDesktopShell(
      key: const ValueKey('payment_links_desktop_screen'),
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(padding: EdgeInsets.zero, child: pane),
    );
  }

  Widget _buildMobileScreen() {
    final page = switch (_page) {
      _PaymentLinksLocalPage.received => _buildMobileReceived(),
      _ => PaymentLinkRedeemMobileView(
        state: PaymentLinkRedeemMobileState.values.byName(_redeemState.name),
        onBack: _leaveMobilePaymentLinks,
        onPaste: _operationInProgress ? null : _pastePaymentLink,
        onClearClipboard: _operationInProgress ? null : _clearClipboard,
      ),
    };

    return Scaffold(
      key: const ValueKey('payment_links_mobile_screen'),
      backgroundColor: context.colors.background.window,
      body: AppToastHost(child: SafeArea(child: page)),
    );
  }

  void _leaveMobilePaymentLinks() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _returnHomeFromReceivedGift() => context.go('/home');

  Widget _buildMobileReceived() {
    final link = _receivedLink;
    if (link == null) {
      return PaymentLinkRedeemMobileView(
        state: PaymentLinkRedeemMobileState.paste,
        onBack: _leaveMobilePaymentLinks,
        onPaste: _operationInProgress ? null : _pastePaymentLink,
        onClearClipboard: _operationInProgress ? null : _clearClipboard,
      );
    }
    final artwork = PaymentLinkCardArtwork.fromProtocolId(
      link.presentation?.artworkId,
    );
    final message = link.presentation?.message ?? '';
    final hasMessage = message.isNotEmpty;
    final front = PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: kPaymentLinkMobileCardWidth,
      cardHeight: kPaymentLinkMobileCardHeight,
      amountText: formatZecAmount(link.amountZatoshi),
      showCaret: false,
    );
    final card = hasMessage
        ? PaymentLinkCardFlip(
            showBack: _receivedShowsBack,
            front: front,
            back: PaymentLinkGiftCard(
              artwork: artwork,
              cardWidth: kPaymentLinkMobileCardWidth,
              cardHeight: kPaymentLinkMobileCardHeight,
              showBack: true,
              message: message,
            ),
          )
        : front;
    return PaymentLinkReceivedMobileView(
      card: card,
      hasMessage: hasMessage,
      onClose: _returnHomeFromReceivedGift,
      decoration: const PaymentLinkConfetti(),
      onRevealMessage: hasMessage
          ? () => setState(() => _receivedShowsBack = !_receivedShowsBack)
          : null,
      onClaim: _activeClaimInProgress ? null : _claimReceivedLink,
      claimLabel: _activeClaimInProgress ? 'Claiming...' : 'Claim the gift',
    );
  }

  Widget _buildCurrentPage() {
    return switch (_page) {
      _PaymentLinksLocalPage.home => _buildHome(),
      _PaymentLinksLocalPage.amount => _buildAmount(),
      _PaymentLinksLocalPage.message => _buildMessage(),
      _PaymentLinksLocalPage.review => _buildReview(),
      _PaymentLinksLocalPage.ready => _buildReady(),
      _PaymentLinksLocalPage.redeem => PaymentLinkRedeemDesktopView(
        state: _redeemState,
        onBack: () => _showPage(_PaymentLinksLocalPage.home),
        onPaste: _operationInProgress ? null : _pastePaymentLink,
        onClearClipboard: _operationInProgress ? null : _clearClipboard,
      ),
      _PaymentLinksLocalPage.received => _buildReceived(),
    };
  }

  Widget _buildHome() {
    if (_recoveries.isNotEmpty || _receivedCards.isNotEmpty) {
      return _buildCardsList();
    }
    return PaymentLinksHomeDesktopView(
      illustration: Image.asset(
        'assets/illustrations/payment_links/payment_link_empty_card.png',
        width: 243,
        height: 162,
        fit: BoxFit.contain,
        semanticLabel: 'Gift box',
      ),
      onBack: () => context.go('/home'),
      onShowHelp: _showHelpOverlay,
      onCreate: _startCreate,
      onRedeem: () => _showPage(_PaymentLinksLocalPage.redeem),
    );
  }

  Widget _buildCardsList() {
    final showingCreated = _activeCardsTab == PaymentLinkCardsTab.created;
    final creatingCards = _recoveries
        .where(
          (record) =>
              !(_fundingProgressByAddress[record.link.address]?.isReady ??
                  false),
        )
        .map(_buildRecoveryRow)
        .toList();
    final pendingCards = _recoveries
        .where(
          (record) =>
              _fundingProgressByAddress[record.link.address]?.isReady ?? false,
        )
        .map(_buildRecoveryRow)
        .toList();
    final available = showingCreated
        ? creatingCards
        : _receivedCards.isNotEmpty
        ? _receivedCards.map(_buildReceivedRow).toList()
        : <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No received cards yet.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ];
    final sections = showingCreated
        ? <PaymentLinkCardsSection>[
            if (creatingCards.isNotEmpty)
              PaymentLinkCardsSection(label: 'Creating', cards: creatingCards),
            if (pendingCards.isNotEmpty)
              PaymentLinkCardsSection(label: 'Pending', cards: pendingCards),
          ]
        : <PaymentLinkCardsSection>[
            PaymentLinkCardsSection(label: 'Received', cards: available),
          ];
    return PaymentLinkCardsDesktopView(
      sections: sections,
      onBack: () => context.go('/home'),
      onCreate: _startCreate,
      onRedeem: () => _showPage(_PaymentLinksLocalPage.redeem),
      activeTab: _activeCardsTab,
      onTabSelected: (tab) => setState(() => _activeCardsTab = tab),
    );
  }

  Widget _buildRecoveryRow(PaymentLinkRecoveryRecord record) {
    final fundingReady =
        _fundingProgressByAddress[record.link.address]?.isReady ?? false;
    final canUseLink =
        fundingReady &&
        (record.state == PaymentLinkRecoveryState.funded ||
            record.state == PaymentLinkRecoveryState.shared);
    final copyEnabled = canUseLink && !_operationInProgress;
    final statusText = record.state == PaymentLinkRecoveryState.draft
        ? 'Funding incomplete'
        : canUseLink
        ? 'Copy link'
        : 'Preparing...';
    return PaymentLinkCardListRow(
      key: ValueKey('payment_link_recovery_${record.link.address}'),
      thumbnail: Image.asset(
        PaymentLinkCardArtwork.fromProtocolId(
          record.link.presentation?.artworkId,
        ).assetPath,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
      amountText: '${formatZecAmount(record.link.amountZatoshi)} ZEC',
      dateText: _formatCardDate(record.link.createdAt),
      statusText: statusText,
      onAction: copyEnabled ? () => _copyPaymentLink(record.link) : null,
      showCopyIcon: canUseLink,
      showLoader: !canUseLink && record.state != PaymentLinkRecoveryState.draft,
    );
  }

  Widget _buildReceivedRow(PaymentLinkReceivedRecord record) {
    final statusText = switch (record.status) {
      PaymentLinkReceivedStatus.readyToClaim => 'Claim',
      PaymentLinkReceivedStatus.receiving => 'Receiving...',
      PaymentLinkReceivedStatus.received => 'Received',
    };
    final canClaim =
        record.status == PaymentLinkReceivedStatus.readyToClaim &&
        record.claimLink != null &&
        !_operationInProgress;
    return PaymentLinkCardListRow(
      key: ValueKey('payment_link_received_${record.address}'),
      thumbnail: Image.asset(
        PaymentLinkCardArtwork.fromProtocolId(record.artworkId).assetPath,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
      amountText: '${formatZecAmount(record.amountZatoshi)} ZEC',
      dateText: _formatCardDate(record.createdAt),
      statusText: statusText,
      onAction: canClaim ? () => _openReceivedCard(record) : null,
      showLoader: record.status == PaymentLinkReceivedStatus.receiving,
    );
  }

  Widget _buildAmount() {
    final maxAmountText = _maxAmountText;
    return PaymentLinkAmountDesktopView(
      state: _amountVisualState,
      card: PaymentLinkGiftCard(
        artwork: _selectedArtwork,
        amountController: _amountController,
        amountFocusNode: _amountFocusNode,
        amountEditorKey: const ValueKey('payment_link_amount_editor'),
        amountInputFormatters: [_amountFormatter],
        onAmountChanged: _handleAmountChanged,
        maxAmountText: maxAmountText,
        onUseMax: maxAmountText == null ? null : _useMaxAmount,
        semanticLabel: 'Gift card amount input',
      ),
      cardSelector: PaymentLinkCardSelectorRail(
        artworks: PaymentLinkCardArtwork.values,
        selected: _selectedArtwork,
        onSelected: (artwork) => setState(() => _selectedArtwork = artwork),
      ),
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onCreate: _canContinueAmount
          ? () => _showPage(_PaymentLinksLocalPage.message)
          : null,
      supportingText: _amountSupportingText,
      supportingTextIsError: _amountSupportingTextIsError,
    );
  }

  Widget _buildMessage() {
    final staticMessageCard = PaymentLinkGiftCard(
      artwork: _selectedArtwork,
      showBack: true,
      message: _messageController.text,
      onTap: _revealMessageEditor,
      semanticLabel: 'Start writing gift card message',
    );
    final messageEditorCard = PaymentLinkGiftCard(
      artwork: _selectedArtwork,
      showBack: true,
      messageController: _messageController,
      messageFocusNode: _messageFocusNode,
      messageEditorKey: const ValueKey('payment_link_message_editor'),
      messageInputFormatters: [
        LengthLimitingTextInputFormatter(
          PaymentLinkPresentation.maxMessageCharacters,
        ),
      ],
      onMessageChanged: _handleMessageChanged,
      onDeleteMessage: _hasMessage ? _clearMessage : null,
      semanticLabel: 'Gift card message input',
    );
    return PaymentLinkMessageDesktopView(
      state: _hasMessage
          ? PaymentLinkMessageVisualState.filled
          : PaymentLinkMessageVisualState.empty,
      card: PaymentLinkCardFlip(
        showBack: _messageEditorRevealed,
        front: staticMessageCard,
        back: messageEditorCard,
        onAnimationEnd: _focusMessageEditorAfterFlip,
      ),
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onSkip: _skipMessage,
      onContinue: _hasMessage && !_messageExceedsByteLimit
          ? () => _showPage(_PaymentLinksLocalPage.review)
          : null,
      onStepSelected: _selectWizardStep,
      errorText: _messageExceedsByteLimit
          ? kPaymentLinkMessageTooLargeText
          : null,
    );
  }

  Widget _buildReview() {
    final message = _messageController.text.trim();
    final front = PaymentLinkGiftCard(
      artwork: _selectedArtwork,
      amountText: _amountController.text,
      showCaret: false,
      onTap: message.isEmpty
          ? null
          : () => setState(() => _reviewShowsBack = true),
      semanticLabel: message.isEmpty ? null : 'Reveal gift card message',
    );
    final card = message.isEmpty
        ? front
        : PaymentLinkCardFlip(
            showBack: _reviewShowsBack,
            front: front,
            back: PaymentLinkGiftCard(
              artwork: _selectedArtwork,
              showBack: true,
              message: message,
              onTap: () => setState(() => _reviewShowsBack = false),
              semanticLabel: 'Show gift card front',
            ),
          );
    return PaymentLinkReviewDesktopView(
      card: card,
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      cardAmountText:
          '${formatZecAmount(_fundingQuote!.recipientAmountZatoshi)} ZEC',
      cardFeeText: '${formatZecAmount(_fundingQuote!.cardFeeZatoshi)} ZEC',
      totalAmountText:
          '${formatZecAmount(_fundingQuote!.totalDeductedZatoshi)} ZEC',
      onConfirm: _operationInProgress ? null : _createFundedLink,
      onStepSelected: _operationInProgress ? null : _selectWizardStep,
      confirmLabel: _operationInProgress ? 'Creating...' : 'Create card',
    );
  }

  Widget _buildReady() {
    final link = _readyLink;
    if (link == null) return _buildHome();
    final amountText = formatZecAmount(link.amountZatoshi);
    final artwork = PaymentLinkCardArtwork.fromProtocolId(
      link.presentation?.artworkId,
    );
    final message = link.presentation?.message ?? '';
    final hasMessage = message.isNotEmpty;
    final fundingProgress =
        _fundingProgressByAddress[link.address] ??
        const PaymentLinkFundingProgress(confirmationCount: 0);
    final readyToShare = fundingProgress.isReady;
    final confirmationsRemaining =
        fundingProgress.confirmationTarget - fundingProgress.confirmationCount;
    final linkAvailableSoon =
        fundingProgress.confirmationCount > 0 &&
        confirmationsRemaining <= _linkAvailableSoonRemainingConfirmations;
    final waitingStatusLabel = linkAvailableSoon
        ? 'Link will be available soon'
        : 'Your link will be here';
    final card = hasMessage
        ? PaymentLinkCardFlip(
            showBack: _readyShowsBack,
            front: PaymentLinkGiftCard(
              artwork: artwork,
              amountText: amountText,
              showCaret: false,
            ),
            back: PaymentLinkGiftCard(
              artwork: artwork,
              showBack: true,
              message: message,
            ),
          )
        : PaymentLinkGiftCard(
            artwork: artwork,
            amountText: amountText,
            showCaret: false,
          );
    return PaymentLinkReadyDesktopView(
      state: !readyToShare
          ? PaymentLinkReadyVisualState.waiting
          : PaymentLinkReadyVisualState.ready,
      card: card,
      decoration: readyToShare ? const PaymentLinkConfetti() : null,
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onCopy: !readyToShare || _operationInProgress
          ? null
          : () => _copyPaymentLink(link),
      onCardTap: readyToShare && hasMessage
          ? () => setState(() => _readyShowsBack = !_readyShowsBack)
          : null,
      onReturnHome: () => _showPage(_PaymentLinksLocalPage.home),
      waitingStatusLabel: waitingStatusLabel,
      copyLabel: _operationInProgress ? 'Copying...' : 'Copy link',
    );
  }

  Widget _buildReceived() {
    final link = _receivedLink;
    if (link == null) return _buildHome();
    final artwork = PaymentLinkCardArtwork.fromProtocolId(
      link.presentation?.artworkId,
    );
    final message = link.presentation?.message ?? '';
    final hasMessage = message.isNotEmpty;
    final card = hasMessage
        ? PaymentLinkCardFlip(
            showBack: _receivedShowsBack,
            front: PaymentLinkGiftCard(
              artwork: artwork,
              amountText: formatZecAmount(link.amountZatoshi),
              showCaret: false,
            ),
            back: PaymentLinkGiftCard(
              artwork: artwork,
              showBack: true,
              message: message,
            ),
          )
        : PaymentLinkGiftCard(
            artwork: artwork,
            amountText: formatZecAmount(link.amountZatoshi),
            showCaret: false,
          );
    return PaymentLinkReceivedDesktopView(
      card: card,
      decoration: const PaymentLinkConfetti(),
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onClaim: _activeClaimInProgress ? null : _claimReceivedLink,
      onRevealMessage: hasMessage
          ? () => setState(() => _receivedShowsBack = !_receivedShowsBack)
          : null,
      claimLabel: _activeClaimInProgress ? 'Claiming...' : 'Claim my gift',
    );
  }

  String _formatCardDate(DateTime date) {
    final local = date.toLocal();
    return '${_monthNames[local.month - 1]} ${local.day}';
  }
}

class _PaymentLinkKeystoneFundingRequest {
  const _PaymentLinkKeystoneFundingRequest({
    required this.amountZatoshi,
    required this.sourceAccountUuid,
    required this.presentation,
  });

  final BigInt amountZatoshi;
  final String sourceAccountUuid;
  final PaymentLinkPresentation presentation;
}
