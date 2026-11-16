import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/zcash/spendable_wait.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/spendable_wait_provider.dart';

/// What the account can send now, then each amount it cannot spend yet with
/// its wait, then their total. Only the spendable amount is emphasized.
///
/// The content of the mobile sheet on Send.
class SpendableWaitBreakdown extends StatelessWidget {
  const SpendableWaitBreakdown({
    required this.wait,
    this.privacyModeEnabled = false,
    super.key,
  });

  final SpendableWait wait;
  final bool privacyModeEnabled;

  String _amount(BigInt zatoshi, {bool added = false}) {
    final text = ZecAmount.fromZatoshi(
      zatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    return hideAmountIfPrivacyMode(
      added ? '+$text' : text,
      privacyModeEnabled: privacyModeEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final rows = [
      if (wait.changeWaiting > BigInt.zero)
        (
          key: 'change',
          label: l10n.sendAvailableChangeRow,
          wait: wait.changeWait,
          amount: wait.changeWaiting,
        ),
      if (wait.receivedWaiting > BigInt.zero)
        (
          key: 'received',
          label: l10n.sendAvailableReceivedRow,
          wait: wait.receivedWait,
          amount: wait.receivedWaiting,
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.sendAvailableTitle,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _amount(wait.availableNow),
                key: const ValueKey('spendable_wait_available_now'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headlineLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows) ...[
                  Padding(
                    key: ValueKey('spendable_wait_row_${row.key}'),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        AppIcon(
                          AppIcons.time,
                          size: 20,
                          color: colors.icon.muted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.label,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.primary,
                                ),
                              ),
                              if (row.wait != null)
                                Text(
                                  availableInLabel(l10n, row.wait!),
                                  style: AppTypography.bodySmall.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _amount(row.amount, added: true),
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: colors.border.regular),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.commonTotal,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ),
                      Text(
                        _amount(wait.total),
                        key: const ValueKey('spendable_wait_total'),
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            l10n.sendAvailableFootnote,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the breakdown of what [accountUuid] can send now and what it is
/// still waiting for. The sheet follows the balance while it is open.
Future<void> showMobileSpendableWaitSheet(
  BuildContext context, {
  required String accountUuid,
}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) =>
        _SpendableWaitSheetBody(accountUuid: accountUuid),
  );
}

class _SpendableWaitSheetBody extends ConsumerStatefulWidget {
  const _SpendableWaitSheetBody({required this.accountUuid});

  final String accountUuid;

  @override
  ConsumerState<_SpendableWaitSheetBody> createState() =>
      _SpendableWaitSheetBodyState();
}

class _SpendableWaitSheetBodyState
    extends ConsumerState<_SpendableWaitSheetBody> {
  // The balance is unsettled while a new block is scanned; keep the last
  // settled breakdown rather than blanking the sheet for that moment.
  SpendableWait? _last;

  @override
  Widget build(BuildContext context) {
    final wait = ref.watch(spendableWaitProvider(widget.accountUuid)) ?? _last;
    _last = wait;
    return SpendableWaitSheetContent(
      wait: wait,
      privacyModeEnabled: ref.watch(privacyModeProvider),
      onClose: () => Navigator.of(context).pop(),
    );
  }
}

/// The sheet's content: the breakdown above a Close button.
class SpendableWaitSheetContent extends StatelessWidget {
  const SpendableWaitSheetContent({
    required this.wait,
    required this.onClose,
    this.privacyModeEnabled = false,
    super.key,
  });

  final SpendableWait? wait;
  final bool privacyModeEnabled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('mobile_spendable_wait_sheet'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wait != null)
            SpendableWaitBreakdown(
              wait: wait!,
              privacyModeEnabled: privacyModeEnabled,
            ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: onClose,
            child: Text(context.l10n.commonClose),
          ),
        ],
      ),
    );
  }
}
