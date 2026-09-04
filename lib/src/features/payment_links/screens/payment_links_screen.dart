import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
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
import '../providers/payment_link_claim_coordinator_provider.dart';
import '../providers/payment_link_intake_provider.dart';
import '../services/payment_link_clipboard.dart';
import '../services/payment_link_entry_policy.dart';
import '../services/payment_link_hardware_signing_service.dart';
import '../services/payment_link_qr_image_saver.dart';
import '../services/payment_link_received_store.dart';
import '../services/payment_link_recovery_store.dart';
import '../services/payment_link_service.dart';
import '../widgets/payment_link_card_flip.dart';
import '../widgets/payment_link_card_selector_rail.dart';
import '../widgets/payment_link_confetti.dart';
import '../widgets/payment_link_copy.dart';
import '../widgets/payment_link_desktop_views.dart';
import '../widgets/payment_link_gift_card.dart';
import '../widgets/payment_link_keystone_signing_overlay.dart';
import '../widgets/payment_link_long_sync_warning.dart';
import '../widgets/mobile/payment_link_mobile_views.dart';
import 'payment_links_local_page.dart';
import 'payment_links_mobile_body.dart';

/// Desktop Payment Link lifecycle.
///
/// The presentation remains local to this screen, while all secret creation,
/// recovery persistence, sync, and transaction work stays behind
/// [PaymentLinkOperations]. Artwork and message are carried by the v1
/// presentation payload.
class PaymentLinksScreen extends ConsumerStatefulWidget {
  const PaymentLinksScreen({this.initialCards, super.key});

  final PaymentLinkCardsSnapshot? initialCards;

  @override
  ConsumerState<PaymentLinksScreen> createState() => _PaymentLinksScreenState();
}

class _PaymentLinksScreenState extends ConsumerState<PaymentLinksScreen> {
  static const _estimatedBlockTimeSeconds = 75;
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

  static String _estimatedLinkWaitLabel(PaymentLinkFundingProgress progress) {
    final unconfirmed =
        progress.confirmationTarget - progress.confirmationCount;
    final remaining = unconfirmed > 0 ? unconfirmed : 0;
    final totalSeconds = remaining * _estimatedBlockTimeSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return 'Wait $minutes:$seconds to get the link';
  }

  static String _estimatedClaimWaitLabel(PaymentLinkClaimSession session) {
    final remaining =
        kPaymentLinkClaimConfirmationTarget - session.fundingConfirmationCount;
    final totalSeconds = max(remaining, 0) * _estimatedBlockTimeSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return 'Wait $minutes:$seconds to claim';
  }

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

  PaymentLinksLocalPage _page = PaymentLinksLocalPage.home;
  PaymentLinkCardArtwork _selectedArtwork = PaymentLinkCardArtwork.gift;
  PaymentLinkRedeemVisualState _redeemState =
      PaymentLinkRedeemVisualState.paste;
  PaymentLinkCardsTab _activeCardsTab = PaymentLinkCardsTab.created;
  List<PaymentLinkRecoveryRecord> _recoveries = const [];
  Map<String, PaymentLinkFundingProgress> _fundingProgressByAddress = const {};
  List<PaymentLinkReceivedRecord> _receivedCards = const [];
  final GlobalKey _shareQrCardKey = GlobalKey();
  PaymentLinkRecoveryRecord? _shareQrRecord;
  PaymentLinkFundingQuote? _maxFundingQuote;
  PaymentLinkFundingQuote? _fundingQuote;
  String? _fundingQuoteRequestedAccountUuid;
  PaymentLinkClaimSession? _receivedClaimSession;
  VizorPaymentLink? _readyLink;
  VizorPaymentLink? _receivedLink;
  VizorPaymentLink? _lastDeferredPendingLink;
  VizorPaymentLink? _longSyncLink;
  VizorPaymentLink? _retryLink;
  PaymentLinkFundingResult? _pendingFundingMetadata;
  _PaymentLinkKeystoneFundingRequest? _keystoneFundingRequest;
  bool _showHelp = false;
  bool _amountFocused = false;
  bool _maxFundingQuoteInProgress = false;
  bool _fundingQuoteInProgress = false;
  String? _amountSupportingText;
  bool _amountSupportingTextIsError = false;
  int _fundingQuoteGeneration = 0;
  int _maxFundingQuoteGeneration = 0;
  bool _fundingQuoteRetryScheduled = false;
  bool _reviewShowsBack = false;
  bool _readyShowsBack = false;
  bool _receivedShowsBack = false;
  bool _messageEditorRevealed = false;
  bool _operationInProgress = false;
  bool _receivedRefreshInProgress = false;
  bool _claimConfirmationRefreshInProgress = false;
  bool _pendingIntakeScheduled = false;
  bool _initialCardsLoaded = false;

