import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../models/swap_amount_input_mapper.dart';
import '../models/swap_deposit_broadcast_result.dart';
import '../models/swap_intent_presentation_mapper.dart';
import '../models/swap_models.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/fiat_currency_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import 'swap_activity_tracker.dart';
import 'swap_deposit_sender.dart';
import 'swap_failure_policy.dart';
import 'swap_max_amount_estimator.dart';
import 'swap_composer_preferences_store.dart';
import 'swap_provider_config.dart';
import 'swap_zec_staging_address_service.dart';
import '../../../core/config/fiat_currencies.dart';
import '../../../providers/zec_price_change_provider.dart';

export 'swap_provider_config.dart';

final swapInitialIntentsProvider = Provider<List<SwapIntent>>((ref) {
  return const [];
});

sealed class SwapStartResult {
  const SwapStartResult(this.intentId);

  final String intentId;
}

final class SwapStartedActivity extends SwapStartResult {
  const SwapStartedActivity(super.intentId);
}

final class SwapStartedKeystoneSigning extends SwapStartResult {
  const SwapStartedKeystoneSigning(super.intentId);
}

SwapQuoteMode _inputQuoteModeForDirection(SwapDirection direction) =>
    direction.sendsZec ? SwapQuoteMode.exactInput : SwapQuoteMode.flexInput;

class SwapNotifier extends Notifier<SwapState> {
  /// Latest display info WITHOUT resurrecting the autoDispose provider
  /// chain. A plain `ref.read(fiatDisplayProvider)` from this keepAlive
  /// notifier re-creates the disposed market-data poller (and its CoinGecko
  /// fetch) on every status-poll/price-refresh tick while no fiat surface is
  /// mounted. While the provider is dead nothing renders fiat, so the last
  /// known display is the correct denomination for state texts until a
  /// surface revives the chain and live reads resume.
  FiatDisplay get _fiatDisplay {
    if (ref.exists(fiatDisplayProvider)) {
      return _lastKnownFiatDisplay = ref.read(fiatDisplayProvider);
    }
    return _lastKnownFiatDisplay;
  }

  /// Starts as the USD fallback every fresh notifier resolves to before
  /// market data arrives (`FiatDisplay.displayCurrency` falls back to USD
  /// while the rate is unknown).
  FiatDisplay _lastKnownFiatDisplay = kUsdFiatDisplay;

  var _quoteGeneration = 0;
  var _accountScopeGeneration = 0;
  var _statusRefreshInFlight = false;

  /// Display-currency code the state's fiat texts were last derived in.
  String? _fiatTextsCurrencyCode;

  /// Fiat-mode side the user is typing in right now (composer focus), or
  /// null. Reported by the composer surfaces via [setActiveFiatEntrySide].
  SwapAmountInputSide? _activeFiatEntrySide;

  /// A currency change arrived while a fiat side was being typed in; that
  /// side's re-expression is deferred until the entry side changes.
  bool _fiatReexpressDeferred = false;

  String? get _activeAccountUuidOrNull =>
      ref.read(accountProvider).value?.activeAccountUuid;

  String? _accountUuidForIntent(SwapIntent intent) {
    final activeAccountUuid = _activeAccountUuidOrNull;
    if (activeAccountUuid == null || intent.accountUuid != activeAccountUuid) {
      return null;
    }
    return activeAccountUuid;
  }

