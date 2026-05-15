import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/near_intents_one_click_swap_provider.dart';
import '../domain/zip321_payment_request.dart';
import '../models/swap_prototype_models.dart';
import '../../../providers/account_provider.dart';
import 'swap_deposit_sender.dart';
import 'swap_failure_policy.dart';
import 'swap_shielding_service.dart';
import 'swap_session_store.dart';
import 'swap_zec_staging_address_service.dart';

const _oneClickBaseUrl = String.fromEnvironment(
  'ZCASH_SWAP_1CLICK_BASE_URL',
  defaultValue: 'https://1click.chaindefuser.com',
);
const _oneClickJwt = String.fromEnvironment('ZCASH_SWAP_1CLICK_JWT');
const _oneClickReferral = String.fromEnvironment('ZCASH_SWAP_1CLICK_REFERRAL');

final swapIntentProvider = Provider<SwapProvider>((ref) {
  return NearIntentsOneClickSwapProvider(
    baseUri: Uri.parse(_oneClickBaseUrl),
    bearerToken: _oneClickJwt.isEmpty ? null : _oneClickJwt,
    referral: _oneClickReferral.isEmpty ? null : _oneClickReferral,
  );
});

final swapStatusPollIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 20);
});

final swapPriceRefreshIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 30);
});

