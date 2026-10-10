import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/swap_feature_config.dart';
import '../../../core/feedback/app_haptics.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../send/services/send_amount_conversion.dart';
import '../../swap/models/swap_fiat_value_formatting.dart';
import '../models/gift_card_usage.dart';
import '../models/vizor_payment_link.dart';
import '../providers/gift_card_tracking_provider.dart';
import '../providers/payment_link_cards_provider.dart';
import '../providers/payment_link_claim_coordinator_provider.dart';
import '../providers/payment_link_intake_provider.dart';
import '../providers/gift_card_check_progress_provider.dart';
import '../services/payment_link_clipboard.dart';
import '../services/payment_link_batch_export.dart';
import '../services/payment_link_batch_limits.dart';
import '../services/payment_link_entry_policy.dart';
import '../services/payment_link_hardware_signing_service.dart';
import '../services/payment_link_qr_export.dart';
import '../services/payment_link_qr_image_saver.dart';
import '../services/payment_link_received_store.dart';
import '../services/payment_link_recovery_store.dart';
import '../services/payment_link_service.dart';
import '../services/payment_link_sharing.dart';
import '../widgets/gift_card_usage_status.dart';
import '../widgets/mobile/payment_link_claim_account_sheet.dart';
import '../widgets/mobile/payment_link_mobile_views.dart';
import '../providers/payment_link_scanner_provider.dart';
import '../widgets/mobile/payment_link_share_sheet.dart';
import '../widgets/payment_link_archive_header.dart';
import '../widgets/payment_link_amount_card.dart';
import '../widgets/payment_link_card_flip.dart';
import '../widgets/payment_link_batch_detail_desktop_view.dart';
import '../widgets/payment_link_bulk_desktop_flow.dart';
import '../widgets/payment_link_card_selector_rail.dart';
import '../widgets/payment_link_claim_outcome_view.dart';
import '../widgets/payment_link_confetti.dart';
import '../widgets/payment_link_confirm_modal.dart';
import '../widgets/payment_link_copy.dart';
import '../widgets/payment_link_desktop_views.dart';
import '../widgets/payment_link_gift_card.dart';
import '../widgets/payment_link_keystone_signing_overlay.dart';
import '../widgets/payment_link_ledger_signing_overlay.dart';
import '../widgets/payment_link_long_sync_warning.dart';
import '../widgets/payment_link_wizard_chrome.dart';
import 'payment_links_local_page.dart';
import 'payment_links_mobile_body.dart';

part 'payment_links_batch_creation.dart';

/// Desktop Payment Link lifecycle.
///
/// The presentation remains local to this screen, while all secret creation,
/// recovery persistence, sync, and transaction work stays behind
/// [PaymentLinkOperations]. Artwork and message are carried by the v1
/// presentation payload.
class PaymentLinksScreen extends ConsumerStatefulWidget {
  const PaymentLinksScreen({
    this.initialCards,
    this.initialReceivedCardAddress,
    super.key,
  });

  final PaymentLinkCardsSnapshot? initialCards;
  final String? initialReceivedCardAddress;

  @override
  ConsumerState<PaymentLinksScreen> createState() => _PaymentLinksScreenState();
}

