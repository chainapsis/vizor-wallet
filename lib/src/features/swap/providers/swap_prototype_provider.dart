import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../domain/zip321_payment_request.dart';
import '../models/swap_fiat_amount.dart';
import '../models/swap_intent_presentation_mapper.dart';
import '../models/swap_prototype_models.dart';
import '../../../providers/account_provider.dart';
import 'swap_activity_tracker.dart';
import 'swap_deposit_sender.dart';
import 'swap_failure_policy.dart';
import 'swap_max_amount_estimator.dart';
import 'swap_draft_store.dart';
import 'swap_provider_config.dart';
import 'swap_zec_staging_address_service.dart';

export 'swap_provider_config.dart';

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
  var _previewQuoteGeneration = 0;
  var _statusRefreshInFlight = false;
  Timer? _previewQuoteDebounce;

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
    final priceRefreshInterval = ref.watch(swapPriceRefreshIntervalProvider);
    final priceRefreshTimer = Timer.periodic(priceRefreshInterval, (_) {
      unawaited(_loadSupportedExternalAssets(forceRefreshPrices: true));
    });
    ref.onDispose(priceRefreshTimer.cancel);
    ref.onDispose(() {
      _previewQuoteDebounce?.cancel();
    });
    unawaited(_restorePersistedDraft());
    unawaited(_loadSupportedExternalAssets());
    unawaited(_restorePersistedIntents(accountUuid: _activeAccountUuidOrNull));
    final initialIntents = ref.watch(swapInitialIntentsProvider);
    final initialRequests = ref.watch(swapInitialExternalRequestsProvider);
    return const SwapPrototypeState(
      direction: SwapDirection.zecToExternal,
      amountText: '',
      receiveAmountText: '',
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
    state = _withDerivedFiatTexts(
      _withIndicativeCounterpart(
        state.copyWith(
          direction: direction,
          quoteMode: SwapQuoteMode.exactInput,
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          reviewVisible: false,
          clearPreviewQuote: true,
          clearPreviewQuoteError: true,
        ),
      ),
    );
    unawaited(_persistDraft(_currentDraftSnapshot));
    _schedulePreviewQuote();
  }

  void toggleDirection() {
    final currentQuote = state.quote;
    final nextDirection = state.direction.toggled;
    final nextAmountText = currentQuote == null
        ? state.quoteAmountText
        : currentQuote.receiveAsset.formatAmount(currentQuote.receiveAmount);

    _clearReviewState();
    state = _withDerivedFiatTexts(
      _withIndicativeCounterpart(
        state.copyWith(
          direction: nextDirection,
          quoteMode: SwapQuoteMode.exactInput,
          amountText: nextAmountText,
          receiveAmountText: '',
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          reviewVisible: false,
          clearPreviewQuote: true,
          clearPreviewQuoteError: true,
        ),
      ),
    );
    unawaited(_persistDraft(_currentDraftSnapshot));
    _schedulePreviewQuote();
  }

  void updateAmount(String value) {
    _clearReviewState();
    state = _withDerivedFiatTexts(
      _withIndicativeCounterpart(
        state.copyWith(
          quoteMode: SwapQuoteMode.exactInput,
          amountText: value,
          reviewVisible: false,
          clearPreviewQuote: true,
          clearPreviewQuoteError: true,
          clearMaxAmountError: true,
        ),
      ),
    );
    _schedulePreviewQuote();
  }

  void updateAmountFiat(String value) {
    _clearReviewState();
    final tokenText = swapTokenAmountTextFromFiatText(
      state,
      asset: state.direction.fromAsset(state.externalAsset),
      fiatAmountText: value,
    );
    state = _withDerivedFiatTexts(
      _withIndicativeCounterpart(
        state.copyWith(
          quoteMode: SwapQuoteMode.exactInput,
          amountInputMode: SwapAmountInputMode.fiat,
          amountFiatText: value,
          amountText: tokenText ?? '',
          reviewVisible: false,
          clearPreviewQuote: true,
          clearPreviewQuoteError: true,
          clearMaxAmountError: true,
        ),
      ),
      preserveAmountFiatInput: true,
    );
    _schedulePreviewQuote();
  }

  void updateReceiveAmount(String value) {
    _clearReviewState();
    state = _withDerivedFiatTexts(
      _withIndicativeCounterpart(
        state.copyWith(
          quoteMode: SwapQuoteMode.exactOutput,
          receiveAmountText: value,
          reviewVisible: false,
          clearPreviewQuote: true,
          clearPreviewQuoteError: true,
          clearMaxAmountError: true,
        ),
      ),
    );
    _schedulePreviewQuote();
  }

  void updateReceiveAmountFiat(String value) {
    _clearReviewState();
    final tokenText = swapTokenAmountTextFromFiatText(
      state,
      asset: state.direction.toAsset(state.externalAsset),
      fiatAmountText: value,
    );
    state = _withDerivedFiatTexts(
      _withIndicativeCounterpart(
        state.copyWith(
          quoteMode: SwapQuoteMode.exactOutput,
          receiveAmountInputMode: SwapAmountInputMode.fiat,
          receiveFiatText: value,
          receiveAmountText: tokenText ?? '',
          reviewVisible: false,
          clearPreviewQuote: true,
          clearPreviewQuoteError: true,
          clearMaxAmountError: true,
        ),
      ),
      preserveReceiveFiatInput: true,
    );
    _schedulePreviewQuote();
  }

  void toggleFiatInputMode(SwapAmountInputSide side) {
    _clearReviewState();
    final next = switch (side) {
      SwapAmountInputSide.pay => _togglePayInputMode(state),
      SwapAmountInputSide.receive => _toggleReceiveInputMode(state),
    };
    state = next.copyWith(
      reviewVisible: false,
      clearPreviewQuote: true,
      clearPreviewQuoteError: true,
      clearMaxAmountError: true,
    );
    _schedulePreviewQuote();
  }

  void updateDestination(String value) {
    _clearReviewState();
    state = state.copyWith(
      destinationText: value,
      reviewVisible: false,
      clearPreviewQuote: true,
      clearPreviewQuoteError: true,
      clearMaxAmountError: true,
    );
    _schedulePreviewQuote();
  }

  void selectExternalAsset(SwapAsset asset) {
    final supportedAsset = _supportedAssetFor(
      asset,
      state.supportedExternalAssets,
    );
    if (supportedAsset == null) return;
    _clearReviewState();
    state = _withDerivedFiatTexts(
      _withIndicativeCounterpart(
        _withTokenAmountsForFiatModes(
          state.copyWith(
            externalAsset: supportedAsset,
            reviewVisible: false,
            clearPreviewQuote: true,
            clearPreviewQuoteError: true,
          ),
        ),
      ),
      preserveAmountFiatInput:
          state.amountInputMode == SwapAmountInputMode.fiat,
      preserveReceiveFiatInput:
          state.receiveAmountInputMode == SwapAmountInputMode.fiat,
    );
    unawaited(_persistDraft(_currentDraftSnapshot));
    _schedulePreviewQuote();
  }

  void updateSlippageBps(int value) {
    final normalized = value.clamp(10, 500).toInt();
    _clearReviewState();
    state = state.copyWith(
      slippageBps: normalized,
      reviewVisible: false,
      clearPreviewQuote: true,
      clearPreviewQuoteError: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
    state = _withDerivedFiatTexts(
      _withIndicativeCounterpart(state),
      preserveAmountFiatInput:
          state.amountInputMode == SwapAmountInputMode.fiat,
      preserveReceiveFiatInput:
          state.receiveAmountInputMode == SwapAmountInputMode.fiat,
    );
    unawaited(_persistDraft(_currentDraftSnapshot));
    _schedulePreviewQuote();
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
      state = _withDerivedFiatTexts(
        _withIndicativeCounterpart(
          state.copyWith(
            quoteMode: SwapQuoteMode.exactInput,
            amountText: amountText,
            amountInputMode: SwapAmountInputMode.token,
            maxAmountLoading: false,
            reviewVisible: false,
            clearReview: true,
            clearPreviewQuote: true,
            clearPreviewQuoteError: true,
            clearMaxAmountError: true,
            clearQuoteError: true,
            clearStatusError: true,
          ),
        ),
      );
      _schedulePreviewQuote();
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
      var nextState = state.copyWith(
        supportedExternalAssets: supported,
        indicativeExternalPerZec:
            pricing?.externalPerZec ?? state.indicativeExternalPerZec,
        externalAsset: selected,
        reviewVisible: selectedChanged ? false : state.reviewVisible,
        clearReview: selectedChanged,
        clearQuoteError: true,
      );
      nextState = _withTokenAmountsForFiatModes(nextState);
      if (nextState.reviewQuote == null && nextState.previewQuote == null) {
        nextState = _withIndicativeCounterpart(nextState);
      }
      state = _withDerivedFiatTexts(
        nextState,
        preserveAmountFiatInput:
            nextState.amountInputMode == SwapAmountInputMode.fiat,
        preserveReceiveFiatInput:
            nextState.receiveAmountInputMode == SwapAmountInputMode.fiat,
      );
    } catch (_) {
      // Keep the static fallback so the prototype remains usable offline.
    }
  }

  Future<void> showReview() async {
    if (!state.canReviewQuote) return;

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final amount = state.quoteAmount;
    if (accountUuid == null || amount == null) {
      return;
    }

    final direction = state.direction;
    final externalAsset = state.externalAsset;
    final userExternalAddress = state.destinationText;
    final quoteMode = state.quoteMode;
    final amountText = state.quoteAmountText;
    final generation = ++_quoteGeneration;
    _previewQuoteGeneration++;
    _previewQuoteDebounce?.cancel();
    final draft = _currentDraftSnapshot;

    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: true,
      previewQuoteLoading: false,
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
              mode: quoteMode,
              amount: amount,
              amountText: amountText,
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
    var intent = swapIntentFromSnapshot(
      snapshot: snapshot,
      quote: quote,
      addressPlan: addressPlan,
      accountUuid: accountUuid,
      now: DateTime.now().toUtc(),
    );
    if (activeAccountIsHardware && quote.direction.sendsZec) {
      const nextAction = 'Sign and send the ZEC deposit with Keystone.';
      intent = intent.copyWith(
        nextAction: nextAction,
        steps: swapStepsForStatus(intent.status, nextAction),
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
      receiveAmountText: '',
      quoteMode: SwapQuoteMode.exactInput,
      amountInputMode: SwapAmountInputMode.token,
      receiveAmountInputMode: SwapAmountInputMode.token,
      amountFiatText: '',
      receiveFiatText: '',
      destinationText: '',
      intents: [intent, ...state.intents],
      startSubmitting: false,
      quoteLoading: false,
      selectedIntentId: intent.id,
      depositTxHashText: '',
      clearReview: true,
      clearPreviewQuote: true,
      clearPreviewQuoteError: true,
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
    await _refreshIntentStatuses(
      intentIds: [selected.id],
      showBusy: true,
      includeTerminal: true,
    );
  }

  Future<void> refreshOpenIntentStatuses() async {
    await _refreshIntentStatuses(
      intentIds: [for (final intent in state.intents) intent.id],
      showBusy: false,
      includeTerminal: false,
    );
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
      quoteMode: SwapQuoteMode.exactInput,
      amountText: amountText,
      receiveAmountText: '',
      amountInputMode: SwapAmountInputMode.token,
      receiveAmountInputMode: SwapAmountInputMode.token,
      amountFiatText: '',
      receiveFiatText: '',
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
      clearPreviewQuote: true,
      clearPreviewQuoteError: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
    state = _withDerivedFiatTexts(_withIndicativeCounterpart(state));
    _schedulePreviewQuote();
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
      quoteMode: SwapQuoteMode.exactInput,
      amountText: amountText,
      receiveAmountText: '',
      amountInputMode: SwapAmountInputMode.token,
      receiveAmountInputMode: SwapAmountInputMode.token,
      amountFiatText: '',
      receiveFiatText: '',
      destinationText: destinationText,
      reviewVisible: false,
      quoteLoading: false,
      depositTxHashText: '',
      clearReview: true,
      clearPreviewQuote: true,
      clearPreviewQuoteError: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
    state = _withDerivedFiatTexts(_withIndicativeCounterpart(state));
    _schedulePreviewQuote();
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
    final checkpointed = swapPrototypeIntentFromRecord(
      SwapIntentRecord.fromIntent(selected).copyWith(
        depositTxHash: txHash,
        statusError: broadcastNotice,
        broadcastNotice: broadcastNotice,
        clearStatusError: broadcastNotice == null,
        clearBroadcastNotice: broadcastNotice == null,
        updatedAt: DateTime.now().toUtc(),
      ),
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
    final storedIntents = await ref
        .read(swapActivityTrackerProvider)
        .loadIntents(accountUuid: scopedAccountUuid);
    final intent = _intentByIdFrom(storedIntents, intentId);
    if (intent == null) return;

    final broadcastNotice = _hardwareBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final checkpointed = swapPrototypeIntentFromRecord(
      SwapIntentRecord.fromIntent(intent).copyWith(
        depositTxHash: txHash,
        statusError: statusError ?? broadcastNotice,
        broadcastNotice: broadcastNotice,
        clearStatusError: statusError == null && broadcastNotice == null,
        clearBroadcastNotice: broadcastNotice == null,
        updatedAt: DateTime.now().toUtc(),
      ),
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
        .read(swapActivityTrackerProvider)
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
    late final String txHash;
    try {
      txHash = await ref
          .read(swapDepositSenderProvider)
          .sendZecDeposit(accountUuid: accountUuid, quote: quote);
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
        return;
      }
      state = state.copyWith(depositSubmitting: false, statusError: message);
      return;
    }

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
    final checkpointed = swapPrototypeIntentFromRecord(
      SwapIntentRecord.fromIntent(
        intent,
      ).copyWith(depositTxHash: txHash, updatedAt: DateTime.now().toUtc()),
    );
    state = state.copyWith(
      depositTxHashText: txHash,
      intents: _replaceIntent(state.intents, intentId, checkpointed),
    );
    await _persistCurrentIntents();

    try {
      final snapshot = await ref
          .read(swapIntentProvider)
          .submitDepositTransaction(
            depositAddress: _providerDepositAddress(intent),
            txHash: txHash,
            depositMemo: intent.depositMemo,
          );
      final updated = swapPrototypeIntentFromRecord(
        SwapIntentRecord.fromIntent(
          updateSwapIntentFromSnapshot(checkpointed, snapshot),
        ).copyWith(
          depositTxHash: txHash,
          clearStatusError: true,
          updatedAt: DateTime.now().toUtc(),
        ),
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
        'Swap: live ZEC deposit submit failed after broadcast '
        'intent=${_shortSwapValue(intentId)} tx=${_shortSwapValue(txHash)} '
        'error=$e',
      );
      final message = swapFailureMessage(SwapFailureOperation.submitDeposit, e);
      if (!_isAccountActive(accountUuid)) {
        await _submitDepositTransactionForStoredIntent(
          accountUuid: accountUuid,
          intentId: intentId,
          txHash: txHash,
          submitProviderStatus: false,
          statusError: message,
        );
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

  SwapPrototypeState _withIndicativeCounterpart(SwapPrototypeState next) {
    final estimate = next.draftQuote;
    if (estimate == null) {
      return next.quoteMode == SwapQuoteMode.exactInput
          ? next.copyWith(receiveAmountText: '')
          : next.copyWith(amountText: '');
    }
    if (next.quoteMode == SwapQuoteMode.exactInput) {
      return next.copyWith(
        receiveAmountText: estimate.receiveAsset.formatAmount(
          estimate.receiveAmount,
        ),
      );
    }
    return next.copyWith(
      amountText: estimate.sellAsset.formatAmount(estimate.sellAmount),
    );
  }

  SwapPrototypeState _withDerivedFiatTexts(
    SwapPrototypeState next, {
    bool preserveAmountFiatInput = false,
    bool preserveReceiveFiatInput = false,
  }) {
    return next.copyWith(
      amountFiatText: preserveAmountFiatInput
          ? next.amountFiatText
          : swapFiatInputTextFromTokenText(
              next,
              asset: next.direction.fromAsset(next.externalAsset),
              tokenAmountText: next.amountText,
            ),
      receiveFiatText: preserveReceiveFiatInput
          ? next.receiveFiatText
          : swapFiatInputTextFromTokenText(
              next,
              asset: next.direction.toAsset(next.externalAsset),
              tokenAmountText: next.receiveAmountText,
            ),
    );
  }

  SwapPrototypeState _withTokenAmountsForFiatModes(SwapPrototypeState current) {
    var next = current;
    if (next.amountInputMode == SwapAmountInputMode.fiat) {
      final tokenText = swapTokenAmountTextFromFiatText(
        next,
        asset: next.direction.fromAsset(next.externalAsset),
        fiatAmountText: next.amountFiatText,
      );
      next = next.copyWith(amountText: tokenText ?? '');
    }
    if (next.receiveAmountInputMode == SwapAmountInputMode.fiat) {
      final tokenText = swapTokenAmountTextFromFiatText(
        next,
        asset: next.direction.toAsset(next.externalAsset),
        fiatAmountText: next.receiveFiatText,
      );
      next = next.copyWith(receiveAmountText: tokenText ?? '');
    }
    return next;
  }

  SwapPrototypeState _togglePayInputMode(SwapPrototypeState current) {
    final nextMode = current.amountInputMode == SwapAmountInputMode.token
        ? SwapAmountInputMode.fiat
        : SwapAmountInputMode.token;
    return current.copyWith(
      amountInputMode: nextMode,
      amountFiatText: nextMode == SwapAmountInputMode.fiat
          ? swapFiatInputTextFromTokenText(
              current,
              asset: current.direction.fromAsset(current.externalAsset),
              tokenAmountText: current.amountText,
            )
          : current.amountFiatText,
    );
  }

  SwapPrototypeState _toggleReceiveInputMode(SwapPrototypeState current) {
    final nextMode = current.receiveAmountInputMode == SwapAmountInputMode.token
        ? SwapAmountInputMode.fiat
        : SwapAmountInputMode.token;
    return current.copyWith(
      receiveAmountInputMode: nextMode,
      receiveFiatText: nextMode == SwapAmountInputMode.fiat
          ? swapFiatInputTextFromTokenText(
              current,
              asset: current.direction.toAsset(current.externalAsset),
              tokenAmountText: current.receiveAmountText,
            )
          : current.receiveFiatText,
    );
  }

  void _schedulePreviewQuote() {
    _previewQuoteDebounce?.cancel();
    final generation = ++_previewQuoteGeneration;
    if (state.quoteMode != SwapQuoteMode.exactOutput) {
      state = state.copyWith(
        previewQuoteLoading: false,
        clearPreviewQuote: true,
        clearPreviewQuoteError: true,
      );
      return;
    }
    final amount = state.quoteAmount;
    final accountUuid = _activeAccountUuidOrNull;
    if (amount == null ||
        accountUuid == null ||
        state.destinationText.trim().isEmpty) {
      state = state.copyWith(
        previewQuoteLoading: false,
        clearPreviewQuote: true,
        clearPreviewQuoteError: true,
      );
      return;
    }

    state = state.copyWith(
      previewQuoteLoading: true,
      clearPreviewQuoteError: true,
    );
    final delay = ref.read(swapPreviewQuoteDebounceProvider);
    if (delay == Duration.zero) {
      unawaited(_loadPreviewQuote(generation));
      return;
    }
    _previewQuoteDebounce = Timer(delay, () {
      unawaited(_loadPreviewQuote(generation));
    });
  }

  Future<void> _loadPreviewQuote(int generation) async {
    final accountUuid = _activeAccountUuidOrNull;
    final amount = state.quoteAmount;
    if (accountUuid == null || amount == null) {
      return;
    }
    final direction = state.direction;
    final externalAsset = state.externalAsset;
    final userExternalAddress = state.destinationText;
    final quoteMode = state.quoteMode;
    final amountText = state.quoteAmountText;
    final slippageBps = state.slippageBps;

    try {
      final stagingAddress = await ref
          .read(swapZecStagingAddressServiceProvider)
          .prepareForPreviewQuote(accountUuid: accountUuid);
      final addressPlan = stagingAddress.toAddressPlan(
        direction: direction,
        externalAsset: externalAsset,
        userExternalAddress: userExternalAddress,
      );
      final quote = await ref
          .read(swapIntentProvider)
          .quote(
            addressPlan.toQuoteRequest(
              mode: quoteMode,
              amount: amount,
              amountText: amountText,
              dryRun: true,
              slippageBps: slippageBps,
            ),
          );
      if (generation != _previewQuoteGeneration) return;
      if (!_isAccountActive(accountUuid)) return;
      if (state.quoteMode != quoteMode ||
          state.direction != direction ||
          state.externalAsset != externalAsset ||
          state.destinationText != userExternalAddress) {
        return;
      }
      state = _withPreviewQuoteCounterpart(
        state.copyWith(
          previewQuote: quote,
          previewQuoteLoading: false,
          clearPreviewQuoteError: true,
        ),
        quote,
      );
    } catch (e) {
      if (generation != _previewQuoteGeneration) return;
      state = state.copyWith(
        previewQuoteLoading: false,
        previewQuoteError: _friendlyQuoteError(e),
        clearPreviewQuote: true,
      );
    }
  }

  SwapPrototypeState _withPreviewQuoteCounterpart(
    SwapPrototypeState next,
    SwapQuote quote,
  ) {
    return _withDerivedFiatTexts(
      next.copyWith(amountText: quote.sellAsset.formatAmount(quote.sellAmount)),
      preserveAmountFiatInput: next.amountInputMode == SwapAmountInputMode.fiat,
      preserveReceiveFiatInput:
          next.receiveAmountInputMode == SwapAmountInputMode.fiat,
    );
  }

  void _clearAccountScopedTransientState() {
    _quoteGeneration++;
    _previewQuoteGeneration++;
    _previewQuoteDebounce?.cancel();
    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: false,
      previewQuoteLoading: false,
      startSubmitting: false,
      maxAmountLoading: false,
      depositSubmitting: false,
      depositTxHashText: '',
      statusRefreshing: false,
      clearReview: true,
      clearPreviewQuote: true,
      clearPreviewQuoteError: true,
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
          .read(swapActivityTrackerProvider)
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
      final draft = await ref.read(swapDraftStoreProvider).loadDraft();
      if (draft == null) return;
      if (state.amountText.isNotEmpty ||
          state.receiveAmountText.isNotEmpty ||
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

  Future<void> _refreshIntentStatuses({
    required Iterable<String> intentIds,
    required bool showBusy,
    required bool includeTerminal,
  }) async {
    final ids = intentIds.toSet();
    if (_statusRefreshInFlight || ids.isEmpty) return;
    final refreshAccountUuid = _activeAccountUuidOrNull;
    if (refreshAccountUuid == null || refreshAccountUuid.trim().isEmpty) {
      return;
    }
    _statusRefreshInFlight = true;
    if (showBusy) {
      state = state.copyWith(statusRefreshing: true, clearStatusError: true);
    }

    try {
      final result = includeTerminal
          ? await ref
                .read(swapActivityTrackerProvider)
                .refreshIntents(
                  accountUuid: refreshAccountUuid,
                  currentIntents: state.intents,
                  intentIds: ids,
                  includeTerminal: true,
                )
          : await ref
                .read(swapActivityTrackerProvider)
                .refreshOpenIntents(
                  accountUuid: refreshAccountUuid,
                  currentIntents: state.intents,
                );

      if (!result.didRefresh) {
        if (showBusy) {
          state = state.copyWith(statusRefreshing: false);
        }
        return;
      }

      if (!_isAccountActive(refreshAccountUuid)) {
        return;
      }

      _logStatusTransitions(state.intents, result.intents);
      state = state.copyWith(
        statusRefreshing: false,
        intents: result.intents,
        statusError: showBusy ? result.refreshError : null,
        clearStatusError: result.refreshError == null,
      );
    } finally {
      _statusRefreshInFlight = false;
    }
  }

  void _logStatusTransitions(
    List<SwapPrototypeIntent> before,
    List<SwapPrototypeIntent> after,
  ) {
    for (final updated in after) {
      final previous = _intentByIdFrom(before, updated.id);
      if (previous == null || previous.status == updated.status) continue;
      log(
        'Swap: status transition intent=${_shortSwapValue(updated.id)} '
        '${previous.status.name}->${updated.status.name}',
      );
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
    await ref
        .read(swapActivityTrackerProvider)
        .saveIntents(accountUuid: scopedAccountUuid, intents: intentsToPersist);
  }

  bool _isAccountActive(String? accountUuid) {
    final scopedAccountUuid = accountUuid?.trim();
    return scopedAccountUuid == null ||
        scopedAccountUuid.isEmpty ||
        scopedAccountUuid == _activeAccountUuidOrNull;
  }

  Future<void> _persistDraft(SwapDraftSnapshot draft) async {
    try {
      await ref.read(swapDraftStoreProvider).saveDraft(draft);
    } catch (_) {}
  }

  SwapDraftSnapshot get _currentDraftSnapshot {
    return SwapDraftSnapshot(
      direction: state.direction,
      externalAsset: state.externalAsset,
      slippageBps: state.slippageBps,
    );
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

  SwapPrototypeIntent _depositSnapshotIntent(
    SwapPrototypeIntent intent,
    SwapIntentSnapshot snapshot, {
    required String txHash,
    String? broadcastNotice,
  }) {
    final updated = updateSwapIntentFromSnapshot(intent, snapshot);
    return swapPrototypeIntentFromRecord(
      SwapIntentRecord.fromIntent(updated).copyWith(
        depositTxHash: txHash,
        statusError: broadcastNotice,
        broadcastNotice: broadcastNotice,
        clearStatusError: broadcastNotice == null,
        clearBroadcastNotice: broadcastNotice == null,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  bool _isHardwareIntent(SwapPrototypeIntent intent) {
    final accountUuid = _accountUuidForIntent(intent);
    if (accountUuid == null || accountUuid.trim().isEmpty) return false;
    return ref.read(accountProvider.notifier).isHardwareAccount(accountUuid);
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
