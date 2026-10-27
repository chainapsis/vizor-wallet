import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../models/swap_amount_input_mapper.dart';
import '../models/swap_deposit_broadcast_result.dart';
import '../models/swap_intent_presentation_mapper.dart';
import '../models/swap_models.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/one_time_ivk.dart'
    show ReceiveError, ReceiveErrorKind;
import 'swap_activity_tracker.dart';
import 'swap_address_wait_provider.dart';
import 'swap_deposit_sender.dart';
import 'swap_failure_policy.dart';
import 'swap_max_amount_estimator.dart';
import 'pay_selected_asset_store.dart';
import 'swap_composer_preferences_store.dart';
import 'swap_provider_config.dart';
import 'swap_zec_staging_address_service.dart';
import '../../../providers/network_upgrade_window_provider.dart';
import '../../../core/zcash/network_upgrade_hold.dart';

export 'swap_provider_config.dart';

/// Shown when a private incoming quote still gets no receive address after
/// the recovery round before its retry failed.
const kPrivateSwapAddressUnavailableMessage =
    "Private swaps aren't available right now. Try again in a few minutes.";

/// Shown when open quotes hold every one-time receive address, with a link
/// to the swaps holding them.
const kPrivateSwapAddressLimitMessage =
    'Too many swaps are waiting. Try again after one finishes or expires.';

final swapInitialIntentsProvider = Provider<List<SwapIntent>>((ref) {
  return const [];
});

/// Session-only memory for Pay's payout asset. This deliberately lives apart
/// from persisted Swap composer preferences so moving between the two flows
/// cannot overwrite either selection.
class PaySelectedAssetNotifier extends Notifier<SwapAsset> {
  static const defaultAsset = SwapAsset.usdc;

  @override
  SwapAsset build() => defaultAsset;

  void select(SwapAsset asset) {
    state = asset;
  }
}

final paySelectedAssetProvider =
    NotifierProvider<PaySelectedAssetNotifier, SwapAsset>(
      PaySelectedAssetNotifier.new,
    );

sealed class SwapStartResult {
  const SwapStartResult(this.intentId);

  final String intentId;
}

final class SwapStartedActivity extends SwapStartResult {
  const SwapStartedActivity(super.intentId);
}

final class SwapStartedHardwareSigning extends SwapStartResult {
  const SwapStartedHardwareSigning(super.intentId);
}

SwapQuoteMode _inputQuoteModeForDirection(SwapDirection direction) =>
    direction.sendsZec ? SwapQuoteMode.exactInput : SwapQuoteMode.flexInput;

class SwapNotifier extends Notifier<SwapState> {
  var _quoteGeneration = 0;

