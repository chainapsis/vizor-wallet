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
  const PaymentLinksDesktopScreen({super.key});

  @override
  ConsumerState<PaymentLinksDesktopScreen> createState() =>
      _PaymentLinksDesktopScreenState();
}

class _PaymentLinksDesktopScreenState
    extends ConsumerState<PaymentLinksDesktopScreen> {
  static const _linkAvailableSoonRemainingConfirmations = 3;

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
  PaymentLinkClaimSession? _receivedClaimSession;
  VizorPaymentLink? _readyLink;
  VizorPaymentLink? _receivedLink;
  _PaymentLinkKeystoneFundingRequest? _keystoneFundingRequest;
  bool _showHelp = false;
  bool _amountFocused = false;
  bool _fundingQuoteInProgress = false;
  String? _amountErrorText;
  int _fundingQuoteGeneration = 0;
  bool _readyShowsBack = false;
  bool _receivedShowsBack = false;
  bool _operationInProgress = false;
  bool _receivedRefreshInProgress = false;
  bool _pendingIntakeScheduled = false;

  @override
  void initState() {
    super.initState();
    _paymentLinkOperations = ref.read(paymentLinkOperationsProvider);
    _amountFocusNode.addListener(_handleAmountFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_loadRecoveries());
      unawaited(_loadReceivedCards());
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
    final claimSession = _receivedClaimSession;
    if (claimSession != null) {
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
      _amountErrorText = null;
      _readyLink = null;
      _readyShowsBack = false;
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
    if (_operationInProgress) return;
    final link = ref.read(paymentLinkIntakeProvider.notifier).takePending();
    if (link == null || !mounted) return;
    await _checkPaymentLink(link);
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
    if (!hasReceiving || _operationInProgress || _receivedRefreshInProgress) {
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
    if (link == null || _operationInProgress) return;
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
      _amountErrorText == null;

  void _handleAmountChanged(String value) {
    _fundingQuoteDebounce?.cancel();
    final generation = ++_fundingQuoteGeneration;
    final amount = parseZecAmount(value);
    setState(() {
      _fundingQuote = null;
      _fundingQuoteInProgress = false;
      _amountErrorText = null;
    });
    if (amount == null || amount <= BigInt.zero) return;

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final sync = ref.read(syncProvider).value;
    if (accountUuid == null || accountUuid.isEmpty || sync == null) return;
    final minimumFunding = paymentLinkFundingAmountZatoshi(amount);
    if (sync.hasBalanceData && sync.spendableBalance < minimumFunding) {
      setState(() {
        _amountErrorText =
            'Insufficient balance to cover the Card amount and fees.';
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
      final sync = ref.read(syncProvider).value;
      final insufficient =
          sync?.hasBalanceData == true &&
          sync!.spendableBalance < quote.totalDeductedZatoshi;
      setState(() {
        _fundingQuoteInProgress = false;
        _fundingQuote = insufficient ? null : quote;
        _amountErrorText = insufficient
            ? 'Insufficient balance to cover the Card amount and fees.'
            : null;
      });
    } catch (_) {
      if (!mounted || generation != _fundingQuoteGeneration) return;
      setState(() {
        _fundingQuoteInProgress = false;
        _fundingQuote = null;
        _amountErrorText = 'Card fee could not be estimated. Try again.';
      });
    }
  }

  bool get _hasMessage => _messageController.text.trim().isNotEmpty;

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
    final sourceAccountUuid = accountState?.activeAccountUuid;
    if (amount == null || amount <= BigInt.zero || quote == null) {
      _showError('Enter a valid Gift Card amount.');
      return;
    }
    if (sourceAccountUuid == null || sourceAccountUuid.isEmpty) {
      _showError('No active account is available.');
      return;
    }
    final presentation = PaymentLinkPresentation(
      artworkId: _selectedArtwork.protocolId,
      message: _messageController.text,
    );
    if (ref.read(accountProvider.notifier).isActiveAccountHardware) {
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
      final link = await ref
          .read(paymentLinkOperationsProvider)
          .createFundedLink(
            amountZatoshi: amount,
            sourceAccountUuid: sourceAccountUuid,
            presentation: presentation,
          );
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
    if (status == 'broadcasted_storage_failed') {
      showAppToast(
        context,
        message ??
            'Funding was sent, but local transaction storage needs to sync.',
        iconName: AppIcons.warning,
      );
    }
  }

  Future<void> _copyPaymentLink(VizorPaymentLink link) async {
    if (_operationInProgress) return;
    setState(() => _operationInProgress = true);
    try {
      await ref.read(paymentLinkClipboardProvider).copySecret(link.encode());
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
      final result = notifier.ingest(rawLink);
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
    if (_operationInProgress) return;
    setState(() {
      _operationInProgress = true;
      _redeemState = PaymentLinkRedeemVisualState.loading;
      _page = _PaymentLinksLocalPage.redeem;
      _showHelp = false;
    });
    try {
      await _prepareDecodedPaymentLink(link);
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<void> _prepareDecodedPaymentLink(VizorPaymentLink link) async {
    final previousSession = _receivedClaimSession;
    if (previousSession != null &&
        previousSession.link.address != link.address) {
      await ref
          .read(paymentLinkOperationsProvider)
          .discardClaimSession(previousSession);
      _receivedClaimSession = null;
    }
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
          _receivedClaimSession = null;
          _redeemState = PaymentLinkRedeemVisualState.unavailable;
          _page = _PaymentLinksLocalPage.redeem;
        });
        return;
      }
      setState(() {
        _receivedClaimSession = session;
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
    }
    ref.read(paymentLinkIntakeProvider.notifier).clearError();
    if (mounted) {
      setState(() {
        _receivedClaimSession = null;
        _redeemState = PaymentLinkRedeemVisualState.paste;
      });
    }
  }

  Future<void> _claimReceivedLink() async {
    final link = _receivedLink;
    final session = _receivedClaimSession;
    if (link == null || session == null || _operationInProgress) return;
    setState(() {
      _operationInProgress = true;
      _receivedLink = null;
      _receivedShowsBack = false;
      _setReceivedCardStatus(link.address, PaymentLinkReceivedStatus.receiving);
      _activeCardsTab = PaymentLinkCardsTab.received;
      _page = _PaymentLinksLocalPage.home;
      _showHelp = false;
    });
    try {
      await ref.read(paymentLinkOperationsProvider).claimPreparedLink(session);
      if (!mounted) return;
      setState(() {
        // Broadcast acceptance is not receipt. The persisted receiver record
        // remains Receiving until main-wallet history sees the claim mined.
        _receivedClaimSession = null;
      });
      showAppToast(context, 'Gift claim submitted');
      unawaited(_refreshReceivedClaims());
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
      if (mounted) setState(() => _operationInProgress = false);
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
    final pendingLink = ref.watch(
      paymentLinkIntakeProvider.select((state) => state.pendingLink),
    );
    if (pendingLink != null) _schedulePendingPaymentLink();

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

  Widget _buildCurrentPage() {
    return switch (_page) {
      _PaymentLinksLocalPage.home => _buildHome(),
      _PaymentLinksLocalPage.amount => _buildAmount(),
      _PaymentLinksLocalPage.message => _buildMessage(),
      _PaymentLinksLocalPage.review => PaymentLinkReviewDesktopView(
        card: PaymentLinkGiftCard(
          artwork: _selectedArtwork,
          amountText: _amountController.text,
          showCaret: false,
        ),
        onBack: () => _showPage(_PaymentLinksLocalPage.home),
        cardAmountText:
            '${formatZecAmount(_fundingQuote!.recipientAmountZatoshi)} ZEC',
        cardFeeText: '${formatZecAmount(_fundingQuote!.cardFeeZatoshi)} ZEC',
        totalAmountText:
            '${formatZecAmount(_fundingQuote!.totalDeductedZatoshi)} ZEC',
        onConfirm: _operationInProgress ? null : _createFundedLink,
        onStepSelected: _operationInProgress ? null : _selectWizardStep,
        confirmLabel: _operationInProgress ? 'Creating...' : 'Create card',
      ),
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
      errorText: _amountErrorText,
    );
  }

  Widget _buildMessage() {
    return PaymentLinkMessageDesktopView(
      state: _hasMessage
          ? PaymentLinkMessageVisualState.filled
          : PaymentLinkMessageVisualState.empty,
      card: PaymentLinkGiftCard(
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
      ),
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onSkip: _skipMessage,
      onContinue: _hasMessage
          ? () => _showPage(_PaymentLinksLocalPage.review)
          : null,
      onStepSelected: _selectWizardStep,
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
      decoration: readyToShare || linkAvailableSoon
          ? const PaymentLinkConfetti()
          : null,
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
      onClaim: _operationInProgress ? null : _claimReceivedLink,
      onRevealMessage: hasMessage
          ? () => setState(() => _receivedShowsBack = !_receivedShowsBack)
          : null,
      claimLabel: _operationInProgress ? 'Claiming...' : 'Claim my gift',
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