  @override
  void initState() {
    super.initState();
    _paymentLinkOperations = ref.read(paymentLinkOperationsProvider);
    // Both form factors open on the Gift Card home (the cards list once any
    // exist, the create/redeem landing otherwise). Only a link that is
    // already waiting jumps mobile straight to the redeem page, so the landing
    // never flashes before the loading state it is about to show.
    if (kAppFormFactor == AppFormFactor.mobile &&
        ref.read(paymentLinkIntakeProvider).pendingLink != null) {
      _page = PaymentLinksLocalPage.redeem;
      _redeemState = PaymentLinkRedeemVisualState.loading;
    }
    final initialCards = widget.initialCards;
    if (initialCards != null) {
      _recoveries = initialCards.created;
      _receivedCards = initialCards.received;
      _initialCardsLoaded = true;
    }
    _amountFocusNode.addListener(_handleAmountFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kAppFormFactor == AppFormFactor.desktop) {
        ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      }
      unawaited(_initializeCardsAndPendingLink(initialCards));
    });
    _fundingProgressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshFundingProgress());
      unawaited(_refreshReceivedClaims());
      unawaited(_refreshPendingClaimConfirmations());
    });
  }

  @override
  void dispose() {
    _fundingQuoteDebounce?.cancel();
    _fundingProgressTimer?.cancel();
    final claimSession = _receivedClaimSession;
    if (claimSession != null) {
      unawaited(
        _shouldKeepCard(claimSession)
            ? _paymentLinkOperations.retainPendingClaim(claimSession)
            : _paymentLinkOperations.discardClaimSession(claimSession),
      );
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

  void _showPage(PaymentLinksLocalPage page) {
    if (_pendingFundingMetadata != null &&
        page != PaymentLinksLocalPage.review) {
      _showError('Save this Gift Card before leaving this screen.');
      return;
    }
    _amountFocusNode.unfocus();
    _messageFocusNode.unfocus();
    setState(() {
      if (page == PaymentLinksLocalPage.message &&
          _page != PaymentLinksLocalPage.message) {
        _messageEditorRevealed = _hasMessage;
      }
      if (page == PaymentLinksLocalPage.review &&
          _page != PaymentLinksLocalPage.review) {
        _reviewShowsBack = false;
      }
      _page = page;
      if (page != PaymentLinksLocalPage.shareQr) _shareQrRecord = null;
      _showHelp = false;
      _longSyncLink = null;
    });
  }

  void _startCreate() {
    _fundingQuoteDebounce?.cancel();
    _fundingQuoteGeneration++;
    _maxFundingQuoteGeneration++;
    _amountController.clear();
    _messageController.clear();
    setState(() {
      _selectedArtwork = PaymentLinkCardArtwork.gift;
      _maxFundingQuote = null;
      _maxFundingQuoteInProgress = false;
      _fundingQuote = null;
      _fundingQuoteInProgress = false;
      _amountSupportingText = null;
      _amountSupportingTextIsError = false;
      _readyLink = null;
      _shareQrRecord = null;
      _reviewShowsBack = false;
      _readyShowsBack = false;
      _messageEditorRevealed = false;
      _page = PaymentLinksLocalPage.amount;
      _showHelp = false;
      _longSyncLink = null;
    });
    unawaited(_loadMaxFundingQuote());
  }

  void _showHelpOverlay() => setState(() => _showHelp = true);

  void _hideHelpOverlay() => setState(() => _showHelp = false);

  void _schedulePendingPaymentLink() {
    if (!_initialCardsLoaded || _pendingIntakeScheduled) return;
    _pendingIntakeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingIntakeScheduled = false;
      if (mounted) _consumePendingPaymentLink();
    });
  }

  Future<void> _consumePendingPaymentLink() async {
    if (!_initialCardsLoaded || _operationInProgress) return;
    final pendingLink = ref.read(paymentLinkIntakeProvider).pendingLink;
    if (pendingLink == null) return;
    if (_page != PaymentLinksLocalPage.home &&
        _page != PaymentLinksLocalPage.redeem) {
      if (!identical(_lastDeferredPendingLink, pendingLink)) {
        _lastDeferredPendingLink = pendingLink;
        _showDeferredPendingLinkMessage();
      }
      return;
    }
    _lastDeferredPendingLink = null;
    final link = ref.read(paymentLinkIntakeProvider.notifier).takePending();
    if (link == null || !mounted) return;
    await _checkPaymentLink(link);
  }

  void _showDeferredPendingLinkMessage() {
    showAppToast(
      context,
      kPaymentLinkDeferredByActiveFlowMessage,
      iconName: AppIcons.warning,
    );
  }

  Future<void> _initializeCardsAndPendingLink(
    PaymentLinkCardsSnapshot? initialCards,
  ) async {
    if (initialCards == null) {
      await Future.wait<void>([
        _loadRecoveries(),
        _loadReceivedCardsWithRetry(),
      ]);
      if (!mounted) return;
      _initialCardsLoaded = true;
    } else {
      unawaited(_refreshFundingProgress(records: initialCards.created));
      unawaited(_refreshReceivedClaims(records: initialCards.received));
    }
    await _consumePendingPaymentLink();
  }

  Future<void> _loadRecoveries({bool showError = true}) async {
    try {
      final records = await ref
          .read(paymentLinkOperationsProvider)
          .loadCreatedLinkRecoveries();
      if (!mounted) return;
      final visible = records.toList()
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
      final expiredAddresses = {
        for (final record in pending)
          if (!updates.containsKey(record.link.address)) record.link.address,
      };
      final readyFundingExpired =
          _readyLink != null && expiredAddresses.contains(_readyLink!.address);
      final mergedUpdates = {
        for (final entry in updates.entries)
          entry.key:
              (_fundingProgressByAddress[entry.key]?.broadcastAccepted ?? false)
              ? entry.value.copyWith(broadcastAccepted: true)
              : entry.value,
      };
      setState(() {
        _recoveries.removeWhere(
          (record) => expiredAddresses.contains(record.link.address),
        );
        _fundingProgressByAddress = {
          for (final entry in _fundingProgressByAddress.entries)
            if (!expiredAddresses.contains(entry.key)) entry.key: entry.value,
          ...mergedUpdates,
        };
        if (readyFundingExpired) {
          _readyLink = null;
          _page = PaymentLinksLocalPage.home;
        }
      });
      if (readyFundingExpired) {
        _showError('Gift Card funding expired. Create it again.');
      }
    } catch (_) {
      // Keep the last known progress. A later foreground sync or timer tick
      // retries this read without hiding an already-ready link.
    }
  }

  Future<void> _loadReceivedCardsWithRetry() async {
    final loaded = await _loadReceivedCards(showError: false, attempt: 1);
    if (!loaded && mounted) {
      await _loadReceivedCards(attempt: 2);
    }
  }

  Future<bool> _loadReceivedCards({
    bool showError = true,
    required int attempt,
  }) async {
    try {
      final records = await ref
          .read(paymentLinkClaimCoordinatorProvider)
          .refresh();
      if (!mounted) return true;
      final sorted = List<PaymentLinkReceivedRecord>.of(records)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() => _receivedCards = sorted);
      unawaited(_refreshReceivedClaims(records: sorted));
      return true;
    } catch (error) {
      log(
        'PaymentLinkCards: received load failed '
        'attempt=$attempt type=${error.runtimeType}',
      );
      if (mounted && showError) {
        _showError('Received Gift Cards could not be loaded.');
      }
      return false;
    }
  }

  Future<void> _refreshReceivedClaims({
    List<PaymentLinkReceivedRecord>? records,
  }) async {
    final receivedCards = records ?? _receivedCards;
    final hasReceiving = receivedCards.any((record) => record.isClaimInFlight);
    if (!hasReceiving || _receivedRefreshInProgress) {
      return;
    }
    _receivedRefreshInProgress = true;
    try {
      final updated = await ref
          .read(paymentLinkClaimCoordinatorProvider)
          .refresh();
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

  /// Releasing [session] keeps its claim wallet for a Card already listed in
  /// Received, or one still waiting for confirmations (nothing persisted yet).
  bool _shouldKeepCard(PaymentLinkClaimSession session) =>
      session.waitingForFundingConfirmations ||
      _receivedCards.any((record) => record.address == session.link.address);

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
    if (link == null ||
        _operationInProgress ||
        ref
            .read(paymentLinkClaimCoordinatorProvider)
            .isSubmitting(record.address)) {
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
    if (_page != PaymentLinksLocalPage.amount || next.accountUuid == null) {
      return;
    }
    final shouldLoadMax =
        _maxFundingQuote?.sourceAccountUuid != next.accountUuid &&
        !_maxFundingQuoteInProgress;
    final shouldLoadAmount =
        _fundingQuoteRequestedAccountUuid == next.accountUuid &&
        _hasPositiveAmount &&
        _fundingQuote == null &&
        !_fundingQuoteInProgress;
    if (!shouldLoadMax && !shouldLoadAmount) return;

    _fundingQuoteRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fundingQuoteRetryScheduled = false;
      if (!mounted || _page != PaymentLinksLocalPage.amount) return;
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      final sync = ref.read(syncProvider).value;
      if (accountUuid != next.accountUuid ||
          !_canEstimateCardFee(sync, next.accountUuid!)) {
        return;
      }
      if (shouldLoadMax) unawaited(_loadMaxFundingQuote());
      if (shouldLoadAmount) _handleAmountChanged(_amountController.text);
    });
  }

  Future<void> _loadMaxFundingQuote() async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final sync = ref.read(syncProvider).value;
    if (accountUuid == null ||
        accountUuid.isEmpty ||
        !_canEstimateCardFee(sync, accountUuid) ||
        _maxFundingQuoteInProgress ||
        _maxFundingQuote?.sourceAccountUuid == accountUuid) {
      return;
    }

    final generation = ++_maxFundingQuoteGeneration;
    setState(() => _maxFundingQuoteInProgress = true);
    try {
      final quote = await ref
          .read(paymentLinkOperationsProvider)
          .quoteMaxFunding(sourceAccountUuid: accountUuid);
      if (!mounted || generation != _maxFundingQuoteGeneration) return;
      final currentAccountUuid = ref
          .read(accountProvider)
          .value
          ?.activeAccountUuid;
      if (quote.sourceAccountUuid != accountUuid ||
          currentAccountUuid != accountUuid) {
        throw StateError('Gift Card max quote no longer matches the account.');
      }
      setState(() {
        _maxFundingQuote = quote;
        _maxFundingQuoteInProgress = false;
      });
    } catch (_) {
      if (!mounted || generation != _maxFundingQuoteGeneration) return;
      setState(() {
        _maxFundingQuote = null;
        _maxFundingQuoteInProgress = false;
      });
    }
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
    final maxQuote = _maxFundingQuote;
    if (maxQuote?.sourceAccountUuid == accountUuid &&
        amount > maxQuote!.recipientAmountZatoshi) {
      setState(() {
        _amountSupportingText = 'Above your maximum ZEC';
        _amountSupportingTextIsError = true;
      });
      return;
    }
    final minimumFunding = paymentLinkFundingAmountZatoshi(amount);
    if (readySync.hasBalanceData &&
        readySync.spendableBalance < minimumFunding) {
      setState(() {
        _amountSupportingText = 'Above your maximum ZEC';
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
    if (current != null) _handleClaimDestinationAccountChanged(current);
    final quotedAccount = _fundingQuote?.sourceAccountUuid;
    final priorAccount =
        previous ?? quotedAccount ?? _fundingQuoteRequestedAccountUuid;
    if (current == null || priorAccount == null || priorAccount == current) {
      return;
    }
    if (_page != PaymentLinksLocalPage.amount &&
        _page != PaymentLinksLocalPage.message &&
        _page != PaymentLinksLocalPage.review) {
      return;
    }

    final wasPastAmountStep = _page != PaymentLinksLocalPage.amount;
    final hadKeystoneRequest = _keystoneFundingRequest != null;
    _fundingQuoteDebounce?.cancel();
    _fundingQuoteGeneration += 1;
    _maxFundingQuoteGeneration += 1;
    setState(() {
      _maxFundingQuote = null;
      _maxFundingQuoteInProgress = false;
      _fundingQuote = null;
      _fundingQuoteInProgress = false;
      if (hadKeystoneRequest) {
        _keystoneFundingRequest = null;
        _operationInProgress = false;
      }
      _amountSupportingText = null;
      _amountSupportingTextIsError = false;
      _page = PaymentLinksLocalPage.amount;
    });
    unawaited(_loadMaxFundingQuote());
    _handleAmountChanged(_amountController.text);
    if (wasPastAmountStep) {
      showAppToast(
        context,
        'Active account changed. Review the Gift Card amount and fees again.',
        iconName: AppIcons.warning,
      );
    }
  }

  /// A prepared claim session is bound to the account it was prepared for:
  /// its destination address, and the revalidation that runs just before the
  /// broadcast, both belong to that account. Switching the active account
  /// while the session is on screen would otherwise pay the previous account
  /// without saying so, so the session is released and the redeem entry is
  /// reopened for the account now in front of the user.
  void _handleClaimDestinationAccountChanged(String current) {
    final session = _receivedClaimSession;
    if (session == null || session.destinationAccountUuid == current) return;
    final link = _receivedLink;
    final keepCard = _shouldKeepCard(session);
    setState(() {
      _receivedClaimSession = null;
      _receivedLink = null;
      _receivedShowsBack = false;
      _retryLink = null;
      _longSyncLink = null;
      _showHelp = false;
      _redeemState = PaymentLinkRedeemVisualState.paste;
      _page = PaymentLinksLocalPage.redeem;
      // The switch must not cost the Card: a kept one stays in Received so the
      // recipient can reopen it under the account they moved to.
      if (keepCard && link != null) {
        _rememberReceivedLink(link);
        _activeCardsTab = PaymentLinkCardsTab.received;
      }
    });
    _releaseClaimSession(session, keepCard: keepCard);
    showAppToast(
      context,
      'Active account changed. Redeem this Gift Card again to receive it in '
      'the new account.',
      iconName: AppIcons.warning,
    );
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
        _amountSupportingText = insufficient ? 'Above your maximum ZEC' : null;
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

  /// The received cards this account should see. A claim lands in one
  /// account, so a card that is being received or has been received shows
  /// only under that account — the way balances and activity are scoped.
  /// A card that has not been claimed yet stays visible everywhere: opening
  /// it retargets the claim to whichever account is active. So does a card
  /// whose destination is unknown (claim metadata still to be recovered):
  /// hiding it would hide the recovery.
  List<PaymentLinkReceivedRecord> get _visibleReceivedCards {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    return [
      for (final record in _receivedCards)
        if (record.status == PaymentLinkReceivedStatus.readyToClaim ||
            record.destinationAccountUuid == null ||
            record.destinationAccountUuid == accountUuid)
          record,
    ];
  }

  /// Created Cards show under the account that funded them, like their funding
  /// transaction; a record of unknown origin stays visible so its recovery is.
  List<PaymentLinkRecoveryRecord> get _visibleRecoveries {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    return [
      for (final record in _recoveries)
        if (record.sourceAccountUuid.isEmpty ||
            record.sourceAccountUuid == accountUuid)
          record,
    ];
  }

  String? get _maxAmountText {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final quote = _maxFundingQuote;
    if (quote == null || quote.sourceAccountUuid != accountUuid) return null;
    return formatZecAmount(quote.recipientAmountZatoshi);
  }

  void _useMaxAmount() {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final quote = _maxFundingQuote;
    if (quote == null || quote.sourceAccountUuid != accountUuid) return;
    final text = formatZecAmount(quote.recipientAmountZatoshi);
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
          _page != PaymentLinksLocalPage.message ||
          _messageFocusNode.context == null) {
        return;
      }
      _messageFocusNode.requestFocus();
    });
  }

  void _focusMessageEditorAfterFlip() {
    if (!mounted ||
        !_messageEditorRevealed ||
        _page != PaymentLinksLocalPage.message) {
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
    _showPage(PaymentLinksLocalPage.review);
  }

  void _selectWizardStep(int step) {
    if (_pendingFundingMetadata != null) {
      _showError('Save this Gift Card before leaving this screen.');
      return;
    }
    switch (step) {
      case 0:
        _showPage(PaymentLinksLocalPage.amount);
      case 1:
        if (_canContinueAmount) {
          _showPage(PaymentLinksLocalPage.message);
        }
    }
  }

  Future<void> _createFundedLink() async {
    if (_operationInProgress) return;
    if (_pendingFundingMetadata != null) {
      await _retryFundingMetadata();
      return;
    }
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
      if (!funding.fundingMetadataSaved) {
        if (!mounted) return;
        setState(() => _pendingFundingMetadata = funding);
        _showError(
          'Funding was sent, but the Gift Card could not be saved. '
          'Try again before closing Vizor.',
        );
        return;
      }
      await _loadRecoveries(showError: false);
      if (!mounted) return;
      setState(() {
        _readyLink = link;
        _fundingProgressByAddress = {
          ..._fundingProgressByAddress,
          link.address: PaymentLinkFundingProgress(
            confirmationCount: 0,
            broadcastAccepted: funding.broadcastAccepted,
          ),
        };
        _readyShowsBack = false;
        _page = PaymentLinksLocalPage.ready;
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

  Future<void> _retryFundingMetadata() async {
    final pending = _pendingFundingMetadata;
    if (pending == null || _operationInProgress) return;
    setState(() => _operationInProgress = true);
    try {
      await ref
          .read(paymentLinkOperationsProvider)
          .retryFundingMetadata(
            address: pending.link.address,
            fundingTxids: pending.txids,
          );
      await _loadRecoveries(showError: false);
      if (!mounted) return;
      setState(() {
        _pendingFundingMetadata = null;
        _readyLink = pending.link;
        _fundingProgressByAddress = {
          ..._fundingProgressByAddress,
          pending.link.address: PaymentLinkFundingProgress(
            confirmationCount: 0,
            broadcastAccepted: pending.broadcastAccepted,
          ),
        };
        _readyShowsBack = false;
        _page = PaymentLinksLocalPage.ready;
      });
    } catch (_) {
      if (mounted) {
        _showError(
          'The Gift Card still could not be saved. Try again before closing Vizor.',
        );
      }
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
    PaymentLinkHardwareFundingResult result,
  ) async {
    await _loadRecoveries(showError: false);
    if (!mounted) return;
    if (!result.fundingMetadataSaved) {
      setState(() {
        _keystoneFundingRequest = null;
        _operationInProgress = false;
        _pendingFundingMetadata = PaymentLinkFundingResult(
          link: link,
          txids: result.txids,
          fundingMetadataSaved: false,
          broadcastAccepted: isPaymentLinkFundingBroadcastAccepted(
            result.status,
          ),
        );
      });
      _showError(
        'Funding was sent, but the Gift Card could not be saved. '
        'Try again before closing Vizor.',
      );
      return;
    }
    setState(() {
      _keystoneFundingRequest = null;
      _operationInProgress = false;
      _readyLink = link;
      _fundingProgressByAddress = {
        ..._fundingProgressByAddress,
        link.address: PaymentLinkFundingProgress(
          confirmationCount: 0,
          broadcastAccepted: isPaymentLinkFundingBroadcastAccepted(
            result.status,
          ),
        ),
      };
      _readyShowsBack = false;
      _page = PaymentLinksLocalPage.ready;
    });
    unawaited(_refreshFundingProgress());
    if (result.status == 'broadcasted_storage_failed' ||
        result.status == 'broadcast_unknown') {
      showAppToast(
        context,
        result.message ??
            (result.status == 'broadcast_unknown'
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
      _retryLink = null;
    });
    try {
      final rawLink = await ref.read(paymentLinkClipboardProvider).readText();
      if (rawLink == null || rawLink.trim().isEmpty) {
        if (mounted) {
          setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
        }
        return;
      }
      final link = VizorPaymentLink.parse(rawLink);
      if (!mounted) return;
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
    if (ref
        .read(paymentLinkClaimCoordinatorProvider)
        .isSubmitting(link.address)) {
      setState(() {
        _rememberReceivedLink(link);
        _setReceivedCardStatus(
          link.address,
          PaymentLinkReceivedStatus.receiving,
        );
        _activeCardsTab = PaymentLinkCardsTab.received;
        _page = PaymentLinksLocalPage.home;
      });
      if (kAppFormFactor == AppFormFactor.mobile) context.go('/home');
      return;
    }
    setState(() {
      _operationInProgress = true;
      _redeemState = PaymentLinkRedeemVisualState.loading;
      _page = PaymentLinksLocalPage.redeem;
      _showHelp = false;
      _longSyncLink = null;
    });
    try {
      await _prepareDecodedPaymentLink(link);
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<void> _prepareDecodedPaymentLink(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    final previousSession = _receivedClaimSession;
    if (previousSession != null &&
        paymentLinkClaimWalletDirectoryName(previousSession.link) !=
            paymentLinkClaimWalletDirectoryName(link)) {
      await ref
          .read(paymentLinkOperationsProvider)
          .discardClaimSession(previousSession);
      _receivedClaimSession = null;
    }
    try {
      final session = await ref
          .read(paymentLinkOperationsProvider)
          .prepareClaim(link, allowLongSync: allowLongSync);
      if (!mounted) {
        await ref
            .read(paymentLinkOperationsProvider)
            .discardClaimSession(session);
        return;
      }
      // Preparation can outlast an account switch; a session bound to the
      // previous account is released instead of installed.
      final activeAccountUuid = ref
          .read(accountProvider)
          .value
          ?.activeAccountUuid;
      if (activeAccountUuid != null &&
          activeAccountUuid != session.destinationAccountUuid &&
          (session.waitingForFundingConfirmations || session.canClaim)) {
        _receivedClaimSession = session;
        _receivedLink = link;
        _handleClaimDestinationAccountChanged(activeAccountUuid);
        return;
      }
      if (session.waitingForFundingConfirmations) {
        setState(() {
          _receivedClaimSession = session;
          _receivedLink = link;
          _longSyncLink = null;
          _retryLink = null;
          _receivedShowsBack = false;
          _redeemState = PaymentLinkRedeemVisualState.paste;
          _page = PaymentLinksLocalPage.received;
        });
        return;
      }
      if (!session.canClaim) {
        await ref
            .read(paymentLinkOperationsProvider)
            .discardClaimSession(session);
        setState(() {
          _receivedClaimSession = null;
          _longSyncLink = null;
          _retryLink = null;
          _redeemState = PaymentLinkRedeemVisualState.unavailable;
          _page = PaymentLinksLocalPage.redeem;
        });
        return;
      }
      setState(() {
        _receivedClaimSession = session;
        _receivedLink = link;
        _longSyncLink = null;
        _retryLink = null;
        _receivedShowsBack = false;
        _redeemState = PaymentLinkRedeemVisualState.paste;
        _page = PaymentLinksLocalPage.received;
      });
      log('PaymentLinkClaim: preview ready');
    } on PaymentLinkLongSyncConfirmationRequired {
      log('PaymentLinkClaim: waiting for long sync confirmation');
      if (!mounted) return;
      setState(() {
        _redeemState = PaymentLinkRedeemVisualState.paste;
        if (kAppFormFactor == AppFormFactor.desktop) {
          _longSyncLink = link;
        }
      });
      if (kAppFormFactor == AppFormFactor.mobile) {
        final confirmed = await showPaymentLinkLongSyncWarningSheet(context);
        if (!confirmed || !mounted) return;
        setState(() => _redeemState = PaymentLinkRedeemVisualState.loading);
        await _prepareDecodedPaymentLink(link, allowLongSync: true);
      }
    } on PaymentLinkClaimInFlightException catch (error) {
      log('PaymentLinkClaim: ignored duplicate in-flight link');
      if (!mounted) return;
      setState(() {
        _activeCardsTab = PaymentLinkCardsTab.received;
        _longSyncLink = null;
        _retryLink = null;
        _redeemState = PaymentLinkRedeemVisualState.paste;
        _page = PaymentLinksLocalPage.home;
      });
      _showError(error.toString());
    } on PaymentLinkNetworkMismatchException catch (error) {
      log(
        'PaymentLinkClaim: rejected link for another network '
        'link=${error.linkNetwork} wallet=${error.walletNetwork}',
      );
      if (!mounted) return;
      // A different network is a permanent property of the link, so there is
      // nothing to retry: clear the retry affordance and name the reason.
      setState(() {
        _longSyncLink = null;
        _retryLink = null;
        _redeemState = PaymentLinkRedeemVisualState.paste;
      });
      _showError(error.toString());
    } on FormatException catch (error) {
      log(
        'PaymentLinkClaim: preparation rejected '
        'category=${_paymentLinkFormatFailureCategory(error)}',
      );
      if (mounted) {
        setState(() {
          _longSyncLink = null;
          _retryLink = null;
          _redeemState = PaymentLinkRedeemVisualState.invalid;
        });
      }
    } catch (error) {
      log('PaymentLinkClaim: preparation failed type=${error.runtimeType}');
      if (mounted) {
        setState(() {
          _longSyncLink = null;
          _retryLink = link;
          _redeemState = PaymentLinkRedeemVisualState.paste;
        });
        _showError('Card balance could not be checked. Try again.');
      }
    }
  }

  Future<void> _refreshPendingClaimConfirmations() async {
    final currentSession = _receivedClaimSession;
    final link = _receivedLink;
    if (_page != PaymentLinksLocalPage.received ||
        currentSession == null ||
        link == null ||
        !currentSession.waitingForFundingConfirmations ||
        _operationInProgress ||
        _claimConfirmationRefreshInProgress) {
      return;
    }
    _claimConfirmationRefreshInProgress = true;
    try {
      final refreshed = await ref
          .read(paymentLinkOperationsProvider)
          .prepareClaim(link, allowLongSync: true);
      if (!mounted) {
        await _discardRefreshedClaim(refreshed);
        return;
      }
      final stillWaitingForThisLink =
          _page == PaymentLinksLocalPage.received &&
          _receivedLink?.address == link.address &&
          identical(_receivedClaimSession, currentSession);
      if (!stillWaitingForThisLink) {
        await _discardRefreshedClaim(refreshed);
        return;
      }
      if (!refreshed.canClaim && !refreshed.waitingForFundingConfirmations) {
        await ref
            .read(paymentLinkOperationsProvider)
            .discardClaimSession(refreshed);
        setState(() {
          _receivedClaimSession = null;
          _receivedLink = null;
          _redeemState = PaymentLinkRedeemVisualState.unavailable;
          _page = PaymentLinksLocalPage.redeem;
        });
        return;
      }
      setState(() => _receivedClaimSession = refreshed);
    } catch (error) {
      log(
        'PaymentLinkClaim: confirmation refresh failed '
        'type=${error.runtimeType}',
      );
    } finally {
      _claimConfirmationRefreshInProgress = false;
    }
  }

  /// A refresh opens a second session over the same claim wallet; delete it
  /// only when neither the live session nor a listed Card still owns it.
  Future<void> _discardRefreshedClaim(PaymentLinkClaimSession refreshed) async {
    final directory = paymentLinkClaimWalletDirectoryName(refreshed.link);
    final live = _receivedClaimSession;
    final stillOwned =
        (live != null &&
            paymentLinkClaimWalletDirectoryName(live.link) == directory) ||
        _receivedCards.any(
          (record) => record.address == refreshed.link.address,
        );
    if (stillOwned) return;
    await _paymentLinkOperations.discardClaimSession(refreshed);
  }

  /// Leaving the confirmation wait keeps the Card. Nothing has been persisted
  /// yet at this point, so releasing only the in-memory session would drop the
  /// Card entirely and send the recipient back to the external bearer link.
  void _leavePendingClaim() {
    final session = _receivedClaimSession;
    final link = _receivedLink;
    setState(() {
      _receivedClaimSession = null;
      _receivedLink = null;
      _receivedShowsBack = false;
      if (link != null) {
        _rememberReceivedLink(link);
        _activeCardsTab = PaymentLinkCardsTab.received;
      }
    });
    if (session != null) {
      _releaseClaimSession(session, keepCard: link != null);
    }
    if (kAppFormFactor == AppFormFactor.mobile) {
      context.go('/home');
    } else {
      _showPage(PaymentLinksLocalPage.home);
    }
  }

  /// Backing out of a claimable preview releases its prepared claim. A session
  /// left live would make a later account switch pull the user back into
  /// Redeem, and would hold the temporary claim wallet until route dispose.
  void _abandonReceivedPreview() {
    final session = _receivedClaimSession;
    setState(() {
      _receivedClaimSession = null;
      _receivedLink = null;
      _receivedShowsBack = false;
    });
    if (session != null) {
      _releaseClaimSession(session, keepCard: _shouldKeepCard(session));
    }
    _showPage(PaymentLinksLocalPage.home);
  }

  /// A Card that stays in the Received list keeps its scanned claim wallet; an
  /// abandoned preview deletes it.
  void _releaseClaimSession(
    PaymentLinkClaimSession session, {
    required bool keepCard,
  }) {
    final operations = ref.read(paymentLinkOperationsProvider);
    unawaited(
      keepCard
          ? operations.retainPendingClaim(session)
          : operations.discardClaimSession(session),
    );
  }

  void _cancelLongSyncWarning() {
    setState(() => _longSyncLink = null);
  }

  Future<void> _confirmLongSyncWarning() async {
    final link = _longSyncLink;
    if (link == null) return;
    setState(() {
      _longSyncLink = null;
      _operationInProgress = true;
      _redeemState = PaymentLinkRedeemVisualState.loading;
    });
    try {
      await _prepareDecodedPaymentLink(link, allowLongSync: true);
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
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
        _longSyncLink = null;
        _retryLink = null;
        _redeemState = PaymentLinkRedeemVisualState.paste;
      });
    }
  }

  Future<void> _runRedeemAction() async {
    final retryLink = _retryLink;
    if (retryLink == null) {
      await _pastePaymentLink();
      return;
    }
    await _checkPaymentLink(retryLink);
  }

  String get _redeemActionLabel =>
      _retryLink == null ? 'Paste card link' : 'Try again';

  void _claimReceivedLink() {
    final link = _receivedLink;
    final session = _receivedClaimSession;
    if (link == null ||
        session == null ||
        !session.canClaim ||
        _operationInProgress) {
      return;
    }
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final submission = ref
        .read(paymentLinkClaimCoordinatorProvider)
        .submit(session);
    setState(() {
      _receivedShowsBack = false;
      _rememberReceivedLink(link);
      _setReceivedCardStatus(link.address, PaymentLinkReceivedStatus.receiving);
      _activeCardsTab = PaymentLinkCardsTab.received;
      _receivedClaimSession = null;
      _receivedLink = null;
      if (!mobile) _page = PaymentLinksLocalPage.home;
      _showHelp = false;
    });
    unawaited(_finishClaimSubmission(link, submission));
    if (mobile) context.go('/home');
  }

  Future<void> _finishClaimSubmission(
    VizorPaymentLink link,
    Future<PaymentLinkClaimResult> submission,
  ) async {
    try {
      await submission;
      if (!mounted) return;
      showAppToast(context, 'Gift claim submitted');
      unawaited(_refreshReceivedClaims());
    } on PaymentLinkClaimDestinationChangedException {
      if (mounted) {
        setState(() {
          _setReceivedCardStatus(
            link.address,
            PaymentLinkReceivedStatus.readyToClaim,
          );
          _redeemState = PaymentLinkRedeemVisualState.paste;
          _page = PaymentLinksLocalPage.redeem;
        });
        _showError(
          'Receiving account changed. Open the Gift Card again to continue.',
        );
      }
    } catch (_) {
      if (mounted) {
        unawaited(_refreshReceivedClaims());
        _showError(
          'Gift Card claim failed. It may still be waiting for confirmation '
          'or may already be spent.',
        );
      }
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
      final mobileKeystoneRequest = _keystoneFundingRequest;
      return PaymentLinksMobileBody(
        page: _page,
        redeemState: _redeemState,
        operationInProgress: _operationInProgress,
        redeemActionLabel: _redeemActionLabel,
        keystoneOverlay: mobileKeystoneRequest == null
            ? null
            : PaymentLinkKeystoneSigningOverlay(
                amountZatoshi: mobileKeystoneRequest.amountZatoshi,
                sourceAccountUuid: mobileKeystoneRequest.sourceAccountUuid,
                presentation: mobileKeystoneRequest.presentation,
                onCancel: _cancelKeystoneFunding,
                onFundingBroadcast: _completeKeystoneFunding,
              ),
        hasCards:
            _visibleRecoveries.isNotEmpty || _visibleReceivedCards.isNotEmpty,
        cardsSections: () => _cardsSections(
          recoveryRow: _buildMobileRecoveryRow,
          receivedRow: _buildMobileReceivedRow,
        ),
        activeCardsTab: _activeCardsTab,
        selectedArtwork: _selectedArtwork,
        amountController: _amountController,
        amountFocusNode: _amountFocusNode,
        amountInputFormatters: [_amountFormatter],
        maxAmountText: _maxAmountText,
        canContinueAmount: _canContinueAmount,
        amountSupportingText: _amountSupportingText,
        amountSupportingTextIsError: _amountSupportingTextIsError,
        messageController: _messageController,
        messageFocusNode: _messageFocusNode,
        hasMessage: _hasMessage,
        messageExceedsByteLimit: _messageExceedsByteLimit,
        fundingQuote: _fundingQuote,
        reviewShowsBack: _reviewShowsBack,
        hasPendingFundingMetadata: _pendingFundingMetadata != null,
        readyLink: _readyLink,
        fundingProgressByAddress: _fundingProgressByAddress,
        readyShowsBack: _readyShowsBack,
        receivedLink: _receivedLink,
        receivedShowsBack: _receivedShowsBack,
        receivedClaimSession: _receivedClaimSession,
        linkWaitLabel: _estimatedLinkWaitLabel,
        claimWaitLabel: _estimatedClaimWaitLabel,
        availableSoonRemainingConfirmations:
            _linkAvailableSoonRemainingConfirmations,
        onShowPage: _showPage,
        onStartCreate: _startCreate,
        onRunRedeemAction: _runRedeemAction,
        onClearClipboard: _clearClipboard,
        onTabSelected: (tab) => setState(() => _activeCardsTab = tab),
        onArtworkSelected: (artwork) =>
            setState(() => _selectedArtwork = artwork),
        onAmountChanged: _handleAmountChanged,
        onUseMax: _useMaxAmount,
        onMessageChanged: _handleMessageChanged,
        onClearMessage: _clearMessage,
        onSkipMessage: _skipMessage,
        onReviewShowsBackChanged: (showBack) =>
            setState(() => _reviewShowsBack = showBack),
        onCreateFundedLink: _createFundedLink,
        onRetryFundingMetadata: _retryFundingMetadata,
        onCopyLink: _copyPaymentLink,
        onToggleReadyBack: () =>
            setState(() => _readyShowsBack = !_readyShowsBack),
        onToggleReceivedBack: () =>
            setState(() => _receivedShowsBack = !_receivedShowsBack),
        onLeavePendingClaim: _leavePendingClaim,
        onClaimReceivedLink: _claimReceivedLink,
      );
    }

    final currentPage = _buildCurrentPage();
    final keystoneRequest = _keystoneFundingRequest;
    final longSyncLink = _longSyncLink;
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
        : longSyncLink != null
        ? Stack(
            fit: StackFit.expand,
            children: [
              currentPage,
              PaymentLinkLongSyncWarningModal(
                onConfirm: _confirmLongSyncWarning,
                onCancel: _cancelLongSyncWarning,
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
      PaymentLinksLocalPage.home => _buildHome(),
      PaymentLinksLocalPage.amount => _buildAmount(),
      PaymentLinksLocalPage.message => _buildMessage(),
      PaymentLinksLocalPage.review => _buildReview(),
      PaymentLinksLocalPage.ready => _buildReady(),
      PaymentLinksLocalPage.shareQr => _buildShareQr(),
      PaymentLinksLocalPage.redeem => PaymentLinkRedeemDesktopView(
        state: _redeemState,
        onBack: () => _showPage(PaymentLinksLocalPage.home),
        onPaste: _operationInProgress ? null : _runRedeemAction,
        onClearClipboard: _operationInProgress ? null : _clearClipboard,
        pasteLabel: _redeemActionLabel,
      ),
      PaymentLinksLocalPage.received => _buildReceived(),
    };
  }

  Widget _buildHome() {
    if (_visibleRecoveries.isNotEmpty || _visibleReceivedCards.isNotEmpty) {
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
      onRedeem: () => _showPage(PaymentLinksLocalPage.redeem),
    );
  }

  Widget _buildCardsList() {
    return PaymentLinkCardsDesktopView(
      sections: _cardsSections(
        recoveryRow: _buildRecoveryRow,
        receivedRow: _buildReceivedRow,
        emptyReceivedCards: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              kPaymentLinkNoReceivedCardsText,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
      onBack: () => context.go('/home'),
      onCreate: _startCreate,
      onRedeem: () => _showPage(PaymentLinksLocalPage.redeem),
      activeTab: _activeCardsTab,
      onTabSelected: (tab) => setState(() => _activeCardsTab = tab),
    );
  }

  /// The Gift Card grouping both form factors render.
  ///
  /// Created Cards split into `Creating` / `Pending` by funding readiness and
  /// received Cards form one list; only the row widgets differ per form
  /// factor, so the grouping and the tab selection stay here rather than
  /// being restated in the mobile view.
  List<PaymentLinkCardsSection> _cardsSections({
    required Widget Function(PaymentLinkRecoveryRecord record) recoveryRow,
    required Widget Function(PaymentLinkReceivedRecord record) receivedRow,
    List<Widget> emptyReceivedCards = const <Widget>[],
  }) {
    if (_activeCardsTab == PaymentLinkCardsTab.created) {
      final creatingCards = <Widget>[];
      final pendingCards = <Widget>[];
      for (final record in _visibleRecoveries) {
        final fundingReady =
            _fundingProgressByAddress[record.link.address]?.isReady ?? false;
        (fundingReady ? pendingCards : creatingCards).add(recoveryRow(record));
      }
      return <PaymentLinkCardsSection>[
        if (creatingCards.isNotEmpty)
          PaymentLinkCardsSection(
            label: kPaymentLinkCreatingSectionLabel,
            cards: creatingCards,
          ),
        if (pendingCards.isNotEmpty)
          PaymentLinkCardsSection(
            label: kPaymentLinkPendingSectionLabel,
            cards: pendingCards,
          ),
      ];
    }
    return <PaymentLinkCardsSection>[
      PaymentLinkCardsSection(
        label: kPaymentLinkReceivedTabLabel,
        cards: _visibleReceivedCards.isNotEmpty
            ? _visibleReceivedCards.map(receivedRow).toList()
            : emptyReceivedCards,
      ),
    ];
  }

  /// Whether a created Card's link can be shared yet, plus the status the row
  /// shows while it cannot. Shared by the desktop and mobile rows.
  ({bool canUseLink, String statusText, bool showLoader}) _recoveryRowState(
    PaymentLinkRecoveryRecord record,
  ) {
    final fundingReady =
        _fundingProgressByAddress[record.link.address]?.isReady ?? false;
    final canUseLink =
        fundingReady &&
        (record.state == PaymentLinkRecoveryState.funded ||
            record.state == PaymentLinkRecoveryState.shared);
    return (
      canUseLink: canUseLink,
      statusText: record.state == PaymentLinkRecoveryState.draft
          ? kPaymentLinkFundingIncompleteStatus
          : kPaymentLinkPreparingStatus,
      showLoader: !canUseLink && record.state != PaymentLinkRecoveryState.draft,
    );
  }

  /// The received Card's effective status, folding an in-flight submission
  /// the store has not caught up with into `Receiving...`.
  ({String statusText, bool canClaim, bool showLoader}) _receivedRowState(
    PaymentLinkReceivedRecord record,
  ) {
    final submissionInProgress = ref
        .read(paymentLinkClaimCoordinatorProvider)
        .isSubmitting(record.address);
    final effectiveStatus = submissionInProgress
        ? PaymentLinkReceivedStatus.receiving
        : record.status;
    return (
      statusText: switch (effectiveStatus) {
        PaymentLinkReceivedStatus.readyToClaim => 'Claim',
        PaymentLinkReceivedStatus.submitting => 'Receiving...',
        PaymentLinkReceivedStatus.receiving => 'Receiving...',
        PaymentLinkReceivedStatus.received => 'Received',
      },
      canClaim:
          effectiveStatus == PaymentLinkReceivedStatus.readyToClaim &&
          record.claimLink != null &&
          !_operationInProgress,
      showLoader:
          effectiveStatus == PaymentLinkReceivedStatus.submitting ||
          effectiveStatus == PaymentLinkReceivedStatus.receiving,
    );
  }

  Widget _buildRecoveryRow(PaymentLinkRecoveryRecord record) {
    final state = _recoveryRowState(record);
    final copyEnabled = state.canUseLink && !_operationInProgress;
    return PaymentLinkCardListRow(
      key: ValueKey('payment_link_recovery_${record.link.address}'),
      thumbnail: _cardThumbnail(record.link.presentation?.artworkId),
      amountText: '${formatZecAmount(record.link.amountZatoshi)} ZEC',
      dateText: _formatCardDate(record.link.createdAt),
      statusText: state.canUseLink ? null : state.statusText,
      onAction: null,
      showLinkActions: state.canUseLink,
      onCopyLink: copyEnabled ? () => _copyPaymentLink(record.link) : null,
      onShowQr: copyEnabled ? () => _openShareQr(record) : null,
      showLoader: state.showLoader,
    );
  }

  Widget _buildMobileRecoveryRow(PaymentLinkRecoveryRecord record) {
    final state = _recoveryRowState(record);
    final copyEnabled = state.canUseLink && !_operationInProgress;
    return PaymentLinkCardListMobileRow(
      key: ValueKey('payment_link_mobile_recovery_${record.link.address}'),
      thumbnail: _cardThumbnail(record.link.presentation?.artworkId),
      amountText: '${formatZecAmount(record.link.amountZatoshi)} ZEC',
      dateText: _formatCardDate(record.link.createdAt),
      statusText: state.canUseLink ? null : state.statusText,
      showCopyAction: state.canUseLink,
      onCopyLink: copyEnabled ? () => _copyPaymentLink(record.link) : null,
      showLoader: state.showLoader,
    );
  }

  Widget _cardThumbnail(String? artworkId) {
    return Image.asset(
      PaymentLinkCardArtwork.fromProtocolId(artworkId).assetPath,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
  }

  void _openShareQr(PaymentLinkRecoveryRecord record) {
    if (_operationInProgress) return;
    setState(() {
      _shareQrRecord = record;
      _page = PaymentLinksLocalPage.shareQr;
      _showHelp = false;
      _longSyncLink = null;
    });
  }

  Widget _buildShareQr() {
    final record = _shareQrRecord;
    if (record == null) return _buildHome();
    return PaymentLinkShareQrDesktopView(
      shareCardKey: _shareQrCardKey,
      artwork: PaymentLinkCardArtwork.fromProtocolId(
        record.link.presentation?.artworkId,
      ),
      qrData: record.link.toUri().toString(),
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      onSaveQr: _operationInProgress ? null : () => _savePaymentLinkQr(record),
      onCopyLink: _operationInProgress
          ? null
          : () => _copyPaymentLink(record.link),
      saveLabel: _operationInProgress ? 'Saving...' : 'Save QR code',
      copyLabel: _operationInProgress ? 'Copying...' : 'Copy link',
    );
  }

  Future<void> _savePaymentLinkQr(PaymentLinkRecoveryRecord record) async {
    if (_operationInProgress) return;
    final pixelRatio = max(3.0, View.of(context).devicePixelRatio);
    setState(() => _operationInProgress = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _shareQrCardKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
        throw StateError('Gift Card QR image is not ready.');
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? pngData;
      try {
        pngData = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (pngData == null) {
        throw StateError('Gift Card QR image could not be encoded.');
      }
      final saved = await ref
          .read(paymentLinkQrImageSaverProvider)
          .savePng(
            pngData.buffer.asUint8List(
              pngData.offsetInBytes,
              pngData.lengthInBytes,
            ),
          );
      if (!mounted || !saved) return;
      try {
        await ref
            .read(paymentLinkOperationsProvider)
            .markCreatedLinkShared(record.link);
        await _loadRecoveries(showError: false);
        if (mounted) showAppToast(context, 'Gift Card QR saved');
      } catch (_) {
        if (mounted) {
          _showError(
            'Gift Card QR saved, but its status could not be updated.',
          );
        }
      }
    } catch (_) {
      if (mounted) _showError('Gift Card QR could not be saved.');
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Widget _buildReceivedRow(PaymentLinkReceivedRecord record) {
    final state = _receivedRowState(record);
    return PaymentLinkCardListRow(
      key: ValueKey('payment_link_received_${record.address}'),
      thumbnail: _cardThumbnail(record.artworkId),
      amountText: '${formatZecAmount(record.amountZatoshi)} ZEC',
      dateText: _formatCardDate(record.createdAt),
      statusText: state.statusText,
      onAction: state.canClaim ? () => _openReceivedCard(record) : null,
      showLoader: state.showLoader,
    );
  }

  Widget _buildMobileReceivedRow(PaymentLinkReceivedRecord record) {
    final state = _receivedRowState(record);
    return PaymentLinkCardListMobileRow(
      key: ValueKey('payment_link_mobile_received_${record.address}'),
      thumbnail: _cardThumbnail(record.artworkId),
      amountText: '${formatZecAmount(record.amountZatoshi)} ZEC',
      dateText: _formatCardDate(record.createdAt),
      statusText: state.statusText,
      onAction: state.canClaim ? () => _openReceivedCard(record) : null,
      showLoader: state.showLoader,
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
        showMaxButton: true,
        semanticLabel: 'Gift card amount input',
      ),
      cardSelector: PaymentLinkCardSelectorRail(
        artworks: PaymentLinkCardArtwork.values,
        selected: _selectedArtwork,
        onSelected: (artwork) => setState(() => _selectedArtwork = artwork),
      ),
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      onCreate: _canContinueAmount
          ? () => _showPage(PaymentLinksLocalPage.message)
          : null,
      supportingText: _amountSupportingText,
      supportingTextIsError: _amountSupportingTextIsError,
      emptyActionLabel: _amountSupportingTextIsError
          ? 'Enter amount'
          : 'Continue',
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
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      onSkip: _skipMessage,
      onContinue: _hasMessage && !_messageExceedsByteLimit
          ? () => _showPage(PaymentLinksLocalPage.review)
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
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      cardAmountText:
          '${formatZecAmount(_fundingQuote!.recipientAmountZatoshi)} ZEC',
      cardFeeText: '${formatZecAmount(_fundingQuote!.cardFeeZatoshi)} ZEC',
      totalAmountText:
          '${formatZecAmount(_fundingQuote!.totalDeductedZatoshi)} ZEC',
      onConfirm: _operationInProgress
          ? null
          : _pendingFundingMetadata == null
          ? _createFundedLink
          : _retryFundingMetadata,
      onStepSelected: _operationInProgress ? null : _selectWizardStep,
      confirmLabel: _operationInProgress
          ? _pendingFundingMetadata == null
                ? 'Creating...'
                : 'Saving...'
          : _pendingFundingMetadata == null
          ? 'Create card'
          : 'Try saving again',
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
      decoration: const PaymentLinkConfetti(),
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      onCopy: !readyToShare || _operationInProgress
          ? null
          : () => _copyPaymentLink(link),
      onCardTap: readyToShare && hasMessage
          ? () => setState(() => _readyShowsBack = !_readyShowsBack)
          : null,
      onReturnHome: () => _showPage(PaymentLinksLocalPage.home),
      waitingStatusLabel: _estimatedLinkWaitLabel(fundingProgress),
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
    final session = _receivedClaimSession;
    if (session?.waitingForFundingConfirmations ?? false) {
      return PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.waiting,
        card: card,
        onBack: _leavePendingClaim,
        onCopy: null,
        waitingHeading: 'Your Gift Card\nis almost ready!',
        waitingPrimaryText: 'Waiting for 6 confirmations.',
        waitingSecondaryText:
            'Vizor will keep checking. You can claim the card as soon as\n'
            'the funds are ready.',
        waitingStatusLabel: _estimatedClaimWaitLabel(session!),
      );
    }
    return PaymentLinkReceivedDesktopView(
      card: card,
      decoration: const PaymentLinkConfetti(),
      onBack: _abandonReceivedPreview,
      onClaim: _operationInProgress ? null : _claimReceivedLink,
      onRevealMessage: hasMessage
          ? () => setState(() => _receivedShowsBack = !_receivedShowsBack)
          : null,
      claimLabel: _operationInProgress ? 'Claiming...' : 'Claim the Gift Card',
    );
  }

  String _formatCardDate(DateTime date) {
    final local = date.toLocal();
    return '${_monthNames[local.month - 1]} ${local.day}';
  }
}

String _paymentLinkFormatFailureCategory(FormatException error) {
  final message = error.message.toString().toLowerCase();
  if (message.contains('birthday is ahead')) return 'birthday_ahead_of_tip';
  if (message.contains('address does not match')) return 'address_mismatch';
  if (message.contains('birthday must be positive')) {
    return 'invalid_birthday';
  }
  return 'format_error';
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
