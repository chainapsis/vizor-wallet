import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/swap_feature_config.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/content_overlay_inset.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_modal_overlay_scope.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../send/services/send_flow.dart';
import '../../swap/models/swap_activity_navigation.dart';
import '../../swap/providers/swap_state_provider.dart';
import '../../swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';
import '../../swap/widgets/swap_slippage_modal.dart';
import '../models/payment_request_resolution.dart';
import '../providers/cross_chain_payment_request_provider.dart';
import 'cross_chain_payment_request_card.dart';

class CrossChainPaymentRequestHost extends ConsumerWidget {
  const CrossChainPaymentRequestHost({
    required this.router,
    required this.child,
    super.key,
  });
  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(crossChainPaymentFlowProvider);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (flow != null)
          AppModalOverlayScope(
            child: _RequestOverlay(
              key: ValueKey(flow.request.id),
              router: router,
              flow: flow,
            ),
          ),
      ],
    );
  }
}

class _RequestOverlay extends ConsumerStatefulWidget {
  const _RequestOverlay({required this.router, required this.flow, super.key});
  final GoRouter router;
  final CrossChainPaymentFlowState flow;

  @override
  ConsumerState<_RequestOverlay> createState() => _RequestOverlayState();
}

class _RequestOverlayState extends ConsumerState<_RequestOverlay> {
  bool _closingRequest = false;

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final enabled = ref.watch(swapFeatureEnabledProvider);
    // Respect the feature gate before initializing the pricing/network lane.
    final swap = enabled ? ref.watch(swapStateProvider) : null;
    final notifier = enabled ? ref.read(swapStateProvider.notifier) : null;
    final privacy = enabled ? ref.watch(networkPrivacyProvider) : null;
    final connectingTor =
        privacy?.isBusy == true &&
        (privacy?.targetTorEnabled ?? privacy?.torEnabled) == true;
    final torFailed =
        privacy?.torRouteRetained == true &&
        privacy?.status == NetworkPrivacyConnectionStatus.failed;
    final loading =
        !torFailed && (connectingTor || (swap?.pricingLoading ?? false));
    final availability = torFailed
        ? 'Could not connect to Tor. Try again to load payment options.'
        : flow.reviewError ??
              (!enabled
                  ? null
                  : swap!.supportedAssetsError ??
                        (!loading && !notifier!.paymentRequestAssetsReady
                            ? 'Payment options could not be loaded. Check your connection and try again.'
                            : null));
    final resolution = !enabled
        ? const PaymentRequestResolution(
            message: 'Pay is not available for this wallet.',
          )
        : resolveCrossChainPaymentRequest(
            flow.request,
            swap!.supportedExternalAssets,
            selectedChain: flow.selectedChain,
          );
    final flowNotifier = ref.read(crossChainPaymentFlowProvider.notifier);
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final slippageBps = flow.slippageBps ?? swap?.slippageBps;
    final editingSlippage =
        flow.isEditingSlippage && enabled && slippageBps != null;
    void closeSlippage() => flowNotifier.setSlippageEditing(false);

    void closeRequest() {
      if (!mounted) return;
      if (ref.read(crossChainPaymentFlowProvider)?.request.id ==
          flow.request.id) {
        flowNotifier.clear();
      }
    }

    void beginClosingRequest() {
      if (!mounted || _closingRequest) return;
      setState(() => _closingRequest = true);
      if (flow.isPreparingReview) notifier?.cancelReviewQuote();
    }

    void dismissRequest() {
      if (mobile) {
        beginClosingRequest();
      } else {
        closeRequest();
      }
    }

    Future<void> continueToPay({required bool review}) async {
      if (_closingRequest ||
          !identical(ref.read(crossChainPaymentFlowProvider), flow)) {
        return;
      }
      if (!await flowNotifier.preparePay(review: review) ||
          !context.mounted ||
          _closingRequest) {
        return;
      }
      final prepared = ref.read(swapStateProvider);
      final showReview = review && prepared.reviewVisible;
      flowNotifier.clear();
      ref.read(sendStatusRoutePayloadProvider.notifier).clear();
      widget.router.go(
        mobile && showReview ? '/pay/review' : '/pay',
        extra: PayComposerNavigationArgs(
          preservePreparedComposer: true,
          paymentRequestId: flow.request.id,
          showPreparedReview: showReview,
          reviewAfterAmount: review && !showReview,
        ),
      );
    }

    final card = Material(
      type: MaterialType.transparency,
      child: CrossChainPaymentRequestCard(
        key: ValueKey(flow.request.id),
        request: flow.request,
        resolution: resolution,
        estimatedZecAmount: swap == null
            ? null
            : resolution.estimateZecAmount(swap.indicativeExternalPerZec),
        selectedChain: flow.selectedChain,
        isLoading: loading,
        loadingMessage: connectingTor
            ? 'Connecting to Tor…'
            : 'Checking payment options…',
        isPreparingReview: flow.isPreparingReview,
        availabilityMessage: availability,
        isMobile: mobile,
        slippageBps: slippageBps,
        onOpenSlippage: () => flowNotifier.setSlippageEditing(true),
        onCancel: dismissRequest,
        onNetworkSelected: flowNotifier.chooseNetwork,
        onRetry: () {
          if (torFailed) {
            unawaited(ref.read(networkPrivacyProvider.notifier).retry());
          } else if (flow.reviewError != null) {
            unawaited(continueToPay(review: true));
          } else if (notifier != null) {
            unawaited(notifier.refreshPaymentRequestAssets());
          }
        },
        onContinue: () => unawaited(continueToPay(review: true)),
        onEdit: () => unawaited(continueToPay(review: false)),
      ),
    );
    void updateSlippage(int bps) {
      if (!mounted ||
          ref.read(crossChainPaymentFlowProvider)?.request.id !=
              flow.request.id) {
        return;
      }
      flowNotifier.chooseSlippage(bps);
      closeSlippage();
    }

    final editor = !editingSlippage
        ? null
        : Material(
            type: MaterialType.transparency,
            child: mobile
                ? MobileSwapSlippageStepperModal(
                    slippageBps: slippageBps,
                    paymentMode: true,
                    onSubmitted: updateSlippage,
                    onCancel: closeSlippage,
                  )
                : SwapSlippageModal(
                    slippageBps: slippageBps,
                    paymentMode: true,
                    onSubmitted: updateSlippage,
                    onCancel: closeSlippage,
                    onBack: closeSlippage,
                  ),
          );
    return AppPaneModalOverlay(
      onDismiss: dismissRequest,
      alignment: mobile ? Alignment.bottomCenter : Alignment.center,
      child: mobile
          ? SafeArea(
              bottom: false,
              minimum: const EdgeInsets.only(top: AppSpacing.base),
              child: AppDraggableMobileSheet(
                key: ValueKey((flow.request.id, editingSlippage)),
                dismissRequested: _closingRequest,
                onClosing: beginClosingRequest,
                onDismiss: closeRequest,
                child: MobileModalCard(
                  onBack: editingSlippage ? closeSlippage : null,
                  child:
                      editor ??
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.base,
                        ),
                        child: card,
                      ),
                ),
              ),
            )
          : ContentPaneCenteringPadding(
              child: editor == null
                  ? AppModalCard(width: 396, child: card)
                  : SizedBox(width: 396, child: editor),
            ),
    );
  }
}
