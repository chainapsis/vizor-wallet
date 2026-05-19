import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../domain/near_intents_one_click_swap_provider.dart';
import '../domain/zip321_payment_request.dart';
import '../models/swap_prototype_models.dart';
import '../../../providers/account_provider.dart';
import 'swap_deposit_sender.dart';
import 'swap_failure_policy.dart';
import 'swap_max_amount_estimator.dart';
import 'swap_shielding_service.dart';
import 'swap_session_store.dart';
import 'swap_zec_staging_address_service.dart';

const _oneClickBaseUrl = String.fromEnvironment(
  'ZCASH_SWAP_1CLICK_BASE_URL',
  defaultValue: 'https://config-lambda.keplr.app/api/near-intents/1click',
);

final swapIntentProvider = Provider<SwapProvider>((ref) {
  return NearIntentsOneClickSwapProvider(baseUri: Uri.parse(_oneClickBaseUrl));
});

final swapStatusPollIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 20);
});

final swapShieldStatusPollIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 5);
});

final swapPriceRefreshIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 30);
});

const _liveFundsEnabled = bool.fromEnvironment(
  'ZCASH_SWAP_ENABLE_LIVE_FUNDS',
  defaultValue: true,
);

final swapLiveFundsEnabledProvider = Provider<bool>((ref) {
  return _liveFundsEnabled;
});

final swapInitialIntentsProvider = Provider<List<SwapPrototypeIntent>>((ref) {
  return const [];
});

final swapInitialExternalRequestsProvider = Provider<List<SwapExternalRequest>>(
  (ref) {
    return const [];
  },
);

class SwapPrototypeNotifier extends Notifier<SwapPrototypeState> {
  var _quoteGeneration = 0;
  var _statusRefreshInFlight = false;

  String? get _activeAccountUuidOrNull =>
      ref.read(accountProvider).value?.activeAccountUuid;

  String? _accountUuidForIntent(SwapPrototypeIntent intent) {
    final activeAccountUuid = _activeAccountUuidOrNull;
    if (activeAccountUuid == null || intent.accountUuid != activeAccountUuid) {
      return null;
    }
    return activeAccountUuid;
  }

