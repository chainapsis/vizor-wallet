import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_shape.dart';
import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../accounts/widgets/mobile/account_edit_sheets.dart'
    show MobileSheetCancel;
import '../../swap/models/swap_models.dart';
import '../../swap/providers/pay_deposit_transaction_provider.dart';
import '../../swap/providers/swap_activity_tracker.dart';

/// Title of the confirmation before NEAR swap privacy turns off.
const kNearSwapPrivacyTurnOffTitle = 'Turn off NEAR swap privacy?';

/// Why turning it off matters while a one-time payout is still owed.
const kNearSwapPrivacyTurnOffPayoutCopy =
    "A swap is still waiting for its ZEC. While this is off, Vizor won't "
    'find it.';

/// Why turning it off matters while a swap that sent ZEC can still refund.
const kNearSwapPrivacyTurnOffRefundCopy =
    "A swap is still in progress. If it's refunded while this is off, Vizor "
    "won't find the refund.";

/// What happens to that ZEC.
const kNearSwapPrivacyTurnOffKeptCopy =
    'Nothing is lost. It shows up when you turn this back on.';

/// Which one-time swap ZEC the wallet would stop looking for: a payout still
/// owed, or a refund still possible.
typedef NearSwapPrivacyPendingSwaps = ({bool payout, bool refund});

/// How long after a payout completes the wallet may still be finding it.
const _payoutDiscoveryWindow = Duration(days: 7);

/// Reads the software accounts' swaps whose ZEC goes to a one-time address and
/// may still arrive (see [nearSwapPrivacyPendingSwapsIn]). Overridable in
/// tests.
final nearSwapPrivacyPendingSwapsProvider =
    Provider<Future<NearSwapPrivacyPendingSwaps> Function()>((ref) {
      return () async {
        final accounts = ref.read(accountProvider).value?.accounts ?? const [];
        final tracker = ref.read(swapActivityTrackerProvider);
        return nearSwapPrivacyPendingSwapsIn(
          [
            for (final account in accounts)
              if (!account.isHardware)
                for (final intent in await tracker.loadIntents(
                  accountUuid: account.uuid,
                ))
                  (account.uuid, intent),
          ],
          loadTransaction: ref.read(payDepositTransactionLoaderProvider),
          now: DateTime.now().toUtc(),
        );
      };
    });

/// Which of `swaps`, each with its account, may still send ZEC to a one-time
/// address: any unfinished one, and a payout completed in the last week that
/// [loadTransaction] doesn't find in the wallet yet.
Future<NearSwapPrivacyPendingSwaps> nearSwapPrivacyPendingSwapsIn(
  Iterable<(String, SwapIntent)> swaps, {
  required PayDepositTransactionLoader loadTransaction,
  required DateTime now,
}) async {
  final recent = now.subtract(_payoutDiscoveryWindow);
  var payout = false;
  var refund = false;
  for (final (accountUuid, intent) in swaps) {
    final direction = intent.direction;
    if (!intent.privateAddress || intent.startPending || direction == null) {
      continue;
    }
    if (direction.sendsZec) {
      refund |= !intent.status.isTerminal;
    } else if (!intent.status.isTerminal) {
      payout = true;
    } else if (!payout &&
        intent.status == SwapIntentStatus.complete &&
        (intent.completedAt?.isAfter(recent) ?? false)) {
      final txid = swapChainTxidToWalletTxidHex(intent.destinationChainTxHash);
      payout =
          txid != null &&
          await loadTransaction(accountUuid: accountUuid, walletTxid: txid) ==
              null;
    }
  }
  return (payout: payout, refund: refund);
}

/// The confirmation's lines for [pending], or null when nothing is pending.
List<String>? nearSwapPrivacyTurnOffLines(NearSwapPrivacyPendingSwaps pending) {
  if (!pending.payout && !pending.refund) return null;
  return [
    if (pending.payout) kNearSwapPrivacyTurnOffPayoutCopy,
    if (pending.refund) kNearSwapPrivacyTurnOffRefundCopy,
    kNearSwapPrivacyTurnOffKeptCopy,
  ];
}