  /// Swap addresses prepared for review, per account and direction, so amount
  /// edits, cancels, direction switches and quote errors reuse one reservation
  /// (see [_prepareReviewAddress]).
  final _reviewStagingAddresses =
      <(String, SwapDirection), Future<SwapZecStagingAddress>>{};
  var _pricingLoadGeneration = 0;
  var _accountScopeGeneration = 0;
  var _payEntryGeneration = 0;
  var _hasResolvedSupportedAssets = false;
  Set<String> _deprecatedAssetIdentityKeys = const {};
  Set<(String, String, int)> _deprecatedAssetMarkets = const {};
  var _statusRefreshInFlight = false;
  SwapAsset? _payRetryAsset;
  String? _restoredPayAssetAccountUuid;
  String? _payAssetRestoreAccountUuid;
  Future<SwapAsset?>? _payAssetRestoreFuture;

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
    // NEAR swap privacy chooses between a swap address and an ordinary one for
    // new quotes, so a change drops the cached address. Turning it on also
    // drops any quote or review prepared with an ordinary address. Turning it
    // off keeps them, since only new reservations need it and a quote for an
    // address that's already reserved still finishes.
    ref.listen<bool>(nearSwapPrivacyProvider, (previous, next) {
      if (previous == next) return;
      _reviewStagingAddresses.clear();
      if (!next) return;
      _quoteGeneration++;
      if (state.reviewVisible || state.quoteLoading) {
        state = state.copyWith(
          reviewVisible: false,
          quoteLoading: false,
          clearReview: true,
        );
      }
    });
    ref.listen<NetworkPrivacyState>(networkPrivacyProvider, (previous, next) {
      final becameDirect =
          !next.torEnabled &&
          next.status == NetworkPrivacyConnectionStatus.off &&
          (previous?.torEnabled == true ||
              previous?.status != NetworkPrivacyConnectionStatus.off);
      final becameConnected =
          previous?.status != NetworkPrivacyConnectionStatus.connected &&
          next.status == NetworkPrivacyConnectionStatus.connected;
      if (becameDirect) {
        state = state.copyWith(clearSupportedAssetsError: true);
        unawaited(_loadSupportedExternalAssets(forceRefreshPrices: true));
      } else if (becameConnected) {
        unawaited(_loadSupportedExternalAssets(forceRefreshPrices: true));
      }
    });
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next) return;
        if (previous != null) {
          unawaited(_persistCurrentIntents(accountUuid: previous));
          // In Pay mode the composer state carries Pay's direction/payout
          // asset, which must not overwrite the previous account's saved
          // swap composer selection.
          if (!state.payMode) {
            unawaited(
              _persistComposerPreferences(
                _currentComposerPreferences,
                accountUuid: previous,
              ),
            );
          }
        }
        _clearAccountScopedTransientState();
        unawaited(_restoreComposerPreferences(accountUuid: next));
        unawaited(_ensurePaySelectedAssetRestored(accountUuid: next));
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
    unawaited(_ensurePaySelectedAssetRestored(accountUuid: activeAccountUuid));
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
      pricingLoading: true,
    ).copyWith(
      intents: initialIntents,
      selectedIntentId: initialIntents.isEmpty ? null : initialIntents.first.id,
    );
  }

  void selectDirection(SwapDirection direction) {
    _clearReviewState();
    state = swapStateWithDerivedFiatTexts(
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          direction: direction,
          quoteMode: _inputQuoteModeForDirection(direction),
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          reviewVisible: false,
          payMode: false,
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
          payMode: false,
        ),
      ),
    );
    unawaited(_persistComposerPreferences(_currentComposerPreferences));
  }

  void updateAmount(String value) {
    _clearReviewState();
    state = swapStateWithDerivedFiatTexts(
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
    final tokenText = swapPayTokenTextFromFiatInput(state, value);
    state = swapStateWithDerivedFiatTexts(
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
    final tokenText = swapReceiveTokenTextFromFiatInput(state, value);
    state = swapStateWithDerivedFiatTexts(
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

  bool preparePayFromShieldedZec({
    SwapAsset? preferredAsset,
    String? expectedAccountUuid,
  }) {
    final scopedExpectedAccountUuid = expectedAccountUuid?.trim();
    if (scopedExpectedAccountUuid != null &&
        (scopedExpectedAccountUuid.isEmpty ||
            !_isAccountActive(scopedExpectedAccountUuid))) {
      return false;
    }
    _clearReviewState();
    _payRetryAsset = null;
    final SwapAsset preferredPayAsset =
        preferredAsset ?? ref.read(paySelectedAssetProvider);
    final rememberedAsset = _isDeprecatedForSelection(preferredPayAsset)
        ? PaySelectedAssetNotifier.defaultAsset
        : preferredPayAsset;
    final supportedAssets = state.supportedExternalAssets;
    final payAsset =
        _supportedAssetFor(rememberedAsset, supportedAssets) ??
        (state.pricingLoading && !_hasResolvedSupportedAssets
            ? rememberedAsset
            : null) ??
        _supportedAssetFor(SwapAsset.usdc, supportedAssets) ??
        (supportedAssets.isEmpty ? rememberedAsset : supportedAssets.first);
    state = swapStateWithDerivedFiatTexts(
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '',
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          externalAsset: payAsset,
          destinationText: '',
          clearUserExternalContactId: true,
          reviewVisible: false,
          depositTxHashText: '',
          payMode: true,
          clearReview: true,
          clearQuoteError: true,
          clearStatusError: true,
          clearMaxAmountError: true,
        ),
      ),
    );
    return true;
  }

  Future<SwapAsset?> resolvePaySelectedAssetForEntry({
    required String accountUuid,
  }) async {
    final scopedAccountUuid = accountUuid.trim();
    if (scopedAccountUuid.isEmpty || !_isAccountActive(scopedAccountUuid)) {
      return null;
    }
    final entryGeneration = ++_payEntryGeneration;
    final asset = await _ensurePaySelectedAssetRestored(
      accountUuid: scopedAccountUuid,
    );
    if (entryGeneration != _payEntryGeneration ||
        !_isAccountActive(scopedAccountUuid)) {
      return null;
    }
    return asset;
  }

  void prepareSwapComposer() {
    if (!state.payMode) return;
    _clearReviewState();
    _payRetryAsset = null;
    final supportedAssets = state.supportedExternalAssets;
    final defaultSwapAsset =
        _supportedAssetFor(SwapAsset.usdc, supportedAssets) ??
        (supportedAssets.isEmpty ? SwapAsset.usdc : supportedAssets.first);
    state = swapStateWithDerivedFiatTexts(
      swapStateWithIndicativeCounterpart(
        state.copyWith(
          direction: SwapDirection.zecToExternal,
          externalAsset: defaultSwapAsset,
          quoteMode: SwapQuoteMode.exactInput,
          amountText: '',
          receiveAmountText: '',
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          destinationText: '',
          clearUserExternalContactId: true,
          reviewVisible: false,
          depositTxHashText: '',
          payMode: false,
          clearReview: true,
          clearQuoteError: true,
          clearStatusError: true,
          clearMaxAmountError: true,
        ),
      ),
    );
    unawaited(
      _restoreComposerPreferences(
        accountUuid: _activeAccountUuidOrNull,
        replaceComposer: true,
      ),
    );
  }

  void toggleFiatInputMode(SwapAmountInputSide side) {
    _clearReviewState();
    final next = swapStateWithToggledFiatInputMode(state, side);
    state = next.copyWith(reviewVisible: false, clearMaxAmountError: true);
  }

  void updateDestination(String value) {
    _clearReviewState();
    state = state.copyWith(
      destinationText: value,
      reviewVisible: false,
      clearMaxAmountError: true,
      clearUserExternalContactId: true,
    );
  }

  void selectDestinationContact({
    required String address,
    required String contactId,
  }) {
    _clearReviewState();
    state = state.copyWith(
      destinationText: address,
      userExternalContactId: contactId,
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
      swapStateWithIndicativeCounterpart(
        swapStateWithTokenAmountsForFiatModes(
          state.copyWith(
            externalAsset: supportedAsset,
            reviewVisible: false,
            destinationText: chainChanged ? '' : null,
            payMode: false,
            clearUserExternalContactId: chainChanged,
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

  void selectPayExternalAsset(
    SwapAsset asset, {
    bool clearDestinationOnChainChange = false,
    bool rememberSelection = true,
  }) {
    final supportedAsset = _supportedAssetFor(
      asset,
      state.supportedExternalAssets,
    );
    if (supportedAsset == null) return;
    _payRetryAsset = null;
    if (rememberSelection) {
      ref.read(paySelectedAssetProvider.notifier).select(supportedAsset);
      unawaited(_persistPaySelectedAsset(supportedAsset));
    }
    // Pay surfaces that select the payout asset before the recipient opt into
    // clearing a stale address when the selected chain changes. The default
    // remains non-destructive for state restoration and other internal calls.
    final chainChanged =
        supportedAsset.chainTicker != state.externalAsset.chainTicker;
    _clearReviewState();
    state = swapStateWithDerivedFiatTexts(
      swapStateWithIndicativeCounterpart(
        swapStateWithTokenAmountsForFiatModes(
          state.copyWith(
            externalAsset: supportedAsset,
            reviewVisible: false,
            destinationText: clearDestinationOnChainChange && chainChanged
                ? ''
                : null,
            payMode: true,
            clearUserExternalContactId:
                clearDestinationOnChainChange && chainChanged,
          ),
        ),
      ),
      preserveAmountFiatInput:
          state.amountInputMode == SwapAmountInputMode.fiat,
      preserveReceiveFiatInput:
          state.receiveAmountInputMode == SwapAmountInputMode.fiat,
    );
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
      swapStateWithIndicativeCounterpart(state),
      preserveAmountFiatInput:
          state.amountInputMode == SwapAmountInputMode.fiat,
      preserveReceiveFiatInput:
          state.receiveAmountInputMode == SwapAmountInputMode.fiat,
    );
    unawaited(
      state.payMode
          ? _persistSlippageOnlyPreference(normalized)
          : _persistComposerPreferences(_currentComposerPreferences),
    );
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
    final generation = ++_pricingLoadGeneration;
    // build() starts the initial load before the notifier's state is assigned.
    // Yield once so both that first load and later refreshes use the same state
    // transition without reading an uninitialized notifier.
    await Future<void>.value();
    if (generation != _pricingLoadGeneration) return;
    state = state.copyWith(pricingLoading: true);
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
      // Pricing omits assets without positive prices, including deprecated ones.
      final catalog = await provider.listSupportedExternalAssets();
      final selectionCandidates =
          pricing?.supportedExternalAssets.isNotEmpty == true
          ? pricing!.supportedExternalAssets
          : catalog;
      if (generation != _pricingLoadGeneration) return;
      _hasResolvedSupportedAssets = true;
      _deprecatedAssetIdentityKeys = {
        for (final asset in catalog)
          if (asset.isDeprecated) asset.identityKey,
      };
      // An ID-less preference cannot distinguish two provider contracts for
      // the same market. Keep it when the catalog still has an active match.
      _deprecatedAssetMarkets =
          {
            for (final asset in catalog)
              if (asset.isDeprecated) _deprecatedAssetMarketKey(asset),
          }.difference({
            for (final asset in catalog)
              if (!asset.isDeprecated) _deprecatedAssetMarketKey(asset),
          });
      final supported = [
        for (final asset in selectionCandidates)
          if (asset != SwapAsset.zec && !_isDeprecatedForSelection(asset))
            asset,
      ];
      if (supported.isEmpty) {
        state = state.copyWith(
          supportedExternalAssets: supported,
          externalAsset: _isDeprecatedForSelection(state.externalAsset)
              ? SwapAsset.usdc
              : state.externalAsset,
          reviewVisible: false,
          clearReview: true,
          clearSupportedAssetsError: true,
        );
        return;
      }
      if (!state.payMode &&
          _isDeprecatedForSelection(ref.read(paySelectedAssetProvider))) {
        ref
            .read(paySelectedAssetProvider.notifier)
            .select(
              _supportedAssetFor(
                    PaySelectedAssetNotifier.defaultAsset,
                    supported,
                  ) ??
                  supported.first,
            );
      }
      final retryAsset = state.payMode ? _payRetryAsset : null;
      final supportedRetryAsset = retryAsset == null
          ? null
          : _supportedAssetFor(retryAsset, supported);
      final rememberedAsset = state.payMode
          ? ref.read(paySelectedAssetProvider)
          : state.externalAsset;
      final retryUnsupported =
          retryAsset != null && supportedRetryAsset == null;
      final selected = retryUnsupported
          ? retryAsset
          : supportedRetryAsset ??
                _supportedAssetFor(rememberedAsset, supported) ??
                supported.first;
      if (state.payMode) {
        ref.read(paySelectedAssetProvider.notifier).select(selected);
        if (supportedRetryAsset != null && selected != rememberedAsset) {
          unawaited(_persistPaySelectedAsset(selected));
        }
      }
      final selectedChanged = selected != state.externalAsset;
      var nextState = state.copyWith(
        supportedExternalAssets: supported,
        indicativeExternalPerZec:
            pricing?.externalPerZec ?? state.indicativeExternalPerZec,
        indicativeUsdPrices: pricing?.usdPrices ?? state.indicativeUsdPrices,
        externalAsset: selected,
        reviewVisible: selectedChanged ? false : state.reviewVisible,
        clearReview: selectedChanged || retryUnsupported,
        clearQuoteError: true,
        clearSupportedAssetsError: true,
      );
      nextState = swapStateWithTokenAmountsForFiatModes(nextState);
      if (nextState.reviewQuote == null) {
        nextState = swapStateWithIndicativeCounterpart(nextState);
      }
      state = swapStateWithDerivedFiatTexts(
        nextState,
        preserveAmountFiatInput:
            nextState.amountInputMode == SwapAmountInputMode.fiat,
        preserveReceiveFiatInput:
            nextState.receiveAmountInputMode == SwapAmountInputMode.fiat,
      );
    } catch (error) {
      if (generation != _pricingLoadGeneration) return;
      final torEnabled = ref.read(networkPrivacyProvider).torEnabled;
      final category = swapFailureCategory(
        SwapFailureOperation.tokenList,
        error,
        torEnabled: torEnabled,
      );
      final message = _providerFailureMessage(
        SwapFailureOperation.tokenList,
        error,
        surface: state.payMode
            ? SwapFailureSurface.pay
            : SwapFailureSurface.swap,
      );
      if (category == SwapFailureCategory.torBlocked) {
        state = state.copyWith(supportedAssetsError: message);
      }
      log(
        'Swap: supported assets load failed '
        'torEnabled=$torEnabled error=$error',
      );
    } finally {
      if (generation == _pricingLoadGeneration) {
        state = state.copyWith(pricingLoading: false);
      }
    }
  }

  /// The swap address `direction` quotes with on `accountUuid`: the one cached
  /// for them, or a new preparation, cached before it is awaited so edits during
  /// preparation do not allocate another key. An incoming address stays cached
  /// until NEAR swap privacy changes, its reservation goes stale, or its swap
  /// starts; the wallet also resumes its draft until the latest quote expires.
  /// A refund address serves one quote request, so [_showReview] drops it once
  /// it commits to sending one, and returns it only if the request never left
  /// the device. An ordinary address, with no reservation, is never kept or
  /// shared: when the account uses ordinary addresses, each quote prepares its
  /// own at once, as before private swaps. So does a quote that joined a
  /// preparation that turned out ordinary, or failed before reserving anything.
  Future<SwapZecStagingAddress> _prepareReviewAddress(
    String accountUuid,
    SwapDirection direction,
  ) async {
    final service = ref.read(swapZecStagingAddressServiceProvider);
    Future<SwapZecStagingAddress> prepare() =>
        service.prepareForQuote(accountUuid: accountUuid, direction: direction);
    if (!service.usesSwapAddress(accountUuid)) return prepare();
    final key = (accountUuid, direction);
    final joined = _reviewStagingAddresses[key];
    final pending = joined ?? (_reviewStagingAddresses[key] = prepare());
    final SwapZecStagingAddress address;
    try {
      address = await pending;
    } catch (e) {
      if (identical(_reviewStagingAddresses[key], pending)) {
        _reviewStagingAddresses.remove(key);
      }
      if (joined != null &&
          e is SwapZecStagingAddressUnavailableException &&
          !e.privateAddress) {
        return prepare();
      }
      rethrow;
    }
    if (!address.isPrivate) {
      if (identical(_reviewStagingAddresses[key], pending)) {
        _reviewStagingAddresses.remove(key);
      }
      if (joined != null) return prepare();
    }
    return address;
  }

  /// Drops the swap address cached for `accountUuid` and `direction`, so the
  /// next quote prepares another.
  void _dropReviewAddress(String accountUuid, SwapDirection direction) {
    _reviewStagingAddresses.remove((accountUuid, direction));
  }

  Future<void> showReview({bool preserveCurrentReview = false}) =>
      _showReview(preserveCurrentReview: preserveCurrentReview, retry: true);

  /// Quotes for review. A reservation that went stale is dropped and, when
  /// `retry` is set, quoted once more with a new address. `recoveryFailure`
  /// is how the recovery round before that retry failed, if it did.
  Future<void> _showReview({
    required bool preserveCurrentReview,
    required bool retry,
    Object? recoveryFailure,
  }) async {
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
    final keepCurrentReview =
        preserveCurrentReview &&
        state.reviewVisible &&
        state.reviewQuote != null &&
        state.reviewAddressPlan != null;

    state = state.copyWith(
      reviewVisible: keepCurrentReview,
      quoteLoading: true,
      clearReview: !keepCurrentReview,
      clearQuoteError: true,
    );

    // The refund address this request took from the cache, if any, and
    // whether the provider adapter's send hook returned, after which NEAR may
    // have seen the request.
    SwapZecStagingAddress? takenRefund;
    var mayHaveSent = false;
    try {
      if (!state.payMode) {
        await _persistComposerPreferences(preferences);
      }
      final stagingAddress = await _prepareReviewAddress(
        accountUuid,
        direction,
      );
      // An outdated quote with a private address stops before it takes the
      // address or reaches NEAR. An ordinary one is still sent, as before
      // private swaps, and its response is discarded below.
      if (stagingAddress.isPrivate &&
          (generation != _quoteGeneration || !_isAccountActive(accountUuid))) {
        return;
      }
      // This request binds the refund key to its deposit, so no other quote,
      // an edit's or a refresh's, may use it even while this one is in flight.
      if (stagingAddress.refundIndex != null) {
        _dropReviewAddress(accountUuid, direction);
        takenRefund = stagingAddress;
      }
      final addressPlan = stagingAddress.toAddressPlan(
        direction: direction,
        externalAsset: externalAsset,
        userExternalAddress: userExternalAddress,
      );
      final quote = await ref
          .read(swapZecStagingAddressServiceProvider)
          .quote(
            accountUuid,
            stagingAddress,
            (beforeSend) => ref
                .read(swapIntentProvider)
                .quote(
                  addressPlan.toQuoteRequest(
                    mode: quoteMode,
                    amount: amount,
                    amountText: amountText,
                    slippageBps: state.slippageBps,
                    beforeSend: (deadline) async {
                      // A hook that throws stops the request before it leaves.
                      await beforeSend?.call(deadline);
                      mayHaveSent = true;
                    },
                  ),
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
      final kind = _receiveError(e)?.kind;
      // Only a request that never left the device returns its refund key.
      // Once sent, NEAR may have seen the address even without a response, so
      // a refusal, timeout or bad response retires it. An outdated request
      // gives its key up too, since a newer one may have reserved another.
      if (takenRefund != null && !mayHaveSent) {
        _reviewStagingAddresses[(accountUuid, direction)] ??= Future.value(
          takenRefund,
        );
      }
      // An incoming reservation survives other errors. It is dropped once stale,
      // when the next attempt needs another address, or once its history needs
      // checking again, since another device may have paid it.
      if (kind == ReceiveErrorKind.stale ||
          kind == ReceiveErrorKind.receiveHistory) {
        _dropReviewAddress(accountUuid, direction);
      }
      // A stale reservation is quoted once more with a new address. Issuance
      // can also wait on work the wallet finishes itself, so do it once and ask
      // again: a recovery round for an address whose history is unchecked, or
      // fresh statuses and a recovery round for swaps holding every eligible
      // address, since a paid one holds its address until its payout is
      // recovered.
      if (retry &&
          (kind == ReceiveErrorKind.stale ||
              kind == ReceiveErrorKind.receiveHistory ||
              kind == ReceiveErrorKind.limit)) {
        Object? recoveryFailure;
        try {
          if (kind == ReceiveErrorKind.limit) {
            await _refreshReceiveQuoteStatuses();
          }
          if (kind != ReceiveErrorKind.stale) {
            recoveryFailure = await ref
                .read(syncProvider.notifier)
                .awaitSwapRecovery();
          }
        } catch (retryError) {
          // The wallet work that could free an address failed, so the quote
          // ends with the reason it was refused.
          log('Swap: receive address retry failed: $retryError');
          if (generation != _quoteGeneration) return;
          state = state.copyWith(
            reviewVisible: false,
            quoteLoading: false,
            quoteError: _friendlyQuoteError(e),
            clearReview: true,
          );
          return;
        }
        if (generation != _quoteGeneration || !_isAccountActive(accountUuid)) {
          return;
        }
        state = state.copyWith(quoteLoading: false);
        return _showReview(
          preserveCurrentReview: preserveCurrentReview,
          retry: false,
          recoveryFailure: recoveryFailure,
        );
      }
      // A payout address the wallet is still checking waits for the next
      // recovery round, which the button shows, rather than an error.
      if (kind == ReceiveErrorKind.receiveHistory &&
          !state.payMode &&
          !state.direction.sendsZec &&
          ref.read(swapUsesOneTimeAddressProvider) &&
          _addressRecoveryFailureMessage(recoveryFailure) == null) {
        ref.read(swapAddressHistoryPendingProvider.notifier).quoteRefused();
        state = state.copyWith(
          reviewVisible: false,
          quoteLoading: false,
          clearQuoteError: true,
          clearReview: true,
        );
        return;
      }
      state = state.copyWith(
        reviewVisible: false,
        quoteLoading: false,
        quoteError:
            kind == ReceiveErrorKind.receiveHistory ||
                kind == ReceiveErrorKind.limit
            ? _addressRecoveryFailureMessage(recoveryFailure) ??
                  _friendlyQuoteError(e)
            : _friendlyQuoteError(e),
        clearReview: true,
      );
    }
  }

  /// Refreshes the provider statuses of the active account's private incoming
  /// swaps that can still hold a receive address: open ones, ones whose deposit
  /// deadline passed within the last day, and ones the wallet may still hold
  /// however old. A started quote keeps its address until a recent status
  /// releases it, or a day past its deadline if it never gets one and the
  /// address is unpaid, so an expired quote cannot block issuance for good.
  /// Ordinary swaps hold no reserved address, so they are left to the usual
  /// polling.
  Future<void> _refreshReceiveQuoteStatuses() async {
    final recent = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final ids = [
      for (final intent in state.intents)
        if (intent.direction == SwapDirection.externalToZec &&
            intent.privateAddress &&
            (!intent.status.isTerminal ||
                (intent.depositDeadline?.isAfter(recent) ?? false) ||
                !intent.walletReleased))
          intent.id,
    ];
    await _refreshIntentStatuses(
      intentIds: ids,
      showBusy: false,
      includeTerminal: true,
    );
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
    final actionDeadline = quote.actionDeadline;
    if (actionDeadline != null &&
        !DateTime.now().toUtc().isBefore(actionDeadline)) {
      log('Swap: start blocked; quote action deadline was $actionDeadline');
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
    // Only private swaps hold wallet state for their account, so only they
    // stay with it across an account switch during the start.
    final privateQuote =
        quote.receiveRequestId != null || quote.swapRefundIndex != null;
    // Advances on every account switch, including a switch back.
    final scope = _accountScopeGeneration;
    // Whether the screen moved to other swaps since the start began: another
    // account, or this one again while its swaps reload.
    bool screenMoved() =>
        scope != _accountScopeGeneration || !_isAccountActive(accountUuid);
    final startingPayMode = state.payMode;
    final startingUserExternalContactId = state.userExternalContactId;
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
    final hardwareSignerKind = ref
        .read(accountProvider.notifier)
        .hardwareSignerKindForAccount(accountUuid);
    final hardwareSignerLabel = hardwareSignerKind == HardwareSignerKind.ledger
        ? 'Ledger'
        : 'Keystone';
    if (quote.direction.sendsZec) {
      // The provider would open a swap for a deposit Rust then refuses.
      if (ref.read(networkUpgradeWindowProvider).holdsTransactions) {
        log('Swap: start held for the network upgrade');
        state = state.copyWith(
          startSubmitting: false,
          statusError: kNetworkUpgradeHoldMessage,
        );
        return null;
      }
      try {
        await ref
            .read(swapDepositSenderProvider)
            .estimateZecDepositFee(accountUuid: accountUuid, quote: quote);
      } catch (e) {
        // The screen now belongs to another account.
        if (privateQuote && screenMoved()) return null;
        log(
          'Swap: live ZEC deposit preflight failed '
          'quote=${_shortSwapValue(quote.providerQuoteId)} error=$e',
        );
        state = state.copyWith(
          startSubmitting: false,
          statusError: _providerFailureMessage(
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
      if (privateQuote && screenMoved()) return null;
      _showStartFailure(accountUuid, quote, e);
      return null;
    }
    // A switch to another account during these checks leaves nothing started,
    // so a private swap is not started for an account the user left.
    if (privateQuote && screenMoved()) {
      log('Swap: start dropped after an account switch');
      return null;
    }
    var intent = swapIntentFromSnapshot(
      snapshot: snapshot,
      quote: quote,
      addressPlan: addressPlan,
      accountUuid: accountUuid,
      userExternalContactId: startingUserExternalContactId,
      payMode: startingPayMode,
      now: DateTime.now().toUtc(),
    );
    if (activeAccountIsHardware && quote.direction.sendsZec) {
      final nextAction =
          'Sign and send the ZEC deposit with $hardwareSignerLabel.';
      intent = intent.copyWith(nextAction: nextAction);
    }
    // Only an incoming private quote holds a wallet reservation to start.
    if (quote.receiveRequestId != null &&
        !await _startPrivateReceive(accountUuid, quote, intent, screenMoved)) {
      return null;
    }
    _quoteGeneration++;
    if (activeAccountIsHardware && quote.direction.sendsZec) {
      if (hardwareSignerKind == HardwareSignerKind.ledger) {
        // The provider intent already exists at this point. Persist it before
        // opening the direct-USB signing surface so an app exit, device
        // disconnect, or expired Ledger request cannot orphan the swap/pay
        // intent. The deposit PCZT itself is safe to recreate while the
        // provider intent remains within its deadline.
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
          clearUserExternalContactId: true,
          intents: [
            intent,
            for (final stored in state.intents)
              if (stored.id != intent.id) stored,
          ],
          selectedIntentId: intent.id,
          startSubmitting: false,
          quoteLoading: false,
          depositTxHashText: '',
          clearReview: true,
          clearQuoteError: true,
          clearStatusError: true,
          clearPendingHardwareSigningIntent: true,
        );
        await (privateQuote
            ? _saveStartedIntentForAccount(accountUuid, intent)
            : _persistCurrentIntents());
        log(
          'Swap: persisted Ledger signing checkpoint '
          'intent=${_shortSwapValue(intent.id)}',
        );
        return SwapStartedHardwareSigning(intent.id);
      }
      log(
        'Swap: start pending $hardwareSignerLabel signing '
        'intent=${_shortSwapValue(intent.id)} '
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
        clearUserExternalContactId: true,
        pendingHardwareSigningIntent: intent,
        startSubmitting: false,
        quoteLoading: false,
        depositTxHashText: '',
        clearReview: true,
        clearQuoteError: true,
        clearStatusError: true,
        clearSelectedIntent: true,
      );
      log(
        'Swap: hardware ZEC deposit waiting for $hardwareSignerLabel signing '
        'intent=${_shortSwapValue(intent.id)}',
      );
      return SwapStartedHardwareSigning(intent.id);
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
      clearUserExternalContactId: true,
      // An incoming private swap is listed already, perhaps with a newer
      // status, since it was saved before its wallet start.
      intents: state.intents.any((stored) => stored.id == intent.id)
          ? state.intents
          : [intent, ...state.intents],
      startSubmitting: false,
      quoteLoading: false,
      selectedIntentId: intent.id,
      depositTxHashText: '',
      clearReview: true,
      clearQuoteError: true,
      clearStatusError: true,
      clearPendingHardwareSigningIntent: true,
    );
    if (quote.receiveRequestId == null) {
      await (privateQuote
          ? _saveStartedIntentForAccount(accountUuid, intent)
          : _persistCurrentIntents());
    }

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
    final accountUuid = _activeAccountUuidOrNull;
    final updated = selected.copyWith(depositClaimedAt: DateTime.now().toUtc());
    state = state.copyWith(
      intents: state.intents.replaceSwapIntent(selected.id, updated),
    );
    await _persistCurrentIntents();
    if (_activeAccountUuidOrNull != accountUuid ||
        state.intents.swapIntentById(selected.id) == null) {
      return;
    }
    await _refreshIntentStatuses(
      intentIds: [selected.id],
      showBusy: true,
      includeTerminal: true,
    );
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

  void clearPendingHardwareSigningIntent(String intentId) {
    final pending = state.pendingHardwareSigningIntent;
    if (pending == null || pending.id != intentId) return;
    state = state.copyWith(clearPendingHardwareSigningIntent: true);
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

    final retryingPay =
        intent.payMode && direction == SwapDirection.zecToExternal;
    final sellAmountText = intent.sellAmount.split(' ').first.trim();
    final receiveAmountText = intent.receiveEstimate.split(' ').first.trim();
    final destinationText = direction.sendsZec
        ? intent.oneClickRecipient ?? ''
        : intent.oneClickRefundTo ?? '';
    final inputAmountText = retryingPay ? receiveAmountText : sellAmountText;
    if (inputAmountText.isEmpty || destinationText.isEmpty) return;
    final selectedExternalAsset = externalAsset;
    _payRetryAsset = retryingPay ? externalAsset : null;
    if (retryingPay) {
      ref.read(paySelectedAssetProvider.notifier).select(selectedExternalAsset);
      unawaited(_persistPaySelectedAsset(selectedExternalAsset));
    }

    _quoteGeneration++;
    state = state.copyWith(
      direction: direction,
      externalAsset: selectedExternalAsset,
      quoteMode: retryingPay
          ? SwapQuoteMode.exactOutput
          : _inputQuoteModeForDirection(direction),
      amountText: retryingPay ? '' : sellAmountText,
      receiveAmountText: retryingPay ? receiveAmountText : '',
      amountInputMode: SwapAmountInputMode.token,
      receiveAmountInputMode: SwapAmountInputMode.token,
      amountFiatText: '',
      receiveFiatText: '',
      destinationText: destinationText,
      userExternalContactId: intent.userExternalContactId,
      clearUserExternalContactId: intent.userExternalContactId == null,
      reviewVisible: false,
      quoteLoading: false,
      depositTxHashText: '',
      payMode: retryingPay,
      clearReview: true,
      clearQuoteError: true,
      clearStatusError: true,
    );
    state = swapStateWithDerivedFiatTexts(
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

  Future<void> recordHardwareDepositBroadcast({
    required SwapIntent intent,
    required SwapDepositBroadcastResult broadcast,
  }) async {
    final normalizedTxHash = broadcast.txHash.trim();
    if (normalizedTxHash.isEmpty) return;

    final existing = state.intents.swapIntentById(intent.id);
    if (existing != null) {
      clearPendingHardwareSigningIntent(intent.id);
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
      clearPendingHardwareSigningIntent(intent.id);
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
          statusError: _providerFailureMessage(
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
      'Swap: hardware deposit checkpoint begin '
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
      clearPendingHardwareSigningIntent: true,
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
        'Swap: hardware deposit submitted intent=${_shortSwapValue(updated.id)} '
        'status=${updated.status.name}',
      );
      await _persistCurrentIntents();
    } catch (e) {
      log(
        'Swap: hardware deposit submit failed after broadcast '
        'intent=${_shortSwapValue(intent.id)} '
        'tx=${_shortSwapValue(normalizedTxHash)} error=$e',
      );
      final message = _providerFailureMessage(
        SwapFailureOperation.submitDeposit,
        e,
      );
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
      final message = _providerFailureMessage(
        SwapFailureOperation.submitDeposit,
        e,
      );
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
        statusError: _providerFailureMessage(
          SwapFailureOperation.submitDeposit,
          e,
        ),
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
      final message = _providerFailureMessage(
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
      final message = _providerFailureMessage(
        SwapFailureOperation.submitDeposit,
        e,
      );
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
    // Cached swap addresses are kept: a refund key leaves the cache when its
    // quote request is sent, and the wallet resumes an incoming draft until
    // the latest quote expires, then refuses it as stale.
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
    _payEntryGeneration++;
    _payRetryAsset = null;
    _restoredPayAssetAccountUuid = null;
    _payAssetRestoreAccountUuid = null;
    _payAssetRestoreFuture = null;
    state = state.copyWith(
      amountText: '',
      receiveAmountText: '',
      quoteMode: _inputQuoteModeForDirection(state.direction),
      amountInputMode: SwapAmountInputMode.token,
      receiveAmountInputMode: SwapAmountInputMode.token,
      amountFiatText: '',
      receiveFiatText: '',
      destinationText: '',
      clearUserExternalContactId: true,
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
      clearPendingHardwareSigningIntent: true,
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
          clearPendingHardwareSigningIntent: true,
          clearStatusError: true,
        );
      }
      return;
    }
    final accountScopeGeneration = _accountScopeGeneration;
    try {
      final tracker = ref.read(swapActivityTrackerProvider);
      final loaded = await tracker.loadIntents(accountUuid: scopedAccountUuid);
      if (accountScopeGeneration != _accountScopeGeneration ||
          !_isAccountActive(scopedAccountUuid)) {
        return;
      }
      // The load may have read a swap before its start finished.
      final persisted = tracker.withFinishedStarts(scopedAccountUuid, loaded);
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
    bool replaceComposer = false,
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
      if (!replaceComposer &&
          (state.payMode ||
              state.amountText.isNotEmpty ||
              state.receiveAmountText.isNotEmpty ||
              state.destinationText.isNotEmpty ||
              state.quoteLoading ||
              state.reviewVisible)) {
        return;
      }
      final deprecated = _isDeprecatedForSelection(preferences.externalAsset);
      final rememberedAsset = deprecated
          ? SwapAsset.usdc
          : preferences.externalAsset;
      final supportedAssets = state.supportedExternalAssets;
      final externalAsset =
          _supportedAssetFor(rememberedAsset, supportedAssets) ??
          (deprecated && supportedAssets.isNotEmpty
              ? supportedAssets.first
              : rememberedAsset);
      _quoteGeneration++;
      state = state.copyWith(
        direction: preferences.direction,
        externalAsset: externalAsset,
        slippageBps: preferences.slippageBps,
        reviewVisible: false,
        quoteLoading: false,
        payMode: false,
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

  /// Adds `intent`, a private swap starting on `accountUuid`, to that
  /// account's saved swaps by id, keeping the others and any saved copy of it.
  /// The screen's list may not hold every saved swap yet, so it is not what a
  /// private swap saves.
  Future<void> _saveStartedIntentForAccount(
    String accountUuid,
    SwapIntent intent,
  ) async {
    await ref
        .read(swapActivityTrackerProvider)
        .updateIntents(
          accountUuid: accountUuid,
          transform: (saved) => saved.any((stored) => stored.id == intent.id)
              ? saved
              : [intent, ...saved],
        );
  }

  /// Lists and saves `intent`, an incoming private swap, as starting before
  /// the wallet locks its reservation, so any later save of its account's
  /// screen keeps it while no surface shows its funding instructions (see
  /// [SwapIntent.startPending]). Once the lock succeeds only that flag is
  /// cleared, on screen and in storage. If the save or the start fails, the
  /// swap is removed by id, as when a start fails before it is listed. Returns
  /// whether it started with the screen still showing its account.
  Future<bool> _startPrivateReceive(
    String accountUuid,
    SwapQuote quote,
    SwapIntent intent,
    bool Function() screenMoved,
  ) async {
    final starting = intent.copyWith(startPending: true);
    state = state.copyWith(intents: [starting, ...state.intents]);
    try {
      await _saveStartedIntentForAccount(accountUuid, starting);
      await ref
          .read(swapZecStagingAddressServiceProvider)
          .startQuote(accountUuid, quote);
    } catch (e) {
      await _removeUnstartedIntent(accountUuid, intent.id);
      if (!screenMoved()) _showStartFailure(accountUuid, quote, e);
      return false;
    }
    // The swap started on this address, so the next swap prepares another.
    _dropReviewAddress(accountUuid, quote.direction);
    if (_isAccountActive(accountUuid)) {
      state = state.copyWith(
        intents: [
          for (final shown in state.intents)
            shown.id == intent.id && shown.startPending
                ? shown.copyWith(startPending: false)
                : shown,
        ],
      );
    }
    try {
      await ref
          .read(swapActivityTrackerProvider)
          .finishStart(accountUuid: accountUuid, intentId: intent.id);
    } catch (e) {
      // The account's next save stores it started. Until then a later launch
      // finds it starting and marks it failed, hiding its instructions.
      log(
        'Swap: started swap not saved as started '
        'intent=${_shortSwapValue(intent.id)} error=$e',
      );
    }
    if (screenMoved()) {
      log(
        'Swap: start saved after an account switch '
        'intent=${_shortSwapValue(intent.id)}',
      );
      return false;
    }
    return true;
  }

  /// Removes `intentId`, a private swap whose wallet start failed, from
  /// `accountUuid`'s screen and saved swaps, by id. The screen drops it first,
  /// so no later save of it brings the swap back, and again once the removal
  /// is saved, in case a reload read it before. A failed removal is logged.
  Future<void> _removeUnstartedIntent(
    String accountUuid,
    String intentId,
  ) async {
    void dropFromScreen() {
      if (!_isAccountActive(accountUuid)) return;
      state = state.copyWith(
        intents: [
          for (final intent in state.intents)
            if (intent.id != intentId) intent,
        ],
        clearSelectedIntent: state.selectedIntentId == intentId,
      );
    }

    dropFromScreen();
    try {
      await ref
          .read(swapActivityTrackerProvider)
          .updateIntents(
            accountUuid: accountUuid,
            transform: (saved) => [
              for (final intent in saved)
                if (intent.id != intentId) intent,
            ],
          );
    } catch (e) {
      log(
        'Swap: unstarted swap not removed '
        'intent=${_shortSwapValue(intentId)} error=$e',
      );
    }
    dropFromScreen();
  }

  /// Shows why the start of `quote` failed with `error`, and lets a wallet
  /// reservation that cannot start again go. A refusal that needs a wait or
  /// a new quote shows the wallet's wording, which says so.
  void _showStartFailure(String accountUuid, SwapQuote quote, Object error) {
    log(
      'Swap: start failed quote=${_shortSwapValue(quote.providerQuoteId)} '
      'error=$error',
    );
    final receiveError = _receiveError(error);
    final historyPending =
        receiveError?.kind == ReceiveErrorKind.receiveHistory;
    final stale = receiveError?.kind == ReceiveErrorKind.stale;
    // A reservation another request started, or whose deposit deadline
    // passed, cannot be quoted again. One whose history needs checking again
    // may have been paid elsewhere, so the next quote prepares an address
    // after a recovery round.
    if (historyPending || stale) {
      _dropReviewAddress(accountUuid, quote.direction);
    }
    if (historyPending) {
      ref.read(syncProvider.notifier).continueSwapRecovery();
    }
    state = state.copyWith(
      startSubmitting: false,
      quoteLoading: false,
      statusError: historyPending || stale
          ? receiveError!.message
          : _providerFailureMessage(SwapFailureOperation.start, error),
    );
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

  Future<void> _persistPaySelectedAsset(SwapAsset asset) async {
    final accountUuid = _activeAccountUuidOrNull?.trim();
    if (accountUuid == null || accountUuid.isEmpty) return;
    try {
      await ref
          .read(paySelectedAssetStoreProvider)
          .saveSelectedAsset(accountUuid: accountUuid, asset: asset);
    } catch (_) {}
  }

  Future<SwapAsset?> _ensurePaySelectedAssetRestored({String? accountUuid}) {
    final scopedAccountUuid = (accountUuid ?? _activeAccountUuidOrNull)?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) {
      return Future<SwapAsset?>.value();
    }
    if (_restoredPayAssetAccountUuid == scopedAccountUuid &&
        _isAccountActive(scopedAccountUuid)) {
      return Future<SwapAsset?>.value(ref.read(paySelectedAssetProvider));
    }
    final pending = _payAssetRestoreFuture;
    if (_payAssetRestoreAccountUuid == scopedAccountUuid && pending != null) {
      return pending;
    }

    final accountScopeGeneration = _accountScopeGeneration;
    late final Future<SwapAsset?> restoreFuture;
    restoreFuture =
        _restorePaySelectedAssetForAccount(
          accountUuid: scopedAccountUuid,
          accountScopeGeneration: accountScopeGeneration,
        ).whenComplete(() {
          if (identical(_payAssetRestoreFuture, restoreFuture)) {
            _payAssetRestoreAccountUuid = null;
            _payAssetRestoreFuture = null;
          }
        });
    _payAssetRestoreAccountUuid = scopedAccountUuid;
    _payAssetRestoreFuture = restoreFuture;
    return restoreFuture;
  }

  Future<SwapAsset?> _restorePaySelectedAssetForAccount({
    required String accountUuid,
    required int accountScopeGeneration,
  }) async {
    var restoredAsset = PaySelectedAssetNotifier.defaultAsset;
    var loadSucceeded = false;
    try {
      final saved = await ref
          .read(paySelectedAssetStoreProvider)
          .loadSelectedAsset(accountUuid: accountUuid);
      if (saved != null && _isDeprecatedForSelection(saved)) {
        final supportedAssets = state.supportedExternalAssets;
        restoredAsset =
            _supportedAssetFor(
              PaySelectedAssetNotifier.defaultAsset,
              supportedAssets,
            ) ??
            (supportedAssets.isEmpty
                ? PaySelectedAssetNotifier.defaultAsset
                : supportedAssets.first);
      } else {
        restoredAsset = saved ?? PaySelectedAssetNotifier.defaultAsset;
      }
      loadSucceeded = true;
    } catch (_) {}
    if (accountScopeGeneration != _accountScopeGeneration ||
        !_isAccountActive(accountUuid)) {
      return null;
    }
    try {
      // A retry is pinned to the intent's original payout rail. Ignore a
      // slower restore of the ordinary Pay preference so it cannot overwrite
      // the prepared retry after navigation.
      if (state.payMode && _payRetryAsset != null) {
        if (loadSucceeded) {
          _restoredPayAssetAccountUuid = accountUuid;
        }
        final SwapAsset retryAsset = ref.read(paySelectedAssetProvider);
        return retryAsset;
      }
      // No saved value must reset the memory: keeping the previous account's
      // selection would leak it into this account's Pay flow.
      ref.read(paySelectedAssetProvider.notifier).select(restoredAsset);
      if (state.payMode) {
        final supportedAssets = state.supportedExternalAssets;
        final liveAsset =
            _supportedAssetFor(restoredAsset, supportedAssets) ??
            (state.pricingLoading && !_hasResolvedSupportedAssets
                ? restoredAsset
                : null) ??
            _supportedAssetFor(
              PaySelectedAssetNotifier.defaultAsset,
              supportedAssets,
            ) ??
            (supportedAssets.isEmpty ? restoredAsset : supportedAssets.first);
        selectPayExternalAsset(
          liveAsset,
          clearDestinationOnChainChange: true,
          rememberSelection: false,
        );
      }
      if (loadSucceeded) {
        _restoredPayAssetAccountUuid = accountUuid;
      }
      return restoredAsset;
    } catch (_) {
      return restoredAsset;
    }
  }

  bool _isDeprecatedForSelection(SwapAsset asset) =>
      asset.isDeprecated ||
      _deprecatedAssetIdentityKeys.contains(asset.identityKey) ||
      (asset.assetId == null &&
          _deprecatedAssetMarkets.contains(_deprecatedAssetMarketKey(asset)));

  /// Slippage is shared with Pay, but Pay's direction/payout asset must not
  /// overwrite the saved swap composer selection — only the stored slippage
  /// field is updated, and nothing is written when no swap preferences exist.
  Future<void> _persistSlippageOnlyPreference(int slippageBps) async {
    final accountUuid = _activeAccountUuidOrNull?.trim();
    if (accountUuid == null || accountUuid.isEmpty) return;
    try {
      final store = ref.read(swapComposerPreferencesStoreProvider);
      final saved = await store.loadPreferences(accountUuid: accountUuid);
      if (saved == null) return;
      await store.savePreferences(
        accountUuid: accountUuid,
        preferences: SwapComposerPreferences(
          direction: saved.direction,
          externalAsset: saved.externalAsset,
          slippageBps: slippageBps,
        ),
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

  /// The wallet's swap address failure behind `error`, if any, whether thrown
  /// directly or while preparing the address.
  ReceiveError? _receiveError(Object error) => switch (error) {
    final ReceiveError e => e,
    SwapZecStagingAddressUnavailableException(:final ReceiveError cause) =>
      cause,
    _ => null,
  };

  /// What a quote still refused a receive address, because its history check
  /// is unfinished or every address is held, shows after the recovery round
  /// before its retry ended with `failure`, or null to keep the wallet's
  /// wording. Without a failure, or while the round only waits for wallet
  /// sync or for the receiver service to reach a new wallet's birthday, the
  /// wallet's wording still holds. A round that needs a newer app says so.
  String? _addressRecoveryFailureMessage(Object? failure) => switch (failure) {
    null ||
    ReceiveError(kind: ReceiveErrorKind.waitingForSync) ||
    ReceiveError(kind: ReceiveErrorKind.waitingForService) => null,
    ReceiveError(kind: ReceiveErrorKind.upgradeRequired) =>
      kSwapRecoveryUpdateMessage,
    _ => kPrivateSwapAddressUnavailableMessage,
  };

  String _friendlyQuoteError(Object error) {
    if (_receiveError(error) case final receiveError?) {
      return switch (receiveError.kind) {
        ReceiveErrorKind.limit => kPrivateSwapAddressLimitMessage,
        ReceiveErrorKind.upgradeRequired => kSwapRecoveryUpdateMessage,
        _ => receiveError.message,
      };
    }
    if (error is SwapZecStagingAddressUnavailableException) {
      return error.toString();
    }
    return _providerFailureMessage(
      SwapFailureOperation.quote,
      error,
      surface: state.payMode ? SwapFailureSurface.pay : SwapFailureSurface.swap,
    );
  }

  String _providerFailureMessage(
    SwapFailureOperation operation,
    Object error, {
    SwapFailureSurface surface = SwapFailureSurface.swap,
  }) {
    return swapFailureMessage(
      operation,
      error,
      surface: surface,
      torEnabled: ref.read(networkPrivacyProvider).torEnabled,
    );
  }

  Future<SwapIntentSnapshot> _submitProviderDepositTransaction(
    SwapIntent intent,
    String txHash,
  ) async {
    final checkedAt = DateTime.now().toUtc();
    final snapshot = await ref
        .read(swapIntentProvider)
        .submitDepositTransaction(
          depositAddress: _providerDepositAddress(intent),
          txHash: txHash,
          depositMemo: intent.depositMemo,
        );
    // Like a refreshed status, it decides when the swap's reservation is released
    // or its refund key retired.
    // Failing to record it only delays that. Only a terminal status's failure
    // reaches here (see `recordProviderSnapshot`), and saving that status would
    // end polling, so the swap stays open until a refresh records it.
    try {
      await ref
          .read(swapActivityTrackerProvider)
          .recordProviderSnapshot(intent, snapshot, checkedAt);
    } catch (e) {
      log('Swap: deposit status not recorded in the wallet error=$e');
      return snapshot.withStatus(SwapIntentStatus.providerStatusUnknown);
    }
    return snapshot;
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

(String, String, int) _deprecatedAssetMarketKey(SwapAsset asset) => (
  asset.symbol
      .toUpperCase()
      .replaceAll(RegExp(r'[_\s]*\(DEPRECATED\)[_\s]*'), '')
      .trim(),
  asset.chainTicker.trim().toLowerCase(),
  asset.decimals,
);

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