const _liveFundsEnabled = bool.fromEnvironment('ZCASH_SWAP_ENABLE_LIVE_FUNDS');

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

  @override
  SwapPrototypeState build() {
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
    unawaited(_restorePersistedDraft());
    unawaited(_loadSupportedExternalAssets());
    unawaited(_restorePersistedIntents());
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
    state = state.copyWith(amountText: value, reviewVisible: false);
  }

  void updateDestination(String value) {
    _clearReviewState();
    state = state.copyWith(destinationText: value, reviewVisible: false);
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
              slippageBps: state.slippageBps,
            ),
          );
      if (generation != _quoteGeneration) return;

      state = state.copyWith(
        reviewVisible: true,
        reviewQuote: quote,
        reviewAddressPlan: addressPlan,
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
      return false;
    }
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;

    late final SwapIntentSnapshot snapshot;
    try {
      snapshot = await ref.read(swapIntentProvider).startSwap(quote);
    } catch (e) {
      state = state.copyWith(
        quoteLoading: false,
        statusError: swapFailureMessage(SwapFailureOperation.start, e),
      );
      return false;
    }
    final intent = _intentFromSnapshot(snapshot, quote, addressPlan);
    _quoteGeneration++;
    state = state.copyWith(
      reviewVisible: false,
      amountText: '',
      destinationText: '',
      intents: [intent, ...state.intents],
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
        state = state.copyWith(
          statusError:
              'Live ZEC deposit is disabled in this build. The quote is saved, but no wallet transaction was signed or broadcast.',
        );
        return true;
      }
      if (accountUuid == null) {
        state = state.copyWith(statusError: 'No active account');
        return true;
      }
      await _sendAndSubmitZecDeposit(
        accountUuid: accountUuid,
        quote: quote,
        intentId: intent.id,
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

    const nextAction = 'Retrying wallet shielding from the staging address';
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
    if (!ref.read(swapLiveFundsEnabledProvider)) {
      state = state.copyWith(
        statusError:
            'Live deposit submission is disabled in this build. No swap status update was sent.',
      );
      return;
    }
    final selected = state.selectedIntent;
    final txHash = state.depositTxHashText.trim();

    state = state.copyWith(depositSubmitting: true, clearStatusError: true);
    try {
      final snapshot = await ref
          .read(swapIntentProvider)
          .submitDepositTransaction(
            depositAddress: _providerDepositAddress(selected),
            txHash: txHash,
            depositMemo: selected.depositMemo,
          );
      final updated = _updateIntentFromSnapshot(selected, snapshot).copyWith(
        depositTxHash: txHash,
        receipt: _receiptWithDepositTx(selected.receipt, txHash),
      );
      state = state.copyWith(
        depositSubmitting: false,
        intents: _replaceIntent(state.intents, selected.id, updated),
        clearStatusError: true,
      );
      await _persistCurrentIntents();
    } catch (e) {
      state = state.copyWith(
        depositSubmitting: false,
        statusError: swapFailureMessage(SwapFailureOperation.submitDeposit, e),
      );
    }
  }

  Future<void> _sendAndSubmitZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
    required String intentId,
  }) async {
    state = state.copyWith(depositSubmitting: true, clearStatusError: true);
    try {
      final txHash = await ref
          .read(swapDepositSenderProvider)
          .sendZecDeposit(accountUuid: accountUuid, quote: quote);
      final intent = _intentById(intentId);
      if (intent == null) return;
      final snapshot = await ref
          .read(swapIntentProvider)
          .submitDepositTransaction(
            depositAddress: _providerDepositAddress(intent),
            txHash: txHash,
            depositMemo: intent.depositMemo,
          );
      final updated = _updateIntentFromSnapshot(intent, snapshot).copyWith(
        depositTxHash: txHash,
        receipt: _receiptWithDepositTx(intent.receipt, txHash),
      );
      state = state.copyWith(
        depositTxHashText: txHash,
        depositSubmitting: false,
        intents: _replaceIntent(state.intents, intentId, updated),
        clearStatusError: true,
      );
      await _persistCurrentIntents();
    } catch (e) {
      state = state.copyWith(
        depositSubmitting: false,
        statusError: swapFailureMessage(SwapFailureOperation.sendZecDeposit, e),
      );
    }
  }

  void _clearReviewState() {
    _quoteGeneration++;
    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: false,
      clearReview: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
  }

  Future<void> _restorePersistedIntents() async {
    try {
      final persisted = await ref.read(swapSessionStoreProvider).loadIntents();
      if (persisted.isEmpty) return;
      state = state.copyWith(
        intents: persisted,
        selectedIntentId: persisted.first.id,
        depositTxHashText: persisted.first.depositTxHash ?? '',
        clearStatusError: true,
      );
      unawaited(refreshOpenIntentStatuses());
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
          state.supportedExternalAssets.contains(draft.externalAsset)
          ? draft.externalAsset
          : state.externalAsset;
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
    _statusRefreshInFlight = true;
    if (showBusy) {
      state = state.copyWith(statusRefreshing: true, clearStatusError: true);
    }

    try {
      var updatedIntents = state.intents;
      var changed = false;
      for (final intent in intents) {
        final currentIntent = _intentByIdFrom(updatedIntents, intent.id);
        if (currentIntent == null) continue;
        final updated =
            currentIntent.status == SwapIntentStatus.shieldingConfirming
            ? await _tryTrackShieldTransaction(currentIntent)
            : await _refreshProviderBackedIntent(currentIntent);
        updatedIntents = _replaceIntent(
          updatedIntents,
          currentIntent.id,
          updated,
        );
        changed = true;
      }

      if (!changed) {
        if (showBusy) {
          state = state.copyWith(statusRefreshing: false);
        }
        return;
      }

      state = state.copyWith(
        statusRefreshing: false,
        intents: updatedIntents,
        clearStatusError: true,
      );
      await _persistCurrentIntents();
    } catch (e) {
      if (showBusy) {
        state = state.copyWith(
          statusRefreshing: false,
          statusError: swapFailureMessage(
            SwapFailureOperation.refreshStatus,
            e,
          ),
        );
      }
    } finally {
      _statusRefreshInFlight = false;
    }
  }

  Future<void> _persistCurrentIntents() async {
    final intents = [
      for (final intent in state.intents)
        if (_isPersistableIntent(intent)) intent,
    ];
    await ref.read(swapSessionStoreProvider).saveIntents(intents);
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

  bool _isPersistableIntent(SwapPrototypeIntent intent) {
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
              ? 'Wallet t-address is used only if a refund arrives'
              : '${addressPlan.zecStagingLabel}; ${addressPlan.zecShieldingLabel} follows',
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
          label: sendsZec ? 'Transparent window' : 'ZEC destination',
          value: sendsZec
              ? 'opens only if refund arrives; shield prompt follows'
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
        SwapPrototypeField(label: 'Swap id', value: snapshot.id),
        SwapPrototypeField(label: 'Pair', value: quote.pairText),
        if (quote.providerQuoteId != null)
          SwapPrototypeField(
            label: 'Provider quote',
            value: quote.providerQuoteId!,
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
        const SwapPrototypeField(
          label: 'Shared fields',
          value: 'txid + status only',
        ),
      ],
      direction: quote.direction,
      externalAsset: quote.externalAsset,
      depositAddress: quote.depositInstruction.address,
      depositMemo: quote.depositInstruction.memo,
      depositDeadline: quote.depositInstruction.deadline,
      providerQuoteId: quote.providerQuoteId,
      providerSignature: quote.providerSignature,
      oneClickRecipient: addressPlan.oneClickRecipient,
      oneClickRefundTo: addressPlan.oneClickRefundTo,
    );
  }

  SwapPrototypeIntent _updateIntentFromSnapshot(
    SwapPrototypeIntent intent,
    SwapIntentSnapshot snapshot,
  ) {
    final status = _walletAwareStatus(intent, snapshot.status);
    final nextAction = _walletAwareNextAction(
      intent,
      snapshot.status,
      snapshot.nextAction,
    );
    return intent.copyWith(
      id: intent.id,
      pair: snapshot.pairText,
      sellAmount: snapshot.sellAmountText,
      receiveEstimate: snapshot.receiveEstimateText,
      provider: snapshot.providerLabel,
      status: status,
      nextAction: nextAction,
      steps: _stepsForStatus(status, nextAction),
      depositAddress:
          intent.depositAddress ?? snapshot.depositInstruction.address,
      depositMemo: intent.depositMemo ?? snapshot.depositInstruction.memo,
      depositDeadline:
          snapshot.depositInstruction.deadline ?? intent.depositDeadline,
    );
  }

  SwapIntentStatus _walletAwareStatus(
    SwapPrototypeIntent intent,
    SwapIntentStatus providerStatus,
  ) {
    if (intent.direction == SwapDirection.externalToZec &&
        providerStatus == SwapIntentStatus.complete) {
      return SwapIntentStatus.shieldingPending;
    }
    return providerStatus;
  }

  String _walletAwareNextAction(
    SwapPrototypeIntent intent,
    SwapIntentStatus providerStatus,
    String providerNextAction,
  ) {
    if (intent.direction == SwapDirection.externalToZec &&
        providerStatus == SwapIntentStatus.complete) {
      return 'Provider delivery observed. Shield the staging address before marking complete.';
    }
    return providerNextAction;
  }

  Future<SwapPrototypeIntent> _tryShieldStagingAddress(
    SwapPrototypeIntent intent,
  ) async {
    if (!_needsWalletShielding(intent)) return intent;

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final transparentAddress = intent.oneClickRecipient;
    if (accountUuid == null ||
        transparentAddress == null ||
        transparentAddress.trim().isEmpty) {
      return _shieldingFailedIntent(intent);
    }

    try {
      final result = await ref
          .read(swapShieldingServiceProvider)
          .shieldStagingAddress(
            accountUuid: accountUuid,
            transparentAddress: transparentAddress,
          );
      final shieldTxHash = result.firstTxid;
      if (shieldTxHash == null || shieldTxHash.isEmpty) {
        return _shieldingFailedIntent(intent);
      }
      const nextAction = 'Waiting for shield transaction confirmation.';
      return intent.copyWith(
        status: SwapIntentStatus.shieldingConfirming,
        nextAction: nextAction,
        steps: _stepsForStatus(
          SwapIntentStatus.shieldingConfirming,
          nextAction,
        ),
        receipt: _receiptWithShieldTx(intent.receipt, shieldTxHash),
        shieldTxHash: shieldTxHash,
      );
    } on SwapShieldingNotReadyException {
      return intent;
    } catch (_) {
      return _shieldingFailedIntent(intent);
    }
  }

  bool _needsWalletShielding(SwapPrototypeIntent intent) {
    return intent.direction == SwapDirection.externalToZec &&
        intent.status == SwapIntentStatus.shieldingPending;
  }

  Future<SwapPrototypeIntent> _tryTrackShieldTransaction(
    SwapPrototypeIntent intent,
  ) async {
    if (intent.status != SwapIntentStatus.shieldingConfirming) return intent;

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
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
          const nextAction = 'Shield transaction confirmed.';
          return intent.copyWith(
            status: SwapIntentStatus.complete,
            nextAction: nextAction,
            steps: _stepsForStatus(SwapIntentStatus.complete, nextAction),
          );
        case SwapShieldTxStatus.expired:
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
    } catch (_) {
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

  List<SwapPrototypeField> _receiptWithShieldTx(
    List<SwapPrototypeField> receipt,
    String? txHash,
  ) {
    if (txHash == null || txHash.isEmpty) return receipt;
    return [
      for (final field in receipt)
        if (field.label != 'Shield tx') field,
      SwapPrototypeField(label: 'Shield tx', value: txHash),
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
