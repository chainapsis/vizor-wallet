import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/swap_feature_config.dart';
import '../../../core/payments/cross_chain_payment_request.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/payment_uri_prefill_provider.dart';
import '../../../rust/api/payment_uri.dart' as rust_payment;
import '../../swap/providers/swap_state_provider.dart';
import '../models/payment_request_resolution.dart';

typedef CrossChainPaymentParser =
    Future<CrossChainPaymentRequest> Function(String raw);

var _requestSequence = 0;
final crossChainPaymentParserProvider = Provider<CrossChainPaymentParser>((
  ref,
) {
  return (raw) async {
    try {
      final json = await rust_payment.parseCrossChainPaymentUri(uri: raw);
      return CrossChainPaymentRequest.fromParserJson(
        id: 'cross-chain-${++_requestSequence}',
        rawUri: raw,
        json: json,
      );
    } catch (_) {
      throw const CrossChainPaymentParseException();
    }
  };
});

class CrossChainPaymentFlowState {
  const CrossChainPaymentFlowState(
    this.request, {
    this.selectedChain,
    this.slippageBps,
    this.isPreparingReview = false,
    this.reviewError,
    this.isEditingSlippage = false,
  });
  final CrossChainPaymentRequest request;
  final String? selectedChain;
  final int? slippageBps;
  final bool isPreparingReview;
  final String? reviewError;

  /// The slippage editor is inline card state, not a route, so the Android
  /// back dispatcher above the router reads it here to close the editor
  /// instead of dropping the request.
  final bool isEditingSlippage;
}

class CrossChainPaymentFlowNotifier
    extends Notifier<CrossChainPaymentFlowState?> {
  @override
  CrossChainPaymentFlowState? build() {
    ref.listen(appSecurityProvider, (previous, next) {
      if (previous?.isUnlocked == true && !next.isUnlocked) {
        final request = state?.request;
        // A newer request parked during lock wins over the visible card.
        if (request != null && ref.read(paymentUriPrefillProvider) == null) {
          ref.read(paymentUriPrefillProvider.notifier).set(request);
        }
        clear();
      }
    });
    ref.listen(accountProvider, (previous, next) {
      if (previous?.value?.activeAccountUuid != next.value?.activeAccountUuid) {
        clear();
      }
    });
    return null;
  }

  void present(CrossChainPaymentRequest request) {
    clear();
    state = CrossChainPaymentFlowState(request);
  }

  void chooseNetwork(String chain) {
    final current = state;
    if (current == null ||
        current.isPreparingReview ||
        !current.request.needsNetwork) {
      return;
    }
    if (!evmPaymentNetworks.values.any((network) => network.chain == chain)) {
      return;
    }
    state = CrossChainPaymentFlowState(
      current.request,
      selectedChain: chain,
      slippageBps: current.slippageBps,
      isEditingSlippage: current.isEditingSlippage,
    );
  }

  void setSlippageEditing(bool editing) {
    final current = state;
    if (current == null ||
        current.isPreparingReview ||
        current.isEditingSlippage == editing) {
      return;
    }
    state = CrossChainPaymentFlowState(
      current.request,
      selectedChain: current.selectedChain,
      slippageBps: current.slippageBps,
      reviewError: current.reviewError,
      isEditingSlippage: editing,
    );
  }

  void chooseSlippage(int bps) {
    final current = state;
    if (current == null || current.isPreparingReview) return;
    state = CrossChainPaymentFlowState(
      current.request,
      selectedChain: current.selectedChain,
      slippageBps: bps.clamp(10, 500),
    );
  }

  Future<bool> preparePay({required bool review}) async {
    final current = state;
    if (current == null ||
        current.isPreparingReview ||
        !ref.read(appSecurityProvider).isUnlocked ||
        !ref.read(swapFeatureEnabledProvider)) {
      return false;
    }
    final swap = ref.read(swapStateProvider);
    final resolution = resolveCrossChainPaymentRequest(
      current.request,
      swap.supportedExternalAssets,
      selectedChain: current.selectedChain,
    );
    final account = ref.read(accountProvider).value?.activeAccountUuid;
    if (!resolution.isReady || account == null) return false;
    final notifier = ref.read(swapStateProvider.notifier);
    if (!notifier.preparePayPaymentRequest(
      asset: resolution.asset!,
      destination: current.request.address,
      amountText: resolution.amountText,
      expectedAccountUuid: account,
    )) {
      return false;
    }
    if (current.slippageBps case final bps?) {
      notifier.updateSlippageBps(bps);
    }
    if (!review || resolution.amountText == null) return true;

    final pending = CrossChainPaymentFlowState(
      current.request,
      selectedChain: current.selectedChain,
      slippageBps: current.slippageBps,
      isPreparingReview: true,
    );
    state = pending;
    await notifier.showReview();
    if (!ref.mounted || !identical(state, pending)) return false;
    final prepared = ref.read(swapStateProvider);
    final ready =
        prepared.reviewVisible &&
        prepared.reviewQuote != null &&
        prepared.reviewAddressPlan != null &&
        prepared.reviewAccountUuid == account &&
        prepared.externalAssetIsAvailable &&
        ref.read(swapFeatureEnabledProvider) &&
        ref.read(appSecurityProvider).isUnlocked &&
        ref.read(accountProvider).value?.activeAccountUuid == account;
    if (!ready) notifier.cancelReviewQuote();
    state = CrossChainPaymentFlowState(
      current.request,
      selectedChain: current.selectedChain,
      slippageBps: current.slippageBps,
      reviewError: ready
          ? null
          : prepared.externalAssetSupportError ??
                prepared.quoteError ??
                'Payment review could not be prepared. Try again or edit the payment.',
    );
    return ready;
  }

  void clear() {
    if (state?.isPreparingReview == true) {
      ref.read(swapStateProvider.notifier).cancelReviewQuote();
    }
    state = null;
  }
}

final crossChainPaymentFlowProvider =
    NotifierProvider<
      CrossChainPaymentFlowNotifier,
      CrossChainPaymentFlowState?
    >(CrossChainPaymentFlowNotifier.new);
