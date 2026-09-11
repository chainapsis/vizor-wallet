import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../domain/swap_contract.dart';
import '../models/swap_deposit_recovery_info.dart';
import '../models/swap_refund_policy.dart';

export '../models/swap_deposit_recovery_info.dart';

/// Timeout-page prompt under the restart action. A quiet ghost button so it
/// reads as a question, not as a peer of the page's one recovery action.
class SwapLateDepositPrompt extends StatelessWidget {
  const SwapLateDepositPrompt({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('swap_late_deposit_prompt'),
      onPressed: onTap,
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.large,
      height: 36,
      child: const Text(SwapRefundPolicy.lateDepositPrompt),
    );
  }
}

void _copyLateDepositDetails(BuildContext context, SwapDepositRecoveryInfo info) {
  copyTextWithToast(
    context,
    text: info.bundleText,
    toastMessage: 'Deposit details copied',
  );
}

/// Desktop late-deposit explainer: the pane modal card with the refund
/// fact, the support fallback, and two actions. No close button by product
/// decision — the host's `AppPaneModalOverlay` dismisses on scrim tap and
/// Escape.
class SwapLateDepositModal extends StatelessWidget {
  const SwapLateDepositModal({required this.info, super.key});

  final SwapDepositRecoveryInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppModalCard(
      key: const ValueKey('swap_late_deposit_modal'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            SwapRefundPolicy.lateDepositTitle,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            SwapRefundPolicy.lateDepositBody,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            SwapRefundPolicy.lateDepositSupport,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // The copy action sits outside `AppModalActions`: its two-up slots
          // cap the label at ~74px once a leading icon is set.
          AppButton(
            key: const ValueKey('swap_late_deposit_copy_button'),
            onPressed: () => _copyLateDepositDetails(context, info),
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.mediumLarge,
            height: kAppModalButtonHeight,
            expand: true,
            leading: const AppIcon(AppIcons.copy, size: 16),
            child: const Text(SwapRefundPolicy.lateDepositAction),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The arrow is the project's external-link cue.
          AppButton(
            key: const ValueKey('swap_late_deposit_support_button'),
            onPressed: _openSupport,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.mediumLarge,
            height: kAppModalButtonHeight,
            expand: true,
            trailing: const AppIcon(AppIcons.arrowTopRight, size: 16),
            child: const Text(SwapRefundPolicy.lateDepositSupportAction),
          ),
        ],
      ),
    );
  }
}

void _openSupport() {
  unawaited(
    launchUrl(SwapRefundPolicy.supportUri, mode: LaunchMode.externalApplication),
  );
}

/// Mobile late-deposit explainer: the shared `_Modal Type` sheet layout
/// with the same copy and actions. Present through `showAppMobileSheet`.
class SwapLateDepositSheet extends StatelessWidget {
  const SwapLateDepositSheet({required this.info, super.key});

  final SwapDepositRecoveryInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      key: const ValueKey('swap_late_deposit_sheet'),
      title: SwapRefundPolicy.lateDepositTitle,
      onClose: () => Navigator.of(context).maybePop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            SwapRefundPolicy.lateDepositBody,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            SwapRefundPolicy.lateDepositSupport,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('swap_late_deposit_copy_button'),
            onPressed: () => _copyLateDepositDetails(context, info),
            variant: AppButtonVariant.secondary,
            expand: true,
            leading: const AppIcon(AppIcons.copy, size: 20),
            child: const Text(SwapRefundPolicy.lateDepositAction),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The scaffold's pinned close button dismisses the sheet.
          AppButton(
            key: const ValueKey('swap_late_deposit_support_button'),
            onPressed: _openSupport,
            variant: AppButtonVariant.ghost,
            expand: true,
            trailing: const AppIcon(AppIcons.arrowTopRight, size: 20),
            child: const Text(SwapRefundPolicy.lateDepositSupportAction),
          ),
        ],
      ),
    );
  }
}

/// Mobile counterpart of the desktop tooltip on the deposit page's "Network"
/// row: the shared `_Modal Type` layout with the same help text and a single
/// dismiss action. Present through `showAppMobileSheet`, which supplies the
/// card chrome.
class SwapDepositNetworkSheet extends StatelessWidget {
  const SwapDepositNetworkSheet({required this.asset, super.key});

  final SwapAsset asset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      key: const ValueKey('swap_deposit_network_sheet'),
      title: SwapRefundPolicy.depositNetworkHelpTitle,
      onClose: () => Navigator.of(context).maybePop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            SwapRefundPolicy.depositNetworkHelp(
              symbol: asset.symbol,
              chainLabel: asset.chainLabel,
            ),
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('swap_deposit_network_sheet_dismiss'),
            onPressed: () => Navigator.of(context).maybePop(),
            expand: true,
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
