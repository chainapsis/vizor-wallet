part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationStatusScaffold extends ConsumerWidget {
  const _MobileMigrationStatusScaffold({
    required this.data,
    required this.child,
    this.showAccountNav = true,
    this.contentPadding = const EdgeInsets.fromLTRB(
      AppSpacing.sm,
      44,
      AppSpacing.sm,
      AppSpacing.md,
    ),
    super.key,
  });

  final IronwoodMigrationFlowData data;
  final Widget child;
  final bool showAccountNav;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final sync = ref.watch(syncProvider).value ?? SyncState();
    final syncLabel = SyncStatusLabel.from(sync).label;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            if (showAccountNav) ...[
              MobileTopNav.account(
                accountName: data.accountName,
                syncLabel: syncLabel,
                avatar: AppProfilePicture(
                  profilePictureId: data.profilePictureId,
                  size: AppProfilePictureSize.navLarge,
                ),
              ),
            ],
            Expanded(
              child: Padding(padding: contentPadding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileStatusCard extends StatelessWidget {
  const _MobileStatusCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
          boxShadow: appSurfaceShadow(colors),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _MobileMigrationRecoveryCard extends StatelessWidget {
  const _MobileMigrationRecoveryCard({
    required this.sending,
    required this.schedulingBackground,
    required this.backgroundRetryScheduled,
    required this.supportsBackgroundRetry,
    required this.error,
    required this.onSendOne,
    required this.onRetryInBackground,
  });

  final bool sending;
  final bool schedulingBackground;
  final bool backgroundRetryScheduled;
  final bool supportsBackgroundRetry;
  final String? error;
  final VoidCallback onSendOne;
  final VoidCallback onRetryInBackground;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final busy = sending || schedulingBackground;
    return _MobileStatusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.warning, size: 20, color: colors.icon.warning),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Transfer ready',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            supportsBackgroundRetry
                ? 'A scheduled transfer is still waiting. Send one now, or '
                      'let Vizor try again in the background.'
                : 'A scheduled transfer is still waiting. Send the next '
                      'transfer now to continue.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sending now can link this transfer more closely to your current '
            'app activity.',
            style: AppTypography.labelMedium.copyWith(color: colors.text.muted),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              error!,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('mobile_ironwood_send_one_due_button'),
            expand: true,
            constrainContent: true,
            height: 44,
            onPressed: busy ? null : onSendOne,
            child: Text(
              sending ? 'Sending...' : 'Send one now',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (supportsBackgroundRetry) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              key: const ValueKey('mobile_ironwood_retry_background_button'),
              variant: AppButtonVariant.secondary,
              expand: true,
              constrainContent: true,
              height: 44,
              onPressed: busy ? null : onRetryInBackground,
              child: Text(
                schedulingBackground
                    ? 'Scheduling...'
                    : backgroundRetryScheduled
                    ? 'Background retry scheduled'
                    : 'Retry in background',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// States used by the Figma status surface. These are intentionally supplied
/// by the caller: the current migration status API does not expose stable
/// part identifiers, fractional progress, or per-part input requirements.
enum MobileIronwoodMigrationPartStatus { complete, needsInput, active, pending }

class MobileIronwoodMigrationPartPresentation {
  const MobileIronwoodMigrationPartPresentation({
    required this.label,
    required this.status,
    this.detail,
    this.eta,
    // ignore: unused_element_parameter
    this.progress,
    this.valueZatoshi,
  });

  final String label;
  final MobileIronwoodMigrationPartStatus status;
  final String? detail;
  final String? eta;
  final BigInt? valueZatoshi;

  /// Only used for an explicitly supplied fixture or a future API contract.
  final double? progress;
}

List<MobileIronwoodMigrationPartPresentation>
_mobileMigrationPartPresentations({
  required rust_sync.MigrationStatus? status,
  required rust_sync.OrchardMigrationPrivatePlan? previewPlan,
  required List<MobileIronwoodMigrationPartPresentation>? explicitParts,
}) {
  if (explicitParts != null) return explicitParts;

  final broadcasts = status?.scheduledBroadcasts ?? const [];
  if (broadcasts.isNotEmpty) {
    return [
      for (var index = 0; index < broadcasts.length; index++)
        MobileIronwoodMigrationPartPresentation(
          label: 'Part ${index + 1}',
          status: switch (broadcasts[index].status.toLowerCase()) {
            'confirmed' => MobileIronwoodMigrationPartStatus.complete,
            'needs_input' => MobileIronwoodMigrationPartStatus.needsInput,
            'broadcasted' ||
            'submitted' ||
            'mined' => MobileIronwoodMigrationPartStatus.active,
            _ => MobileIronwoodMigrationPartStatus.pending,
          },
          detail: '${_compactZec(broadcasts[index].valueZatoshi)} ZEC',
          valueZatoshi: broadcasts[index].valueZatoshi,
          eta: broadcasts[index].status.toLowerCase() == 'confirmed'
              ? null
              : _mobileBatchDispatchLabel(status: status, index: index),
        ),
    ];
  }

  final targetValues = status?.targetValuesZatoshi ?? const [];
  if (targetValues.isNotEmpty) {
    final confirmedCount = status!.confirmedTxCount.clamp(
      0,
      targetValues.length,
    );
    final activeCount = math.max(
      confirmedCount,
      status.broadcastedTxCount.clamp(0, targetValues.length),
    );
    return [
      for (var index = 0; index < targetValues.length; index++)
        MobileIronwoodMigrationPartPresentation(
          label: 'Part ${index + 1}',
          status: index < confirmedCount
              ? MobileIronwoodMigrationPartStatus.complete
              : index < activeCount
              ? MobileIronwoodMigrationPartStatus.active
              : MobileIronwoodMigrationPartStatus.pending,
          detail: '${_compactZec(targetValues[index])} ZEC',
          valueZatoshi: targetValues[index],
        ),
    ];
  }

  final transfers = previewPlan?.scheduledTransfers ?? const [];
  return [
    for (var index = 0; index < transfers.length; index++)
      MobileIronwoodMigrationPartPresentation(
        label: 'Part ${index + 1}',
        status: MobileIronwoodMigrationPartStatus.pending,
        detail: '${_compactZec(transfers[index].valueZatoshi)} ZEC',
        valueZatoshi: transfers[index].valueZatoshi,
        eta: '+${transfers[index].blockOffset} blocks',
      ),
  ];
}

/// Reusable waiting card for the mobile migration status design.
///
/// [partCount] and confirmation values are data-driven. In particular, the
/// Figma sample amount/counts are never used as production defaults.
// ignore: unused_element
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Note split',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              _MobileMigrationWaitingDetailRow(
                label: 'Split notes into $partCount migration parts',
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
                animated: false,
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

class _MobileIronwoodActiveStatus extends StatelessWidget {
  const _MobileIronwoodActiveStatus({
    required this.parts,
    // ignore: unused_element_parameter
    this.onPartTap,
  });

  final List<MobileIronwoodMigrationPartPresentation> parts;
  final ValueChanged<int>? onPartTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = parts.fold<BigInt>(
          BigInt.zero,
          (sum, part) => sum + (_mobilePartValueZatoshi(part) ?? BigInt.zero),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MobileMigrationStatusRail(parts: parts),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView.separated(
                physics: const ClampingScrollPhysics(),
                itemCount: parts.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: context.colors.border.subtle),
                itemBuilder: (context, index) => _MobileMigrationPartRow(
                  key: ValueKey('mobile_ironwood_part_row_$index'),
                  part: parts[index],
                  totalZatoshi: total,
                  onTap: onPartTap == null ? null : () => onPartTap!(index),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MobileMigrationStatusRail extends StatelessWidget {
  const _MobileMigrationStatusRail({required this.parts});

  final List<MobileIronwoodMigrationPartPresentation> parts;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox(height: 20);
    final total = parts.fold<BigInt>(
      BigInt.zero,
      (sum, part) => sum + (_mobilePartValueZatoshi(part) ?? BigInt.zero),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(
            children: [
              for (var index = 0; index < parts.length; index++) ...[
                _MobileMigrationRailSegment(
                  width: _mobileRailSegmentWidth(
                    available: constraints.maxWidth,
                    value: _mobilePartValueZatoshi(parts[index]) ?? BigInt.one,
                    total: total,
                    count: parts.length,
                  ),
                  status: parts[index].status,
                  progress: parts[index].progress,
                ),
                if (index < parts.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MobileMigrationPartRow extends StatelessWidget {
  const _MobileMigrationPartRow({
    required this.part,
    required this.totalZatoshi,
    this.onTap,
    super.key,
  });

  final MobileIronwoodMigrationPartPresentation part;
  final BigInt totalZatoshi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = _mobilePartValueZatoshi(part);
    final percentage = value == null
        ? null
        : _mobileMigrationPercentage(value, totalZatoshi);
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  part.label,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                    children: [
                      if (part.detail != null) TextSpan(text: part.detail),
                      if (percentage != null)
                        TextSpan(
                          text: ' $percentage',
                          style: TextStyle(color: colors.text.secondary),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _MobileMigrationPartStatusLabel(part: part),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileMigrationPartStatusLabel extends StatelessWidget {
  const _MobileMigrationPartStatusLabel({required this.part});

  final MobileIronwoodMigrationPartPresentation part;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.bodyMedium.copyWith(
      color: part.status == MobileIronwoodMigrationPartStatus.needsInput
          ? colors.text.brandCrimson
          : colors.text.secondary,
    );
    return switch (part.status) {
      MobileIronwoodMigrationPartStatus.complete => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.checkCircle, size: 18, color: colors.icon.success),
          const SizedBox(width: AppSpacing.xxs),
          Text('Completed', style: style),
        ],
      ),
      MobileIronwoodMigrationPartStatus.needsInput => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Needs input', style: style),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(
            AppIcons.chevronForward,
            size: 18,
            color: colors.text.brandCrimson,
          ),
        ],
      ),
      MobileIronwoodMigrationPartStatus.active => Text(
        'Migrating...',
        style: style,
      ),
      MobileIronwoodMigrationPartStatus.pending => Text(
        part.eta ?? 'Pending',
        style: style,
      ),
    };
  }
}

BigInt? _mobilePartValueZatoshi(MobileIronwoodMigrationPartPresentation part) {
  final value = part.valueZatoshi;
  if (value != null) return value;
  final detail = part.detail;
  if (detail == null) return null;
  return parseZecAmount(detail.replaceAll('ZEC', '').trim());
}

class _MigrationCanLeaveMessage extends StatelessWidget {
  const _MigrationCanLeaveMessage();

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.labelMedium.copyWith(
      color: context.colors.text.secondary,
      height: 16 / 14,
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
  final values = status?.targetValuesZatoshi ?? const [];
  final transfers = previewPlan?.scheduledTransfers ?? const [];
  final count = values.isNotEmpty
      ? values.length
      : transfers.isNotEmpty
      ? transfers.length
      : _mobilePlannedBatchCount(status, previewPlan: previewPlan);
  if (count <= 0) return const [];

  final confirmationTarget = status?.denominationConfirmationTarget ?? 0;
  final confirmationCount = status?.denominationConfirmationCount ?? 0;
  final progress = confirmationTarget > 0
      ? (confirmationCount / confirmationTarget).clamp(0.0, 1.0)
      : 0.0;
  return [
    for (var index = 0; index < count; index++)
      MobileIronwoodMigrationPartPresentation(
        label: 'Part ${index + 1}',
        status: index == 0
            ? MobileIronwoodMigrationPartStatus.active
            : MobileIronwoodMigrationPartStatus.pending,
        progress: index == 0 ? progress : null,
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

String _mobileSpendableAmountText(rust_sync.MigrationStatus? status) {
  final broadcasts = status?.scheduledBroadcasts ?? const [];
  if (broadcasts.isEmpty) return '-';
  final spendable = broadcasts
      .where((item) => item.status.toLowerCase() == 'confirmed')
      .fold<BigInt>(BigInt.zero, (sum, item) => sum + item.valueZatoshi);
  return _compactZec(spendable);
}

String _mobileBatchDispatchLabel({
  required rust_sync.MigrationStatus? status,
  required int index,
}) {
  if (status == null) return 'Pending';
  if (index >= status.scheduledBroadcasts.length) return 'Pending';
  return migrationScheduledBroadcastLabel(
    status.scheduledBroadcasts[index],
    approximate: true,
  );
}