/// Reads [nearSwapPrivacyPendingSwapsProvider] and returns the lines to warn
/// with, or null. A failed read can't say a swap is pending, so it doesn't.
Future<List<String>?> nearSwapPrivacyTurnOffWarning(WidgetRef ref) async {
  try {
    return nearSwapPrivacyTurnOffLines(
      await ref.read(nearSwapPrivacyPendingSwapsProvider)(),
    );
  } catch (error) {
    log('NEAR swap privacy: pending swaps not read: $error');
    return null;
  }
}

/// Asks whether to turn NEAR swap privacy off, showing `lines`. Resolves to
/// true only when the user confirms. Overridable through
/// [nearSwapPrivacyTurnOffConfirmerProvider].
typedef NearSwapPrivacyTurnOffConfirmer =
    Future<bool> Function(BuildContext context, List<String> lines);

/// Overridable in tests; production shows the form factor's confirmation.
final nearSwapPrivacyTurnOffConfirmerProvider =
    Provider<NearSwapPrivacyTurnOffConfirmer>(
      (_) => confirmNearSwapPrivacyTurnOff,
    );

/// Shows the confirmation for this binary's form factor: a sheet on mobile, a
/// dialog on desktop.
Future<bool> confirmNearSwapPrivacyTurnOff(
  BuildContext context,
  List<String> lines,
) async {
  final confirmed = kAppFormFactor == AppFormFactor.mobile
      ? await showAppMobileSheet<bool>(
          context: context,
          builder: (_) => NearSwapPrivacyTurnOffSheet(lines: lines),
        )
      : await showDialog<bool>(
          context: context,
          builder: (_) => NearSwapPrivacyTurnOffDialog(lines: lines),
        );
  return confirmed == true;
}

/// Toggles NEAR swap privacy, first confirming a turn-off while a swap's ZEC
/// may still arrive at a one-time address.
Future<void> toggleNearSwapPrivacy(BuildContext context, WidgetRef ref) async {
  final enabled = !ref.read(nearSwapPrivacyProvider);
  if (!enabled) {
    final lines = await nearSwapPrivacyTurnOffWarning(ref);
    if (!context.mounted) return;
    if (lines != null &&
        !await ref.read(nearSwapPrivacyTurnOffConfirmerProvider)(
          context,
          lines,
        )) {
      return;
    }
  }
  if (!context.mounted) return;
  // Apply the choice the user confirmed, regardless of the current state.
  await ref.read(nearSwapPrivacyProvider.notifier).set(enabled);
}

class NearSwapPrivacyTurnOffDialog extends StatelessWidget {
  const NearSwapPrivacyTurnOffDialog({required this.lines, super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      key: const ValueKey('near_swap_privacy_turn_off_dialog'),
      backgroundColor: colors.background.ground,
      shape: appModalShape(BorderRadius.circular(AppRadii.medium)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                kNearSwapPrivacyTurnOffTitle,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              NearSwapPrivacyTurnOffLines(
                lines: lines,
                color: colors.text.secondary,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('near_swap_privacy_turn_off_confirm'),
                expand: true,
                variant: AppButtonVariant.destructive,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Turn off'),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                key: const ValueKey('near_swap_privacy_turn_off_cancel'),
                expand: true,
                variant: AppButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NearSwapPrivacyTurnOffSheet extends StatelessWidget {
  const NearSwapPrivacyTurnOffSheet({required this.lines, super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      key: const ValueKey('near_swap_privacy_turn_off_sheet'),
      title: kNearSwapPrivacyTurnOffTitle,
      onClose: () => Navigator.of(context).pop(false),
      leading: AppIcon(AppIcons.linkOff, size: 20, color: colors.icon.accent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NearSwapPrivacyTurnOffLines(lines: lines, color: colors.text.accent),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('near_swap_privacy_turn_off_confirm'),
            variant: AppButtonVariant.destructive,
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn off'),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileSheetCancel(onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}

/// The warning's paragraphs in [color].
class NearSwapPrivacyTurnOffLines extends StatelessWidget {
  const NearSwapPrivacyTurnOffLines({
    required this.lines,
    required this.color,
    super.key,
  });

  final List<String> lines;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('near_swap_privacy_turn_off_lines'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, line) in lines.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xs),
          Text(line, style: AppTypography.bodyMedium.copyWith(color: color)),
        ],
      ],
    );
  }
}
