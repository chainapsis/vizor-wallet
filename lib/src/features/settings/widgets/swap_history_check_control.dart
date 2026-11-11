import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/swap_history_check_provider.dart';
import '../../../providers/sync_provider.dart'
    show swapRecoveryUpdateRequiredProvider;

/// What the swap history check says for each state.
String swapHistoryCheckStatus(AppLocalizations l10n, SwapHistoryCheck check) =>
    switch (check) {
      SwapHistoryCheck.idle => l10n.settingsSwapHistoryIdle,
      SwapHistoryCheck.checking => l10n.settingsSwapHistoryChecking,
      SwapHistoryCheck.done => l10n.settingsSwapHistoryDone,
      // Mobile runs no rounds in the background (see canRunAppProcessWork).
      SwapHistoryCheck.continuing => l10n.settingsSwapHistoryContinuing,
      SwapHistoryCheck.paused => l10n.settingsSwapHistoryPaused,
      SwapHistoryCheck.failed => l10n.settingsSwapHistoryFailed,
      SwapHistoryCheck.walletChanged => l10n.settingsSwapHistoryWalletChanged,
      SwapHistoryCheck.notStarted => l10n.settingsSwapHistoryNotStarted,
      SwapHistoryCheck.pauseFailed => l10n.settingsSwapHistoryPauseFailed,
      SwapHistoryCheck.waitingForSync => l10n.settingsSwapHistoryWaitingForSync,
      SwapHistoryCheck.waitingForService =>
        l10n.settingsSwapHistoryWaitingForService,
      // Matches the swap quote's update message.
      SwapHistoryCheck.updateRequired => l10n.swapRecoveryUpdateRequired,
    };

/// The "Check swap history" button and its progress, at the bottom of the
/// NEAR swap privacy explanation on desktop and mobile.
class SwapHistoryCheckControl extends ConsumerWidget {
  const SwapHistoryCheckControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final watched = ref.watch(swapHistoryCheckProvider);
    // Automatic rounds can learn of an update first.
    final check =
        (ref.watch(swapRecoveryUpdateRequiredProvider).value ?? false) &&
            watched != SwapHistoryCheck.checking
        ? SwapHistoryCheck.updateRequired
        : watched;
    final running = check == SwapHistoryCheck.checking;
    final notifier = ref.read(swapHistoryCheckProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.settingsSwapHistoryExplanation,
          key: const ValueKey('settings_swap_history_explanation'),
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton(
              key: const ValueKey('settings_check_swap_history'),
              onPressed: running || check == SwapHistoryCheck.updateRequired
                  ? null
                  : () => unawaited(notifier.check()),
              size: AppButtonSize.medium,
              child: Text(context.l10n.settingsSwapHistoryCheckButton),
            ),
            // Only a call in flight or a job the wallet still has can be
            // paused.
            if (running || ref.watch(swapHistoryJobSavedProvider))
              AppButton(
                key: const ValueKey('settings_cancel_swap_history'),
                onPressed: () => unawaited(notifier.cancel()),
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.medium,
                child: Text(context.l10n.settingsSwapHistoryPauseButton),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          swapHistoryCheckStatus(context.l10n, check),
          key: const ValueKey('settings_check_swap_history_status'),
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}
