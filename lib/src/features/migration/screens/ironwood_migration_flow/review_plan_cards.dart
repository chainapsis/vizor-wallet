part of '../ironwood_migration_flow_screen.dart';

String _privateMigrationStartErrorMessage(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('mnemonic')) {
    return "Secret Passphrase isn't available for this account.";
  }
  if (lower.contains('secret storage') || lower.contains('unlocked session')) {
    return 'Unlock Vizor before starting migration.';
  }
  if (lower.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return "Couldn't broadcast the migration transaction. Try again.";
  }
  return "Couldn't start migration. Try again.";
}

String _privateMigrationContinueErrorMessage(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('secret storage') || lower.contains('unlocked session')) {
    return 'Unlock Vizor before continuing migration.';
  }
  if (lower.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return "Couldn't broadcast the migration transaction. Try again.";
  }
  return "Couldn't continue migration. Try again.";
}

// Kept for the unavailable-state fallback used by older deep links.
// ignore: unused_element
class _PrivateReviewLoading extends StatelessWidget {
  const _PrivateReviewLoading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 254,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.background.ground,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _PrivateReviewUnavailable extends StatelessWidget {
  const _PrivateReviewUnavailable({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 254,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppIcon(AppIcons.warning, size: 24),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _PrivateReviewPlan extends StatelessWidget {
  const _PrivateReviewPlan({required this.plan});

  final rust_sync.OrchardMigrationPrivatePlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final feeText =
        '~${_formatZecAmountCompact(plan.estimatedTotalFeeZatoshi)} ZEC';
    final orchardRemainderText =
        '~${_formatZecAmountCompact(plan.orchardChangeZatoshi ?? BigInt.zero)} ZEC';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 112,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ReviewTextRow(
                    key: const ValueKey('ironwood_migration_schedule_view'),
                    label: '${plan.plannedBatchCount} Planned batches',
                    value: 'View',
                    trailingIcon: AppIcons.chevronForward,
                    semiboldLabel: true,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _MigrationScheduleDialog(plan: plan),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ReviewTextRow(
                    label: 'Estimated arrival time',
                    value: _estimatedMigrationArrivalLabel(plan),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 112,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ReviewTextRow(
                    label: 'Fees (estimate)',
                    value: 'Total, $feeText',
                    mutedLabel: true,
                  ),
                  const SizedBox(height: 14),
                  _ReviewTextRow(
                    label: 'Orchard remains',
                    value: orchardRemainderText,
                    trailingIcon: AppIcons.help,
                    mutedLabel: true,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppIcon(AppIcons.shieldKeyhole, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Separate windows reduce correlation — the total '
                      'crossing amount stays publicly visible. Spending is '
                      'best effort, not a delivery time.',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MigrationScheduleDialog extends StatelessWidget {
  const _MigrationScheduleDialog({required this.plan});

  final rust_sync.OrchardMigrationPrivatePlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Migration schedule',
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                'Broadcast heights are relative to the block where the '
                'migration transactions are prepared.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: ListView.separated(
                  key: const ValueKey('ironwood_migration_schedule_list'),
                  shrinkWrap: true,
                  itemCount: plan.scheduledTransfers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final transfer = plan.scheduledTransfers[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: _ReviewTextRow(
                        key: ValueKey(
                          'ironwood_migration_schedule_batch_$index',
                        ),
                        label: 'Part ${index + 1}',
                        value:
                            '${_formatZecAmountCompact(transfer.valueZatoshi)} '
                            'ZEC  ·  +${transfer.blockOffset} blocks',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('ironwood_migration_schedule_close'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTextRow extends StatelessWidget {
  const _ReviewTextRow({
    super.key,
    required this.label,
    required this.value,
    this.trailingIcon,
    this.mutedLabel = false,
    this.semiboldLabel = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String? trailingIcon;
  final bool mutedLabel;
  final bool semiboldLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rowStyle = mutedLabel
        ? AppTypography.bodyMediumStrong
        : AppTypography.labelLarge;
    final row = Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: rowStyle.copyWith(
              color: mutedLabel ? colors.text.secondary : colors.text.accent,
              fontWeight: semiboldLabel ? FontWeight.w600 : rowStyle.fontWeight,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: rowStyle.copyWith(color: colors.text.accent),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                AppIcon(trailingIcon!, size: 12, color: colors.icon.regular),
              ],
            ],
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

// ignore: unused_element
