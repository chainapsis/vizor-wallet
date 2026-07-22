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
  const _MobileStatusCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

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
          padding:
              padding ??
              const EdgeInsets.symmetric(
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
  int? currentHeight,
}) {
  if (explicitParts != null) return explicitParts;

  final statusParts = status?.parts ?? const [];
  if (statusParts.isNotEmpty) {
    final orderedParts = [...statusParts]
      ..sort((left, right) => left.partIndex.compareTo(right.partIndex));
    return [
      for (final part in orderedParts)
        MobileIronwoodMigrationPartPresentation(
          label: 'Part ${part.partIndex + 1}',
          status: _mobileMigrationPartStatus(part.state),
          detail: '${_compactZec(part.valueZatoshi)} ZEC',
          eta: _mobileMigrationPartDetail(
            part,
            status: status,
            currentHeight: currentHeight,
          ),
          progress: _mobileMigrationPartProgress(part),
          valueZatoshi: part.valueZatoshi,
        ),
    ];
  }

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
          eta: switch (broadcasts[index].status.toLowerCase()) {
            'confirmed' ||
            'broadcasted' ||
            'submitted' ||
            'mined' ||
            'needs_input' => null,
            _ =>
              currentHeight == null || currentHeight <= 0
                  ? 'Waiting'
                  : 'Waiting · ${migrationHeightTimingLabel(broadcasts[index].scheduledHeight, currentHeight: currentHeight)}',
          },
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
          eta: index == status.nextActionPartIndex
              ? _mobileWaitingLabel(status, currentHeight: currentHeight)
              : 'Queued',
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

MobileIronwoodMigrationPartStatus _mobileMigrationPartStatus(
  rust_sync.MigrationPartState state,
) => switch (state) {
  rust_sync.MigrationPartState.completed =>
    MobileIronwoodMigrationPartStatus.complete,
  rust_sync.MigrationPartState.needsInput =>
    MobileIronwoodMigrationPartStatus.needsInput,
  rust_sync.MigrationPartState.scheduled =>
    MobileIronwoodMigrationPartStatus.pending,
  rust_sync.MigrationPartState.preparing ||
  rust_sync.MigrationPartState.migrating ||
  rust_sync.MigrationPartState.confirming =>
    MobileIronwoodMigrationPartStatus.active,
};

String? _mobileMigrationPartDetail(
  rust_sync.MigrationPartStatus part, {
  required rust_sync.MigrationStatus? status,
  required int? currentHeight,
}) {
  if (part.state == rust_sync.MigrationPartState.completed) return null;
  if (part.state == rust_sync.MigrationPartState.confirming &&
      part.confirmationTarget > 0) {
    return 'Confirming · '
        '${part.confirmationCount.clamp(0, part.confirmationTarget)}/'
        '${part.confirmationTarget}';
  }
  if (part.state == rust_sync.MigrationPartState.preparing) {
    if (status?.nextActionPartIndex == part.partIndex) {
      return _mobileWaitingLabel(status!, currentHeight: currentHeight);
    }
    return 'Queued';
  }
  return switch (part.state) {
    rust_sync.MigrationPartState.scheduled => _mobileScheduledPartLabel(
      part,
      status: status,
      currentHeight: currentHeight,
    ),
    rust_sync.MigrationPartState.migrating => 'Sending',
    rust_sync.MigrationPartState.needsInput => 'Action needed',
    _ => null,
  };
}

String _mobileScheduledPartLabel(
  rust_sync.MigrationPartStatus part, {
  required rust_sync.MigrationStatus? status,
  required int? currentHeight,
}) {
  final scheduledHeight = part.scheduledHeight;
  if (scheduledHeight == null || currentHeight == null || currentHeight <= 0) {
    return 'Waiting';
  }
  final timing = migrationHeightTimingLabel(
    scheduledHeight,
    currentHeight: currentHeight,
  );
  return 'Waiting · $timing';
}

String _mobileWaitingLabel(
  rust_sync.MigrationStatus status, {
  required int? currentHeight,
}) {
  final timing = migrationNextActionTimingLabel(
    status,
    currentHeight: currentHeight,
  );
  return timing == null ? 'Waiting' : 'Waiting · $timing';
}

double? _mobileMigrationPartProgress(rust_sync.MigrationPartStatus part) {
  if (part.state == rust_sync.MigrationPartState.completed) return 1;
  final confirmationProgress = part.confirmationTarget <= 0
      ? 0.0
      : (part.confirmationCount / part.confirmationTarget).clamp(0.0, 1.0);
  return switch (part.state) {
    rust_sync.MigrationPartState.preparing => confirmationProgress * 0.2,
    rust_sync.MigrationPartState.scheduled => 0.25,
    rust_sync.MigrationPartState.migrating => 0.7,
    rust_sync.MigrationPartState.confirming =>
      0.7 + (confirmationProgress * 0.3),
    rust_sync.MigrationPartState.needsInput => null,
    _ => null,
  };
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
            const SizedBox(height: 47),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    ...ScrollConfiguration.of(context).dragDevices,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: ListView.builder(
                  key: const ValueKey('mobile_ironwood_active_part_list'),
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  itemCount: parts.length,
                  itemBuilder: (context, index) => _MobileMigrationPartRow(
                    key: ValueKey('mobile_ironwood_part_row_$index'),
                    part: parts[index],
                    totalZatoshi: total,
                    isLast: index == parts.length - 1,
                    onTap: onPartTap == null ? null : () => onPartTap!(index),
                  ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _mobileStatusRailSegmentWidths(
          available: constraints.maxWidth,
          values: [
            for (final part in parts)
              _mobilePartValueZatoshi(part) ?? BigInt.one,
          ],
        );
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: SingleChildScrollView(
            key: const ValueKey('mobile_ironwood_status_rail_scroll'),
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              children: [
                for (var index = 0; index < parts.length; index++) ...[
                  Semantics(
                    label: parts[index].progress == null
                        ? null
                        : '${parts[index].label} progress '
                              '${(parts[index].progress! * 100).round()}%',
                    child: _MobileMigrationRailSegment(
                      width: widths[index],
                      status: parts[index].status,
                      progress: parts[index].progress,
                    ),
                  ),
                  if (index < parts.length - 1)
                    const SizedBox(width: _mobileMigrationPlanBarGap),
                ],
              ],
            ),
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
    required this.isLast,
    this.onTap,
    super.key,
  });

  final MobileIronwoodMigrationPartPresentation part;
  final BigInt totalZatoshi;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = _mobilePartValueZatoshi(part);
    final percentage = value == null
        ? null
        : _mobileMigrationPercentage(value, totalZatoshi);
    final availableWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - (AppSpacing.sm * 2),
    );
    final flexibleColumnScale = math.min(
      1.0,
      math.max(0.0, availableWidth - _mobileMigrationPartLabelWidth) /
          (_mobileMigrationPartValueWidth + _mobileMigrationPartStatusWidth),
    );
    final valueWidth = _mobileMigrationPartValueWidth * flexibleColumnScale;
    final statusWidth = _mobileMigrationPartStatusWidth * flexibleColumnScale;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: isLast
              ? _mobileMigrationPartRowContentExtent
              : _mobileMigrationPartRowExtent,
          child: Column(
            children: [
              SizedBox(
                height: _mobileMigrationPartRowContentExtent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: _mobileMigrationPartLabelWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xxs),
                        child: Text(
                          part.label,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: valueWidth,
                      child: Text.rich(
                        TextSpan(
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                          children: [
                            if (part.detail != null)
                              TextSpan(text: part.detail),
                            if (percentage != null)
                              TextSpan(
                                text: ' $percentage',
                                style: TextStyle(color: colors.text.secondary),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    SizedBox(
                      width: statusWidth,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _MobileMigrationPartStatusLabel(part: part),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Center(
                    child: Divider(height: 1, color: colors.border.subtle),
                  ),
                ),
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
    final style = AppTypography.labelLarge.copyWith(
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
          Flexible(
            child: Text(
              'Done',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
      MobileIronwoodMigrationPartStatus.needsInput => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'Action needed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(
            AppIcons.chevronForward,
            size: 18,
            color: colors.text.brandCrimson,
          ),
        ],
      ),
      MobileIronwoodMigrationPartStatus.active => Text(
        part.eta ?? 'Sending',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
      MobileIronwoodMigrationPartStatus.pending => Text(
        part.eta ?? 'Queued',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