  @override
  SwapPrototypeState build() {
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next) return;
        if (previous != null) {
          unawaited(_persistCurrentIntents(accountUuid: previous));
        }
        _clearAccountScopedTransientState();
        unawaited(
          _restorePersistedIntents(accountUuid: next, replaceExisting: true),
        );
      },
    );
    final pollInterval = ref.watch(swapStatusPollIntervalProvider);
    final pollTimer = Timer.periodic(pollInterval, (_) {
      unawaited(refreshOpenIntentStatuses());
    });
    ref.onDispose(pollTimer.cancel);
    final shieldPollInterval = ref.watch(swapShieldStatusPollIntervalProvider);
    final shieldPollTimer = Timer.periodic(shieldPollInterval, (_) {
      unawaited(_refreshShieldingConfirmations());
    });
    ref.onDispose(shieldPollTimer.cancel);
    final priceRefreshInterval = ref.watch(swapPriceRefreshIntervalProvider);
    final priceRefreshTimer = Timer.periodic(priceRefreshInterval, (_) {
      unawaited(_loadSupportedExternalAssets(forceRefreshPrices: true));
    });
    ref.onDispose(priceRefreshTimer.cancel);
    unawaited(_restorePersistedDraft());
    unawaited(_loadSupportedExternalAssets());
    unawaited(_restorePersistedIntents(accountUuid: _activeAccountUuidOrNull));
    final initialIntents = ref.watch(swapInitialIntentsProvider);
    final initialRequests = ref.watch(swapInitialExternalRequestsProvider);
    return const SwapPrototypeState(
      direction: SwapDirection.zecToExternal,
      amountText: '',
      destinationText: '',
      externalAsset: SwapAsset.usdc,
      reviewVisible: false,
      intents: [],
      externalRequests: [],
      requestImportText: '',
    ).copyWith(
      intents: initialIntents,
      externalRequests: initialRequests,
      selectedIntentId: initialIntents.isEmpty ? null : initialIntents.first.id,
      selectedRequestId: initialRequests.isEmpty
          ? null
          : initialRequests.first.id,
    );
  }

  void selectDirection(SwapDirection direction) {
    _clearReviewState();
    state = state.copyWith(direction: direction, reviewVisible: false);
    unawaited(_persistDraft(_currentDraftSnapshot));
  }

  void toggleDirection() {
    final currentQuote = state.quote;
    final nextDirection = state.direction.toggled;
    final nextAmountText = currentQuote == null
        ? state.amountText
        : currentQuote.receiveAsset.formatAmount(currentQuote.receiveAmount);

    _clearReviewState();
    state = state.copyWith(
      direction: nextDirection,
      amountText: nextAmountText,
      reviewVisible: false,
    );
    unawaited(_persistDraft(_currentDraftSnapshot));
  }

  void updateAmount(String value) {
    _clearReviewState();
    state = state.copyWith(
      amountText: value,
      reviewVisible: false,
      clearMaxAmountError: true,
    );
  }

  void updateDestination(String value) {
    _clearReviewState();
    state = state.copyWith(
      destinationText: value,
      reviewVisible: false,
      clearMaxAmountError: true,
    );
  }

  void selectExternalAsset(SwapAsset asset) {
    final supportedAsset = _supportedAssetFor(
      asset,
      state.supportedExternalAssets,
    );
    if (supportedAsset == null) return;
    _clearReviewState();
    state = state.copyWith(externalAsset: supportedAsset, reviewVisible: false);
    unawaited(_persistDraft(_currentDraftSnapshot));
  }

  void updateSlippageBps(int value) {
    final normalized = value.clamp(10, 500).toInt();
    _clearReviewState();
    state = state.copyWith(
      slippageBps: normalized,
      reviewVisible: false,
      clearQuoteError: true,
      clearStatusError: true,
    );
    unawaited(_persistDraft(_currentDraftSnapshot));
  }

  Future<void> useMaxZecAmount() async {
    if (!state.direction.sendsZec) return;
    if (state.maxAmountLoading) {
      log('SwapMaxAmount: duplicate max request ignored');
      return;
    }

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) {
      state = state.copyWith(maxAmountError: 'No active account');
      return;
    }

    _clearReviewState();
    state = state.copyWith(
      maxAmountLoading: true,
      reviewVisible: false,
      clearMaxAmountError: true,
      clearQuoteError: true,
      clearStatusError: true,
    );

    try {
      final maxZatoshi = await ref
          .read(swapMaxAmountEstimatorProvider)
          .estimateMaxZecSellAmount(accountUuid: accountUuid);
      if (maxZatoshi <= BigInt.zero) {
        state = state.copyWith(
          maxAmountLoading: false,
          maxAmountError: 'Insufficient shielded balance to cover fee',
        );
        return;
      }
      final amountText = ZecAmount.fromZatoshi(maxZatoshi).pretty().amountText;
      log('SwapMaxAmount: applied amount=$amountText');
      state = state.copyWith(
        amountText: amountText,
        maxAmountLoading: false,
        reviewVisible: false,
        clearReview: true,
        clearMaxAmountError: true,
        clearQuoteError: true,
        clearStatusError: true,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      state = state.copyWith(
        maxAmountLoading: false,
        maxAmountError: msg.contains('insufficient')
            ? 'Insufficient shielded balance to cover fee'
            : 'Max amount unavailable',
      );
      log('SwapMaxAmount: estimate failed error=$e');
    }
  }

  Future<void> _loadSupportedExternalAssets({
    bool forceRefreshPrices = false,
  }) async {
    try {
      final provider = ref.read(swapIntentProvider);
      final pricingProvider = provider is SwapPricingProvider
          ? provider as SwapPricingProvider
          : null;
      final pricing = pricingProvider == null
          ? null
          : await pricingProvider.loadPricingSnapshot(
              forceRefresh: forceRefreshPrices,
            );
      final liveAssets = pricing?.supportedExternalAssets.isNotEmpty == true
          ? pricing!.supportedExternalAssets
          : await provider.listSupportedExternalAssets();
      final supported = [
        for (final asset in liveAssets)
          if (asset != SwapAsset.zec) asset,
      ];
      if (supported.isEmpty) return;
      final selected =
          _supportedAssetFor(state.externalAsset, supported) ?? supported.first;
      final selectedChanged = selected != state.externalAsset;
      state = state.copyWith(
        supportedExternalAssets: supported,
        indicativeExternalPerZec:
            pricing?.externalPerZec ?? state.indicativeExternalPerZec,
        externalAsset: selected,
        reviewVisible: selectedChanged ? false : state.reviewVisible,
        clearReview: selectedChanged,
        clearQuoteError: true,
      );
    } catch (_) {
      // Keep the static fallback so the prototype remains usable offline.
    }
  }

  Future<void> showReview() async {
    if (!state.canReviewQuote) return;

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final amount = state.sellAmount;
    if (accountUuid == null || amount == null) {
      return;
    }

    final direction = state.direction;
    final externalAsset = state.externalAsset;
    final userExternalAddress = state.destinationText;
    final generation = ++_quoteGeneration;
    final draft = _currentDraftSnapshot;

    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: true,
      clearReview: true,
      clearQuoteError: true,
    );

    try {
      await _persistDraft(draft);
      final stagingAddress = await ref
          .read(swapZecStagingAddressServiceProvider)
          .prepareForQuote(accountUuid: accountUuid);
      final addressPlan = stagingAddress.toAddressPlan(
        direction: direction,
        externalAsset: externalAsset,
        userExternalAddress: userExternalAddress,
      );
      final quote = await ref
          .read(swapIntentProvider)
          .quote(
            addressPlan.toQuoteRequest(
              sellAmount: amount,
              sellAmountText: state.amountText.trim(),
              slippageBps: state.slippageBps,
            ),
          );
      if (generation != _quoteGeneration) {
        return;
      }
      if (!_isAccountActive(accountUuid)) {
        return;
      }

      state = state.copyWith(
        reviewVisible: true,
        reviewQuote: quote,
        reviewAddressPlan: addressPlan,
        reviewAccountUuid: accountUuid,
        quoteLoading: false,
        quoteExpired: false,
        clearQuoteError: true,
      );
    } catch (e) {
      if (generation != _quoteGeneration) return;
      state = state.copyWith(
        reviewVisible: false,
        quoteLoading: false,
        quoteError: _friendlyQuoteError(e),
        clearReview: true,
      );
    }
  }

  Future<bool> startIntent() async {
    final quote = state.reviewQuote;
    final addressPlan = state.reviewAddressPlan;
    if (quote == null || addressPlan == null || state.quoteExpired) {
      log(
        'Swap: start ignored; quote=${quote != null} '
        'addressPlan=${addressPlan != null} expired=${state.quoteExpired}',
      );
      return false;
    }
    if (state.startSubmitting) {
      log('Swap: duplicate start ignored while start is already in flight');
      return false;
    }
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final reviewAccountUuid = state.reviewAccountUuid;
    if (reviewAccountUuid == null || accountUuid != reviewAccountUuid) {
      log(
        'Swap: start blocked; active account changed '
        'review=$reviewAccountUuid active=$accountUuid',
      );
      _clearReviewState();
      state = state.copyWith(
        startSubmitting: false,
        statusError:
            'Active account changed. Review the quote again before starting.',
      );
      return false;
    }

    log(
      'Swap: start begin pair=${quote.pairText} '
      'direction=${quote.direction.name} '
      'quote=${_shortSwapValue(quote.providerQuoteId)} '
      'deposit=${_shortSwapValue(quote.depositInstruction.address)} '
      'liveFunds=${ref.read(swapLiveFundsEnabledProvider)}',
    );
    state = state.copyWith(startSubmitting: true, clearStatusError: true);
    if (accountUuid == null) {
      log('Swap: start blocked; no active account');
      state = state.copyWith(
        startSubmitting: false,
        statusError: 'No active account',
      );
      return false;
    }
    final activeAccountIsHardware = ref
        .read(accountProvider.notifier)
        .isActiveAccountHardware;
    final liveFundsEnabled = ref.read(swapLiveFundsEnabledProvider);
    if (quote.direction.sendsZec && liveFundsEnabled) {
      try {
        await ref
            .read(swapDepositSenderProvider)
            .estimateZecDepositFee(accountUuid: accountUuid, quote: quote);
      } catch (e) {
        log(
          'Swap: live ZEC deposit preflight failed '
          'quote=${_shortSwapValue(quote.providerQuoteId)} error=$e',
        );
        state = state.copyWith(
          startSubmitting: false,
          statusError: swapFailureMessage(
            SwapFailureOperation.sendZecDeposit,
            e,
          ),
        );
        return false;
      }
    }

    late final SwapIntentSnapshot snapshot;
    try {
      snapshot = await ref.read(swapIntentProvider).startSwap(quote);
    } catch (e) {
      log(
        'Swap: start failed quote=${_shortSwapValue(quote.providerQuoteId)} '
        'error=$e',
      );
      state = state.copyWith(
        startSubmitting: false,
        quoteLoading: false,
        statusError: swapFailureMessage(SwapFailureOperation.start, e),
      );
      return false;
    }
    var intent = _intentFromSnapshot(snapshot, quote, addressPlan, accountUuid);
    if (activeAccountIsHardware && quote.direction.sendsZec) {
      const nextAction = 'Sign and send the ZEC deposit with Keystone.';
      intent = intent.copyWith(
        nextAction: nextAction,
        steps: _stepsForStatus(intent.status, nextAction),
      );
    }
    log(
      'Swap: start saved intent=${_shortSwapValue(intent.id)} '
      'status=${intent.status.name}',
    );
    _quoteGeneration++;
    state = state.copyWith(
      reviewVisible: false,
      amountText: '',
      destinationText: '',
      intents: [intent, ...state.intents],
      startSubmitting: false,
      quoteLoading: false,
      selectedIntentId: intent.id,
      depositTxHashText: '',
      clearReview: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
    await _persistCurrentIntents();

    if (quote.direction.sendsZec) {
      if (!ref.read(swapLiveFundsEnabledProvider)) {
        log(
          'Swap: live ZEC deposit skipped; live funds disabled '
          'intent=${_shortSwapValue(intent.id)}',
        );
        state = state.copyWith(
          statusError:
              'Live ZEC deposit is disabled in this build. The quote is saved, but no wallet transaction was signed or broadcast.',
        );
        return true;
      }
      if (activeAccountIsHardware) {
        log(
          'Swap: hardware ZEC deposit waiting for Keystone signing '
          'intent=${_shortSwapValue(intent.id)}',
        );
        return true;
      }
      unawaited(
        _sendAndSubmitZecDeposit(
          accountUuid: accountUuid,
          quote: quote,
          intentId: intent.id,
        ),
      );
    }
    return true;
  }

  Future<void> refreshSelectedIntentStatus() async {
    if (state.statusRefreshing || state.intents.isEmpty) return;
    final selected = state.selectedIntent;
    await _refreshIntentStatuses([selected], showBusy: true);
  }

  Future<void> refreshOpenIntentStatuses() async {
    final refreshable = [
      for (final intent in state.intents)
        if (_shouldRefreshIntentStatus(intent)) intent,
    ];
    await _refreshIntentStatuses(refreshable, showBusy: false);
  }

  Future<void> _refreshShieldingConfirmations() async {
    final refreshable = [
      for (final intent in state.intents)
        if (intent.status == SwapIntentStatus.shieldingConfirming) intent,
    ];
    await _refreshIntentStatuses(refreshable, showBusy: false);
  }

  void updateDepositTxHash(String value) {
    state = state.copyWith(depositTxHashText: value, clearStatusError: true);
  }

  void selectIntent(String intentId) {
    final intent = _intentById(intentId);
    if (intent == null) return;
    state = state.copyWith(
      selectedIntentId: intent.id,
      depositTxHashText: intent.depositTxHash ?? '',
      clearStatusError: true,
    );
  }

  Future<void> removeIntent(String intentId) async {
    final remaining = [
      for (final intent in state.intents)
        if (intent.id != intentId) intent,
    ];
    if (remaining.length == state.intents.length) return;

    final removedSelected =
        state.selectedIntentId == intentId ||
        state.selectedIntentOrNull?.id == intentId;
    final nextSelectedId = removedSelected
        ? (remaining.isEmpty ? null : remaining.first.id)
        : state.selectedIntentId;
    final nextSelectedIntent = nextSelectedId == null
        ? null
        : _intentByIdFrom(remaining, nextSelectedId);

    state = state.copyWith(
      intents: remaining,
      selectedIntentId: nextSelectedId,
      depositTxHashText: nextSelectedIntent?.depositTxHash ?? '',
      clearSelectedIntent: nextSelectedId == null,
      clearStatusError: true,
    );
    await _persistCurrentIntents();
  }

  Future<void> removeUnsentHardwareDepositIntent(String intentId) async {
    final intent = _intentById(intentId);
    if (intent == null || !_isHardwareIntent(intent)) return;
    if (intent.direction != SwapDirection.zecToExternal) return;
    if (intent.depositTxHash?.trim().isNotEmpty ?? false) return;
    if (intent.shieldTxHash?.trim().isNotEmpty ?? false) return;

    await removeIntent(intentId);
  }

  void selectExternalRequest(String requestId) {
    final request = _externalRequestById(requestId);
    if (request == null) return;
    state = state.copyWith(
      selectedRequestId: request.id,
      clearStatusError: true,
    );
  }

  void updateRequestImportText(String value) {
    state = state.copyWith(
      requestImportText: value,
      clearRequestImportError: true,
    );
  }

  void importExternalRequest() {
    try {
      final parsed = Zip321PaymentRequest.parse(state.requestImportText);
      final request = _externalRequestFromZip321(parsed);
      state = state.copyWith(
        externalRequests: [request, ...state.externalRequests],
        selectedRequestId: request.id,
        requestImportText: '',
        clearRequestImportError: true,
      );
    } on Zip321ParseException catch (e) {
      state = state.copyWith(requestImportError: e.message);
    }
  }

  bool stageSelectedExternalRequest() {
    if (state.externalRequests.isEmpty) return false;
    final request = state.selectedRequest;
    if (!request.canStageSwap) return false;
    final direction = request.direction;
    final externalAsset = request.externalAsset;
    final amountText = request.amountText;
    final destinationText = request.destinationText;
    if (direction == null ||
        externalAsset == null ||
        amountText == null ||
        destinationText == null) {
      return false;
    }

    _quoteGeneration++;
    state = state.copyWith(
      direction: direction,
      externalAsset: externalAsset,
      amountText: amountText,
      destinationText: destinationText,
      reviewVisible: false,
      quoteLoading: false,
      externalRequests: _replaceExternalRequest(
        state.externalRequests,
        request.id,
        request.copyWith(status: SwapExternalRequestStatus.accepted),
      ),
      selectedRequestId: request.id,
      clearReview: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
    return true;
  }

  void rejectSelectedExternalRequest() {
    if (state.externalRequests.isEmpty) return;
    final request = state.selectedRequest;
    if (!request.isOpen) return;
    state = state.copyWith(
      externalRequests: _replaceExternalRequest(
        state.externalRequests,
        request.id,
        request.copyWith(status: SwapExternalRequestStatus.rejected),
      ),
      selectedRequestId: request.id,
      clearStatusError: true,
    );
  }

  void cancelReviewQuote() {
    _clearReviewState();
  }

  void prepareRetryFromSelectedIntent() {
    if (state.intents.isEmpty) return;
    final intent = state.selectedIntent;
    final direction = intent.direction;
    final externalAsset = intent.externalAsset;
    if (direction == null || externalAsset == null) return;

    final amountText = intent.sellAmount.split(' ').first.trim();
    final destinationText = direction.sendsZec
        ? intent.oneClickRecipient ?? ''
        : intent.oneClickRefundTo ?? '';
    if (amountText.isEmpty || destinationText.isEmpty) return;

    _quoteGeneration++;
    state = state.copyWith(
      direction: direction,
      externalAsset: externalAsset,
      amountText: amountText,
      destinationText: destinationText,
      reviewVisible: false,
      quoteLoading: false,
      depositTxHashText: '',
      clearReview: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
  }

  Future<void> retryShieldSelectedIntent() async {
    if (state.intents.isEmpty) return;
    final selected = state.selectedIntent;
    if (selected.status != SwapIntentStatus.shieldingFailed) return;

    final hardwareIntent = _isHardwareIntent(selected);
    final nextAction = hardwareIntent
        ? 'Sign a shield transaction with Keystone to make ZEC spendable.'
        : 'Retrying wallet shielding from the staging address';
    final pending = selected.copyWith(
      status: SwapIntentStatus.shieldingPending,
      nextAction: nextAction,
      steps: _stepsForStatus(SwapIntentStatus.shieldingPending, nextAction),
    );
    state = state.copyWith(
      intents: _replaceIntent(state.intents, selected.id, pending),
      selectedIntentId: pending.id,
      clearStatusError: true,
    );
    if (hardwareIntent) {
      await _persistCurrentIntents();
      return;
    }
    final updated = await _tryShieldStagingAddress(pending);
    if (updated != pending) {
      state = state.copyWith(
        intents: _replaceIntent(state.intents, pending.id, updated),
        selectedIntentId: updated.id,
        clearStatusError: true,
      );
    }
    await _persistCurrentIntents();
  }

  void expireReviewQuote() {
    if (state.reviewQuote == null || state.reviewAddressPlan == null) return;
    state = state.copyWith(
      reviewVisible: true,
      quoteLoading: false,
      quoteExpired: true,
      clearQuoteError: true,
    );
  }

  Future<void> submitSelectedDepositTransaction() async {
    if (!state.canSubmitDepositTx || state.intents.isEmpty) return;
    await _submitDepositTransaction(
      state.selectedIntent,
      state.depositTxHashText.trim(),
    );
  }

  Future<void> submitDepositTransactionForIntent({
    required String intentId,
    required String accountUuid,
    required String txHash,
    String? broadcastStatus,
    String? broadcastMessage,
  }) async {
    final selected = _intentById(intentId);
    final normalizedTxHash = txHash.trim();
    if (normalizedTxHash.isEmpty) return;
    if (selected == null) {
      await _submitDepositTransactionForStoredIntent(
        accountUuid: accountUuid,
        intentId: intentId,
        txHash: normalizedTxHash,
        broadcastStatus: broadcastStatus,
        broadcastMessage: broadcastMessage,
      );
      return;
    }
    await _submitDepositTransaction(
      selected,
      normalizedTxHash,
      broadcastStatus: broadcastStatus,
      broadcastMessage: broadcastMessage,
    );
  }

  Future<void> recordHardwareShieldSubmission({
    required String intentId,
    required String accountUuid,
    required String txHash,
    required BigInt feeZatoshi,
    String? broadcastStatus,
    String? broadcastMessage,
  }) async {
    final intent = _intentById(intentId);
    final normalizedTxHash = txHash.trim();
    if (normalizedTxHash.isEmpty) return;
    if (intent == null) {
      await _recordHardwareShieldSubmissionForStoredIntent(
        accountUuid: accountUuid,
        intentId: intentId,
        txHash: normalizedTxHash,
        feeZatoshi: feeZatoshi,
        broadcastStatus: broadcastStatus,
        broadcastMessage: broadcastMessage,
      );
      return;
    }

    if (!_isAccountActive(intent.accountUuid)) {
      await _recordHardwareShieldSubmissionForStoredIntent(
        accountUuid: intent.accountUuid ?? accountUuid,
        intentId: intentId,
        txHash: normalizedTxHash,
        feeZatoshi: feeZatoshi,
        broadcastStatus: broadcastStatus,
        broadcastMessage: broadcastMessage,
      );
      return;
    }

    log(
      'Swap: hardware shield submitted intent=${_shortSwapValue(intent.id)} '
      'tx=${_shortSwapValue(normalizedTxHash)}',
    );
    const nextAction = 'Waiting for shield transaction confirmation.';
    final broadcastNotice = _hardwareBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final updated = intent.copyWith(
      status: SwapIntentStatus.shieldingConfirming,
      nextAction: nextAction,
      steps: _stepsForStatus(SwapIntentStatus.shieldingConfirming, nextAction),
      receipt: _receiptWithBroadcastNotice(
        _receiptWithShieldSubmission(
          intent.receipt,
          txHash: normalizedTxHash,
          feeZatoshi: feeZatoshi,
        ),
        broadcastNotice,
      ),
      statusError: broadcastNotice,
      shieldTxHash: normalizedTxHash,
      clearStatusError: broadcastNotice == null,
    );
    state = state.copyWith(
      intents: _replaceIntent(state.intents, intent.id, updated),
      selectedIntentId: updated.id,
      clearStatusError: true,
    );
    await _persistCurrentIntents();
  }

  Future<void> _submitDepositTransaction(
    SwapPrototypeIntent selected,
    String txHash, {
    String? broadcastStatus,
    String? broadcastMessage,
  }) async {
    if (!_isAccountActive(selected.accountUuid)) {
      await _submitDepositTransactionForStoredIntent(
        accountUuid: selected.accountUuid,
        intentId: selected.id,
        txHash: txHash,
        broadcastStatus: broadcastStatus,
        broadcastMessage: broadcastMessage,
      );
      return;
    }
    if (!ref.read(swapLiveFundsEnabledProvider)) {
      state = state.copyWith(
        statusError:
            'Live deposit submission is disabled in this build. No swap status update was sent.',
      );
      return;
    }

    log(
      'Swap: submit deposit begin intent=${_shortSwapValue(selected.id)} '
      'deposit=${_shortSwapValue(_providerDepositAddress(selected))} '
      'tx=${_shortSwapValue(txHash)}',
    );
    state = state.copyWith(depositSubmitting: true, clearStatusError: true);
    final broadcastNotice = _hardwareBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final checkpointed = selected.copyWith(
      depositTxHash: txHash,
      receipt: _receiptWithBroadcastNotice(
        _receiptWithDepositTx(selected.receipt, txHash),
        broadcastNotice,
      ),
      statusError: broadcastNotice,
      clearStatusError: broadcastNotice == null,
    );
    state = state.copyWith(
      depositTxHashText: state.selectedIntentId == selected.id
          ? txHash
          : state.depositTxHashText,
      intents: _replaceIntent(state.intents, selected.id, checkpointed),
      clearStatusError: true,
    );
    await _persistCurrentIntents();
    try {
      final snapshot = await ref
          .read(swapIntentProvider)
          .submitDepositTransaction(
            depositAddress: _providerDepositAddress(checkpointed),
            txHash: txHash,
            depositMemo: checkpointed.depositMemo,
          );
      final updated = _depositSnapshotIntent(
        checkpointed,
        snapshot,
        txHash: txHash,
        broadcastNotice: broadcastNotice,
      );
      if (!_isAccountActive(selected.accountUuid)) {
        await _recordDepositSnapshotForStoredIntent(
          accountUuid: selected.accountUuid,
          intentId: checkpointed.id,
          txHash: txHash,
          snapshot: snapshot,
          broadcastStatus: broadcastStatus,
          broadcastMessage: broadcastMessage,
        );
        return;
      }
      state = state.copyWith(
        depositSubmitting: false,
        depositTxHashText: state.selectedIntentId == selected.id
            ? txHash
            : state.depositTxHashText,
        intents: _replaceIntent(state.intents, checkpointed.id, updated),
        clearStatusError: true,
      );
      log(
        'Swap: submit deposit complete intent=${_shortSwapValue(updated.id)} '
        'status=${updated.status.name}',
      );
      await _persistCurrentIntents();
    } catch (e) {
      log(
        'Swap: submit deposit failed intent=${_shortSwapValue(selected.id)} '
        'error=$e',
      );
      final message = swapFailureMessage(SwapFailureOperation.submitDeposit, e);
      if (selected.accountUuid != null &&
          !_isAccountActive(selected.accountUuid)) {
        await _submitDepositTransactionForStoredIntent(
          accountUuid: selected.accountUuid,
          intentId: selected.id,
          txHash: txHash,
          broadcastStatus: broadcastStatus,
          broadcastMessage: broadcastMessage,
          submitProviderStatus: false,
          statusError: message,
        );
        return;
      }
      state = state.copyWith(depositSubmitting: false, statusError: message);
    }
  }

  Future<void> _submitDepositTransactionForStoredIntent({
    required String? accountUuid,
    required String intentId,
    required String txHash,
    String? broadcastStatus,
    String? broadcastMessage,
    bool submitProviderStatus = true,
    String? statusError,
  }) async {
    final scopedAccountUuid = accountUuid?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) return;
    final store = ref.read(swapSessionStoreProvider);
    final storedIntents = await store.loadIntents(
      accountUuid: scopedAccountUuid,
    );
    final intent = _intentByIdFrom(storedIntents, intentId);
    if (intent == null) return;

    final broadcastNotice = _hardwareBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final checkpointed = intent.copyWith(
      depositTxHash: txHash,
      receipt: _receiptWithBroadcastNotice(
        _receiptWithDepositTx(intent.receipt, txHash),
        broadcastNotice,
      ),
      statusError: statusError ?? broadcastNotice,
      clearStatusError: statusError == null && broadcastNotice == null,
    );
    var updatedIntents = _replaceIntent(storedIntents, intentId, checkpointed);
    await _persistIntentsForAccount(scopedAccountUuid, updatedIntents);

    if (!submitProviderStatus) return;

    try {
      final snapshot = await ref
          .read(swapIntentProvider)
          .submitDepositTransaction(
            depositAddress: _providerDepositAddress(checkpointed),
            txHash: txHash,
            depositMemo: checkpointed.depositMemo,
          );
      final updated = _depositSnapshotIntent(
        checkpointed,
        snapshot,
        txHash: txHash,
        broadcastNotice: broadcastNotice,
      );
      updatedIntents = _replaceIntent(updatedIntents, intentId, updated);
      await _persistIntentsForAccount(scopedAccountUuid, updatedIntents);
    } catch (e) {
      final failed = checkpointed.copyWith(
        statusError: swapFailureMessage(SwapFailureOperation.submitDeposit, e),
      );
      updatedIntents = _replaceIntent(updatedIntents, intentId, failed);
      await _persistIntentsForAccount(scopedAccountUuid, updatedIntents);
    }
  }

  Future<void> _recordDepositSnapshotForStoredIntent({
    required String? accountUuid,
    required String intentId,
    required String txHash,
    required SwapIntentSnapshot snapshot,
    String? broadcastStatus,
    String? broadcastMessage,
  }) async {
    final scopedAccountUuid = accountUuid?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) return;
    final storedIntents = await ref
        .read(swapSessionStoreProvider)
        .loadIntents(accountUuid: scopedAccountUuid);
    final intent = _intentByIdFrom(storedIntents, intentId);
    if (intent == null) return;

    final broadcastNotice = _hardwareBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final updated = _depositSnapshotIntent(
      intent,
      snapshot,
      txHash: txHash,
      broadcastNotice: broadcastNotice,
    );
    await _persistIntentsForAccount(
      scopedAccountUuid,
      _replaceIntent(storedIntents, intentId, updated),
    );
  }

  Future<void> _recordHardwareShieldSubmissionForStoredIntent({
    required String? accountUuid,
    required String intentId,
    required String txHash,
    required BigInt feeZatoshi,
    String? broadcastStatus,
    String? broadcastMessage,
  }) async {
    final scopedAccountUuid = accountUuid?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) return;
    final storedIntents = await ref
        .read(swapSessionStoreProvider)
        .loadIntents(accountUuid: scopedAccountUuid);
    final intent = _intentByIdFrom(storedIntents, intentId);
    if (intent == null) return;

    const nextAction = 'Waiting for shield transaction confirmation.';
    final broadcastNotice = _hardwareBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final updated = intent.copyWith(
      status: SwapIntentStatus.shieldingConfirming,
      nextAction: nextAction,
      steps: _stepsForStatus(SwapIntentStatus.shieldingConfirming, nextAction),
      receipt: _receiptWithBroadcastNotice(
        _receiptWithShieldSubmission(
          intent.receipt,
          txHash: txHash,
          feeZatoshi: feeZatoshi,
        ),
        broadcastNotice,
      ),
      statusError: broadcastNotice,
      shieldTxHash: txHash,
      clearStatusError: broadcastNotice == null,
    );
    await _persistIntentsForAccount(
      scopedAccountUuid,
      _replaceIntent(storedIntents, intentId, updated),
    );
  }

  Future<void> _sendAndSubmitZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
    required String intentId,
  }) async {
    log(
      'Swap: live ZEC deposit begin intent=${_shortSwapValue(intentId)} '
      'quote=${_shortSwapValue(quote.providerQuoteId)} '
      'deposit=${_shortSwapValue(quote.depositInstruction.address)}',
    );
    state = state.copyWith(depositSubmitting: true, clearStatusError: true);
    String? broadcastTxHash;
    try {
      final txHash = await ref
          .read(swapDepositSenderProvider)
          .sendZecDeposit(accountUuid: accountUuid, quote: quote);
      broadcastTxHash = txHash;
      log(
        'Swap: live ZEC deposit broadcast tx=${_shortSwapValue(txHash)} '
        'intent=${_shortSwapValue(intentId)}',
      );
      if (!_isAccountActive(accountUuid)) {
        await _submitDepositTransactionForStoredIntent(
          accountUuid: accountUuid,
          intentId: intentId,
          txHash: txHash,
        );
        return;
      }
      final intent = _intentById(intentId);
      if (intent == null) {
        state = state.copyWith(
          depositTxHashText: txHash,
          depositSubmitting: false,
          statusError:
              'ZEC deposit was broadcast, but the saved swap intent was not found. Copy the transaction hash before leaving this screen.',
        );
        return;
      }
      final checkpointed = intent.copyWith(
        depositTxHash: txHash,
        receipt: _receiptWithDepositTx(intent.receipt, txHash),
      );
      state = state.copyWith(
        depositTxHashText: txHash,
        intents: _replaceIntent(state.intents, intentId, checkpointed),
      );
      await _persistCurrentIntents();
      final snapshot = await ref
          .read(swapIntentProvider)
          .submitDepositTransaction(
            depositAddress: _providerDepositAddress(intent),
            txHash: txHash,
            depositMemo: intent.depositMemo,
          );
      final updated = _updateIntentFromSnapshot(checkpointed, snapshot)
          .copyWith(
            depositTxHash: txHash,
            receipt: _receiptWithDepositTx(checkpointed.receipt, txHash),
            clearStatusError: true,
          );
      if (!_isAccountActive(accountUuid)) {
        await _recordDepositSnapshotForStoredIntent(
          accountUuid: accountUuid,
          intentId: intentId,
          txHash: txHash,
          snapshot: snapshot,
        );
        return;
      }
      state = state.copyWith(
        depositTxHashText: txHash,
        depositSubmitting: false,
        intents: _replaceIntent(state.intents, intentId, updated),
        clearStatusError: true,
      );
      log(
        'Swap: live ZEC deposit submitted intent=${_shortSwapValue(intentId)} '
        'status=${updated.status.name}',
      );
      await _persistCurrentIntents();
    } catch (e) {
      log(
        'Swap: live ZEC deposit failed intent=${_shortSwapValue(intentId)} '
        'error=$e',
      );
      final message = swapFailureMessage(
        SwapFailureOperation.sendZecDeposit,
        e,
      );
      if (!_isAccountActive(accountUuid)) {
        if (broadcastTxHash != null) {
          await _submitDepositTransactionForStoredIntent(
            accountUuid: accountUuid,
            intentId: intentId,
            txHash: broadcastTxHash,
            submitProviderStatus: false,
            statusError: message,
          );
        }
        return;
      }
      state = state.copyWith(depositSubmitting: false, statusError: message);
    }
  }

  void _clearReviewState() {
    _quoteGeneration++;
    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: false,
      startSubmitting: false,
      clearReview: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
  }

  void _clearAccountScopedTransientState() {
    _quoteGeneration++;
    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: false,
      startSubmitting: false,
      maxAmountLoading: false,
      depositSubmitting: false,
      depositTxHashText: '',
      statusRefreshing: false,
      clearReview: true,
      clearQuoteError: true,
      clearStatusError: true,
      clearMaxAmountError: true,
      clearSelectedIntent: true,
    );
  }

  Future<void> _restorePersistedIntents({
    required String? accountUuid,
    bool replaceExisting = false,
  }) async {
    if (accountUuid == null) {
      if (replaceExisting) {
        state = state.copyWith(
          intents: const [],
          statusRefreshing: false,
          depositTxHashText: '',
          depositSubmitting: false,
          clearSelectedIntent: true,
          clearStatusError: true,
        );
      }
      return;
    }
    try {
      final persisted = await ref
          .read(swapSessionStoreProvider)
          .loadIntents(accountUuid: accountUuid);
      if (persisted.isEmpty && !replaceExisting) return;
      state = state.copyWith(
        intents: persisted,
        selectedIntentId: persisted.isEmpty ? null : persisted.first.id,
        statusRefreshing: replaceExisting ? false : null,
        depositTxHashText: persisted.isEmpty
            ? ''
            : persisted.first.depositTxHash ?? '',
        depositSubmitting: replaceExisting ? false : null,
        clearSelectedIntent: persisted.isEmpty,
        clearStatusError: true,
      );
      if (persisted.isNotEmpty) {
        unawaited(refreshOpenIntentStatuses());
      }
    } catch (_) {}
  }

  Future<void> _restorePersistedDraft() async {
    try {
      final draft = await ref.read(swapSessionStoreProvider).loadDraft();
      if (draft == null) return;
      if (state.amountText.isNotEmpty ||
          state.destinationText.isNotEmpty ||
          state.quoteLoading ||
          state.reviewVisible) {
        return;
      }
      final externalAsset =
          _supportedAssetFor(
            draft.externalAsset,
            state.supportedExternalAssets,
          ) ??
          draft.externalAsset;
      _quoteGeneration++;
      state = state.copyWith(
        direction: draft.direction,
        externalAsset: externalAsset,
        slippageBps: draft.slippageBps,
        reviewVisible: false,
        quoteLoading: false,
        clearReview: true,
        clearQuoteError: true,
        clearStatusError: true,
      );
    } catch (_) {}
  }

  Future<void> _refreshIntentStatuses(
    List<SwapPrototypeIntent> intents, {
    required bool showBusy,
  }) async {
    if (_statusRefreshInFlight || intents.isEmpty) return;
    final refreshAccountUuid = _activeAccountUuidOrNull;
    _statusRefreshInFlight = true;
    if (showBusy) {
      state = state.copyWith(statusRefreshing: true, clearStatusError: true);
    }

    try {
      var updatedIntents = state.intents;
      var changed = false;
      String? refreshError;

      for (final intent in intents) {
        final currentIntent = _intentByIdFrom(updatedIntents, intent.id);
        if (currentIntent == null) continue;
        final checkedAt = DateTime.now().toUtc();
        try {
          final refreshed =
              currentIntent.status == SwapIntentStatus.shieldingConfirming
              ? await _tryTrackShieldTransaction(currentIntent)
              : await _refreshProviderBackedIntent(currentIntent);
          final updated = refreshed.copyWith(
            lastStatusCheckedAt: checkedAt,
            clearStatusError: true,
          );
          if (updated.status != currentIntent.status) {
            log(
              'Swap: status transition intent=${_shortSwapValue(updated.id)} '
              '${currentIntent.status.name}->${updated.status.name}',
            );
          }
          updatedIntents = _replaceIntent(
            updatedIntents,
            currentIntent.id,
            updated,
          );
        } catch (e) {
          final message = swapFailureMessage(
            SwapFailureOperation.refreshStatus,
            e,
          );
          refreshError ??= message;
          log(
            'Swap: status refresh failed intent=${_shortSwapValue(currentIntent.id)} '
            'error=$e',
          );
          updatedIntents = _replaceIntent(
            updatedIntents,
            currentIntent.id,
            currentIntent.copyWith(
              lastStatusCheckedAt: checkedAt,
              statusError: message,
            ),
          );
        }
        changed = true;
      }

      if (!changed) {
        if (showBusy) {
          state = state.copyWith(statusRefreshing: false);
        }
        return;
      }

      if (refreshAccountUuid != null && !_isAccountActive(refreshAccountUuid)) {
        await _persistIntentsForAccount(refreshAccountUuid, updatedIntents);
        return;
      }

      state = state.copyWith(
        statusRefreshing: false,
        intents: updatedIntents,
        statusError: showBusy ? refreshError : null,
        clearStatusError: refreshError == null,
      );
      await _persistCurrentIntents();
    } finally {
      _statusRefreshInFlight = false;
    }
  }

  Future<void> _persistCurrentIntents({String? accountUuid}) async {
    final activeAccountUuid = accountUuid ?? _activeAccountUuidOrNull;
    if (activeAccountUuid == null) return;
    await _persistIntentsForAccount(activeAccountUuid, state.intents);
  }

  Future<void> _persistIntentsForAccount(
    String? accountUuid,
    List<SwapPrototypeIntent> intentsToPersist,
  ) async {
    final scopedAccountUuid = accountUuid?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) return;
    final intents = [
      for (final intent in intentsToPersist)
        if (_isPersistableIntent(intent, accountUuid: scopedAccountUuid))
          intent.copyWith(accountUuid: scopedAccountUuid),
    ];
    await ref
        .read(swapSessionStoreProvider)
        .saveIntents(accountUuid: scopedAccountUuid, intents: intents);
  }

  bool _isAccountActive(String? accountUuid) {
    final scopedAccountUuid = accountUuid?.trim();
    return scopedAccountUuid == null ||
        scopedAccountUuid.isEmpty ||
        scopedAccountUuid == _activeAccountUuidOrNull;
  }

  Future<void> _persistDraft(SwapDraftSnapshot draft) async {
    try {
      await ref.read(swapSessionStoreProvider).saveDraft(draft);
    } catch (_) {}
  }

  SwapDraftSnapshot get _currentDraftSnapshot {
    return SwapDraftSnapshot(
      direction: state.direction,
      externalAsset: state.externalAsset,
      slippageBps: state.slippageBps,
    );
  }

  bool _isPersistableIntent(SwapPrototypeIntent intent, {String? accountUuid}) {
    final expectedAccountUuid = accountUuid ?? _activeAccountUuidOrNull;
    if (expectedAccountUuid == null ||
        intent.accountUuid != expectedAccountUuid) {
      return false;
    }
    return intent.direction != null &&
        intent.depositAddress != null &&
        (intent.providerQuoteId != null ||
            intent.depositTxHash != null ||
            intent.shieldTxHash != null);
  }

  bool _shouldRefreshIntentStatus(SwapPrototypeIntent intent) {
    if (!_isPersistableIntent(intent)) return false;
    return !intent.status.isTerminal;
  }

  String _providerDepositAddress(SwapPrototypeIntent intent) {
    return intent.depositAddress ?? intent.id;
  }

  String _friendlyQuoteError(Object error) {
    if (error is SwapZecStagingAddressUnavailableException) {
      return error.toString();
    }
    return swapFailureMessage(SwapFailureOperation.quote, error);
  }

  Future<SwapPrototypeIntent> _refreshProviderBackedIntent(
    SwapPrototypeIntent intent,
  ) async {
    final snapshot = await ref
        .read(swapIntentProvider)
        .getStatus(
          _providerDepositAddress(intent),
          depositMemo: intent.depositMemo,
        );
    return _tryShieldStagingAddress(
      _updateIntentFromSnapshot(intent, snapshot),
    );
  }

  SwapPrototypeIntent _intentFromSnapshot(
    SwapIntentSnapshot snapshot,
    SwapQuote quote,
    SwapAddressPlan addressPlan,
    String accountUuid,
  ) {
    final sendsZec = quote.direction.sendsZec;
    final externalSymbol = quote.externalAsset.symbol;
    return SwapPrototypeIntent(
      id: snapshot.id,
      title: sendsZec ? 'ZEC to $externalSymbol' : '$externalSymbol to ZEC',
      pair: snapshot.pairText,
      sellAmount: snapshot.sellAmountText,
      receiveEstimate: snapshot.receiveEstimateText,
      provider: snapshot.providerLabel,
      status: snapshot.status,
      nextAction: snapshot.nextAction,
      steps: [
        SwapPrototypeStep(
          label: 'Quote locked',
          state: SwapPrototypeStepState.done,
          evidence: 'Quote saved locally',
        ),
        SwapPrototypeStep(
          label: sendsZec
              ? 'One-time transparent address prepared'
              : 'One-time $externalSymbol source address prepared',
          state: SwapPrototypeStepState.active,
          evidence: '0 previous uses',
        ),
        SwapPrototypeStep(
          label: sendsZec
              ? 'Awaiting ZEC deposit'
              : 'Awaiting $externalSymbol deposit',
          state: SwapPrototypeStepState.pending,
          evidence: 'Do not reuse this address',
        ),
        SwapPrototypeStep(
          label: sendsZec ? 'Deposit observed' : 'External deposit observed',
          state: SwapPrototypeStepState.pending,
          evidence: 'Waiting for chain observation',
        ),
        SwapPrototypeStep(
          label: sendsZec ? 'Refund path monitored' : 'Shielded receive',
          state: SwapPrototypeStepState.pending,
          evidence: sendsZec
              ? 'Wallet unified address is used only if a refund arrives'
              : addressPlan.deliverySummary,
        ),
      ],
      exposure: [
        SwapPrototypeField(
          label: sendsZec ? 'ZEC deposit' : '$externalSymbol source deposit',
          value: sendsZec
              ? 'one-time transparent address'
              : 'one-time $externalSymbol address',
        ),
        const SwapPrototypeField(
          label: 'Address reuse',
          value: '0 previous uses',
        ),
        SwapPrototypeField(
          label: sendsZec ? 'Refund path' : 'ZEC destination',
          value: sendsZec
              ? 'wallet unified address'
              : addressPlan.deliverySummary,
        ),
        SwapPrototypeField(
          label: 'Third-party data',
          value: sendsZec
              ? 'solver sees ZEC deposit and $externalSymbol route'
              : 'solver sees $externalSymbol deposit and ZEC route',
        ),
        const SwapPrototypeField(
          label: 'Network disclosure',
          value: 'direct connection; Tor not enabled',
        ),
      ],
      receipt: [
        SwapPrototypeField(label: 'Pair', value: quote.pairText),
        if (quote.providerQuoteId != null)
          SwapPrototypeField(
            label: 'Provider quote',
            value: quote.providerQuoteId!,
          ),
        if (sendsZec)
          SwapPrototypeField(
            label: '$externalSymbol recipient',
            value: addressPlan.oneClickRecipient,
          )
        else
          SwapPrototypeField(
            label: 'ZEC recipient',
            value: addressPlan.oneClickRecipient,
          ),
        SwapPrototypeField(
          label: sendsZec ? 'ZEC deposit' : '$externalSymbol source deposit',
          value: quote.depositInstruction.address,
        ),
        if (quote.depositInstruction.memo != null)
          SwapPrototypeField(
            label: 'Memo',
            value: quote.depositInstruction.memo!,
          ),
        SwapPrototypeField(
          label: 'Refund to',
          value: addressPlan.oneClickRefundTo,
        ),
      ],
      direction: quote.direction,
      externalAsset: quote.externalAsset,
      depositAddress: quote.depositInstruction.address,
      depositMemo: quote.depositInstruction.memo,
      depositDeadline: quote.depositInstruction.deadline,
      providerQuoteId: quote.providerQuoteId,
      providerSignature: quote.providerSignature,
      providerStatusRaw: snapshot.providerStatusRaw,
      nearIntentHash: snapshot.nearIntentHash,
      nearTransactionHash: snapshot.nearTransactionHash,
      oneClickRecipient: addressPlan.oneClickRecipient,
      oneClickRefundTo: addressPlan.oneClickRefundTo,
      accountUuid: accountUuid,
    );
  }

  SwapPrototypeIntent _updateIntentFromSnapshot(
    SwapPrototypeIntent intent,
    SwapIntentSnapshot snapshot,
  ) {
    final status = snapshot.status;
    final nextAction = snapshot.nextAction;
    return intent.copyWith(
      id: intent.id,
      pair: snapshot.pairText,
      sellAmount: snapshot.sellAmountText,
      receiveEstimate: snapshot.receiveEstimateText,
      provider: snapshot.providerLabel,
      status: status,
      nextAction: nextAction,
      steps: _stepsForStatus(status, nextAction),
      providerStatusRaw: snapshot.providerStatusRaw,
      nearIntentHash: snapshot.nearIntentHash ?? intent.nearIntentHash,
      nearTransactionHash:
          snapshot.nearTransactionHash ?? intent.nearTransactionHash,
      receipt: snapshot.providerStatusRaw == null
          ? intent.receipt
          : _receiptWithProviderStatus(
              intent.receipt,
              snapshot.providerStatusRaw!,
            ),
      depositAddress:
          intent.depositAddress ?? snapshot.depositInstruction.address,
      depositMemo: intent.depositMemo ?? snapshot.depositInstruction.memo,
      depositDeadline:
          snapshot.depositInstruction.deadline ?? intent.depositDeadline,
    );
  }

  SwapPrototypeIntent _depositSnapshotIntent(
    SwapPrototypeIntent intent,
    SwapIntentSnapshot snapshot, {
    required String txHash,
    String? broadcastNotice,
  }) {
    return _updateIntentFromSnapshot(intent, snapshot).copyWith(
      depositTxHash: txHash,
      receipt: _receiptWithBroadcastNotice(
        _receiptWithDepositTx(intent.receipt, txHash),
        broadcastNotice,
      ),
      statusError: broadcastNotice,
      clearStatusError: broadcastNotice == null,
    );
  }

  Future<SwapPrototypeIntent> _tryShieldStagingAddress(
    SwapPrototypeIntent intent,
  ) async {
    if (!_needsWalletShielding(intent)) return intent;

    final accountUuid = _accountUuidForIntent(intent);
    final transparentAddress = intent.oneClickRecipient;
    if (accountUuid == null ||
        transparentAddress == null ||
        transparentAddress.trim().isEmpty) {
      log(
        'Swap: shielding failed before start; missing account/address '
        'intent=${_shortSwapValue(intent.id)}',
      );
      return _shieldingFailedIntent(intent);
    }
    if (_isHardwareIntent(intent)) {
      const nextAction =
          'Sign a shield transaction with Keystone to make ZEC spendable.';
      log(
        'Swap: hardware shielding waiting for Keystone signing '
        'intent=${_shortSwapValue(intent.id)} '
        'staging=${_shortSwapValue(transparentAddress)}',
      );
      return intent.copyWith(
        status: SwapIntentStatus.shieldingPending,
        nextAction: nextAction,
        steps: _stepsForStatus(SwapIntentStatus.shieldingPending, nextAction),
      );
    }

    try {
      log(
        'Swap: shielding begin intent=${_shortSwapValue(intent.id)} '
        'staging=${_shortSwapValue(transparentAddress)}',
      );
      final result = await ref
          .read(swapShieldingServiceProvider)
          .shieldStagingAddress(
            accountUuid: accountUuid,
            transparentAddress: transparentAddress,
          );
      final shieldTxHash = result.firstTxid;
      if (shieldTxHash == null || shieldTxHash.isEmpty) {
        log(
          'Swap: shielding returned no txid intent=${_shortSwapValue(intent.id)}',
        );
        return _shieldingFailedIntent(intent);
      }
      log(
        'Swap: shielding submitted intent=${_shortSwapValue(intent.id)} '
        'tx=${_shortSwapValue(shieldTxHash)}',
      );
      const nextAction = 'Waiting for shield transaction confirmation.';
      final updated = intent.copyWith(
        status: SwapIntentStatus.shieldingConfirming,
        nextAction: nextAction,
        steps: _stepsForStatus(
          SwapIntentStatus.shieldingConfirming,
          nextAction,
        ),
        receipt: _receiptWithShieldSubmission(
          intent.receipt,
          txHash: shieldTxHash,
          feeZatoshi: result.feeZatoshi,
        ),
        shieldTxHash: shieldTxHash,
      );
      await _persistShieldSubmissionCheckpoint(updated);
      return updated;
    } on SwapShieldingNotReadyException {
      log(
        'Swap: shielding not ready intent=${_shortSwapValue(intent.id)} '
        'staging=${_shortSwapValue(transparentAddress)}',
      );
      return intent;
    } catch (e) {
      log(
        'Swap: shielding failed intent=${_shortSwapValue(intent.id)} '
        'error=$e',
      );
      return _shieldingFailedIntent(intent);
    }
  }

  bool _needsWalletShielding(SwapPrototypeIntent intent) {
    return intent.direction == SwapDirection.externalToZec &&
        intent.status == SwapIntentStatus.shieldingPending;
  }

  bool _isHardwareIntent(SwapPrototypeIntent intent) {
    final accountUuid = _accountUuidForIntent(intent);
    if (accountUuid == null || accountUuid.trim().isEmpty) return false;
    return ref.read(accountProvider.notifier).isHardwareAccount(accountUuid);
  }

  Future<void> _persistShieldSubmissionCheckpoint(
    SwapPrototypeIntent updated,
  ) async {
    if (_intentById(updated.id) == null) return;
    state = state.copyWith(
      intents: _replaceIntent(state.intents, updated.id, updated),
      clearStatusError: true,
    );
    try {
      await _persistCurrentIntents();
    } catch (e) {
      log(
        'Swap: shield checkpoint persist failed '
        'intent=${_shortSwapValue(updated.id)} error=$e',
      );
    }
  }

  Future<SwapPrototypeIntent> _tryTrackShieldTransaction(
    SwapPrototypeIntent intent,
  ) async {
    if (intent.status != SwapIntentStatus.shieldingConfirming) return intent;

    final accountUuid = _accountUuidForIntent(intent);
    final txHash = intent.shieldTxHash;
    if (accountUuid == null || txHash == null || txHash.trim().isEmpty) {
      return _shieldingFailedIntent(intent);
    }

    try {
      final tracked = await ref
          .read(swapShieldingServiceProvider)
          .trackShieldTransaction(accountUuid: accountUuid, txHash: txHash);
      switch (tracked.status) {
        case SwapShieldTxStatus.mined:
          log(
            'Swap: shield tx mined intent=${_shortSwapValue(intent.id)} '
            'tx=${_shortSwapValue(txHash)}',
          );
          const nextAction = 'Shield transaction confirmed.';
          return intent.copyWith(
            status: SwapIntentStatus.complete,
            nextAction: nextAction,
            steps: _stepsForStatus(SwapIntentStatus.complete, nextAction),
          );
        case SwapShieldTxStatus.expired:
          log(
            'Swap: shield tx expired intent=${_shortSwapValue(intent.id)} '
            'tx=${_shortSwapValue(txHash)}',
          );
          return _shieldingFailedIntent(intent);
        case SwapShieldTxStatus.pending:
        case SwapShieldTxStatus.unknown:
          const nextAction = 'Waiting for shield transaction confirmation.';
          return intent.copyWith(
            nextAction: nextAction,
            steps: _stepsForStatus(
              SwapIntentStatus.shieldingConfirming,
              nextAction,
            ),
          );
      }
    } catch (e) {
      log(
        'Swap: shield tx track failed intent=${_shortSwapValue(intent.id)} '
        'error=$e',
      );
      return intent;
    }
  }

  SwapPrototypeIntent _shieldingFailedIntent(SwapPrototypeIntent intent) {
    const nextAction = 'Retry wallet shielding from the staging address';
    return intent.copyWith(
      status: SwapIntentStatus.shieldingFailed,
      nextAction: nextAction,
      steps: _stepsForStatus(SwapIntentStatus.shieldingFailed, nextAction),
    );
  }

  List<SwapPrototypeStep> _stepsForStatus(
    SwapIntentStatus status,
    String nextAction,
  ) {
    final doneBeforeProcessing = switch (status) {
      SwapIntentStatus.awaitingDeposit ||
      SwapIntentStatus.awaitingExternalDeposit ||
      SwapIntentStatus.providerStatusUnknown ||
      SwapIntentStatus.expired => false,
      _ => true,
    };
    final complete = status == SwapIntentStatus.complete;
    final failed =
        status == SwapIntentStatus.failed ||
        status == SwapIntentStatus.expired ||
        status == SwapIntentStatus.refunded ||
        status == SwapIntentStatus.shieldingFailed;
    return [
      const SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Stored locally',
      ),
      SwapPrototypeStep(
        label: 'Deposit observed',
        state: doneBeforeProcessing
            ? SwapPrototypeStepState.done
            : SwapPrototypeStepState.active,
        evidence: doneBeforeProcessing ? 'Deposit confirmed' : nextAction,
      ),
      SwapPrototypeStep(
        label: status.label,
        state: failed
            ? SwapPrototypeStepState.warning
            : complete
            ? SwapPrototypeStepState.done
            : SwapPrototypeStepState.active,
        evidence: nextAction,
      ),
    ];
  }

  List<SwapPrototypeField> _receiptWithDepositTx(
    List<SwapPrototypeField> receipt,
    String txHash,
  ) {
    return [
      for (final field in receipt)
        if (field.label != 'Deposit tx') field,
      SwapPrototypeField(label: 'Deposit tx', value: txHash),
    ];
  }

  List<SwapPrototypeField> _receiptWithProviderStatus(
    List<SwapPrototypeField> receipt,
    String providerStatus,
  ) {
    return [
      for (final field in receipt)
        if (field.label != 'Provider status') field,
      SwapPrototypeField(label: 'Provider status', value: providerStatus),
    ];
  }

  String? _hardwareBroadcastNotice({String? status, String? message}) {
    final normalizedStatus = status?.trim();
    if (normalizedStatus == null ||
        normalizedStatus.isEmpty ||
        normalizedStatus == 'broadcasted') {
      return null;
    }
    final trimmedMessage = message?.trim();
    if (trimmedMessage != null && trimmedMessage.isNotEmpty) {
      return trimmedMessage;
    }
    if (normalizedStatus == 'broadcast_unknown') {
      return 'The transaction may have reached the network, but confirmation timed out. Check activity before trying again.';
    }
    if (normalizedStatus == 'broadcasted_storage_failed') {
      return 'The transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';
    }
    return null;
  }

  List<SwapPrototypeField> _receiptWithBroadcastNotice(
    List<SwapPrototypeField> receipt,
    String? notice,
  ) {
    final trimmedNotice = notice?.trim();
    return [
      for (final field in receipt)
        if (field.label != 'Broadcast status') field,
      if (trimmedNotice != null && trimmedNotice.isNotEmpty)
        SwapPrototypeField(label: 'Broadcast status', value: trimmedNotice),
    ];
  }

  List<SwapPrototypeField> _receiptWithShieldSubmission(
    List<SwapPrototypeField> receipt, {
    required String? txHash,
    required BigInt feeZatoshi,
  }) {
    if (txHash == null || txHash.isEmpty) return receipt;
    return [
      for (final field in receipt)
        if (field.label != 'Shield tx' && field.label != 'Shield fee') field,
      SwapPrototypeField(label: 'Shield tx', value: txHash),
      if (feeZatoshi > BigInt.zero)
        SwapPrototypeField(
          label: 'Shield fee',
          value: ZecAmount.fromZatoshi(feeZatoshi).fee.toString(),
        ),
    ];
  }

  SwapPrototypeIntent? _intentById(String intentId) {
    return _intentByIdFrom(state.intents, intentId);
  }

  SwapExternalRequest? _externalRequestById(String requestId) {
    for (final request in state.externalRequests) {
      if (request.id == requestId) return request;
    }
    return null;
  }

  SwapExternalRequest _externalRequestFromZip321(Zip321PaymentRequest parsed) {
    final payment = parsed.primaryPayment;
    final amount = payment.amount;
    final unsupportedReason = parsed.unsupportedReason;
    final id = 'zip321-${DateTime.now().microsecondsSinceEpoch}';
    final requestedAction =
        unsupportedReason ??
        (amount == null
            ? 'Review ZEC payment request'
            : 'Review payment of $amount ZEC');
    return SwapExternalRequest(
      id: id,
      source: 'ZIP-321 URI',
      title: 'Zcash payment request',
      requestedAction: requestedAction,
      route: parsed.payments.length == 1
          ? 'ZEC payment'
          : '${parsed.payments.length} ZEC payments',
      receivedAt: 'just now',
      status: unsupportedReason == null
          ? SwapExternalRequestStatus.needsReview
          : SwapExternalRequestStatus.unsupported,
      riskLabel: unsupportedReason ?? 'Approval required',
      riskDetail:
          unsupportedReason ??
          'This request creates no transaction until you review it in the wallet.',
      disclosures: [
        SwapPrototypeField(label: 'Address', value: payment.address),
        if (amount != null)
          SwapPrototypeField(label: 'Amount', value: '$amount ZEC'),
        if (payment.label != null)
          SwapPrototypeField(label: 'Label', value: payment.label!),
        if (payment.message != null)
          SwapPrototypeField(label: 'Message', value: payment.message!),
        if (payment.memoBase64Url != null)
          const SwapPrototypeField(
            label: 'Memo',
            value: 'base64url memo present',
          ),
        SwapPrototypeField(
          label: 'Payments',
          value: parsed.payments.length.toString(),
        ),
      ],
      paymentAddress: unsupportedReason == null ? payment.address : null,
      paymentAmountText: unsupportedReason == null ? amount : null,
      paymentMemoText: unsupportedReason == null ? payment.memoText : null,
      paymentLabel: unsupportedReason == null ? payment.label : null,
      paymentMessage: unsupportedReason == null ? payment.message : null,
    );
  }

  SwapPrototypeIntent? _intentByIdFrom(
    List<SwapPrototypeIntent> intents,
    String intentId,
  ) {
    for (final intent in intents) {
      if (intent.id == intentId) return intent;
    }
    return null;
  }

  List<SwapPrototypeIntent> _replaceIntent(
    List<SwapPrototypeIntent> intents,
    String intentId,
    SwapPrototypeIntent updated,
  ) {
    return [
      for (final intent in intents)
        if (intent.id == intentId) updated else intent,
    ];
  }

  List<SwapExternalRequest> _replaceExternalRequest(
    List<SwapExternalRequest> requests,
    String requestId,
    SwapExternalRequest updated,
  ) {
    return [
      for (final request in requests)
        if (request.id == requestId) updated else request,
    ];
  }
}

SwapAsset? _supportedAssetFor(SwapAsset asset, List<SwapAsset> supported) {
  for (final candidate in supported) {
    if (candidate == asset) return candidate;
  }
  for (final candidate in supported) {
    if (candidate.hasSameMarketAs(asset)) return candidate;
  }
  return null;
}

String _shortSwapValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '-';
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 7)}...${trimmed.substring(trimmed.length - 6)}';
}

final swapPrototypeProvider =
    NotifierProvider<SwapPrototypeNotifier, SwapPrototypeState>(
      SwapPrototypeNotifier.new,
    );

final swapPrototypeIntentsProvider = Provider<List<SwapPrototypeIntent>>((ref) {
  return ref.watch(swapPrototypeProvider).intents;
});

final selectedSwapPrototypeIntentProvider = Provider<SwapPrototypeIntent?>((
  ref,
) {
  return ref.watch(swapPrototypeProvider).selectedIntentOrNull;
});
