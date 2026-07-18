part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationStatusScaffold extends ConsumerWidget {
  const _MobileMigrationStatusScaffold({
    required this.data,
    required this.child,
    this.topNavSpacing = 0,
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
  final double topNavSpacing;
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
            if (topNavSpacing > 0) SizedBox(height: topNavSpacing),
            MobileTopNav.account(
              accountName: data.accountName,
              syncLabel: syncLabel,
              avatar: AppProfilePicture(
                profilePictureId: data.profilePictureId,
                size: AppProfilePictureSize.navLarge,
              ),
            ),
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

enum _PreparingStatusState { complete, waiting, pending }

class _PreparingStatusRow extends StatelessWidget {
  const _PreparingStatusRow({
    required this.state,
    required this.label,
    this.showConnector = false,
  });

  final _PreparingStatusState state;
  final String label;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leading = switch (state) {
      _PreparingStatusState.complete => DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF00A460),
          shape: BoxShape.circle,
        ),
        child: const SizedBox.square(
          dimension: 24,
          child: Center(
            child: AppIcon(AppIcons.check, size: 16, color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
      _PreparingStatusState.waiting => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.inverse,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 24,
          child: Center(
            child: AppIcon(
              AppIcons.loader,
              size: 16,
              color: colors.icon.inverse,
              animated: false,
            ),
          ),
        ),
      ),
      _PreparingStatusState.pending => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.raised,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 24,
          child: Center(
            child: Text(
              '3',
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ),
      ),
    };
    return SizedBox(
      height: showConnector ? 58 : 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                leading,
                if (showConnector)
                  SizedBox(
                    width: 24,
                    height: 34,
                    child: Center(
                      child: SizedBox(
                        width: 1,
                        height: 18,
                        child: ColoredBox(color: colors.border.subtle),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTextRow extends StatelessWidget {
  const _StatusTextRow({
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
    this.emphasizeLabel = false,
    this.largeValue = false,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool emphasizeLabel;
  final bool largeValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(
          alignment: Alignment.center,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xxs),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.accent,
                      fontWeight: emphasizeLabel
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (largeValue
                              ? AppTypography.labelLarge
                              : AppTypography.labelMedium)
                          .copyWith(color: colors.text.accent),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.xxs),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentBatchRow extends StatelessWidget {
  const _CurrentBatchRow({required this.batch});

  final _MobileCurrentBatch batch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text(
          batch.number.toString().padLeft(2, '0'),
          style: AppTypography.codeMedium.copyWith(color: colors.text.muted),
        ),
        const SizedBox(width: AppSpacing.xxs),
        const _ZecBatchBadge(),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            batch.amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ),
        Text(
          batch.status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ],
    );
  }
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
  const _MobileStatusBackHomeButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Center(
        child: AppButton(
          height: 50,
          minWidth: 134,
          onPressed: onPressed,
          child: const Text('Back home'),
        ),
      ),
    );
  }
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

double _mobileMigrationProgress(
  rust_sync.MigrationStatus? status, {
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  if (status == null) return previewPlan == null ? 0 : 0.1;
  final total = _mobilePlannedBatchCount(status, previewPlan: previewPlan);
  if (total <= 0) return 0;
  return (status.confirmedTxCount / total).clamp(0, 1);
}

String _mobileRemainingAmountText(
  rust_sync.MigrationStatus? status, {
  required String fallback,
}) {
  if (status == null || status.targetValuesZatoshi.isEmpty) return fallback;

  final values = status.targetValuesZatoshi;
  final total = values.fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
  if (total <= BigInt.zero) return fallback;

  final completed = math.min(values.length, status.confirmedTxCount);
  final BigInt remaining;
  if (status.totalCount > 0 && values.length == status.totalCount) {
    remaining = values
        .skip(completed)
        .fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
  } else {
    final progress = _mobileMigrationProgress(status);
    final scaledProgress = BigInt.from((progress * 10000).round());
    remaining = total - (total * scaledProgress) ~/ BigInt.from(10000);
  }

  return ZecAmount.fromZatoshi(
    remaining > BigInt.zero ? remaining : BigInt.zero,
  ).balance.amountText;
}

class _MobileCurrentBatch {
  const _MobileCurrentBatch({
    required this.number,
    required this.amount,
    required this.status,
  });

  final int number;
  final String amount;
  final String status;
}

_MobileCurrentBatch _mobileCurrentBatch(
  rust_sync.MigrationStatus? status, {
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  if (status == null) {
    final values = previewPlan?.targetValuesZatoshi;
    return _MobileCurrentBatch(
      number: values?.isNotEmpty ?? false ? 1 : 0,
      amount: values?.isNotEmpty ?? false
          ? '${ZecAmount.fromZatoshi(values!.first).balance.amountText} ZEC'
          : 'Amount pending',
      status: 'Not started',
    );
  }
  final count = _mobilePlannedBatchCount(status, previewPlan: previewPlan);
  final number = math.min(count, math.max(1, status.confirmedTxCount + 1));
  final values = status.targetValuesZatoshi;
  final amount = number <= values.length
      ? '${ZecAmount.fromZatoshi(values[number - 1]).balance.amountText} ZEC'
      : 'Amount pending';
  final label = switch (status.phase) {
    kIronwoodMigrationReadyToMigratePhase => 'Preparing...',
    kIronwoodMigrationBroadcastScheduledPhase => 'Scheduled',
    kIronwoodMigrationBroadcastingPhase => 'Broadcasting...',
    _ => 'Confirming...',
  };
  return _MobileCurrentBatch(number: number, amount: amount, status: label);
}

String _mobileStatusArrivalLabel(
  rust_sync.MigrationStatus? status, {
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  if (status == null) {
    return previewPlan == null
        ? 'Schedule pending'
        : migrationPlanCompletionLabel(previewPlan);
  }
  return migrationDispatchTimingLabel(status);
}

String _mobileStatusTimingLabel(rust_sync.MigrationStatus? status) {
  if (status?.phase == kIronwoodMigrationWaitingConfirmationsPhase) {
    return 'Migration status';
  }
  return 'Estimated arrival time';
}

class _MigrationBatchModal extends StatefulWidget {
  const _MigrationBatchModal({
    required this.onClose,
    required this.previewPlan,
    this.status,
  });

  final VoidCallback onClose;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final rust_sync.MigrationStatus? status;

  @override
  State<_MigrationBatchModal> createState() => _MigrationBatchModalState();
}

class _MigrationBatchModalState extends State<_MigrationBatchModal> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final batchCount = _mobilePlannedBatchCount(
      widget.status,
      previewPlan: widget.previewPlan,
    );
    final targetValues =
        widget.status?.targetValuesZatoshi ??
        widget.previewPlan?.targetValuesZatoshi;
    final arrivalLabel = _mobileStatusArrivalLabel(
      widget.status,
      previewPlan: widget.previewPlan,
    );
    return ColoredBox(
      color: colors.background.neutralScrim,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.sm,
            AppSpacing.base,
          ),
          child: SizedBox(
            height: 480,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.base,
                borderRadius: BorderRadius.circular(AppRadii.large),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    blurRadius: 28,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.base + AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          migrationBatchesLabel(batchCount),
                          style: AppTypography.bodyLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Schedule: $arrivalLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Expanded(
                      child: RawScrollbar(
                        key: const ValueKey('migration_batch_scrollbar'),
                        controller: _scrollController,
                        thumbVisibility: true,
                        interactive: true,
                        radius: const Radius.circular(AppRadii.full),
                        thickness: 4,
                        mainAxisMargin: 20,
                        padding: EdgeInsets.zero,
                        crossAxisMargin: AppSpacing.xs,
                        thumbColor: colors.background.overlay,
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.md),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: ListView.separated(
                              controller: _scrollController,
                              physics: const ClampingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: batchCount,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                thickness: 1,
                                color: colors.border.subtle,
                              ),
                              itemBuilder: (context, index) {
                                final number = '${index + 1}'.padLeft(2, '0');
                                final dispatchLabel = _mobileBatchDispatchLabel(
                                  status: widget.status,
                                  index: index,
                                );
                                return SizedBox(
                                  height: 53,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          number,
                                          style: AppTypography.codeMedium
                                              .copyWith(
                                                color: colors.text.muted,
                                              ),
                                        ),
                                      ),
                                      const _ZecBatchBadge(),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Expanded(
                                        child: Text(
                                          targetValues != null &&
                                                  index < targetValues.length
                                              ? '${ZecAmount.fromZatoshi(targetValues[index]).balance.amountText} ZEC'
                                              : 'Amount pending',
                                          style: AppTypography.labelLarge
                                              .copyWith(
                                                color: colors.text.accent,
                                              ),
                                        ),
                                      ),
                                      Text(
                                        dispatchLabel,
                                        style: AppTypography.labelLarge
                                            .copyWith(
                                              color: colors.text.accent,
                                            ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.background.ground,
                          borderRadius: BorderRadius.circular(AppRadii.full),
                        ),
                        child: AppButton(
                          variant: AppButtonVariant.ghost,
                          expand: true,
                          height: 44,
                          onPressed: widget.onClose,
                          child: const Text('Close'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _mobileBatchDispatchLabel({
  required rust_sync.MigrationStatus? status,
  required int index,
}) {
  if (status == null) return 'Pending';
  if (index >= status.scheduledBroadcasts.length) return 'Pending';
  return migrationScheduledBroadcastLabel(status.scheduledBroadcasts[index]);
}

class _ZecBatchBadge extends StatelessWidget {
  const _ZecBatchBadge();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFFF6C744),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 19,
        child: Center(
          child: AppIcon(
            AppIcons.zcashCurrency,
            size: 11,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

class _PreparingParticlesPainter extends CustomPainter {
  const _PreparingParticlesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Figma node 6533:120710 uses a fixed 353 x 120 particle field inside
    // the 361 px title area. Scale the deterministic coordinates as a group
    // so compact widths keep the same arc rather than reflowing randomly.
    const particles = <(double, double, double)>[
      (268, 36, 19),
      (327, 84, 16),
      (4, 99, 13),
      (103, 37, 13),
      (56, 52, 13),
      (344, 97, 13),
      (22, 95, 11),
      (209, 13, 19),
      (135, 15, 20),
      (291, 55, 15),
      (316, 62, 15),
      (54, 72, 15),
      (33, 76, 15),
      (37, 57, 11),
      (234, 30, 11),
      (249, 17, 13),
      (202, 5, 6),
      (309, 80, 6),
      (255, 40, 6),
      (279, 60, 6),
      (120, 26, 6),
      (89, 62, 6),
      (75, 63, 6),
      (126, 15, 6),
      (152, 35, 10),
      (232, 14, 10),
      (5, 118, 6),
      (351, 118, 6),
      (335, 76, 6),
      (299, 45, 6),
      (13, 84, 6),
      (106, 24, 6),
      (164, 4, 37),
      (74, 34, 21),
    ];
    final paint = Paint()..color = color;
    final scale = size.width / 361;
    for (final particle in particles) {
      final diameter = particle.$3 * scale;
      canvas.drawCircle(
        Offset(
          (4 + particle.$1 + particle.$3 / 2) * scale,
          (4 + particle.$2 + particle.$3 / 2) * scale,
        ),
        diameter / 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PreparingParticlesPainter oldDelegate) =>
      oldDelegate.color != color;
}
