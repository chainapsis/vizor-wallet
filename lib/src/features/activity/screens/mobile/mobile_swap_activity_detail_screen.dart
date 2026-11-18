import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../swap/models/swap_activity_navigation.dart';
import '../../../swap/models/swap_activity_status_mapper.dart';
import '../../../swap/models/swap_models.dart';
import '../../../swap/providers/swap_payout_discovery_provider.dart';
import '../../../swap/providers/swap_state_provider.dart';
import '../../../swap/widgets/swap_activity_panel.dart';
import '../../../../core/l10n/l10n.dart';

/// Mobile host for the swap intent detail — Figma `Review Progress`
/// (4752:30028), `Swap Completed` (4752:82692), the deposit QR quote
/// (4731:96923), and the expired `Swap failed` frame (4752:28424).
/// The shared [SwapActivityDetailSurface] keeps all orchestration
/// (status refresh, deposit submission, Keystone signing); this host
/// provides the mobile chrome and the status-driven serif title.
class MobileSwapActivityDetailScreen extends ConsumerWidget {
  const MobileSwapActivityDetailScreen({
    required this.swapIntentId,
    this.returnTarget = SwapActivityReturnTarget.activity,
    this.autoSignZecDeposit = false,
    super.key,
  });

  final String swapIntentId;
  final SwapActivityReturnTarget returnTarget;
  final bool autoSignZecDeposit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(swapStateProvider);
    final canPop = Navigator.of(context).canPop();
    SwapIntent? intent;
    for (final candidate in state.intents) {
      if (candidate.id == swapIntentId.trim()) {
        intent = candidate;
        break;
      }
    }

    return PopScope<void>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canPop) context.go(returnTarget.path);
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: AppToastHost(
          child: SafeArea(
            child: Column(
              children: [
                MobileTopNav.back(
                  title: mobileSwapActivityTitle(
                    context.l10n,
                    state,
                    intent,
                    findingPayout:
                        intent != null && watchIntentFindingPayout(ref, intent),
                  ),
                  // Normal flow/row entry has a predecessor. Direct entry or
                  // restoration may have only this page, so use its return target.
                  onBack: () {
                    if (canPop) {
                      context.pop();
                    } else {
                      context.go(returnTarget.path);
                    }
                  },
                ),
                Expanded(
                  child: SwapActivityDetailSurface(
                    intentId: swapIntentId,
                    returnTarget: returnTarget,
                    autoSignZecDeposit: autoSignZecDeposit,
                    layout: SwapActivityDetailLayout.mobile,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String mobileSwapActivityTitle(
  AppLocalizations l10n,
  SwapState state,
  SwapIntent? intent, {
  bool findingPayout = false,
}) {
  if (intent == null) return l10n.activitySwapTitle;
  final presentation = swapActivityStatusPresentationForIntent(
    l10n,
    state,
    intent,
    findingPayout: findingPayout,
  );
  if (presentation.paymentMode) {
    return switch (intent.status) {
      SwapIntentStatus.complete => l10n.activityPayPaid,
      SwapIntentStatus.incompleteDeposit => l10n.activityPayIncomplete,
      SwapIntentStatus.refunded => l10n.commonPaymentRefunded,
      SwapIntentStatus.failed ||
      SwapIntentStatus.expired => l10n.commonPaymentFailed,
      _ => l10n.activityPayPaying,
    };
  }
  if (intent.status == SwapIntentStatus.expired) {
    return l10n.commonSwapFailed;
  }
  if (swapActivityShowsExternalDepositPage(intent)) {
    return l10n.commonReviewQuote;
  }
  return presentation.title;
}