  @override
  SwapState build() {
    // Fiat texts in state are denominated in the display currency they were
    // derived with. When the display currency changes (user picks a new one,
    // or the USD fallback resolves to the selected currency once market data
    // loads), re-express them from the canonical token amounts so a "$10"
    // fiat entry never silently relabels as "₩10" while the quote still uses
    // the USD-derived token amount. Rate drift within the same currency is
    // deliberately ignored — it would fight active typing without changing
    // the unit.
    //
    // The sync has two triggers, neither of which may pin the autoDispose
    // market-data poller from this keepAlive notifier (a strong listen on
    // fiatDisplayProvider here kept the 3-minute CoinGecko fetch alive for
    // the whole session; a weak one kept the disposed element resurrectable
    // on every state flush):
    //  1. the selected-currency listener below — safe, it targets a
    //     keepAlive provider — covers user picks while the chain is alive
    //     (any fiat surface mounted);
    //  2. the swap screens call [syncFiatTextsCurrency] on mount and on
    //     resolved-display changes, covering USD-fallback flips — those can
    //     only happen while some fiat surface keeps the chain alive anyway.
    _fiatTextsCurrencyCode = _fiatDisplay.displayCurrency.code;
    ref.listen<String>(
      fiatCurrencyProvider.select((currency) => currency.code),
      (previous, next) => syncFiatTextsCurrency(),
    );
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next) return;
        if (previous != null) {
          unawaited(_persistCurrentIntents(accountUuid: previous));
          unawaited(
            _persistComposerPreferences(
              _currentComposerPreferences,
              accountUuid: previous,
            ),
          );
        }
        _clearAccountScopedTransientState();
        unawaited(_restoreComposerPreferences(accountUuid: next));
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
    final activeAccountUuid = _activeAccountUuidOrNull;
    unawaited(_restoreComposerPreferences(accountUuid: activeAccountUuid));
    unawaited(_loadSupportedExternalAssets());
    unawaited(_restorePersistedIntents(accountUuid: activeAccountUuid));
    final initialIntents = ref.watch(swapInitialIntentsProvider);
    return const SwapState(
      direction: SwapDirection.zecToExternal,
      amountText: '',
      receiveAmountText: '',
      destinationText: '',
      externalAsset: SwapAsset.usdc,
      reviewVisible: false,
      intents: [],
    ).copyWith(
      intents: initialIntents,
      selectedIntentId: initialIntents.isEmpty ? null : initialIntents.first.id,
    );
  }

  void selectDirection(SwapDirection direction) {
    _clearReviewState();
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          direction: direction,
          quoteMode: _inputQuoteModeForDirection(direction),
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          reviewVisible: false,
        ),
      ),
    );
    unawaited(_persistComposerPreferences(_currentComposerPreferences));
  }

  void toggleDirection() {
    final currentQuote = state.quote;
    final nextDirection = state.direction.toggled;
    final nextAmountText = currentQuote == null
        ? state.quoteAmountText
        : currentQuote.receiveAsset.formatAmount(currentQuote.receiveAmount);

    _clearReviewState();
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          direction: nextDirection,
          quoteMode: _inputQuoteModeForDirection(nextDirection),
          amountText: nextAmountText,
          receiveAmountText: '',
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          reviewVisible: false,
        ),
      ),
    );
    unawaited(_persistComposerPreferences(_currentComposerPreferences));
  }

  void updateAmount(String value) {
    _clearReviewState();
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          quoteMode: _inputQuoteModeForDirection(state.direction),
          amountText: value,
          reviewVisible: false,
          clearMaxAmountError: true,
        ),
      ),
    );
  }

  void updateAmountFiat(String value) {
    _clearReviewState();
    final tokenText = swapPayTokenTextFromFiatInput(
      state,
      value,
      fiatDisplay: _fiatDisplay,
    );
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          quoteMode: _inputQuoteModeForDirection(state.direction),
          receiveAmountInputMode: SwapAmountInputMode.fiat,
          amountInputMode: SwapAmountInputMode.fiat,
          amountFiatText: value,
          amountText: tokenText ?? '',
          reviewVisible: false,
          clearMaxAmountError: true,
        ),
      ),
      preserveAmountFiatInput: true,
    );
  }

  void updateReceiveAmount(String value) {
    _clearReviewState();
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          quoteMode: SwapQuoteMode.exactOutput,
          receiveAmountText: value,
          reviewVisible: false,
          clearMaxAmountError: true,
        ),
      ),
    );
  }

  void updateReceiveAmountFiat(String value) {
    _clearReviewState();
    final tokenText = swapReceiveTokenTextFromFiatInput(
      state,
      value,
      fiatDisplay: _fiatDisplay,
    );
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          quoteMode: SwapQuoteMode.exactOutput,
          amountInputMode: SwapAmountInputMode.fiat,
          receiveAmountInputMode: SwapAmountInputMode.fiat,
          receiveFiatText: value,
          receiveAmountText: tokenText ?? '',
          reviewVisible: false,
          clearMaxAmountError: true,
        ),
      ),
      preserveReceiveFiatInput: true,
    );
  }

  void toggleFiatInputMode(SwapAmountInputSide side) {
    _clearReviewState();
    final next = swapStateWithToggledFiatInputMode(
      state,
      side,
      fiatDisplay: _fiatDisplay,
    );
    state = next.copyWith(reviewVisible: false, clearMaxAmountError: true);
  }

  /// The reported entry side, but only while that side is still in fiat
  /// input mode — mode changes happen without a focus event, so the check
  /// lives at use time instead of chasing every mode-changing handler.
  SwapAmountInputSide? get _currentFiatEntrySide {
    final side = _activeFiatEntrySide;
    return switch (side) {
      null => null,
      SwapAmountInputSide.pay
          when state.amountInputMode == SwapAmountInputMode.fiat =>
        side,
      SwapAmountInputSide.receive
          when state.receiveAmountInputMode == SwapAmountInputMode.fiat =>
        side,
      _ => null,
    };
  }

  /// Re-expresses the stored fiat texts when the display currency unit
  /// changed; no-op while it still matches, so redundant triggers collapse.
  /// The side the user is actively typing in is preserved — clobbering an
  /// in-progress entry (partial input included) is worse than a briefly
  /// stale label — and re-expressed once the side blurs.
  ///
  /// Called by the swap screens (mount + resolved-display changes) and the
  /// selected-currency listener in [build]; see the pinning note there.
  void syncFiatTextsCurrency() {
    final display = _fiatDisplay;
    final code = display.displayCurrency.code;
    final previous = _fiatTextsCurrencyCode;
    _fiatTextsCurrencyCode = code;
    if (previous == null || previous == code) return;
    final activeSide = _currentFiatEntrySide;
    if (activeSide != null) _fiatReexpressDeferred = true;
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: display,
      state,
      preserveAmountFiatInput: activeSide == SwapAmountInputSide.pay,
      preserveReceiveFiatInput: activeSide == SwapAmountInputSide.receive,
    );
  }

  void _flushDeferredFiatReexpression() {
    if (!_fiatReexpressDeferred) return;
    _fiatReexpressDeferred = false;
    state = swapStateWithDerivedFiatTexts(fiatDisplay: _fiatDisplay, state);
  }

  /// Composer surfaces report which fiat-mode field has focus (null when
  /// neither). When a deferred currency re-expression is pending, it runs as
  /// soon as the entry side changes, preserving only the newly-active side.
  ///
  /// The mounted guard covers the composers' dispose-time microtask, which
  /// can land after the container itself was torn down (widget tests).
  void setActiveFiatEntrySide(SwapAmountInputSide? side) {
    if (!ref.mounted) return;
    if (_activeFiatEntrySide == side) return;
    _activeFiatEntrySide = side;
    if (!_fiatReexpressDeferred) return;
    final activeSide = _currentFiatEntrySide;
    if (activeSide == null) _fiatReexpressDeferred = false;
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      state,
      preserveAmountFiatInput: activeSide == SwapAmountInputSide.pay,
      preserveReceiveFiatInput: activeSide == SwapAmountInputSide.receive,
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
    // The destination is an address on the external asset's chain. When the
    // chain changes (e.g. USDC-on-Ethereum -> SOL-on-Solana) the old address is
    // no longer valid, so clear it; keep it when only the token changes within
    // the same chain (e.g. USDC -> DAI on Ethereum). copyWith treats null as
    // "keep" and '' as "clear".
    final chainChanged =
        supportedAsset.chainTicker != state.externalAsset.chainTicker;
    _clearReviewState();
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(
        swapStateWithTokenAmountsForFiatModes(
          fiatDisplay: _fiatDisplay,
          state.copyWith(
            externalAsset: supportedAsset,
            reviewVisible: false,
            destinationText: chainChanged ? '' : null,
          ),
        ),
      ),
      preserveAmountFiatInput:
          state.amountInputMode == SwapAmountInputMode.fiat,
      preserveReceiveFiatInput:
          state.receiveAmountInputMode == SwapAmountInputMode.fiat,
    );
    unawaited(_persistComposerPreferences(_currentComposerPreferences));
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
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(state),
      preserveAmountFiatInput:
          state.amountInputMode == SwapAmountInputMode.fiat,
      preserveReceiveFiatInput:
          state.receiveAmountInputMode == SwapAmountInputMode.fiat,
    );
    unawaited(_persistComposerPreferences(_currentComposerPreferences));
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
    final quoteGeneration = _quoteGeneration;
    final accountScopeGeneration = _accountScopeGeneration;
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
      if (accountScopeGeneration != _accountScopeGeneration ||
          !_isAccountActive(accountUuid)) {
        return;
      }
      if (quoteGeneration != _quoteGeneration) {
        state = state.copyWith(maxAmountLoading: false);
        return;
      }
      if (maxZatoshi <= BigInt.zero) {
        state = state.copyWith(
          maxAmountLoading: false,
          maxAmountError: 'Insufficient shielded balance to cover fee',
        );
        return;
      }
      final amountText = ZecAmount.fromZatoshi(maxZatoshi).pretty().amountText;
      log('SwapMaxAmount: applied amount=$amountText');
      state = swapStateWithDerivedFiatTexts(
        fiatDisplay: _fiatDisplay,
        swapStateWithIndicativeCounterpart(
          state.copyWith(
            quoteMode: SwapQuoteMode.exactInput,
            amountText: amountText,
            amountInputMode: SwapAmountInputMode.token,
            maxAmountLoading: false,
            reviewVisible: false,
            clearReview: true,
            clearMaxAmountError: true,
            clearQuoteError: true,
            clearStatusError: true,
          ),
        ),
      );
    } catch (e) {
      if (accountScopeGeneration != _accountScopeGeneration ||
          !_isAccountActive(accountUuid)) {
        return;
      }
      if (quoteGeneration != _quoteGeneration) {
        state = state.copyWith(maxAmountLoading: false);
        return;
      }
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
        indicativeUsdPrices: pricing?.usdPrices ?? state.indicativeUsdPrices,
        externalAsset: selected,
        reviewVisible: selectedChanged ? false : state.reviewVisible,
        clearReview: selectedChanged,
        clearQuoteError: true,
      );
      nextState = swapStateWithTokenAmountsForFiatModes(
        nextState,
        fiatDisplay: _fiatDisplay,
      );
      if (nextState.reviewQuote == null) {
        nextState = swapStateWithIndicativeCounterpart(nextState);
      }
      state = swapStateWithDerivedFiatTexts(
        fiatDisplay: _fiatDisplay,
        nextState,
        preserveAmountFiatInput:
            nextState.amountInputMode == SwapAmountInputMode.fiat,
        preserveReceiveFiatInput:
            nextState.receiveAmountInputMode == SwapAmountInputMode.fiat,
      );
    } catch (_) {
      // Keep the static fallback so the swap flow remains usable offline.
    }
  }

  Future<void> showReview() async {
    // Review is the commitment point: apply any currency re-expression that
    // was deferred while a fiat field was focused, so the composer text and
    // symbol agree with the fiat values review derives. Token amounts are
    // unchanged — this only rewrites labels.
    _flushDeferredFiatReexpression();
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
    final preferences = _currentComposerPreferences;

    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: true,
      clearReview: true,
      clearQuoteError: true,
    );

    try {
      await _persistComposerPreferences(preferences);
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

  Future<SwapStartResult?> startIntent() async {
    final quote = state.reviewQuote;
    final addressPlan = state.reviewAddressPlan;
    if (quote == null || addressPlan == null || state.quoteExpired) {
      log(
        'Swap: start ignored; quote=${quote != null} '
        'addressPlan=${addressPlan != null} expired=${state.quoteExpired}',
      );
      return null;
    }
    final quoteExpiresAt = quote.quoteExpiresAt;
    if (quoteExpiresAt != null &&
        !DateTime.now().toUtc().isBefore(
          quoteExpiresAt.subtract(const Duration(seconds: 5)),
        )) {
      log('Swap: start blocked; quote expired at $quoteExpiresAt');
      expireReviewQuote();
      return null;
    }
    if (state.startSubmitting) {
      log('Swap: duplicate start ignored while start is already in flight');
      return null;
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
      return null;
    }

    log(
      'Swap: start begin pair=${quote.pairText} '
      'direction=${quote.direction.name} '
      'quote=${_shortSwapValue(quote.providerQuoteId)} '
      'deposit=${_shortSwapValue(quote.depositInstruction.address)}',
    );
    state = state.copyWith(startSubmitting: true, clearStatusError: true);
    if (accountUuid == null) {
      log('Swap: start blocked; no active account');
      state = state.copyWith(
        startSubmitting: false,
        statusError: 'No active account',
      );
      return null;
    }
    final activeAccountIsHardware = ref
        .read(accountProvider.notifier)
        .isActiveAccountHardware;
    if (quote.direction.sendsZec) {
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
        return null;
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
      return null;
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
      intent = intent.copyWith(nextAction: nextAction);
    }
    _quoteGeneration++;
    if (activeAccountIsHardware && quote.direction.sendsZec) {
      log(
        'Swap: start pending Keystone signing intent=${_shortSwapValue(intent.id)} '
        'status=${intent.status.name}',
      );
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
        pendingKeystoneSigningIntent: intent,
        startSubmitting: false,
        quoteLoading: false,
        depositTxHashText: '',
        clearReview: true,
        clearQuoteError: true,
        clearStatusError: true,
        clearSelectedIntent: true,
      );
      log(
        'Swap: hardware ZEC deposit waiting for Keystone signing '
        'intent=${_shortSwapValue(intent.id)}',
      );
      return SwapStartedKeystoneSigning(intent.id);
    }

    log(
      'Swap: start saved intent=${_shortSwapValue(intent.id)} '
      'status=${intent.status.name}',
    );
    state = state.copyWith(
      reviewVisible: false,
      amountText: '',
      receiveAmountText: '',
      quoteMode: _inputQuoteModeForDirection(state.direction),
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
      clearQuoteError: true,
      clearStatusError: true,
      clearPendingKeystoneSigningIntent: true,
    );
    await _persistCurrentIntents();

    if (quote.direction.sendsZec) {
      unawaited(
        _sendAndSubmitZecDeposit(
          accountUuid: accountUuid,
          quote: quote,
          intentId: intent.id,
        ),
      );
    }
    return SwapStartedActivity(intent.id);
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

  Future<void> markSelectedDepositClaimed() async {
    final selected = state.selectedIntentOrNull;
    if (selected == null) return;
    if (selected.depositClaimedAt != null) return;
    if (selected.status != SwapIntentStatus.awaitingExternalDeposit) return;
    final updated = selected.copyWith(depositClaimedAt: DateTime.now().toUtc());
    state = state.copyWith(
      intents: state.intents.replaceSwapIntent(selected.id, updated),
    );
    await _persistCurrentIntents();
  }

  void selectIntent(String intentId) {
    final intent = state.intents.swapIntentById(intentId);
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
        : remaining.swapIntentById(nextSelectedId);

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
    final intent = state.intents.swapIntentById(intentId);
    if (intent == null || !_isHardwareIntent(intent)) return;
    if (intent.direction != SwapDirection.zecToExternal) return;
    if (intent.depositTxHash?.trim().isNotEmpty ?? false) return;

    await removeIntent(intentId);
  }

  void clearPendingKeystoneSigningIntent(String intentId) {
    final pending = state.pendingKeystoneSigningIntent;
    if (pending == null || pending.id != intentId) return;
    state = state.copyWith(clearPendingKeystoneSigningIntent: true);
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
      quoteMode: _inputQuoteModeForDirection(direction),
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
      clearQuoteError: true,
      clearStatusError: true,
    );
    state = swapStateWithDerivedFiatTexts(
      fiatDisplay: _fiatDisplay,
      swapStateWithIndicativeCounterpart(state),
    );
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
    final selected = state.intents.swapIntentById(intentId);
    final normalizedTxHash = txHash.trim();
    if (normalizedTxHash.isEmpty) return;
    final broadcastNotice = _depositBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final submitProviderStatus = _shouldSubmitProviderDepositStatus(
      broadcastStatus,
    );
    if (!submitProviderStatus) {
      await _switchEndpointAfterUncertainBroadcast(broadcastMessage);
    }
    if (selected == null) {
      await _submitDepositTransactionForStoredIntent(
        accountUuid: accountUuid,
        intentId: intentId,
        txHash: normalizedTxHash,
        broadcastStatus: broadcastStatus,
        broadcastMessage: broadcastMessage,
        submitProviderStatus: submitProviderStatus,
      );
      return;
    }
    await _submitDepositTransaction(
      selected,
      normalizedTxHash,
      broadcastStatus: broadcastStatus,
      broadcastMessage: broadcastMessage,
      submitProviderStatus: submitProviderStatus,
    );
    if (broadcastNotice == null) return;
    final current = state.intents.swapIntentById(selected.id);
    if (current == null ||
        current.statusError != null ||
        current.depositTxHash != normalizedTxHash) {
      return;
    }
    final patched = swapIntentWithBroadcastNotice(
      current,
      notice: broadcastNotice,
      broadcastStatus: broadcastStatus,
    );
    state = state.copyWith(
      intents: state.intents.replaceSwapIntent(selected.id, patched),
    );
    await _persistCurrentIntents();
  }

  Future<void> recordKeystoneDepositBroadcast({
    required SwapIntent intent,
    required SwapDepositBroadcastResult broadcast,
  }) async {
    final normalizedTxHash = broadcast.txHash.trim();
    if (normalizedTxHash.isEmpty) return;

    final existing = state.intents.swapIntentById(intent.id);
    if (existing != null) {
      clearPendingKeystoneSigningIntent(intent.id);
      await submitDepositTransactionForIntent(
        intentId: existing.id,
        accountUuid: existing.accountUuid ?? intent.accountUuid ?? '',
        txHash: normalizedTxHash,
        broadcastStatus: broadcast.status,
        broadcastMessage: broadcast.message,
      );
      return;
    }

    final broadcastNotice = _depositBroadcastNotice(
      status: broadcast.status,
      message: broadcast.message,
    );
    final submitProviderStatus = _shouldSubmitProviderDepositStatus(
      broadcast.status,
    );
    if (!submitProviderStatus) {
      await _switchEndpointAfterUncertainBroadcast(broadcast.message);
    }
    final checkpointed = swapIntentWithDepositCheckpoint(
      intent,
      txHash: normalizedTxHash,
      broadcastNotice: broadcastNotice,
      broadcastStatus: broadcast.status,
      clearStatusError: broadcastNotice == null,
      clearBroadcastNotice: broadcastNotice == null,
    );

    if (!_isAccountActive(intent.accountUuid)) {
      var storedIntents = await ref
          .read(swapActivityTrackerProvider)
          .loadIntents(accountUuid: intent.accountUuid);
      storedIntents = [
        checkpointed,
        for (final stored in storedIntents)
          if (stored.id != checkpointed.id) stored,
      ];
      await _persistIntentsForAccount(intent.accountUuid, storedIntents);
      clearPendingKeystoneSigningIntent(intent.id);
      if (!submitProviderStatus) return;

      try {
        final snapshot = await _submitProviderDepositTransaction(
          checkpointed,
          normalizedTxHash,
        );
        final updated = swapIntentWithDepositSnapshot(
          checkpointed,
          snapshot,
          txHash: normalizedTxHash,
          broadcastNotice: broadcastNotice,
        );
        await _persistIntentsForAccount(
          intent.accountUuid,
          storedIntents.replaceSwapIntent(checkpointed.id, updated),
        );
      } catch (e) {
        final failed = checkpointed.copyWith(
          statusError: swapFailureMessage(
            SwapFailureOperation.submitDeposit,
            e,
          ),
        );
        await _persistIntentsForAccount(
          intent.accountUuid,
          storedIntents.replaceSwapIntent(checkpointed.id, failed),
        );
      }
      return;
    }

    log(
      'Swap: Keystone deposit checkpoint begin '
      'intent=${_shortSwapValue(intent.id)} '
      'deposit=${_shortSwapValue(_providerDepositAddress(intent))} '
      'tx=${_shortSwapValue(normalizedTxHash)} '
      'submitProviderStatus=$submitProviderStatus',
    );
    state = state.copyWith(
      intents: [
        checkpointed,
        for (final stored in state.intents)
          if (stored.id != checkpointed.id) stored,
      ],
      selectedIntentId: checkpointed.id,
      depositTxHashText: normalizedTxHash,
      depositSubmitting: submitProviderStatus,
      clearPendingKeystoneSigningIntent: true,
      clearStatusError: true,
    );
    await _persistCurrentIntents();

    if (!submitProviderStatus) {
      state = state.copyWith(
        depositSubmitting: false,
        statusError: broadcastNotice,
      );
      return;
    }

    try {
      final snapshot = await _submitProviderDepositTransaction(
        checkpointed,
        normalizedTxHash,
      );
      final updated = swapIntentWithDepositSnapshot(
        checkpointed,
        snapshot,
        txHash: normalizedTxHash,
        broadcastNotice: broadcastNotice,
      );
      state = state.copyWith(
        depositSubmitting: false,
        depositTxHashText: normalizedTxHash,
        intents: state.intents.replaceSwapIntent(checkpointed.id, updated),
        clearStatusError: true,
      );
      log(
        'Swap: Keystone deposit submitted intent=${_shortSwapValue(updated.id)} '
        'status=${updated.status.name}',
      );
      await _persistCurrentIntents();
    } catch (e) {
      log(
        'Swap: Keystone deposit submit failed after broadcast '
        'intent=${_shortSwapValue(intent.id)} '
        'tx=${_shortSwapValue(normalizedTxHash)} error=$e',
      );
      final message = swapFailureMessage(SwapFailureOperation.submitDeposit, e);
      state = state.copyWith(depositSubmitting: false, statusError: message);
    }
  }

  Future<void> _submitDepositTransaction(
    SwapIntent selected,
    String txHash, {
    String? broadcastStatus,
    String? broadcastMessage,
    bool submitProviderStatus = true,
  }) async {
    if (!_isAccountActive(selected.accountUuid)) {
      await _submitDepositTransactionForStoredIntent(
        accountUuid: selected.accountUuid,
        intentId: selected.id,
        txHash: txHash,
        broadcastStatus: broadcastStatus,
        broadcastMessage: broadcastMessage,
        submitProviderStatus: submitProviderStatus,
      );
      return;
    }

    log(
      'Swap: deposit tx checkpoint begin '
      'intent=${_shortSwapValue(selected.id)} '
      'deposit=${_shortSwapValue(_providerDepositAddress(selected))} '
      'tx=${_shortSwapValue(txHash)} '
      'submitProviderStatus=$submitProviderStatus',
    );
    state = state.copyWith(depositSubmitting: true, clearStatusError: true);
    final broadcastNotice = _depositBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final checkpointed = swapIntentWithDepositCheckpoint(
      selected,
      txHash: txHash,
      broadcastNotice: broadcastNotice,
      broadcastStatus: broadcastStatus,
      clearStatusError: broadcastNotice == null,
      clearBroadcastNotice: broadcastNotice == null,
    );
    state = state.copyWith(
      depositTxHashText: state.selectedIntentId == selected.id
          ? txHash
          : state.depositTxHashText,
      intents: state.intents.replaceSwapIntent(selected.id, checkpointed),
      clearStatusError: true,
    );
    await _persistCurrentIntents();
    if (!submitProviderStatus) {
      state = state.copyWith(
        depositSubmitting: false,
        statusError: broadcastNotice,
      );
      return;
    }
    try {
      final snapshot = await _submitProviderDepositTransaction(
        checkpointed,
        txHash,
      );
      final updated = swapIntentWithDepositSnapshot(
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
        intents: state.intents.replaceSwapIntent(checkpointed.id, updated),
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
    final storedIntents = await ref
        .read(swapActivityTrackerProvider)
        .loadIntents(accountUuid: accountUuid);
    final intent = storedIntents.swapIntentById(intentId);
    if (intent == null) return;

    final broadcastNotice = _depositBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final checkpointed = swapIntentWithDepositCheckpoint(
      intent,
      txHash: txHash,
      statusError: statusError,
      broadcastNotice: broadcastNotice,
      broadcastStatus: broadcastStatus,
      clearStatusError: statusError == null && broadcastNotice == null,
      clearBroadcastNotice: broadcastNotice == null,
    );
    var updatedIntents = storedIntents.replaceSwapIntent(
      intentId,
      checkpointed,
    );
    await _persistIntentsForAccount(accountUuid, updatedIntents);

    if (!submitProviderStatus) return;

    try {
      final snapshot = await _submitProviderDepositTransaction(
        checkpointed,
        txHash,
      );
      final updated = swapIntentWithDepositSnapshot(
        checkpointed,
        snapshot,
        txHash: txHash,
        broadcastNotice: broadcastNotice,
      );
      updatedIntents = updatedIntents.replaceSwapIntent(intentId, updated);
      await _persistIntentsForAccount(accountUuid, updatedIntents);
    } catch (e) {
      final failed = checkpointed.copyWith(
        statusError: swapFailureMessage(SwapFailureOperation.submitDeposit, e),
      );
      updatedIntents = updatedIntents.replaceSwapIntent(intentId, failed);
      await _persistIntentsForAccount(accountUuid, updatedIntents);
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
    final storedIntents = await ref
        .read(swapActivityTrackerProvider)
        .loadIntents(accountUuid: accountUuid);
    final intent = storedIntents.swapIntentById(intentId);
    if (intent == null) return;

    final broadcastNotice = _depositBroadcastNotice(
      status: broadcastStatus,
      message: broadcastMessage,
    );
    final updated = swapIntentWithDepositSnapshot(
      intent,
      snapshot,
      txHash: txHash,
      broadcastNotice: broadcastNotice,
    );
    await _persistIntentsForAccount(
      accountUuid,
      storedIntents.replaceSwapIntent(intentId, updated),
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
    late final SwapDepositBroadcastResult broadcast;
    try {
      broadcast = await ref
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
      'Swap: live ZEC deposit broadcast tx=${_shortSwapValue(broadcast.txHash)} '
      'status=${broadcast.status} intent=${_shortSwapValue(intentId)}',
    );
    if (!_isAccountActive(accountUuid)) {
      await _submitDepositTransactionForStoredIntent(
        accountUuid: accountUuid,
        intentId: intentId,
        txHash: broadcast.txHash,
        broadcastStatus: broadcast.status,
        broadcastMessage: broadcast.message,
        submitProviderStatus: broadcast.isCertain,
      );
      return;
    }
    final broadcastNotice = _depositBroadcastNotice(
      status: broadcast.status,
      message: broadcast.message,
    );
    final intent = state.intents.swapIntentById(intentId);
    if (intent == null) {
      state = state.copyWith(
        depositTxHashText: broadcast.txHash,
        depositSubmitting: false,
        statusError: broadcast.isCertain
            ? 'ZEC deposit was broadcast, but the saved swap intent was not found. Copy the transaction hash before leaving this screen.'
            : broadcastNotice,
      );
      return;
    }
    final checkpointed = swapIntentWithDepositCheckpoint(
      intent,
      txHash: broadcast.txHash,
      broadcastNotice: broadcastNotice,
      broadcastStatus: broadcast.status,
      clearStatusError: broadcastNotice == null,
      clearBroadcastNotice: broadcastNotice == null,
    );
    state = state.copyWith(
      depositTxHashText: broadcast.txHash,
      intents: state.intents.replaceSwapIntent(intentId, checkpointed),
    );
    await _persistCurrentIntents();

    if (!broadcast.isCertain) {
      await _switchEndpointAfterUncertainBroadcast(broadcast.message);
      state = state.copyWith(
        depositSubmitting: false,
        intents: state.intents.replaceSwapIntent(intentId, checkpointed),
        statusError: broadcastNotice,
      );
      return;
    }

    try {
      final snapshot = await _submitProviderDepositTransaction(
        checkpointed,
        broadcast.txHash,
      );
      final updated = swapIntentWithDepositSnapshot(
        checkpointed,
        snapshot,
        txHash: broadcast.txHash,
      );
      if (!_isAccountActive(accountUuid)) {
        await _recordDepositSnapshotForStoredIntent(
          accountUuid: accountUuid,
          intentId: intentId,
          txHash: broadcast.txHash,
          snapshot: snapshot,
        );
        return;
      }
      state = state.copyWith(
        depositTxHashText: broadcast.txHash,
        depositSubmitting: false,
        intents: state.intents.replaceSwapIntent(intentId, updated),
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
        'intent=${_shortSwapValue(intentId)} tx=${_shortSwapValue(broadcast.txHash)} '
        'error=$e',
      );
      final message = swapFailureMessage(SwapFailureOperation.submitDeposit, e);
      if (!_isAccountActive(accountUuid)) {
        await _submitDepositTransactionForStoredIntent(
          accountUuid: accountUuid,
          intentId: intentId,
          txHash: broadcast.txHash,
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

  void _clearAccountScopedTransientState() {
    _quoteGeneration++;
    _accountScopeGeneration++;
    state = state.copyWith(
      amountText: '',
      receiveAmountText: '',
      quoteMode: _inputQuoteModeForDirection(state.direction),
      amountInputMode: SwapAmountInputMode.token,
      receiveAmountInputMode: SwapAmountInputMode.token,
      amountFiatText: '',
      receiveFiatText: '',
      destinationText: '',
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
      clearPendingKeystoneSigningIntent: true,
    );
  }

  Future<void> _restorePersistedIntents({
    required String? accountUuid,
    bool replaceExisting = false,
  }) async {
    final scopedAccountUuid = SwapActivityTracker.normalizeAccountUuid(
      accountUuid,
    );
    if (scopedAccountUuid == null) {
      if (replaceExisting) {
        state = state.copyWith(
          intents: const [],
          statusRefreshing: false,
          depositTxHashText: '',
          depositSubmitting: false,
          clearSelectedIntent: true,
          clearPendingKeystoneSigningIntent: true,
          clearStatusError: true,
        );
      }
      return;
    }
    final accountScopeGeneration = _accountScopeGeneration;
    try {
      final persisted = await ref
          .read(swapActivityTrackerProvider)
          .loadIntents(accountUuid: scopedAccountUuid);
      if (accountScopeGeneration != _accountScopeGeneration ||
          !_isAccountActive(scopedAccountUuid)) {
        return;
      }
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

  Future<void> _restoreComposerPreferences({
    required String? accountUuid,
  }) async {
    final scopedAccountUuid = accountUuid?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) {
      return;
    }
    try {
      final preferences = await ref
          .read(swapComposerPreferencesStoreProvider)
          .loadPreferences(accountUuid: scopedAccountUuid);
      if (preferences == null) return;
      if (!_isAccountActive(scopedAccountUuid)) return;
      if (state.amountText.isNotEmpty ||
          state.receiveAmountText.isNotEmpty ||
          state.destinationText.isNotEmpty ||
          state.quoteLoading ||
          state.reviewVisible) {
        return;
      }
      final externalAsset =
          _supportedAssetFor(
            preferences.externalAsset,
            state.supportedExternalAssets,
          ) ??
          preferences.externalAsset;
      _quoteGeneration++;
      state = state.copyWith(
        direction: preferences.direction,
        externalAsset: externalAsset,
        slippageBps: preferences.slippageBps,
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

      final reconciledIntents = result.reconcileInto(state.intents);
      final hasRefreshedCurrentIntent = result.hasRequestedCurrentIntent(
        state.intents,
      );

      _logStatusTransitions(state.intents, reconciledIntents);
      state = state.copyWith(
        statusRefreshing: false,
        intents: reconciledIntents,
        statusError: showBusy && hasRefreshedCurrentIntent
            ? result.refreshError
            : null,
        clearStatusError:
            result.refreshError == null || !hasRefreshedCurrentIntent,
      );
      if (result.includesRemovedRequestedIntent(state.intents)) {
        await _persistCurrentIntents(accountUuid: refreshAccountUuid);
      }
    } finally {
      _statusRefreshInFlight = false;
    }
  }

  void _logStatusTransitions(List<SwapIntent> before, List<SwapIntent> after) {
    for (final updated in after) {
      final previous = before.swapIntentById(updated.id);
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
    List<SwapIntent> intentsToPersist,
  ) async {
    await ref
        .read(swapActivityTrackerProvider)
        .saveIntents(accountUuid: accountUuid, intents: intentsToPersist);
  }

  bool _isAccountActive(String? accountUuid) {
    final scopedAccountUuid = SwapActivityTracker.normalizeAccountUuid(
      accountUuid,
    );
    return scopedAccountUuid == null ||
        scopedAccountUuid.isEmpty ||
        scopedAccountUuid == _activeAccountUuidOrNull;
  }

  Future<void> _persistComposerPreferences(
    SwapComposerPreferences preferences, {
    String? accountUuid,
  }) async {
    final scopedAccountUuid = (accountUuid ?? _activeAccountUuidOrNull)?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) {
      return;
    }
    try {
      await ref
          .read(swapComposerPreferencesStoreProvider)
          .savePreferences(
            accountUuid: scopedAccountUuid,
            preferences: preferences,
          );
    } catch (_) {}
  }

  SwapComposerPreferences get _currentComposerPreferences {
    return SwapComposerPreferences(
      direction: state.direction,
      externalAsset: state.externalAsset,
      slippageBps: state.slippageBps,
    );
  }

  String _providerDepositAddress(SwapIntent intent) {
    return intent.depositAddress ?? intent.id;
  }

  String _friendlyQuoteError(Object error) {
    if (error is SwapZecStagingAddressUnavailableException) {
      return error.toString();
    }
    return swapFailureMessage(SwapFailureOperation.quote, error);
  }

  Future<SwapIntentSnapshot> _submitProviderDepositTransaction(
    SwapIntent intent,
    String txHash,
  ) {
    return ref
        .read(swapIntentProvider)
        .submitDepositTransaction(
          depositAddress: _providerDepositAddress(intent),
          txHash: txHash,
          depositMemo: intent.depositMemo,
        );
  }

  bool _isHardwareIntent(SwapIntent intent) {
    final accountUuid = _accountUuidForIntent(intent);
    if (accountUuid == null || accountUuid.trim().isEmpty) return false;
    return ref.read(accountProvider.notifier).isHardwareAccount(accountUuid);
  }

  /// Fails over to a healthy lightwalletd endpoint after an uncertain deposit
  /// broadcast, mirroring `send_status_screen.dart`.
  ///
  /// [message] MUST be the raw broadcast error detail (the `message` field
  /// straight off the Rust broadcast result), not a remapped/friendly notice
  /// such as the output of [_depositBroadcastNotice]. `switchToFallbackFor`
  /// classifies the string via `shouldFallbackFromLightwalletdError`, which
  /// keyword-matches transport errors ("connection refused", "timeout", …);
  /// passing a localized/friendly string would silently stop failover from
  /// ever triggering.
  Future<void> _switchEndpointAfterUncertainBroadcast(String? message) async {
    final trimmed = message?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final switched = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(trimmed, operation: 'swap deposit broadcast');
    if (switched) {
      unawaited(ref.read(syncProvider.notifier).restartSync());
    }
  }

  String? _depositBroadcastNotice({String? status, String? message}) {
    final normalizedStatus = status?.trim();
    if (normalizedStatus == null ||
        normalizedStatus.isEmpty ||
        normalizedStatus == SwapDepositBroadcastStatus.broadcasted) {
      return null;
    }
    final trimmedMessage = message?.trim();
    if (trimmedMessage != null && trimmedMessage.isNotEmpty) {
      return trimmedMessage;
    }
    if (normalizedStatus == SwapDepositBroadcastStatus.partialBroadcast) {
      return 'Some deposit transactions may have reached the network. Check activity before trying again.';
    }
    if (normalizedStatus == SwapDepositBroadcastStatus.pendingBroadcast) {
      return 'The deposit was created locally but could not be broadcast. Check activity before trying again.';
    }
    if (normalizedStatus == SwapDepositBroadcastStatus.broadcastUnknown) {
      return 'The transaction may have reached the network, but confirmation timed out. Check activity before trying again.';
    }
    if (normalizedStatus ==
        SwapDepositBroadcastStatus.broadcastedStorageFailed) {
      return 'The transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';
    }
    return 'The deposit status is uncertain. Check activity before trying again.';
  }

  bool _shouldSubmitProviderDepositStatus(String? status) {
    final normalizedStatus = status?.trim();
    if (normalizedStatus == null || normalizedStatus.isEmpty) return true;
    return normalizedStatus == SwapDepositBroadcastStatus.broadcasted ||
        normalizedStatus == SwapDepositBroadcastStatus.broadcastedStorageFailed;
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

final swapStateProvider = NotifierProvider<SwapNotifier, SwapState>(
  SwapNotifier.new,
);

final swapIntentsProvider = Provider<List<SwapIntent>>((ref) {
  return ref.watch(swapStateProvider).intents;
});

final selectedSwapIntentProvider = Provider<SwapIntent?>((ref) {
  return ref.watch(swapStateProvider).selectedIntentOrNull;
});