class _PaymentLinksScreenState extends ConsumerState<PaymentLinksScreen>
    with _PaymentLinksBatchCreation {
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

  @override
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  // The controller is only the visible input. Quotes, review and funding use
  // the canonical zatoshi so toggling units cannot round the gift amount.
  BigInt? _amountZatoshi;
  PaymentLinkAmountCurrency _amountCurrency = PaymentLinkAmountCurrency.zec;
  bool _amountUsesMax = false;
  double? _amountUsdUnitPrice;
  @override
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  late final PaymentLinkOperations _paymentLinkOperations;
  late final PaymentLinkIntakeNotifier _paymentLinkIntake;
  @override
  Timer? _fundingQuoteDebounce;
  Timer? _fundingProgressTimer;

  VizorPaymentLink? _outcomeLink;
  PaymentLinkAvailability _outcomeAvailability =
      PaymentLinkAvailability.noBalance;
  bool _showArchivedCards = false;

  int _mobileNavigationEpoch = 0;
  bool _softwareFundingInProgress = false;
  bool _claimSubmissionInProgress = false;

  bool _isCurrentNavigation(int epoch) =>
      kAppFormFactor != AppFormFactor.mobile || epoch == _mobileNavigationEpoch;

  @override
  PaymentLinksLocalPage _page = PaymentLinksLocalPage.home;
  @override
  PaymentLinkCardArtwork _selectedArtwork = PaymentLinkCardArtwork.gift;
  PaymentLinkRedeemVisualState _redeemState =
      PaymentLinkRedeemVisualState.paste;
  PaymentLinkCardsTab _activeCardsTab = PaymentLinkCardsTab.created;
  List<PaymentLinkRecoveryRecord> _recoveries = const [];
  @override
  Map<String, PaymentLinkFundingProgress> _fundingProgressByAddress = const {};
  List<PaymentLinkReceivedRecord> _receivedCards = const [];
  final GlobalKey _shareQrCardKey = GlobalKey();
  PaymentLinkRecoveryRecord? _shareQrRecord;
  String? _shareQrData;
  bool _preparingShareQr = false;
  PaymentLinkFundingQuote? _maxFundingQuote;
  PaymentLinkFundingQuote? _fundingQuote;
  String? _fundingQuoteRequestedAccountUuid;
  PaymentLinkClaimSession? _receivedClaimSession;
  bool _claimStageActive = false;
  VizorPaymentLink? _readyLink;
  VizorPaymentLink? _receivedLink;
  VizorPaymentLink? _lastDeferredPendingLink;
  VizorPaymentLink? _longSyncLink;
  VizorPaymentLink? _retryLink;
  @override
  PaymentLinkFundingResult? _pendingFundingMetadata;
  _PaymentLinkHardwareFundingRequest? _hardwareFundingRequest;
  @override
  bool _showHelp = false;
  bool _amountFocused = false;
  bool _maxFundingQuoteInProgress = false;
  bool _fundingQuoteInProgress = false;
  String? _amountSupportingText;
  bool _amountSupportingTextIsError = false;
  @override
  int _fundingQuoteGeneration = 0;
  int _maxFundingQuoteGeneration = 0;
  bool _fundingQuoteRetryScheduled = false;
  bool _reviewShowsBack = false;
  bool _readyShowsBack = false;
  bool _receivedShowsBack = false;
  bool _messageEditorRevealed = false;
  @override
  bool _operationInProgress = false;
  final Set<String> _copyingLinkAddresses = {};
  final Set<String> _savingQrAddresses = {};
  final Set<String> _sharingQrAddresses = {};
  bool _choosingClaimAccount = false;
  bool _redeemFromQrCode = false;
  bool _receivedRefreshInProgress = false;
  bool _claimConfirmationRefreshInProgress = false;
  bool _pendingIntakeScheduled = false;
  bool _initialCardsLoaded = false;
  // Whether funding progress has been read once. Until then a batch's
  // readiness is unknown, not pending.
  bool _fundingProgressChecked = false;
  final Set<String> _exportingBatchIds = {};
  bool _checkingBatchStatus = false;
  List<PaymentLinkRecoveryRecord>? _exportConfirmMembers;
  PaymentLinkReceivedRecord? _removeConfirmRecord;

  @override
  void initState() {
    super.initState();
    _paymentLinkOperations = ref.read(paymentLinkOperationsProvider);
    _batchOperations = ref.read(paymentLinkBatchOperationsProvider);
    _paymentLinkIntake = ref.read(paymentLinkIntakeProvider.notifier);
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
    ref.listenManual(giftCardCheckProgressProvider, (_, next) {
      final link = _receivedLink;
      if (!mounted || link == null || !_operationInProgress) return;
      final progress = next[paymentLinkClaimWalletDirectoryName(link)];
      if (progress == null || !progress.hasFunding || progress.event.complete) {
        return;
      }
      if (_page != PaymentLinksLocalPage.redeem &&
          _page != PaymentLinksLocalPage.received) {
        return;
      }
      setState(() {
        _receivedLink = progress.link;
        _page = PaymentLinksLocalPage.received;
      });
    });
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
    _disposeBatchCreation();
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

  bool get _mobileNavigationLocked =>
      _softwareFundingInProgress ||
      _claimSubmissionInProgress ||
      _pendingFundingMetadata != null ||
      (_operationInProgress &&
          (_page == PaymentLinksLocalPage.review || _choosingClaimAccount));

  @override
  void _showPage(PaymentLinksLocalPage page) {
    if (_batchBusy) return;
    if (kAppFormFactor == AppFormFactor.mobile && _mobileNavigationLocked) {
      return;
    }
    if (_pendingFundingMetadata != null &&
        page != PaymentLinksLocalPage.review) {
      _showError('Save this gift card before leaving this screen.');
      return;
    }
    if (_batchSubmission is _BatchUnsaved &&
        page != PaymentLinksLocalPage.bulk) {
      _showError('Save these gift cards before leaving this screen.');
      return;
    }
    if (_page == PaymentLinksLocalPage.bulk &&
        page != PaymentLinksLocalPage.bulk) {
      _leaveBatchCreation();
    }
    if (page != _page) {
      _mobileNavigationEpoch++;
      if (kAppFormFactor == AppFormFactor.desktop &&
          page == PaymentLinksLocalPage.redeem) {
        _redeemState = PaymentLinkRedeemVisualState.paste;
        _retryLink = null;
      }
      if (kAppFormFactor == AppFormFactor.mobile &&
          _page == PaymentLinksLocalPage.redeem) {
        _redeemState = PaymentLinkRedeemVisualState.paste;
        _retryLink = null;
      }
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
      if (_outcomeLink != null) {
        _outcomeLink = null;
        _redeemState = PaymentLinkRedeemVisualState.paste;
      }
      _page = page;
      if (page == PaymentLinksLocalPage.home ||
          page == PaymentLinksLocalPage.redeem) {
        _claimStageActive = false;
      }
      if (page != PaymentLinksLocalPage.bulk) _batchReviewing = false;
      // The reveal plays once, on the first visit.
      if (page != PaymentLinksLocalPage.batchDetail) _justCreatedBatchId = null;
      if (page != PaymentLinksLocalPage.shareQr) {
        _shareQrRecord = null;
        _shareQrData = null;
      }
      _showHelp = false;
      _longSyncLink = null;
    });
    if (page == PaymentLinksLocalPage.amount) {
      _refreshUsdAmountPrice(ref.read(zecLiveUsdUnitPriceProvider));
    }
    if (page == PaymentLinksLocalPage.message &&
        kAppFormFactor == AppFormFactor.mobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _page == PaymentLinksLocalPage.message) {
          _messageFocusNode.requestFocus();
        }
      });
    }
  }

  void _startCreate() {
    if (_operationInProgress || _pendingFundingMetadata != null) return;
    _mobileNavigationEpoch++;
    _fundingQuoteDebounce?.cancel();
    _fundingQuoteGeneration++;
    _maxFundingQuoteGeneration++;
    _resetAmountInput();
    _messageController.clear();
    _clearPreparedBatch();
    setState(() {
      _batchSubmission = const _BatchNotSent();
      _selectedArtwork = PaymentLinkCardArtwork
          .values[Random().nextInt(PaymentLinkCardArtwork.values.length)];
      _maxFundingQuote = null;
      _maxFundingQuoteInProgress = false;
      _fundingQuote = null;
      _fundingQuoteInProgress = false;
      _amountSupportingText = null;
      _amountSupportingTextIsError = false;
      _readyLink = null;
      _shareQrRecord = null;
      _shareQrData = null;
      _reviewShowsBack = false;
      _readyShowsBack = false;
      _messageEditorRevealed = false;
      _page = PaymentLinksLocalPage.amount;
      _showHelp = false;
      _longSyncLink = null;
    });
    unawaited(_loadMaxFundingQuote());
  }

  @override
  void _resetAmountInput() {
    _amountController.clear();
    _amountZatoshi = null;
    _amountCurrency = PaymentLinkAmountCurrency.zec;
    _amountUsesMax = false;
    _amountUsdUnitPrice = null;
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
    final address = widget.initialReceivedCardAddress;
    if (address != null) {
      final card = _receivedCards
          .where((r) => r.address == address)
          .firstOrNull;
      setState(() => _activeCardsTab = PaymentLinkCardsTab.received);
      if (card != null) _openReceivedCard(card);
      return;
    }
    await _consumePendingPaymentLink();
  }

  /// Whether the open group's records are loaded, in any account.
  bool get _openBatchLoaded =>
      _selectedBatchId != null &&
      _recoveries.any((record) => record.batchId == _selectedBatchId);

  /// Recovery removes a group only once it is known to hold no funds.
  void _leaveVanishedBatch() {
    if (!mounted ||
        _page != PaymentLinksLocalPage.batchDetail ||
        _openBatchLoaded) {
      return;
    }
    setState(() {
      _selectedBatchId = null;
      _page = PaymentLinksLocalPage.home;
    });
    _showError('This group wasn’t funded. Create it again.');
  }

  @override
  Future<void> _loadRecoveries({bool showError = true}) async {
    try {
      final records = await ref
          .read(paymentLinkOperationsProvider)
          .loadCreatedLinkRecoveries();
      if (!mounted) return;
      final visible = records.toList()..sort(compareCreatedPaymentLinks);
      final hadOpenBatch = _openBatchLoaded;
      setState(() => _recoveries = visible);
      if (hadOpenBatch) _leaveVanishedBatch();
      unawaited(_refreshFundingProgress(records: visible));
    } catch (_) {
      if (mounted && showError) {
        _showError('Gift cards could not be loaded.');
      }
    }
  }

  @override
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
    if (pending.isEmpty) {
      if (!_fundingProgressChecked && mounted) {
        setState(() => _fundingProgressChecked = true);
      }
      return;
    }
    if (_operationInProgress) return;
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
      final hadOpenBatch = _openBatchLoaded;
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
          if (_page == PaymentLinksLocalPage.ready) {
            _page = PaymentLinksLocalPage.home;
          }
        }
      });
      if (readyFundingExpired) {
        _showError('Gift card funding expired. Create it again.');
      }
      if (hadOpenBatch) _leaveVanishedBatch();
    } catch (_) {
      // Keep the last known progress. A later foreground sync or timer tick
      // retries this read without hiding an already-ready link.
    } finally {
      if (mounted && !_fundingProgressChecked) {
        setState(() => _fundingProgressChecked = true);
      }
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
      setState(() => _applyReceivedCards(sorted));
      unawaited(_refreshReceivedClaims(records: sorted));
      return true;
    } catch (error) {
      log(
        'PaymentLinkCards: received load failed '
        'attempt=$attempt type=${error.runtimeType}',
      );
      if (mounted && showError) {
        _showError('Received gift cards could not be loaded.');
      }
      return false;
    }
  }

  Future<void> _refreshReceivedClaims({
    List<PaymentLinkReceivedRecord>? records,
  }) async {
    final receivedCards = records ?? _receivedCards;
    final needsRecovery = receivedCards.any(
      (record) => record.needsClaimRecovery,
    );
    if (!needsRecovery || _receivedRefreshInProgress) {
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
      setState(() => _applyReceivedCards(sorted));
    } catch (_) {
      // Keep the last persisted status. The main wallet sync and the next
      // timer tick will retry the mined-history check.
    } finally {
      _receivedRefreshInProgress = false;
    }
  }

  void _applyReceivedCards(List<PaymentLinkReceivedRecord> records) {
    _receivedCards = records;
    if (_page == PaymentLinksLocalPage.redeem &&
        _outcomeLink != null &&
        records.any(
          (record) =>
              record.address == _outcomeLink!.address &&
              record.status == PaymentLinkReceivedStatus.received,
        )) {
      _outcomeLink = null;
      _page = PaymentLinksLocalPage.home;
    }
  }

  /// Saved Cards own a claim wallet while they retain recovery material.
  /// Receipts after recovery and new previews do not retain inspection wallets.
  bool _shouldKeepCard(PaymentLinkClaimSession session) => _receivedCards.any(
    (record) =>
        record.address == session.link.address && record.claimLink != null,
  );

  /// Keeps the link for retry after the recipient explicitly confirms a claim
  /// but preparing it for the selected account fails.
  void _keepClaimLinkForRetry(VizorPaymentLink link) {
    if (mounted) {
      setState(() {
        _rememberReceivedLink(link);
        _activeCardsTab = PaymentLinkCardsTab.received;
      });
    }
    unawaited(_paymentLinkOperations.keepReceivedLink(link));
  }

  /// An empty scan cannot prove that a Card will never receive funds. Keep
  /// recoverable Cards and their wallets for retry; new previews are disposable.
  Future<void> _releaseUnavailableClaim(PaymentLinkClaimSession session) async {
    final epoch = _mobileNavigationEpoch;
    final availability =
        session.availability == PaymentLinkAvailability.unchecked
        ? PaymentLinkAvailability.noBalance
        : session.availability;
    if (_shouldKeepCard(session)) {
      await _paymentLinkOperations.retainPendingClaim(session);
      _receivedCards = [
        for (final record in _receivedCards)
          if (record.address == session.link.address)
            record.copyWith(availability: availability)
          else
            record,
      ];
    } else {
      await _paymentLinkOperations.discardClaimSession(session);
    }
    if (!mounted || !_isCurrentNavigation(epoch)) return;
    _outcomeLink = session.link;
    _outcomeAvailability = availability;
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
    if (link == null ||
        _operationInProgress ||
        ref
            .read(paymentLinkClaimCoordinatorProvider)
            .isSubmitting(record.address)) {
      return;
    }
    if (record.availability != PaymentLinkAvailability.unchecked &&
        record.availability != PaymentLinkAvailability.available) {
      setState(() {
        _outcomeLink = link;
        _outcomeAvailability = record.availability;
        _page = PaymentLinksLocalPage.redeem;
      });
    } else {
      unawaited(_checkPaymentLink(link));
    }
  }

  Widget? _buildClaimOutcome({bool embedded = false}) {
    final link = _outcomeLink;
    if (link == null) return null;
    final record = _receivedCards
        .where((r) => r.address == link.address)
        .firstOrNull;
    return PaymentLinkClaimOutcomeView(
      embedded: embedded,
      availability: record?.availability ?? _outcomeAvailability,
      busy: _operationInProgress,
      archived: record?.archived ?? false,
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      onCheck: () async {
        final epoch = _mobileNavigationEpoch;
        if (record?.isClaimInFlight ?? false) {
          setState(() => _operationInProgress = true);
          try {
            var records = _receivedCards;
            await ref.read(paymentLinkClaimCoordinatorProvider).trackRetention(
              () async {
                records = await _paymentLinkOperations
                    .inspectReceivedLinkClaims(
                      _receivedCards,
                      allowResubmit: false,
                    );
              },
            );
            if (!mounted || !_isCurrentNavigation(epoch)) return;
            setState(() {
              _applyReceivedCards(records);
              final current = records
                  .where((r) => r.address == link.address)
                  .firstOrNull;
              _outcomeAvailability =
                  current?.availability ?? PaymentLinkAvailability.checking;
              if (current?.status == PaymentLinkReceivedStatus.received) {
                _page = PaymentLinksLocalPage.home;
              }
            });
          } catch (_) {
            if (mounted && _isCurrentNavigation(epoch)) {
              _showError('Card status could not be checked. Try again.');
            }
          } finally {
            if (mounted) setState(() => _operationInProgress = false);
          }
        } else {
          await _checkPaymentLink(link);
        }
      },
      onRemove: record != null && record.canRemove
          ? () => _requestRemoveReceivedCard(record)
          : null,
      onArchive:
          record != null &&
              !record.canRemove &&
              (record.canArchive || record.archived)
          ? () => _setCardArchived(record, !record.archived)
          : null,
    );
  }

  /// Removing a Card cannot be undone from the list, so it is confirmed first.
  Future<void> _requestRemoveReceivedCard(
    PaymentLinkReceivedRecord record,
  ) async {
    if (_operationInProgress) return;
    if (kAppFormFactor == AppFormFactor.desktop) {
      setState(() => _removeConfirmRecord = record);
      return;
    }
    final epoch = _mobileNavigationEpoch;
    final confirmed = await showPaymentLinkConfirmSheet(
      context,
      iconName: AppIcons.trash,
      title: kPaymentLinkRemoveCardTitle,
      body: kPaymentLinkClaimedElsewhereDescription,
      supporting: kPaymentLinkRemoveCardSupporting,
      confirmLabel: kPaymentLinkRemoveCardLabel,
      cancelLabel: 'Cancel',
      sheetKey: const ValueKey('payment_link_remove_card_sheet'),
      confirmKey: const ValueKey(
        'payment_link_remove_card_sheet_confirm_button',
      ),
    );
    if (!confirmed || !mounted || !_isCurrentNavigation(epoch)) return;
    await _removeReceivedCard(record);
  }

  void _cancelRemoveReceivedCard() =>
      setState(() => _removeConfirmRecord = null);

  Future<void> _confirmRemoveReceivedCard() async {
    final record = _removeConfirmRecord;
    if (record == null) return;
    setState(() => _removeConfirmRecord = null);
    await _removeReceivedCard(record);
  }

  Future<void> _removeReceivedCard(PaymentLinkReceivedRecord record) =>
      _updateReceivedCard(
        () => _paymentLinkOperations.removeReceivedCard(record.address),
        errorText: 'Card could not be removed. Try again.',
      );

  Future<void> _setCardArchived(
    PaymentLinkReceivedRecord record,
    bool archived,
  ) => _updateReceivedCard(
    () => _paymentLinkOperations.setReceivedCardArchived(
      record.address,
      archived,
    ),
    errorText: 'Card could not be updated. Try again.',
  );

  /// Applies one change to a received Card, then shows the list as stored. A
  /// refused change reloads too: the stored Card may have moved on, and a
  /// stale row would only offer the same failing action again.
  Future<void> _updateReceivedCard(
    Future<void> Function() update, {
    required String errorText,
  }) async {
    if (_operationInProgress) return;
    final epoch = _mobileNavigationEpoch;
    setState(() => _operationInProgress = true);
    try {
      var updated = true;
      try {
        await update();
      } catch (_) {
        updated = false;
      }
      final records = await _paymentLinkOperations.loadReceivedLinkRecoveries();
      if (!mounted || !_isCurrentNavigation(epoch)) return;
      setState(() {
        _receivedCards = records;
        if (updated) {
          _outcomeLink = null;
          _page = PaymentLinksLocalPage.home;
        }
      });
      if (!updated) _showError(errorText);
    } catch (_) {
      if (mounted && _isCurrentNavigation(epoch)) _showError(errorText);
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  bool get _hasPositiveAmount {
    final amount = _amountZatoshi;
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
      (_page != PaymentLinksLocalPage.amount ||
          !_amountInputIsUsd ||
          (ref.read(zecLiveUsdUnitPriceProvider) != null &&
              (double.tryParse(_amountController.text) ?? 0) > 0)) &&
      !_fundingQuoteInProgress &&
      _fundingQuote != null &&
      _fundingQuote!.recipientAmountZatoshi == _amountZatoshi &&
      _amountSupportingText == null;

  bool get _amountInputIsUsd =>
      _amountCurrency == PaymentLinkAmountCurrency.usd;

  bool _canEnterUsd(double? price) =>
      price != null &&
      price.isFinite &&
      price > 0 &&
      (_amountZatoshi == null ||
          _amountZatoshi! <= BigInt.zero ||
          sendSendableUsdInputTextForZatoshi(
            _amountZatoshi!,
            price,
          ).isNotEmpty);

  bool get _usdPriceLoading =>
      _page == PaymentLinksLocalPage.amount &&
      ref.read(zecLiveUsdUnitPriceProvider) == null &&
      ref.read(zecHomeMarketDataStateProvider).isLoading;

  String? get _usdDisabledReason {
    if (_page != PaymentLinksLocalPage.amount) return null;
    if (ref.read(zecLiveUsdUnitPriceProvider) == null) {
      return _usdPriceLoading ? 'Fetching USD price…' : 'USD price unavailable';
    }
    return 'Amount is too small for USD input.';
  }

  String? _amountConversionText(String? fiatText) {
    if (_amountInputIsUsd) {
      final amount = _amountZatoshi;
      return amount == null ? null : '≈ ${formatZecAmount(amount)} ZEC';
    }
    return fiatText != null && fiatText.startsWith(r'$')
        ? '≈ $fiatText'
        : fiatText;
  }

  void _setAmountControllerText(String text) {
    _amountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _selectAmountCurrency(PaymentLinkAmountCurrency currency) {
    if (currency == _amountCurrency) return;
    final price = ref.read(zecLiveUsdUnitPriceProvider);
    if (currency == PaymentLinkAmountCurrency.usd && !_canEnterUsd(price)) {
      return;
    }
    final wasEditing = _amountFocusNode.hasFocus;
    final amount = _amountZatoshi;
    final text = amount == null
        ? ''
        : currency == PaymentLinkAmountCurrency.usd
        ? sendUsdInputTextForZatoshi(amount, price!)
        : formatZecAmount(amount);
    setState(() {
      _amountCurrency = currency;
      _amountUsdUnitPrice = price;
    });
    _setAmountControllerText(text);
    if (wasEditing) _amountFocusNode.requestFocus();
  }

  void _handleZecUsdPriceChanged(double? previous, double? next) {
    if (previous == next) return;
    _refreshUsdAmountPrice(next);
  }

  void _refreshUsdAmountPrice(double? price) {
    // The ZEC amount is fixed after leaving Amount and is shown on Review.
    // Returning to USD editing resumes conversion at the current live price.
    if (_page != PaymentLinksLocalPage.amount ||
        !_amountInputIsUsd ||
        price == _amountUsdUnitPrice) {
      return;
    }
    _amountUsdUnitPrice = price;
    if (price == null) {
      // Keep the last exact ZEC amount for switching units. Editing the USD
      // input without a live price invalidates it in _handleAmountChanged.
      setState(() {});
      return;
    }
    if (_amountUsesMax && _amountZatoshi != null) {
      _setAmountControllerText(
        sendUsdInputTextForZatoshi(_amountZatoshi!, price),
      );
      setState(() {});
      return;
    }
    _amountZatoshi = sendZatoshiFromUsdText(_amountController.text, price);
    _requoteAmount();
  }

  @override
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
    if (next.accountUuid == null) return;
    if (_page == PaymentLinksLocalPage.bulk) {
      _requoteBatchAfterSync();
      return;
    }
    if (_page != PaymentLinksLocalPage.amount) {
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
      if (shouldLoadAmount) _requoteAmount();
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
    _amountUsesMax = false;
    _amountUsdUnitPrice = ref.read(zecLiveUsdUnitPriceProvider);
    _amountZatoshi = _amountInputIsUsd
        ? sendZatoshiFromUsdText(value, _amountUsdUnitPrice)
        : parseZecAmount(value);
    _requoteAmount();
  }

  void _requoteAmount() {
    _fundingQuoteDebounce?.cancel();
    final generation = ++_fundingQuoteGeneration;
    final amount = _amountZatoshi;
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
    if (_batchBusy) return;
    // Keep the original review and loading label during mobile funding.
    // An unsaved result must also retain its review so saving can be retried.
    if (_pendingFundingMetadata != null ||
        (kAppFormFactor == AppFormFactor.mobile &&
            _softwareFundingInProgress)) {
      return;
    }
    final quotedAccount = _fundingQuote?.sourceAccountUuid;
    final priorAccount =
        previous ?? quotedAccount ?? _fundingQuoteRequestedAccountUuid;
    if (current == null || priorAccount == null || priorAccount == current) {
      return;
    }
    if (_page != PaymentLinksLocalPage.amount &&
        _page != PaymentLinksLocalPage.message &&
        _page != PaymentLinksLocalPage.review &&
        _page != PaymentLinksLocalPage.bulk) {
      return;
    }

    if (_page == PaymentLinksLocalPage.bulk) {
      _requoteBatchForAccount();
      return;
    }

    final wasPastAmountStep = _page != PaymentLinksLocalPage.amount;
    final hadHardwareRequest = _hardwareFundingRequest != null;
    _fundingQuoteDebounce?.cancel();
    _fundingQuoteGeneration += 1;
    _maxFundingQuoteGeneration += 1;
    setState(() {
      _maxFundingQuote = null;
      _maxFundingQuoteInProgress = false;
      _fundingQuote = null;
      _fundingQuoteInProgress = false;
      if (hadHardwareRequest) {
        _hardwareFundingRequest = null;
        _operationInProgress = false;
      }
      _amountSupportingText = null;
      _amountSupportingTextIsError = false;
      _page = PaymentLinksLocalPage.amount;
    });
    unawaited(_loadMaxFundingQuote());
    _refreshUsdAmountPrice(ref.read(zecLiveUsdUnitPriceProvider));
    _requoteAmount();
    if (wasPastAmountStep) {
      showAppToast(
        context,
        'Active account changed. Review the gift card amount and fees again.',
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
    if (session == null ||
        session.isSetupClaim ||
        session.destinationAccountUuid == current) {
      return;
    }
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
      'Active account changed. Redeem this gift card again to receive it in '
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

  @override
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
  /// A draft with no submission trace cannot hold funds. Quoting a batch saves
  /// such drafts before the user chooses Create, so they are not created Cards.
  List<PaymentLinkRecoveryRecord> get _visibleRecoveries {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final batchesNeedingRecovery = {
      for (final record in _recoveries)
        if (record.batchId != null && !record.isInertDraft) record.batchId,
    };
    return [
      for (final record in _recoveries)
        if ((!record.isInertDraft ||
                batchesNeedingRecovery.contains(record.batchId)) &&
            (record.sourceAccountUuid.isEmpty ||
                record.sourceAccountUuid == accountUuid))
          record,
    ];
  }

  String? get _maxAmountText {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final quote = _maxFundingQuote;
    if (quote == null || quote.sourceAccountUuid != accountUuid) return null;
    return _maxAmountTextFor(quote.recipientAmountZatoshi);
  }

  String? _maxAmountTextFor(BigInt amount) {
    if (!_amountInputIsUsd) {
      return formatZecAmount(amount);
    }
    final price = ref.read(zecLiveUsdUnitPriceProvider);
    if (price == null) return null;
    final text = sendSendableUsdInputTextForZatoshi(amount, price);
    return text.isEmpty ? null : text;
  }

  void _useMaxAmount() {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final quote = _maxFundingQuote;
    if (quote == null || quote.sourceAccountUuid != accountUuid) return;
    final text = _maxAmountTextFor(quote.recipientAmountZatoshi);
    if (text == null) return;
    _amountZatoshi = quote.recipientAmountZatoshi;
    _amountUsesMax = true;
    _amountUsdUnitPrice = ref.read(zecLiveUsdUnitPriceProvider);
    _setAmountControllerText(text);
    _amountFocusNode.requestFocus();
    _requoteAmount();
  }

  void _handleMessageChanged(String _) => setState(() {});

  void _revealMessageEditor() {
    if (_messageEditorRevealed) {
      _messageFocusNode.requestFocus();
      return;
    }
    setState(() => _messageEditorRevealed = true);
  }

  void _focusVisibleMessageEditor(bool showingBack) {
    if (!showingBack ||
        !mounted ||
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

  @override
  HardwareSignerKind? _signerFor(String? accountUuid) => accountUuid == null
      ? null
      : ref
            .read(accountProvider.notifier)
            .hardwareSignerKindForAccount(accountUuid);

  void _selectWizardStep(int step) {
    if (_pendingFundingMetadata != null) {
      _showError('Save this gift card before leaving this screen.');
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

  void _confirmCardCreated({required bool broadcastAccepted}) {
    if (kAppFormFactor == AppFormFactor.mobile && broadcastAccepted) {
      unawaited(AppHaptics.sendSuccess());
    }
  }

  Future<void> _createFundedLink() async {
    if (_operationInProgress) return;
    if (_pendingFundingMetadata != null) {
      await _retryFundingMetadata();
      return;
    }
    final amount = _amountZatoshi;
    final quote = _fundingQuote;
    final accountState = ref.read(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    if (amount == null ||
        amount <= BigInt.zero ||
        quote == null ||
        quote.recipientAmountZatoshi != amount) {
      _showError('Enter a valid gift card amount.');
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
      fiatSnapshot: ref.read(swapFeatureEnabledProvider)
          ? PaymentLinkFiatSnapshot.capture(
              amountZatoshi: amount,
              zecUsdUnitPrice: ref
                  .read(zecHomeMarketDataStateProvider)
                  .displayData
                  ?.usdPrice,
            )
          : null,
    );
    if (ref
        .read(accountProvider.notifier)
        .isHardwareAccount(sourceAccountUuid)) {
      setState(() {
        _operationInProgress = true;
        _hardwareFundingRequest = _PaymentLinkHardwareFundingRequest(
          signerKind: _signerFor(sourceAccountUuid),
          amountZatoshi: amount,
          sourceAccountUuid: sourceAccountUuid,
          presentation: presentation,
        );
      });
      return;
    }

    setState(() {
      _operationInProgress = true;
      _softwareFundingInProgress = true;
    });
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
        // An account switch mid-send resets the wizard, which would strand the
        // retry: put Review back with the quote this funding actually used,
        // and drop the requote the reset started so it cannot clear it again.
        _fundingQuoteDebounce?.cancel();
        _fundingQuoteGeneration += 1;
        setState(() {
          _pendingFundingMetadata = funding;
          _fundingQuote = quote;
          _fundingQuoteInProgress = false;
          _amountSupportingText = null;
          _amountSupportingTextIsError = false;
          _reviewShowsBack = false;
          _page = PaymentLinksLocalPage.review;
        });
        _showError(
          'Funding was sent, but the gift card could not be saved. '
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
      _confirmCardCreated(broadcastAccepted: funding.broadcastAccepted);
    } catch (_) {
      if (mounted) _showError('Gift card creation failed. Try again.');
    } finally {
      if (mounted) {
        setState(() {
          _operationInProgress = false;
          _softwareFundingInProgress = false;
        });
        // A switch during funding must keep the existing loading UI visible.
        // Once it finishes, invalidate a failed draft for the new account.
        if (kAppFormFactor == AppFormFactor.mobile) {
          _handleActiveAccountChanged(
            sourceAccountUuid,
            ref.read(accountProvider).value?.activeAccountUuid,
          );
        }
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
      _confirmCardCreated(broadcastAccepted: pending.broadcastAccepted);
    } catch (_) {
      if (mounted) {
        _showError(
          'The gift card still could not be saved. Try again before closing Vizor.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _operationInProgress = false);
        unawaited(_refreshFundingProgress());
      }
    }
  }

  Widget _buildHardwareFundingOverlay(
    _PaymentLinkHardwareFundingRequest request,
  ) {
    if (request.signerKind == HardwareSignerKind.ledger) {
      return PaymentLinkLedgerSigningOverlay(
        key: ObjectKey(request),
        amountZatoshi: request.amountZatoshi,
        sourceAccountUuid: request.sourceAccountUuid,
        presentation: request.presentation,
        onCancel: _cancelHardwareFunding,
        onFundingBroadcast: (link, result) async {
          // Persistence is already complete; an old account must not replace
          // a newly opened wizard after a background completion.
          if (_hardwareFundingRequest != request) return;
          await _completeHardwareFunding(request, link, result);
        },
      );
    }
    return PaymentLinkKeystoneSigningOverlay(
      key: ObjectKey(request),
      amountZatoshi: request.amountZatoshi,
      sourceAccountUuid: request.sourceAccountUuid,
      presentation: request.presentation,
      onCancel: _cancelHardwareFunding,
      onFundingBroadcast: (link, result) =>
          _completeHardwareFunding(request, link, result),
    );
  }

  Future<void> _cancelHardwareFunding() async {
    final request = _hardwareFundingRequest;
    if (request == null) return;
    // The signing surface has released its input lock and refreshed balance.
    // Recheck fees before making the preserved review actionable again.
    PaymentLinkFundingQuote? quote;
    try {
      quote = await ref
          .read(paymentLinkOperationsProvider)
          .quoteFunding(
            amountZatoshi: request.amountZatoshi,
            sourceAccountUuid: request.sourceAccountUuid,
          );
    } catch (error) {
      log('PaymentLinks: cancelled funding review refresh failed: $error');
    }
    if (!mounted || _hardwareFundingRequest != request) return;
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid != request.sourceAccountUuid ||
        (quote != null &&
            quote.sourceAccountUuid != request.sourceAccountUuid)) {
      throw StateError('Gift Card account changed. Review the amount again.');
    }
    setState(() {
      // Preserve the card for inspection even if a fresh fee is unavailable,
      // but require returning to Amount before this old quote can be used.
      if (quote != null) _fundingQuote = quote;
      _amountSupportingText = quote == null
          ? 'Card fee could not be updated. Return to the amount step and try again.'
          : null;
      _amountSupportingTextIsError = quote == null;
      _maxFundingQuote = null;
      _maxFundingQuoteGeneration++;
      _maxFundingQuoteInProgress = false;
      _hardwareFundingRequest = null;
      _operationInProgress = false;
    });
    if (quote == null) _showError(_amountSupportingText!);
    unawaited(_loadMaxFundingQuote());
    unawaited(_loadRecoveries(showError: false));
  }

  Future<void> _completeHardwareFunding(
    _PaymentLinkHardwareFundingRequest request,
    VizorPaymentLink link,
    PaymentLinkHardwareFundingResult result,
  ) async {
    await _loadRecoveries(showError: false);
    if (!mounted || _hardwareFundingRequest != request) return;
    if (!result.fundingMetadataSaved) {
      setState(() {
        _hardwareFundingRequest = null;
        _operationInProgress = false;
        _pendingFundingMetadata = PaymentLinkFundingResult(
          link: link,
          txids: result.txids,
          fundingMetadataSaved: false,
          broadcastAccepted: isPaymentLinkFundingBroadcastAccepted(
            result.status,
          ),
        );
        // Review is where the retry lives; it renders from the quote, so it is
        // only safe to return to while one is still held.
        if (_fundingQuote != null) {
          _reviewShowsBack = false;
          _page = PaymentLinksLocalPage.review;
        }
      });
      _showError(
        'Funding was sent, but the gift card could not be saved. '
        'Try again before closing Vizor.',
      );
      return;
    }
    setState(() {
      _hardwareFundingRequest = null;
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
    _confirmCardCreated(
      broadcastAccepted: isPaymentLinkFundingBroadcastAccepted(result.status),
    );
    unawaited(_refreshFundingProgress());
    _warnUnsettledHardwareFunding(result);
  }

  /// A hardware funding the network may hold that is not settled locally yet.
  @override
  void _warnUnsettledHardwareFunding(PaymentLinkHardwareFundingResult result) {
    if (!mounted ||
        (result.status != 'broadcasted_storage_failed' &&
            result.status != 'broadcast_unknown')) {
      return;
    }
    showAppToast(
      context,
      result.message ??
          (result.status == 'broadcast_unknown'
              ? 'Funding is still being verified. Vizor will keep checking it.'
              : 'Funding was sent, but local transaction storage needs to sync.'),
      iconName: AppIcons.warning,
    );
  }

  Future<void> _copyPaymentLink(VizorPaymentLink link) async {
    if (_operationInProgress || _copyingLinkAddresses.contains(link.address)) {
      return;
    }
    setState(() => _copyingLinkAddresses.add(link.address));
    final epoch = _mobileNavigationEpoch;
    try {
      final uri = await preparePaymentLinkShareUri(link);
      if (!mounted || epoch != _mobileNavigationEpoch) return;
      await ref.read(paymentLinkClipboardProvider).copySecret(uri.toString());
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
      if (mounted && epoch == _mobileNavigationEpoch) {
        _showError('Gift link could not be copied.');
      }
    } finally {
      if (mounted) setState(() => _copyingLinkAddresses.remove(link.address));
    }
  }

  Future<void> _pastePaymentLink() async {
    if (_operationInProgress) return;
    final epoch = _mobileNavigationEpoch;
    setState(() {
      _operationInProgress = true;
      _retryLink = null;
      _redeemFromQrCode = false;
    });
    try {
      final rawLink = await ref.read(paymentLinkClipboardProvider).readText();
      if (!mounted || !_isCurrentNavigation(epoch)) return;
      if (rawLink == null || rawLink.trim().isEmpty) {
        if (mounted && _isCurrentNavigation(epoch)) {
          setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
        }
        return;
      }
      final link = VizorPaymentLink.parse(rawLink);
      if (!mounted) return;
      setState(() => _redeemState = PaymentLinkRedeemVisualState.loading);
      await _prepareDecodedPaymentLink(link);
    } catch (_) {
      if (mounted && _isCurrentNavigation(epoch)) {
        setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
      }
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<void> _scanPaymentLink() async {
    if (_operationInProgress) return;
    final page = _page;
    final epoch = _mobileNavigationEpoch;
    setState(() => _operationInProgress = true);
    VizorPaymentLink? link;
    try {
      link = await ref.read(paymentLinkScannerProvider)(
        context,
        networkName: ref.read(rpcEndpointProvider).networkName,
      );
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
    if (!mounted ||
        !_isCurrentNavigation(epoch) ||
        link == null ||
        _page != page) {
      return;
    }
    setState(() {
      _redeemFromQrCode = true;
      _retryLink = null;
    });
    await _checkPaymentLink(link);
  }

  Future<void> _checkPaymentLink(VizorPaymentLink link) async {
    if (_operationInProgress) return;
    final knownAddress = link.knownAddress;
    final matchingInFlight = _receivedCards
        .where(
          (record) =>
              record.isClaimInFlight &&
              record.claimLink?.hasSameCanonicalPayload(link) == true,
        )
        .firstOrNull;
    final inFlightAddress = knownAddress ?? matchingInFlight?.address;
    if (inFlightAddress != null &&
        (matchingInFlight != null ||
            ref
                .read(paymentLinkClaimCoordinatorProvider)
                .isSubmitting(inFlightAddress))) {
      setState(() {
        if (knownAddress != null) _rememberReceivedLink(link);
        _setReceivedCardStatus(
          inFlightAddress,
          PaymentLinkReceivedStatus.receiving,
        );
        _activeCardsTab = PaymentLinkCardsTab.received;
        _page = PaymentLinksLocalPage.home;
      });
      if (kAppFormFactor == AppFormFactor.mobile) context.go('/home');
      if (matchingInFlight != null) {
        _showError(const PaymentLinkClaimInFlightException().toString());
      }
      return;
    }
    setState(() {
      _operationInProgress = true;
      _outcomeLink = null;
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
    final epoch = _mobileNavigationEpoch;
    _receivedLink = link;
    _claimStageActive = true;
    final previousSession = _receivedClaimSession;
    if (previousSession != null &&
        paymentLinkClaimWalletDirectoryName(previousSession.link) !=
            paymentLinkClaimWalletDirectoryName(link)) {
      await ref
          .read(paymentLinkOperationsProvider)
          .discardClaimSession(previousSession);
      if (!mounted || !_isCurrentNavigation(epoch)) return;
      _receivedClaimSession = null;
    }
    try {
      final session = await ref
          .read(paymentLinkOperationsProvider)
          .prepareClaim(link, allowLongSync: allowLongSync);
      if (!mounted || !_isCurrentNavigation(epoch)) {
        // The element is defunct here, so its ref may already throw; the
        // captured operations still delete the temporary claim wallet.
        if (_shouldKeepCard(session)) {
          await _paymentLinkOperations.retainPendingClaim(session);
        } else {
          await _paymentLinkOperations.discardClaimSession(session);
        }
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
          !session.isSetupClaim &&
          (session.waitingForFundingConfirmations || session.canClaim)) {
        _receivedClaimSession = session;
        _receivedLink = session.link;
        _handleClaimDestinationAccountChanged(activeAccountUuid);
        return;
      }
      if (session.waitingForFundingConfirmations) {
        setState(() {
          _receivedClaimSession = session;
          _receivedLink = session.link;
          _longSyncLink = null;
          _retryLink = null;
          _receivedShowsBack = false;
          _redeemState = PaymentLinkRedeemVisualState.paste;
          _page = PaymentLinksLocalPage.received;
        });
        return;
      }
      if (!session.canClaim) {
        await _releaseUnavailableClaim(session);
        if (!mounted || !_isCurrentNavigation(epoch)) return;
        setState(() {
          _receivedClaimSession = null;
          _longSyncLink = null;
          _retryLink = null;
          _redeemState = PaymentLinkRedeemVisualState.paste;
          _page = PaymentLinksLocalPage.redeem;
        });
        return;
      }
      setState(() {
        _receivedClaimSession = session;
        _receivedLink = session.link;
        _longSyncLink = null;
        _retryLink = null;
        _receivedShowsBack = false;
        _redeemState = PaymentLinkRedeemVisualState.paste;
        _page = PaymentLinksLocalPage.received;
      });
      log('PaymentLinkClaim: preview ready');
    } on PaymentLinkLongSyncConfirmationRequired {
      log('PaymentLinkClaim: waiting for long sync confirmation');
      if (!mounted || !_isCurrentNavigation(epoch)) return;
      setState(() {
        _page = PaymentLinksLocalPage.redeem;
        _redeemState = PaymentLinkRedeemVisualState.paste;
        if (kAppFormFactor == AppFormFactor.desktop) {
          _longSyncLink = link;
        }
      });
      if (kAppFormFactor == AppFormFactor.mobile) {
        final confirmed = await showPaymentLinkLongSyncWarningSheet(context);
        if (!confirmed) return;
        if (!mounted || !_isCurrentNavigation(epoch)) return;
        setState(() => _redeemState = PaymentLinkRedeemVisualState.loading);
        await _prepareDecodedPaymentLink(link, allowLongSync: true);
      }
    } on PaymentLinkClaimInFlightException catch (error) {
      log('PaymentLinkClaim: ignored duplicate in-flight link');
      if (!mounted || !_isCurrentNavigation(epoch)) return;
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
      if (!mounted || !_isCurrentNavigation(epoch)) return;
      // A different network is a permanent property of the link, so there is
      // nothing to retry: clear the retry affordance and name the reason.
      setState(() {
        _page = PaymentLinksLocalPage.redeem;
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
      if (mounted && _isCurrentNavigation(epoch)) {
        setState(() {
          _page = PaymentLinksLocalPage.redeem;
          _longSyncLink = null;
          _retryLink = null;
          _redeemState = PaymentLinkRedeemVisualState.invalid;
        });
      }
    } catch (error) {
      log('PaymentLinkClaim: preparation failed type=${error.runtimeType}');
      if (mounted && _isCurrentNavigation(epoch)) {
        setState(() {
          _page = PaymentLinksLocalPage.redeem;
          _longSyncLink = null;
          _retryLink = link;
          _redeemState = PaymentLinkRedeemVisualState.paste;
        });
        if (kAppFormFactor == AppFormFactor.mobile) {
          _showError('Card balance could not be checked. Try again.');
        }
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
        await _releaseUnavailableClaim(refreshed);
        if (!mounted) return;
        setState(() {
          _receivedClaimSession = null;
          _receivedLink = null;
          _redeemState = PaymentLinkRedeemVisualState.paste;
          _page = PaymentLinksLocalPage.redeem;
        });
        return;
      }
      setState(() {
        _receivedClaimSession = refreshed;
        _receivedLink = refreshed.link;
      });
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
  /// only when neither the live session nor a recoverable Card still owns it.
  Future<void> _discardRefreshedClaim(PaymentLinkClaimSession refreshed) async {
    final directory = paymentLinkClaimWalletDirectoryName(refreshed.link);
    final live = _receivedClaimSession;
    final stillOwned =
        (live != null &&
            paymentLinkClaimWalletDirectoryName(live.link) == directory) ||
        _shouldKeepCard(refreshed);
    if (stillOwned) return;
    await _paymentLinkOperations.discardClaimSession(refreshed);
  }

  /// Backing out of a preview releases its prepared claim. A session
  /// left live would make a later account switch pull the user back into
  /// Redeem, and would hold the temporary claim wallet until route dispose.
  void _abandonReceivedPreview({bool goHome = false}) {
    if (_mobileNavigationLocked) return;
    _mobileNavigationEpoch++;
    final session = _receivedClaimSession;
    setState(() {
      _receivedClaimSession = null;
      _receivedLink = null;
      _receivedShowsBack = false;
    });
    if (session != null) {
      _releaseClaimSession(session, keepCard: _shouldKeepCard(session));
    }
    if (kAppFormFactor == AppFormFactor.mobile &&
        (goHome || !context.canPop())) {
      context.go('/home');
    } else {
      _showPage(PaymentLinksLocalPage.home);
    }
  }

  /// A Card retaining recovery material keeps its scanned claim wallet;
  /// an abandoned preview deletes it.
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
    final epoch = _mobileNavigationEpoch;
    final page = _page;
    final claimSession = _receivedClaimSession;
    await ref.read(paymentLinkClipboardProvider).clear();
    if (!mounted ||
        !_isCurrentNavigation(epoch) ||
        _page != page ||
        _operationInProgress ||
        !identical(_receivedClaimSession, claimSession)) {
      return;
    }
    if (claimSession != null) {
      await _paymentLinkOperations.discardClaimSession(claimSession);
      if (!mounted || !_isCurrentNavigation(epoch)) return;
    }
    _paymentLinkIntake.clearError();
    if (mounted) {
      setState(() {
        _receivedClaimSession = null;
        _longSyncLink = null;
        _retryLink = null;
        _claimStageActive = false;
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

  Future<void> _confirmMobileClaim() async {
    final link = _receivedLink;
    if (link == null || _operationInProgress || _choosingClaimAccount) return;
    final session = _receivedClaimSession;
    // Reconcile a failed submission before offering a different destination.
    if (session == null) {
      await _checkPaymentLink(link);
      return;
    }
    if (!session.canClaim) return;
    final accountState = ref.read(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    if (accountState == null || activeAccountUuid == null) return;
    if (session.isSetupClaim || accountState.accounts.length == 1) {
      _claimReceivedLink();
      return;
    }

    _choosingClaimAccount = true;
    try {
      final confirmed = await showPaymentLinkClaimAccountSheet(
        context: context,
        amountZatoshi: link.amountZatoshi,
        accounts: accountState.accounts,
        activeAccountUuid: activeAccountUuid,
        onConfirm: (uuid) => _prepareMobileClaimDestination(link, uuid),
      );
      if (!mounted || !confirmed || _receivedLink != link) return;
      _claimReceivedLink();
    } finally {
      _choosingClaimAccount = false;
    }
  }

  Future<void> _prepareMobileClaimDestination(
    VizorPaymentLink link,
    String accountUuid,
  ) async {
    if (!mounted || _receivedLink != link || _operationInProgress) {
      throw const PaymentLinkClaimDestinationChangedException();
    }
    final accountState = ref.read(accountProvider).value;
    if (accountState == null ||
        !accountState.accounts.any((account) => account.uuid == accountUuid)) {
      throw const PaymentLinkClaimDestinationChangedException();
    }
    final previousSession = _receivedClaimSession;
    if (accountState.activeAccountUuid == accountUuid &&
        previousSession?.destinationAccountUuid == accountUuid) {
      return;
    }
    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    PaymentLinkClaimSession? pendingSession = previousSession;
    setState(() {
      _operationInProgress = true;
      // This is an explicitly confirmed switch. Drop the old destination
      // before the account listener runs, keeping the card and its wallet for
      // preparation under the selected account (as confirmation refresh does).
      _receivedClaimSession = null;
    });
    try {
      if (accountState.activeAccountUuid != accountUuid) {
        await accountNotifier.switchAccount(accountUuid);
        unawaited(
          syncNotifier.refreshAfterAccountSwitch().catchError((Object error) {
            log(
              'PaymentLinkClaim: account refresh failed: ${error.runtimeType}',
            );
          }),
        );
      }
      if (!mounted ||
          ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        throw const PaymentLinkClaimDestinationChangedException();
      }
      final prepared = await _paymentLinkOperations.prepareClaim(
        link,
        allowLongSync: true,
      );
      pendingSession = prepared;
      if (!mounted) {
        throw const PaymentLinkClaimDestinationChangedException();
      }
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid ||
          prepared.destinationAccountUuid != accountUuid) {
        await _discardRefreshedClaim(prepared);
        pendingSession = null;
        throw const PaymentLinkClaimDestinationChangedException();
      }
      if (!prepared.canClaim && !prepared.waitingForFundingConfirmations) {
        await _releaseUnavailableClaim(prepared);
        pendingSession = null;
        if (!mounted) return;
        setState(() {
          _receivedLink = null;
          _receivedClaimSession = null;
          _redeemState = PaymentLinkRedeemVisualState.paste;
          _page = PaymentLinksLocalPage.redeem;
        });
        return;
      }
      setState(() => _receivedClaimSession = prepared);
      pendingSession = null;
    } catch (_) {
      if (mounted && _receivedClaimSession == null) {
        // Preparation may fail after the account switched. Preserve the
        // bearer link and shared claim wallet for retry or a later reopening.
        _keepClaimLinkForRetry(link);
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _operationInProgress = false);
      } else if (pendingSession != null) {
        if (_shouldKeepCard(pendingSession)) {
          await _paymentLinkOperations.retainPendingClaim(pendingSession);
        } else {
          await _paymentLinkOperations.discardClaimSession(pendingSession);
        }
      }
    }
  }

  void _claimReceivedLink() {
    final link = _receivedLink;
    final session = _receivedClaimSession;
    if (link == null || _operationInProgress) return;
    // A failed submission must be checked again before it can be retried:
    // the retained wallet may already contain a transaction to recover.
    if (session == null) {
      unawaited(_checkPaymentLink(link));
      return;
    }
    if (!session.canClaim) return;
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final submission = ref
        .read(paymentLinkClaimCoordinatorProvider)
        .submit(session);
    setState(() {
      _receivedShowsBack = false;
      _rememberReceivedLink(link);
      _setReceivedCardStatus(link.address, PaymentLinkReceivedStatus.receiving);
      _activeCardsTab = PaymentLinkCardsTab.received;
      // The coordinator owns the session once submission starts. Keep only
      // the card on mobile, so leaving the route cannot release its wallet.
      _receivedClaimSession = null;
      if (mobile) {
        _claimSubmissionInProgress = true;
        _operationInProgress = true;
      } else {
        _receivedLink = null;
        _page = PaymentLinksLocalPage.home;
      }
      _showHelp = false;
    });
    unawaited(_finishClaimSubmission(link, submission));
  }

  Future<void> _finishClaimSubmission(
    VizorPaymentLink link,
    Future<PaymentLinkClaimResult> submission,
  ) async {
    final epoch = _mobileNavigationEpoch;
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    try {
      final result = await submission;
      if (!mounted || !_isCurrentNavigation(epoch)) {
        if (mounted) {
          setState(() => _operationInProgress = false);
          unawaited(_refreshReceivedClaims());
        }
        return;
      }
      if (mobile) {
        setState(() {
          _operationInProgress = false;
          _receivedLink = null;
          _page = PaymentLinksLocalPage.home;
        });
        if (result.status == PaymentLinkClaimBroadcastStatus.broadcasted) {
          unawaited(AppHaptics.sendSuccess());
          context.go('/home');
        } else {
          // Pending or partial broadcast is not success. The Received row
          // already owns progress and recovery for these outcomes.
          showAppToast(
            context,
            'Claim result is not confirmed. Check its status.',
          );
        }
        unawaited(_refreshReceivedClaims());
        return;
      }
      showAppToast(
        context,
        result.status == PaymentLinkClaimBroadcastStatus.broadcasted
            ? 'Gift claim submitted'
            : 'Claim result is not confirmed. Check its status.',
      );
      unawaited(_refreshReceivedClaims());
    } on PaymentLinkClaimDestinationChangedException {
      if (!mounted || !_isCurrentNavigation(epoch)) {
        if (mounted) {
          setState(() => _operationInProgress = false);
          unawaited(_refreshReceivedClaims());
        }
        return;
      }
      if (mounted && _isCurrentNavigation(epoch)) {
        setState(() {
          _setReceivedCardStatus(
            link.address,
            PaymentLinkReceivedStatus.readyToClaim,
          );
          if (mobile) {
            _operationInProgress = false;
          } else {
            _redeemState = PaymentLinkRedeemVisualState.paste;
            _page = PaymentLinksLocalPage.redeem;
          }
        });
        _showError(
          mobile
              ? 'Receiving account changed. Try again to check this gift.'
              : 'Receiving account changed. Open the gift card again to continue.',
        );
      }
    } catch (_) {
      if (!mounted || !_isCurrentNavigation(epoch)) {
        if (mounted) {
          setState(() => _operationInProgress = false);
          unawaited(_refreshReceivedClaims());
        }
        return;
      }
      if (mounted && _isCurrentNavigation(epoch)) {
        if (mobile) setState(() => _operationInProgress = false);
        unawaited(_refreshReceivedClaims());
        _showError(
          mobile
              ? "Couldn't finish receiving this gift. Try again to check its status."
              : 'Gift card claim failed. It may still be waiting for confirmation '
                    'or may already be spent.',
        );
      }
    } finally {
      if (mounted && mobile) {
        setState(() => _claimSubmissionInProgress = false);
      }
    }
  }

  @override
  void _showError(String message) {
    showAppToast(
      context,
      message,
      iconName: AppIcons.warning,
      tone: AppToastTone.destructive,
    );
  }

  @override
  Widget build(BuildContext context) =>
      GiftCardTrackingScope(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
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

    final pricingEnabled = ref.watch(swapFeatureEnabledProvider);
    if (_page == PaymentLinksLocalPage.amount ||
        _page == PaymentLinksLocalPage.message ||
        _page == PaymentLinksLocalPage.review) {
      ref.listen<double?>(
        zecLiveUsdUnitPriceProvider,
        _handleZecUsdPriceChanged,
      );
    }
    final livePrice =
        (_page == PaymentLinksLocalPage.amount ||
            _page == PaymentLinksLocalPage.message ||
            _page == PaymentLinksLocalPage.review)
        ? ref.watch(zecLiveUsdUnitPriceProvider)
        : null;
    final amount = _amountZatoshi;
    // Keep the price subscription through amount edits and Review so clearing
    // the input does not restart the lookup or flash its loading state. The
    // group flow reads it for each card's fiat snapshot.
    final marketData =
        pricingEnabled &&
            (_page == PaymentLinksLocalPage.amount ||
                _page == PaymentLinksLocalPage.message ||
                _page == PaymentLinksLocalPage.review ||
                _page == PaymentLinksLocalPage.received ||
                _page == PaymentLinksLocalPage.bulk)
        ? ref.watch(zecHomeMarketDataStateProvider)
        : null;

    final amountFiatText = !pricingEnabled || amount == null
        ? null
        : amount == BigInt.zero
        ? r'$0.00'
        : fiatTextForZatoshi(
            amount,
            zecUsdUnitPrice: marketData?.displayData?.usdPrice,
          );
    final amountFiatLoading =
        amount != null &&
        amount > BigInt.zero &&
        (marketData?.isLoading ?? false);
    if (kAppFormFactor == AppFormFactor.mobile) {
      final mobileHardwareRequest = _hardwareFundingRequest;
      return PaymentLinksMobileBody(
        page: _page,
        navigationLocked: _mobileNavigationLocked,
        onCancelKeystone: _cancelHardwareFunding,
        redeemState: _redeemState,
        claimOutcome: _buildClaimOutcome(),
        operationInProgress: _operationInProgress,
        redeemActionLabel: _redeemActionLabel,
        redeemFromQrCode: _redeemFromQrCode,
        keystoneOverlay: mobileHardwareRequest == null
            ? null
            : _buildHardwareFundingOverlay(mobileHardwareRequest),
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
        amountCurrency: _amountCurrency,
        onAmountCurrencyChanged: _selectAmountCurrency,
        usdEnabled: _canEnterUsd(livePrice),
        usdDisabledReason: _usdDisabledReason,
        amountZecText: amount == null ? '' : formatZecAmount(amount),
        amountConversionText: _amountConversionText(amountFiatText),
        amountFiatText: amountFiatText,
        amountFiatLoading: amountFiatLoading,
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
        readyFiatText: _savedCardFiatText(_readyLink),
        readyCopyInProgress: _copyingLinkAddresses.contains(
          _readyLink?.address,
        ),
        fundingProgressByAddress: _fundingProgressByAddress,
        readyShowsBack: _readyShowsBack,
        receivedLink: _receivedLink,
        receivedFiatText: _savedCardFiatText(_receivedLink),
        receivedShowsBack: _receivedShowsBack,
        receivedClaimSession: _receivedClaimSession,
        claimPreparationLabel: _claimCheckLabel,
        linkWaitLabel: _estimatedLinkWaitLabel,
        claimWaitLabel: _estimatedClaimWaitLabel,
        availableSoonRemainingConfirmations:
            _linkAvailableSoonRemainingConfirmations,
        onShowPage: _showPage,
        onStartCreate: _startCreate,
        onRunRedeemAction: _runRedeemAction,
        onScanCard: _scanPaymentLink,
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
        onAbandonReceivedPreview: _abandonReceivedPreview,
        onReceivedHome: () => _abandonReceivedPreview(goHome: true),
        onClaimReceivedLink: _confirmMobileClaim,
      );
    }

    final currentPage = _buildCurrentPage(
      amountFiatText: amountFiatText,
      amountFiatLoading: amountFiatLoading,
    );
    final hardwareRequest = _hardwareFundingRequest;
    final hardwareBatch = _hardwareBatchSigning;
    final overlay = hardwareRequest != null
        ? _buildHardwareFundingOverlay(hardwareRequest)
        : hardwareBatch != null
        ? _buildHardwareBatchOverlay(hardwareBatch)
        : _exportConfirmMembers != null
        ? PaymentLinkBatchExportModal(
            onConfirm: () => unawaited(_confirmBatchExport()),
            onCancel: _cancelBatchExport,
          )
        : _longSyncLink != null
        ? PaymentLinkLongSyncWarningModal(
            onConfirm: _confirmLongSyncWarning,
            onCancel: _cancelLongSyncWarning,
          )
        : _removeConfirmRecord != null
        ? PaymentLinkConfirmModal(
            iconName: AppIcons.trash,
            title: kPaymentLinkRemoveCardTitle,
            body: kPaymentLinkClaimedElsewhereDescription,
            supporting: kPaymentLinkRemoveCardSupporting,
            confirmLabel: kPaymentLinkRemoveCardLabel,
            cancelLabel: 'Cancel',
            onConfirm: () => unawaited(_confirmRemoveReceivedCard()),
            onCancel: _cancelRemoveReceivedCard,
            confirmKey: const ValueKey(
              'payment_link_remove_card_confirm_button',
            ),
            cancelKey: const ValueKey('payment_link_remove_card_cancel_button'),
          )
        : null;
    final pane = overlay != null
        ? Stack(fit: StackFit.expand, children: [currentPage, overlay])
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

  String? get _claimCheckLabel {
    final link = _receivedLink;
    if (link == null ||
        !_operationInProgress ||
        _redeemState != PaymentLinkRedeemVisualState.loading) {
      return null;
    }
    final progress = ref.watch(
      giftCardCheckProgressProvider,
    )[paymentLinkClaimWalletDirectoryName(link)];
    // A complete stream event is not yet a prepared claim session. Keep the
    // waiting surface until prepareClaim installs its authoritative result.
    return progress?.label ?? 'Checking the gift…';
  }

  Widget _buildCurrentPage({
    required String? amountFiatText,
    required bool amountFiatLoading,
  }) {
    return switch (_page) {
      PaymentLinksLocalPage.home => _buildHome(),
      PaymentLinksLocalPage.batchDetail => _buildBatchDetail(),
      PaymentLinksLocalPage.bulk => _buildBulk(),
      PaymentLinksLocalPage.amount => _buildAmount(
        fiatText: amountFiatText,
        fiatLoading: amountFiatLoading,
      ),
      PaymentLinksLocalPage.message => _buildMessage(),
      PaymentLinksLocalPage.review => _buildReview(
        fiatText: amountFiatText,
        fiatLoading: amountFiatLoading,
      ),
      PaymentLinksLocalPage.ready => _buildReady(),
      PaymentLinksLocalPage.shareQr => _buildShareQr(),
      PaymentLinksLocalPage.redeem =>
        _redeemState == PaymentLinkRedeemVisualState.loading ||
                _outcomeLink != null ||
                _retryLink != null ||
                (_claimStageActive && _receivedLink != null)
            ? _buildReceived()
            : _buildClaimOutcome() ??
                  PaymentLinkRedeemDesktopView(
                    state: _redeemState,
                    onBack: () => _showPage(PaymentLinksLocalPage.home),
                    onPaste: _operationInProgress ? null : _runRedeemAction,
                    onScan: _scanPaymentLink,
                    scanEnabled: !_operationInProgress,
                    onClearClipboard: _operationInProgress
                        ? null
                        : _clearClipboard,
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
        'assets/illustrations/payment_links/payment_link_empty_card.webp',
        width: 243,
        height: 162,
        fit: BoxFit.contain,
        semanticLabel: 'Gift box',
      ),
      onBack: () => context.go('/home'),
      onShowHelp: _showHelpOverlay,
      onCreate: _startCreate,
      onCreateMultiple: _startBulkCreate,
      isLedger:
          _signerFor(ref.watch(accountProvider).value?.activeAccountUuid) ==
          HardwareSignerKind.ledger,
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
      onCreateMultiple: _startBulkCreate,
      isLedger:
          _signerFor(ref.watch(accountProvider).value?.activeAccountUuid) ==
          HardwareSignerKind.ledger,
      onRedeem: () => _showPage(PaymentLinksLocalPage.redeem),
      activeTab: _activeCardsTab,
      onTabSelected: (tab) => setState(() => _activeCardsTab = tab),
    );
  }

  /// The Gift Card grouping both form factors render.
  ///
  /// Created cards share Pending / Unused / Used groups on both form factors.
  /// Rows retain their detailed status and actions; received grouping is separate.
  List<PaymentLinkCardsSection> _cardsSections({
    required Widget Function(PaymentLinkRecoveryRecord record) recoveryRow,
    required Widget Function(PaymentLinkReceivedRecord record) receivedRow,
    List<Widget> emptyReceivedCards = const <Widget>[],
  }) {
    if (_activeCardsTab == PaymentLinkCardsTab.created) {
      final batches = <Widget>[];
      final pendingCards = <Widget>[];
      final unusedCards = <Widget>[];
      final usedCards = <Widget>[];
      final seenBatchIds = <String>{};
      for (final record in _visibleRecoveries) {
        if (kAppFormFactor == AppFormFactor.desktop && record.batchId != null) {
          if (!seenBatchIds.add(record.batchId!)) continue;
          final members =
              _visibleRecoveries
                  .where((candidate) => candidate.batchId == record.batchId)
                  .toList()
                ..sort(
                  (a, b) => (a.batchIndex ?? 0).compareTo(b.batchIndex ?? 0),
                );
          batches.add(_buildBatchRow(members));
          continue;
        }
        final fundingReady =
            _fundingProgressByAddress[record.link.address]?.isReady ?? false;
        final usage = ref
            .watch(giftCardUsageProvider(record.link.address))
            .value;
        final status = usage?.status ?? record.usage.status;
        final cards = switch ((fundingReady, status)) {
          (true, GiftCardUsageStatus.unused) => unusedCards,
          (true, GiftCardUsageStatus.spendDetected) => usedCards,
          (true, GiftCardUsageStatus.used) => usedCards,
          _ => pendingCards,
        };
        cards.add(recoveryRow(record));
      }
      return <PaymentLinkCardsSection>[
        if (batches.isNotEmpty)
          PaymentLinkCardsSection(label: 'Groups', cards: batches),
        if (pendingCards.isNotEmpty)
          PaymentLinkCardsSection(
            label: kPaymentLinkPendingSectionLabel,
            cards: pendingCards,
          ),
        if (unusedCards.isNotEmpty)
          PaymentLinkCardsSection(
            label: kPaymentLinkUnusedSectionLabel,
            cards: unusedCards,
          ),
        if (usedCards.isNotEmpty)
          PaymentLinkCardsSection(
            label: kPaymentLinkUsedSectionLabel,
            cards: usedCards,
          ),
      ];
    }
    // A Card another wallet claimed never reached this wallet, so it stays in
    // its own group, hidden or not, until the user removes it.
    final claimedElsewhereCards = _visibleReceivedCards
        .where((r) => r.canRemove)
        .toList();
    final receivedCards = _visibleReceivedCards
        .where((r) => !r.canRemove && !r.archived)
        .toList();
    final archivedCards = _visibleReceivedCards
        .where((r) => !r.canRemove && r.archived)
        .toList();
    return <PaymentLinkCardsSection>[
      if (receivedCards.isNotEmpty || claimedElsewhereCards.isEmpty)
        PaymentLinkCardsSection(
          label: kPaymentLinkReceivedTabLabel,
          cards: receivedCards.isNotEmpty
              ? receivedCards.map(receivedRow).toList()
              : emptyReceivedCards,
        ),
      if (claimedElsewhereCards.isNotEmpty)
        PaymentLinkCardsSection(
          label: kPaymentLinkClaimedElsewhereLabel,
          cards: claimedElsewhereCards.map(receivedRow).toList(),
        ),
      if (archivedCards.isNotEmpty)
        PaymentLinkCardsSection(
          label: 'Archived',
          header: PaymentLinkArchiveHeader(
            count: archivedCards.length,
            expanded: _showArchivedCards,
            onToggle: () =>
                setState(() => _showArchivedCards = !_showArchivedCards),
          ),
          cards: [if (_showArchivedCards) ...archivedCards.map(receivedRow)],
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

  /// The received Card's effective status and action, shared by the desktop
  /// and mobile rows. An in-flight submission the store has not caught up with
  /// reads as `Receiving...`.
  ({
    String statusText,
    String? actionLabel,
    VoidCallback? onAction,
    bool showLoader,
  })
  _receivedRowState(PaymentLinkReceivedRecord record) {
    // The Claimed elsewhere group names the state, so the row keeps two lines
    // and its trailing label is the action: nothing is left to claim.
    if (record.canRemove) {
      return (
        statusText: 'Remove',
        actionLabel: null,
        onAction: _operationInProgress
            ? null
            : () => unawaited(_requestRemoveReceivedCard(record)),
        showLoader: false,
      );
    }
    final submissionInProgress = ref
        .read(paymentLinkClaimCoordinatorProvider)
        .isSubmitting(record.address);
    final effectiveStatus = submissionInProgress
        ? PaymentLinkReceivedStatus.receiving
        : record.status;
    return (
      statusText: switch (effectiveStatus) {
        PaymentLinkReceivedStatus.readyToClaim => record.availability.label,
        PaymentLinkReceivedStatus.submitting => 'Checking result',
        PaymentLinkReceivedStatus.receiving =>
          (record.availability == PaymentLinkAvailability.checking ||
                  record.availability == PaymentLinkAvailability.rejected)
              ? 'Checking result'
              : 'Receiving…',
        PaymentLinkReceivedStatus.received => 'Received',
      },
      actionLabel:
          record.status == PaymentLinkReceivedStatus.received ||
              record.availability == PaymentLinkAvailability.unchecked ||
              record.availability == PaymentLinkAvailability.available
          ? null
          : record.archived
          ? 'View card'
          : 'Check status',
      onAction:
          (effectiveStatus == PaymentLinkReceivedStatus.readyToClaim ||
                  record.availability == PaymentLinkAvailability.checking ||
                  record.availability == PaymentLinkAvailability.rejected) &&
              effectiveStatus != PaymentLinkReceivedStatus.received &&
              record.claimLink != null &&
              !_operationInProgress
          ? () {
              if (!record.isClaimInFlight &&
                  !record.archived &&
                  (record.availability == PaymentLinkAvailability.noBalance ||
                      record.availability == PaymentLinkAvailability.failed)) {
                unawaited(_checkPaymentLink(record.claimLink!));
              } else {
                _openReceivedCard(record);
              }
            }
          : null,
      showLoader:
          effectiveStatus == PaymentLinkReceivedStatus.submitting ||
          effectiveStatus == PaymentLinkReceivedStatus.receiving,
    );
  }

  Widget _buildRecoveryRow(PaymentLinkRecoveryRecord record) {
    final state = _recoveryRowState(record);
    final actionsEnabled = state.canUseLink && !_operationInProgress;
    final copyEnabled =
        actionsEnabled && !_copyingLinkAddresses.contains(record.link.address);
    return PaymentLinkCardListRow(
      key: ValueKey('payment_link_recovery_${record.link.address}'),
      thumbnail: _cardThumbnail(record.link.presentation?.artworkId),
      amountText: hideAmountIfPrivacyMode(
        '${formatZecAmount(record.link.amountZatoshi)} ZEC',
        privacyModeEnabled: ref.watch(privacyModeProvider),
      ),
      dateText: _formatCardDate(record.link.createdAt),
      statusText: state.canUseLink ? null : state.statusText,
      onAction: null,
      showLinkActions: state.canUseLink,
      onCopyLink: copyEnabled ? () => _copyPaymentLink(record.link) : null,
      onShowQr: actionsEnabled ? () => _openShareQr(record) : null,
      showLoader: state.showLoader,
      usageStatus: state.canUseLink
          ? GiftCardUsageStatusView(
              address: record.link.address,
              inline: true,
              hideStableLabel: true,
            )
          : null,
    );
  }

  bool _batchMembersReady(List<PaymentLinkRecoveryRecord> members) {
    return isCompletePaymentLinkBatch(members) &&
        members.every(
          (record) =>
              record.fundingTxids == members.first.fundingTxids &&
              _recoveryRowState(record).canUseLink,
        );
  }

  static bool _isUsedStatus(GiftCardUsageStatus status) =>
      status == GiftCardUsageStatus.used ||
      status == GiftCardUsageStatus.spendDetected;

  Widget _buildBatchRow(List<PaymentLinkRecoveryRecord> members) {
    final first = members.first;
    final count = first.batchCount ?? members.length;
    final ready = _batchMembersReady(members);
    final statuses = [
      for (final record in members)
        ref.watch(giftCardUsageProvider(record.link.address)).value?.status ??
            record.usage.status,
    ];
    final usedCount = statuses.where(_isUsedStatus).length;
    final secondArtworkId = members.length > 1
        ? members[1].link.presentation?.artworkId
        : null;
    return PaymentLinkBatchListRow(
      key: ValueKey('payment_link_batch_${first.batchId}'),
      thumbnail: _cardThumbnail(first.link.presentation?.artworkId),
      // A mixed group shows its second design on the card behind.
      backThumbnail: secondArtworkId != first.link.presentation?.artworkId
          ? _cardThumbnail(secondArtworkId)
          : null,
      count: count,
      amountText: hideAmountIfPrivacyMode(
        '${formatZecAmount(first.link.amountZatoshi)} ZEC',
        privacyModeEnabled: ref.watch(privacyModeProvider),
      ),
      dateText: _formatCardDate(first.link.createdAt),
      // Before funding is read once, a batch is unknown rather than pending,
      // so the row does not flash a pending status on entry.
      statusText: !ready && !_fundingProgressChecked
          ? ''
          : ready
          ? switch (usedCount) {
              0 => 'Ready to share',
              _ when usedCount == count => 'All used',
              _ => '$usedCount of $count used',
            }
          : switch (_batchPendingKind(members)) {
              PaymentLinkBatchPendingKind.incomplete =>
                'Some cards aren’t ready',
              PaymentLinkBatchPendingKind.unconfirmedBroadcast =>
                'Payment status pending',
              PaymentLinkBatchPendingKind.confirming => 'Confirming payment',
            },
      onOpen: () => _openBatchDetail(first.batchId!),
    );
  }

  PaymentLinkBatchPendingKind _batchPendingKind(
    List<PaymentLinkRecoveryRecord> members,
  ) {
    if (members.isEmpty || members.length != members.first.batchCount) {
      return PaymentLinkBatchPendingKind.incomplete;
    }
    // Funded members only wait for their confirmation; a draft member means
    // the broadcast result is still unknown.
    return members.any(
          (record) => record.state == PaymentLinkRecoveryState.draft,
        )
        ? PaymentLinkBatchPendingKind.unconfirmedBroadcast
        : PaymentLinkBatchPendingKind.confirming;
  }

  Future<void> _checkBatchStatus() async {
    setState(() => _checkingBatchStatus = true);
    try {
      // Reloading reconciles an ambiguous batch, then refreshes its progress.
      await _loadRecoveries();
    } finally {
      if (mounted) setState(() => _checkingBatchStatus = false);
    }
  }

  void _openBatchDetail(String batchId) {
    _selectedBatchId = batchId;
    _showPage(PaymentLinksLocalPage.batchDetail);
  }

  Widget _buildBatchDetail() {
    final id = _selectedBatchId;
    if (id == null) return _buildHome();
    final members =
        _visibleRecoveries.where((record) => record.batchId == id).toList()
          ..sort((a, b) => (a.batchIndex ?? 0).compareTo(b.batchIndex ?? 0));
    if (members.isEmpty) {
      // Not loaded at all (a failed reload): show the list until it is.
      if (_initialCardsLoaded && !_openBatchLoaded) return _buildHome();
      return PaymentLinkPane(
        backLabel: 'Gift Cards',
        onBack: () => _showPage(PaymentLinksLocalPage.home),
        child: Center(
          child: _initialCardsLoaded
              ? Text(
                  'This group belongs to another account. Switch accounts to view it.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final first = members.first;
    final ready = _batchMembersReady(members);
    final privacyMode = ref.watch(privacyModeProvider);
    GiftCardUsage usageOf(PaymentLinkRecoveryRecord record) =>
        ref.watch(giftCardUsageProvider(record.link.address)).value ??
        record.usage;
    final tracking = ref.watch(giftCardTrackingStateProvider);
    final lastChecked = members
        .map((record) => usageOf(record).checkedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, checked) =>
              latest == null || checked.isAfter(latest) ? checked : latest,
        );
    // Grouped like the created-card list: cards whose use is not known yet,
    // then unused, then used.
    final pendingCards = <Widget>[];
    final unusedCards = <Widget>[];
    final usedCards = <Widget>[];
    for (final record in members) {
      final usage = usageOf(record);
      final used = _isUsedStatus(usage.status);
      final pending = usage.status == GiftCardUsageStatus.unknown;
      (used
              ? usedCards
              : pending
              ? pendingCards
              : unusedCards)
          .add(
            PaymentLinkBatchMemberRow(
              key: ValueKey('payment_link_batch_card_${record.batchIndex}'),
              index: record.batchIndex ?? 0,
              artwork: PaymentLinkCardArtwork.fromProtocolId(
                record.link.presentation?.artworkId,
              ),
              statusLabel: usage.label,
              used: used,
              // The section already says Unused or Used; anything else is
              // spelled out on the row.
              note: pending || usage.status == GiftCardUsageStatus.spendDetected
                  ? usage.label
                  : null,
              updateFailed:
                  !usage.cleaned &&
                  !tracking.checking &&
                  tracking.failedFor(record.link.address),
              onCopyLink: !_copyingLinkAddresses.contains(record.link.address)
                  ? () => _copyPaymentLink(record.link)
                  : null,
              onShowQr: () => _openShareQr(record),
            ),
          );
    }
    final artworks = [
      for (final record in members)
        PaymentLinkCardArtwork.fromProtocolId(
          record.link.presentation?.artworkId,
        ),
    ];
    return PaymentLinkBatchDetailDesktopView(
      count: first.batchCount ?? members.length,
      artwork: artworks.first,
      backArtworks: artworks.toSet().length > 1
          ? artworks.sublist(1)
          : const [],
      amountPerCardText: hideAmountIfPrivacyMode(
        formatZecAmount(first.link.amountZatoshi),
        privacyModeEnabled: privacyMode,
        denomination: '',
      ),
      dateText: _formatCardDate(first.link.createdAt),
      ready: ready,
      justCreated: ready && id == _justCreatedBatchId,
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      onExport: ready && !_exportingBatchIds.contains(id)
          ? () => _requestBatchExport(members)
          : null,
      onCheckStatus: _checkingBatchStatus
          ? null
          : () => unawaited(_checkBatchStatus()),
      pendingKind: _batchPendingKind(members),
      usageActivity: PaymentLinkBatchUsageActivity(
        checking: tracking.checking,
        failed:
            tracking.failed ||
            members.any((record) => tracking.failedFor(record.link.address)),
        checkedText: lastChecked == null ? null : _checkedAgoText(lastChecked),
      ),
      // Only shown once every card is ready to share.
      sections: [
        PaymentLinkCardsSection(
          label: kPaymentLinkPendingSectionLabel,
          cards: pendingCards,
        ),
        PaymentLinkCardsSection(
          label: kPaymentLinkUnusedSectionLabel,
          cards: unusedCards,
        ),
        PaymentLinkCardsSection(
          label: kPaymentLinkUsedSectionLabel,
          cards: usedCards,
        ),
      ],
    );
  }

  String _checkedAgoText(DateTime checkedAt) {
    final elapsed = DateTime.now().toUtc().difference(checkedAt.toUtc());
    if (elapsed.inMinutes < 1) return 'Checked just now';
    if (elapsed.inHours < 1) return 'Checked ${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return 'Checked ${elapsed.inHours}h ago';
    return 'Checked ${_formatCardDate(checkedAt.toLocal())}';
  }

  void _requestBatchExport(List<PaymentLinkRecoveryRecord> members) {
    if (!_batchMembersReady(members) ||
        _exportingBatchIds.contains(members.first.batchId)) {
      _showError('All cards must be ready before exporting links.');
      return;
    }
    setState(() => _exportConfirmMembers = members);
  }

  void _cancelBatchExport() => setState(() => _exportConfirmMembers = null);

  Future<void> _confirmBatchExport() async {
    final members = _exportConfirmMembers;
    if (members == null) return;
    setState(() => _exportConfirmMembers = null);
    final id = members.first.batchId!;
    final currentAccount = ref.read(accountProvider).value?.activeAccountUuid;
    final latest = _recoveries.where((record) => record.batchId == id).toList();
    if (currentAccount != members.first.sourceAccountUuid ||
        !_batchMembersReady(latest)) {
      _showError(
        'The account or card status changed. Check the cards and try again.',
      );
      return;
    }
    setState(() => _exportingBatchIds.add(id));
    try {
      final saved = await exportPaymentLinkBatchCsv(latest);
      if (saved && mounted) showAppToast(context, 'Gift card links saved');
    } catch (error) {
      if (mounted) _showError('Gift card links could not be saved. Try again.');
      log('PaymentLinksScreen: batch export failed: $error');
    } finally {
      if (mounted) setState(() => _exportingBatchIds.remove(id));
    }
  }

  Widget _buildMobileRecoveryRow(PaymentLinkRecoveryRecord record) {
    final state = _recoveryRowState(record);
    final actionsEnabled = state.canUseLink && !_operationInProgress;
    final copyEnabled =
        actionsEnabled && !_copyingLinkAddresses.contains(record.link.address);
    return PaymentLinkCardListMobileRow(
      key: ValueKey('payment_link_mobile_recovery_${record.link.address}'),
      thumbnail: _cardThumbnail(record.link.presentation?.artworkId),
      amountText: hideAmountIfPrivacyMode(
        '${formatZecAmount(record.link.amountZatoshi)} ZEC',
        privacyModeEnabled: ref.watch(privacyModeProvider),
      ),
      dateText: _formatCardDate(record.link.createdAt),
      statusText: state.canUseLink ? null : state.statusText,
      showLinkActions: state.canUseLink,
      onCopyLink: copyEnabled ? () => _copyPaymentLink(record.link) : null,
      onShowQr: actionsEnabled ? () => _openShareQr(record) : null,
      showLoader: state.showLoader,
      metadata: state.canUseLink
          ? GiftCardUsageStatusView(
              address: record.link.address,
              inline: true,
              dateText: _formatCardDate(record.link.createdAt),
              hideStableLabel: true,
            )
          : null,
    );
  }

  Widget _cardThumbnail(String? artworkId, {bool dimmed = false}) {
    final image = Image.asset(
      PaymentLinkCardArtwork.fromProtocolId(artworkId).assetPath,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
    return dimmed ? PaymentLinkDimmedArtwork(child: image) : image;
  }

  Future<void> _openShareQr(PaymentLinkRecoveryRecord record) async {
    if (_operationInProgress || _preparingShareQr) return;
    _preparingShareQr = true;
    final epoch = _mobileNavigationEpoch;
    late final String shareData;
    try {
      shareData = (await preparePaymentLinkShareUri(record.link)).toString();
    } catch (_) {
      if (mounted && epoch == _mobileNavigationEpoch) {
        _showError('Gift link could not be shared.');
      }
      return;
    } finally {
      _preparingShareQr = false;
    }
    if (!mounted || epoch != _mobileNavigationEpoch) return;
    if (kAppFormFactor == AppFormFactor.mobile) {
      unawaited(
        showAppMobileSheet<void>(
          context: context,
          builder: (sheetContext) => PaymentLinkShareSheet(
            artwork: PaymentLinkCardArtwork.fromProtocolId(
              record.link.presentation?.artworkId,
            ),
            link: shareData,
            onShare: (png, origin) =>
                _sharePaymentLinkQr(record.link, png, origin),
            onShareError: () {
              if (mounted) {
                _showError(
                  "Couldn't share this gift card. Copy the link instead.",
                );
              }
            },
            onCopyLink: () => _copyPaymentLink(record.link),
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      );
      return;
    }
    setState(() {
      _shareQrRecord = record;
      _shareQrData = shareData;
      _justCreatedBatchId = null;
      _page = PaymentLinksLocalPage.shareQr;
      _showHelp = false;
      _longSyncLink = null;
    });
  }

  Widget _buildShareQr() {
    final record = _shareQrRecord;
    if (record == null) return _buildHome();
    final saving = _savingQrAddresses.contains(record.link.address);
    final copying = _copyingLinkAddresses.contains(record.link.address);
    return PaymentLinkShareQrDesktopView(
      shareCardKey: _shareQrCardKey,
      artwork: PaymentLinkCardArtwork.fromProtocolId(
        record.link.presentation?.artworkId,
      ),
      qrData: _shareQrData!,
      onBack: () => _showPage(
        _shareQrRecord?.batchId == null
            ? PaymentLinksLocalPage.home
            : PaymentLinksLocalPage.batchDetail,
      ),
      onSaveQr: _operationInProgress || saving
          ? null
          : () => _savePaymentLinkQr(record),
      onCopyLink: _operationInProgress || copying
          ? null
          : () => _copyPaymentLink(record.link),
      saveLabel: saving ? 'Saving…' : 'Save QR code',
      copyLabel: copying ? 'Copying…' : 'Copy link',
    );
  }

  Future<void> _savePaymentLinkQr(PaymentLinkRecoveryRecord record) async {
    if (_operationInProgress ||
        _savingQrAddresses.contains(record.link.address)) {
      return;
    }
    final pixelRatio = max(3.0, View.of(context).devicePixelRatio);
    setState(() => _savingQrAddresses.add(record.link.address));
    try {
      final png = await capturePaymentLinkQr(
        _shareQrCardKey,
        pixelRatio: pixelRatio,
      );
      final saved = await ref
          .read(paymentLinkQrImageSaverProvider)
          .savePng(png);
      if (!mounted || !saved) return;
      try {
        await ref
            .read(paymentLinkOperationsProvider)
            .markCreatedLinkShared(record.link);
        await _loadRecoveries(showError: false);
        if (mounted) showAppToast(context, 'Gift card QR saved');
      } catch (_) {
        if (mounted) {
          _showError(
            'Gift card QR saved, but its status could not be updated.',
          );
        }
      }
    } catch (_) {
      if (mounted) _showError('Gift card QR could not be saved.');
    } finally {
      if (mounted) {
        setState(() => _savingQrAddresses.remove(record.link.address));
      }
    }
  }

  Future<void> _sharePaymentLinkQr(
    VizorPaymentLink link,
    Uint8List png,
    Rect origin,
  ) async {
    if (!mounted ||
        _operationInProgress ||
        !_sharingQrAddresses.add(link.address)) {
      return;
    }
    final share = ref.read(paymentLinkQrShareHandlerProvider);
    try {
      final shared = await share(png: png, sharePositionOrigin: origin);
      if (!shared) return;
      try {
        await _paymentLinkOperations.markCreatedLinkShared(link);
        if (mounted) await _loadRecoveries(showError: false);
      } catch (_) {
        if (mounted) {
          _showError('Gift card shared, but its status could not be updated.');
        }
      }
    } finally {
      _sharingQrAddresses.remove(link.address);
    }
  }

  Widget _buildReceivedRow(PaymentLinkReceivedRecord record) {
    final state = _receivedRowState(record);
    return PaymentLinkCardListRow(
      key: ValueKey('payment_link_received_${record.address}'),
      thumbnail: _cardThumbnail(record.artworkId, dimmed: record.canRemove),
      amountText: hideAmountIfPrivacyMode(
        '${formatZecAmount(record.amountZatoshi)} ZEC',
        privacyModeEnabled: ref.watch(privacyModeProvider),
      ),
      dateText: _formatCardDate(record.createdAt),
      statusText: state.statusText,
      actionLabel: state.actionLabel,
      onAction: state.onAction,
      showLoader: state.showLoader,
    );
  }

  Widget _buildMobileReceivedRow(PaymentLinkReceivedRecord record) {
    final state = _receivedRowState(record);
    return PaymentLinkCardListMobileRow(
      key: ValueKey('payment_link_mobile_received_${record.address}'),
      thumbnail: _cardThumbnail(record.artworkId, dimmed: record.canRemove),
      amountText: hideAmountIfPrivacyMode(
        '${formatZecAmount(record.amountZatoshi)} ZEC',
        privacyModeEnabled: ref.watch(privacyModeProvider),
      ),
      dateText: _formatCardDate(record.createdAt),
      statusText: state.statusText,
      actionLabel: state.actionLabel,
      onAction: state.onAction,
      showLoader: state.showLoader,
    );
  }

  Widget _buildAmount({required String? fiatText, required bool fiatLoading}) {
    final maxAmountText = _maxAmountText;
    return PaymentLinkAmountDesktopView(
      state: _amountVisualState,
      card: PaymentLinkAmountCard(
        artwork: _selectedArtwork,
        amountController: _amountController,
        amountFocusNode: _amountFocusNode,
        currency: _amountCurrency,
        onCurrencyChanged: _selectAmountCurrency,
        usdEnabled: _canEnterUsd(ref.read(zecLiveUsdUnitPriceProvider)),
        usdDisabledReason: _usdDisabledReason,
        onAmountChanged: _handleAmountChanged,
        supportingText: _amountConversionText(fiatText),
        supportingLoading: !_amountInputIsUsd && fiatLoading,
        maxAmountText: maxAmountText,
        onUseMax: maxAmountText == null ? null : _useMaxAmount,
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
        onVisibleSideChanged: _focusVisibleMessageEditor,
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

  Widget _buildReview({required String? fiatText, required bool fiatLoading}) {
    final message = _messageController.text.trim();
    final front = PaymentLinkGiftCard(
      artwork: _selectedArtwork,
      amountText: _amountZatoshi == null
          ? ''
          : formatZecAmount(_amountZatoshi!),
      supportingText: fiatText,
      supportingLoading: fiatLoading,
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
      onConfirm:
          _operationInProgress ||
              (_pendingFundingMetadata == null && !_canContinueAmount)
          ? null
          : _pendingFundingMetadata == null
          ? _createFundedLink
          : _retryFundingMetadata,
      onStepSelected: _operationInProgress ? null : _selectWizardStep,
      confirmLabel: _operationInProgress
          ? _pendingFundingMetadata == null
                ? 'Creating…'
                : 'Saving…'
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
    final copying = _copyingLinkAddresses.contains(link.address);
    final front = PaymentLinkGiftCard(
      artwork: artwork,
      amountText: amountText,
      supportingText: _savedCardFiatText(link),
      showCaret: false,
    );
    final card = hasMessage
        ? PaymentLinkCardFlip(
            showBack: _readyShowsBack,
            front: front,
            back: PaymentLinkGiftCard(
              artwork: artwork,
              showBack: true,
              message: message,
            ),
          )
        : front;
    return PaymentLinkReadyDesktopView(
      state: !readyToShare
          ? PaymentLinkReadyVisualState.waiting
          : PaymentLinkReadyVisualState.ready,
      card: card,
      usageStatus: GiftCardUsageStatusView(
        address: link.address,
        showCheckedAt: true,
      ),
      decoration: const PaymentLinkConfetti(),
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      onCopy: !readyToShare || _operationInProgress || copying
          ? null
          : () => _copyPaymentLink(link),
      onCardTap: readyToShare && hasMessage
          ? () => setState(() => _readyShowsBack = !_readyShowsBack)
          : null,
      onReturnHome: () => _showPage(PaymentLinksLocalPage.home),
      waitingStatusLabel: _estimatedLinkWaitLabel(fundingProgress),
      copyLabel: copying ? 'Copying…' : 'Copy link',
    );
  }

  String? _savedCardFiatText(VizorPaymentLink? link) {
    final snapshot = link?.presentation?.fiatSnapshot;
    if (snapshot == null || !ref.watch(swapFeatureEnabledProvider)) {
      return null;
    }
    return swapFormatCompactFiatValue(snapshot.amount);
  }

  Widget _buildReceived() {
    final loading =
        _page == PaymentLinksLocalPage.redeem &&
        _redeemState == PaymentLinkRedeemVisualState.loading;
    final outcome = !loading && _page == PaymentLinksLocalPage.redeem;
    final link = outcome
        ? _outcomeLink ?? _retryLink ?? _receivedLink
        : _receivedLink;
    if (link == null && !loading) return _buildHome();
    final artwork = PaymentLinkCardArtwork.fromProtocolId(
      link?.presentation?.artworkId,
    );
    final message = link?.presentation?.message ?? '';
    final hasMessage = message.isNotEmpty;
    final front = loading || outcome
        ? const PaymentLinkLoadingCard()
        : PaymentLinkGiftCard(
            artwork: artwork,
            amountText: formatZecAmount(link!.amountZatoshi),
            supportingText: _savedCardFiatText(link),
            showCaret: false,
          );
    final card = !loading && !outcome && hasMessage
        ? PaymentLinkCardFlip(
            showBack: _receivedShowsBack,
            front: front,
            back: PaymentLinkGiftCard(
              artwork: artwork,
              showBack: true,
              message: message,
            ),
          )
        : front;
    final session = _receivedClaimSession;
    final checkLabel = _claimCheckLabel;
    return PaymentLinkReceivedDesktopView(
      state: loading
          ? PaymentLinkClaimDesktopState.loading
          : outcome
          ? PaymentLinkClaimDesktopState.outcome
          : checkLabel != null
          ? PaymentLinkClaimDesktopState.checking
          : (session?.waitingForFundingConfirmations ?? false)
          ? PaymentLinkClaimDesktopState.waiting
          : PaymentLinkClaimDesktopState.ready,
      backLabel: loading || outcome
          ? 'My Cards'
          : checkLabel != null ||
                (session?.waitingForFundingConfirmations ?? false)
          ? 'Home'
          : 'Cards',
      waitingStatusLabel:
          checkLabel ??
          ((session?.waitingForFundingConfirmations ?? false)
              ? _estimatedClaimWaitLabel(session!)
              : 'Checking the gift…'),
      card: card,
      statusContent: outcome
          ? _buildClaimOutcome(embedded: true) ?? _buildPreparationResult()
          : null,
      decoration: const PaymentLinkConfetti(),
      onBack: _abandonReceivedPreview,
      onClaim: _operationInProgress ? null : _claimReceivedLink,
      onRevealMessage: hasMessage
          ? () => setState(() => _receivedShowsBack = !_receivedShowsBack)
          : null,
      claimLabel: _operationInProgress ? 'Claiming…' : 'Claim the gift card',
    );
  }

  Widget _buildPreparationResult() {
    if (_longSyncLink != null) return const SizedBox.shrink();
    final invalid = _redeemState == PaymentLinkRedeemVisualState.invalid;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_retryLink != null)
          Text(
            'Card balance could not be checked. Try again.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          )
        else if (invalid) ...[
          Text(
            kPaymentLinkInvalidTitle,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.destructive,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kPaymentLinkInvalidSubtitle,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        IntrinsicWidth(
          child: AppButton(
            onPressed: _operationInProgress ? null : _runRedeemAction,
            growWithContent: true,
            constrainContent: true,
            child: Text(_redeemActionLabel),
          ),
        ),
        if (invalid) ...[
          const SizedBox(height: AppSpacing.sm),
          PaymentLinkTextAction(
            label: kPaymentLinkClearClipboardLabel,
            onTap: _clearClipboard,
          ),
        ],
      ],
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

class _PaymentLinkHardwareFundingRequest {
  const _PaymentLinkHardwareFundingRequest({
    required this.amountZatoshi,
    required this.sourceAccountUuid,
    required this.presentation,
    required this.signerKind,
  });

  final HardwareSignerKind? signerKind;
  final BigInt amountZatoshi;
  final String sourceAccountUuid;
  final PaymentLinkPresentation presentation;
}
