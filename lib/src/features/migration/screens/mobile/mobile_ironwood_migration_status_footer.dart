part of 'mobile_ironwood_migration_flow_screen.dart';

class _MigrationCanLeaveMessage extends StatelessWidget {
  const _MigrationCanLeaveMessage();

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.labelLarge.copyWith(
      color: context.colors.text.secondary,
    );
    return Column(
      children: [
        Text('You can leave this screen.', style: style),
        const SizedBox(height: AppSpacing.xs),
        Text('But keep Vizor open & running.', style: style),
      ],
    );
  }
}

class _MobileStatusBackHomeButton extends StatelessWidget {
  const _MobileStatusBackHomeButton({
    required this.onPressed,
    this.label = 'Back home',
    super.key,
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: AppButton(
        expand: true,
        height: 50,
        variant: AppButtonVariant.secondary,
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

List<MobileIronwoodMigrationPartPresentation>
_mobilePreparingPartPresentations({
  required rust_sync.MigrationStatus? status,
  required rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  final statusParts = [...?status?.parts]
    ..sort((left, right) => left.partIndex.compareTo(right.partIndex));
  if (statusParts.isNotEmpty) {
    return [
      for (final part in statusParts)
        MobileIronwoodMigrationPartPresentation(
          label: 'Part ${part.partIndex + 1}',
          status: MobileIronwoodMigrationPartStatus.pending,
          valueZatoshi: part.valueZatoshi,
        ),
    ];
  }
  final values = status?.targetValuesZatoshi ?? const [];
  final transfers = previewPlan?.scheduledTransfers ?? const [];
  final count = values.isNotEmpty
      ? values.length
      : transfers.isNotEmpty
      ? transfers.length
      : _mobilePlannedBatchCount(status, previewPlan: previewPlan);
  if (count <= 0) return const [];

  return [
    for (var index = 0; index < count; index++)
      MobileIronwoodMigrationPartPresentation(
        label: 'Part ${index + 1}',
        status: MobileIronwoodMigrationPartStatus.pending,
        valueZatoshi: values.isNotEmpty
            ? values[index]
            : transfers.isNotEmpty
            ? transfers[index].valueZatoshi
            : null,
      ),
  ];
}

int _mobilePlannedBatchCount(
  rust_sync.MigrationStatus? status, {
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  if (status == null) return previewPlan?.plannedBatchCount ?? 0;
  if (status.parts.isNotEmpty) return status.parts.length;
  if (status.totalCount > 0) return status.totalCount;
  if (status.targetValuesZatoshi.isNotEmpty) {
    return status.targetValuesZatoshi.length;
  }
  return math.max(1, status.preparedNoteCount);
}

String _mobileMigrationTotalAmountText(
  rust_sync.MigrationStatus? status, {
  required rust_sync.OrchardMigrationPrivatePlan? previewPlan,
  required String fallback,
}) {
  final planTotal = previewPlan == null
      ? BigInt.zero
      : _mobilePlanTotalZatoshi(previewPlan);
  if (planTotal > BigInt.zero) return _compactZec(planTotal);

  final parts = status?.parts ?? const [];
  if (parts.isNotEmpty) {
    final total = parts.fold<BigInt>(
      BigInt.zero,
      (sum, part) => sum + part.valueZatoshi,
    );
    if (total > BigInt.zero) return _compactZec(total);
  }

  final broadcasts = status?.scheduledBroadcasts ?? const [];
  if (broadcasts.isNotEmpty) {
    final total = broadcasts.fold<BigInt>(
      BigInt.zero,
      (sum, item) => sum + item.valueZatoshi,
    );
    if (total > BigInt.zero) return _compactZec(total);
  }
  final targetValues = status?.targetValuesZatoshi ?? const [];
  if (targetValues.isNotEmpty) {
    final total = targetValues.fold<BigInt>(
      BigInt.zero,
      (sum, value) => sum + value,
    );
    if (total > BigInt.zero) return _compactZec(total);
  }
  return fallback;
}

String _mobileSpendableAmountText(
  rust_sync.MigrationStatus? status, {
  BigInt? ironwoodBalance,
}) {
  if (ironwoodBalance != null) return _compactZec(ironwoodBalance);
  final parts = status?.parts ?? const [];
  if (parts.isNotEmpty) {
    final spendable = parts
        .where((part) => part.state == rust_sync.MigrationPartState.completed)
        .fold<BigInt>(BigInt.zero, (sum, part) => sum + part.valueZatoshi);
    return _compactZec(spendable);
  }
  final broadcasts = status?.scheduledBroadcasts ?? const [];
  if (broadcasts.isEmpty) return '-';
  final spendable = broadcasts
      .where((item) => item.status.toLowerCase() == 'confirmed')
      .fold<BigInt>(BigInt.zero, (sum, item) => sum + item.valueZatoshi);
  return _compactZec(spendable);
}
