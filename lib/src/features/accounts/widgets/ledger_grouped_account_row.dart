import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

/// The identity and selection treatment shared by grouped Ledger accounts.
/// The options control remains separate from the account selection target.
class LedgerGroupedAccountRow extends StatelessWidget {
  const LedgerGroupedAccountRow({
    required this.accountUuid,
    required this.name,
    required this.accountIndex,
    required this.isCurrent,
    required this.leading,
    required this.options,
    this.onTap,
    this.isHovered = false,
    super.key,
  });

  final String accountUuid;
  final String name;
  final int? accountIndex;
  final bool isCurrent;
  final Widget leading;
  final Widget options;
  final VoidCallback? onTap;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      key: ValueKey('ledger_grouped_account_selection_$accountUuid'),
      selected: isCurrent,
      container: true,
      child: Container(
        key: ValueKey('ledger_grouped_account_background_$accountUuid'),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isHovered ? colors.state.hoverOpacity : null,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xxs,
                            children: [
                              Text(
                                'Account ${accountIndex ?? '—'}',
                                style: AppTypography.bodySmall.copyWith(
                                  color: colors.text.secondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Visibility(
                                visible: isCurrent,
                                maintainState: true,
                                maintainAnimation: true,
                                maintainSize: true,
                                child: Text(
                                  '· Current',
                                  key: isCurrent
                                      ? ValueKey(
                                          'ledger_grouped_account_current_$accountUuid',
                                        )
                                      : null,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: colors.text.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            options,
          ],
        ),
      ),
    );
  }
}
