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
  SwapHistoryCheck.idle => 'Missing a payout or refund?',
  SwapHistoryCheck.checking => 'Checking… this can take a few minutes.',
  SwapHistoryCheck.done => 'Check complete.',
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

/// The "Check swap history" control at the bottom of the NEAR swap privacy
/// explanation: why to run it, or how it is going, with the one action that
/// fits. Screen readers hear each change. On desktop it is a row beside a
/// light button; [stacked] puts the line over a full-width primary button,
/// where a mobile sheet's buttons go.
class SwapHistoryCheckControl extends ConsumerWidget {
  const SwapHistoryCheckControl({this.stacked = false, super.key});

  final bool stacked;

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
    final notifier = ref.read(swapHistoryCheckProvider.notifier);
    // Only a call in flight or a job the wallet still has can be paused.
    final pausable =
        check == SwapHistoryCheck.checking ||
        ref.watch(swapHistoryJobSavedProvider);
    final status = Semantics(
      liveRegion: true,
      child: Text(
        swapHistoryCheckStatus(check),
        key: const ValueKey('settings_check_swap_history_status'),
        textAlign: stacked ? TextAlign.center : TextAlign.start,
        style: AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
      ),
    );
    final variant = stacked ? AppButtonVariant.primary : AppButtonVariant.ghost;
    final size = stacked ? AppButtonSize.large : AppButtonSize.small;
    final Widget? action = pausable
        ? AppButton(
            key: const ValueKey('settings_cancel_swap_history'),
            onPressed: () => unawaited(notifier.cancel()),
            variant: variant,
            size: size,
            expand: stacked,
            child: const Text('Pause'),
          )
        : check == SwapHistoryCheck.updateRequired
        ? null
        : AppButton(
            key: const ValueKey('settings_check_swap_history'),
            onPressed: () => unawaited(notifier.check()),
            variant: variant,
            size: size,
            expand: stacked,
            child: Text(
              check == SwapHistoryCheck.idle
                  ? 'Check swap history'
                  : 'Check again',
            ),
          );
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          status,
          if (action != null) ...[const SizedBox(height: AppSpacing.s), action],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: status),
        if (action != null) ...[const SizedBox(width: AppSpacing.xs), action],
      ],
    );
  }
}
