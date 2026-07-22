part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileIronwoodWaitingStatusCard extends StatelessWidget {
  const _MobileIronwoodWaitingStatusCard({
    required this.partCount,
    required this.confirmedConfirmations,
    required this.confirmationTarget,
    required this.requiresKeystoneApproval,
  });

  final int partCount;
  final int confirmedConfirmations;
  final int confirmationTarget;
  final bool requiresKeystoneApproval;

  @override
  Widget build(BuildContext context) {
    final confirmations = confirmedConfirmations.clamp(
      0,
      confirmationTarget > 0 ? confirmationTarget : 0,
    );
    return Column(
      children: [
        _MobileStatusCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.sm,
            27,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Note Split',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              _MobileMigrationWaitingDetailRow(
                label: 'Split Notes into $partCount Migration Parts',
                value: '',
                active: false,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: SizedBox(
                  height: 24,
                  child: VerticalDivider(
                    width: 1,
                    color: context.colors.border.regular,
                  ),
                ),
              ),
              _MobileMigrationWaitingDetailRow(
                label: 'Wait for confirmation',
                value: '$confirmations/$confirmationTarget blocks',
                active:
                    confirmationTarget <= 0 ||
                    confirmations < confirmationTarget,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          requiresKeystoneApproval
              ? 'Another Keystone approval will be needed after these '
                    'confirmations.'
              : 'Migration will start automatically once note split is '
                    'complete.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        const _MigrationCanLeaveMessage(),
      ],
    );
  }
}

class _MobileMigrationWaitingDetailRow extends StatelessWidget {
  const _MobileMigrationWaitingDetailRow({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final animateLoader = active && !MediaQuery.disableAnimationsOf(context);
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: active ? colors.background.inverse : colors.icon.success,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: AppIcon(
                active ? AppIcons.loader : AppIcons.check,
                size: 15,
                color: colors.icon.inverse,
                animated: animateLoader,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ),
        if (value.isNotEmpty)
          Text(
            value,
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
