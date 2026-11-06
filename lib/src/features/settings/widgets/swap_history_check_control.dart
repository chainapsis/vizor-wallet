import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/swap_history_check_provider.dart';
import '../../../providers/sync_provider.dart'
    show swapRecoveryUpdateRequiredProvider;

/// What the swap history check says for each state.
String swapHistoryCheckStatus(SwapHistoryCheck check) => switch (check) {
  SwapHistoryCheck.idle => 'Check older addresses for repeat payments.',
  SwapHistoryCheck.checking => 'Checking swap history…',
  SwapHistoryCheck.done => 'Swap history check complete.',
  // Mobile runs no rounds in the background (see canRunAppProcessWork).
  SwapHistoryCheck.continuing =>
    'The check will keep going while Vizor is open.',
  SwapHistoryCheck.paused => 'Paused. Check again to resume.',
  SwapHistoryCheck.failed =>
    "Swap history can't be checked right now. Try again later.",
  SwapHistoryCheck.walletChanged =>
    'The check stopped because the wallet changed. Try again.',
  SwapHistoryCheck.notStarted =>
    "The check couldn't start. Try again in a moment.",
  SwapHistoryCheck.pauseFailed => "Couldn't pause the check. Try again.",
  SwapHistoryCheck.waitingForSync =>
    'Waiting for wallet sync. Try again in a few minutes.',
  SwapHistoryCheck.waitingForService =>
    "The swap recovery service hasn't caught up with this wallet yet. "
        'Try again in a few minutes.',
  SwapHistoryCheck.updateRequired => kSwapRecoveryUpdateMessage,
};

/// Shown when the receiver service needs a newer app. Matches the swap quote's
/// update message.
const kSwapRecoveryUpdateMessage =
    'Update Vizor to keep checking private swap addresses. '
    'Your saved progress is kept.';

/// Why the check exists, under the button.
const kSwapHistoryCheckExplanation =
    'Only needed if a swap payment or refund is missing.';

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
          kSwapHistoryCheckExplanation,
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
              child: const Text('Check swap history'),
            ),
            // Only a call in flight or a job the wallet still has can be
            // paused.
            if (running || ref.watch(swapHistoryJobSavedProvider))
              AppButton(
                key: const ValueKey('settings_cancel_swap_history'),
                onPressed: () => unawaited(notifier.cancel()),
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.medium,
                child: const Text('Pause check'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          swapHistoryCheckStatus(check),
          key: const ValueKey('settings_check_swap_history_status'),
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}
