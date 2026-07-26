part of '../ironwood_migration_flow_screen.dart';

int _compareMigrationPartsByExpectedProcessingOrder(
  rust_sync.MigrationPartStatus left,
  rust_sync.MigrationPartStatus right,
) {
  final leftOrder = left.scheduleOrder;
  final rightOrder = right.scheduleOrder;
  if (leftOrder != null || rightOrder != null) {
    final comparison = (leftOrder ?? 1 << 30).compareTo(rightOrder ?? 1 << 30);
    if (comparison != 0) return comparison;
  }

  final leftHeight = left.scheduledHeight;
  final rightHeight = right.scheduledHeight;
  if (leftHeight != null || rightHeight != null) {
    final comparison = (leftHeight ?? 1 << 30).compareTo(
      rightHeight ?? 1 << 30,
    );
    if (comparison != 0) return comparison;
  }
  return left.partIndex.compareTo(right.partIndex);
}

class _MigrationStatusContent extends StatefulWidget {
  const _MigrationStatusContent({
    required this.status,
    required this.action,
    required this.isAdvancing,
    required this.currentHeight,
    required this.onAction,
  });

  final rust_sync.MigrationStatus status;
  final _StatusAction action;
  final bool isAdvancing;
  final int currentHeight;
  final VoidCallback? onAction;

  @override
  State<_MigrationStatusContent> createState() =>
      _MigrationStatusContentState();
}

class _MigrationStatusContentState extends State<_MigrationStatusContent> {
  String? _progressRunId;
  int _maxSeenCurrentHeight = 0;

  void _syncProgressRun(String runId) {
    if (_progressRunId == runId) return;
    _progressRunId = runId;
    _maxSeenCurrentHeight = 0;
  }

  int _displayCurrentHeight(int currentHeight) {
    if (currentHeight > _maxSeenCurrentHeight) {
      _maxSeenCurrentHeight = currentHeight;
    }
    if (_maxSeenCurrentHeight > 0) return _maxSeenCurrentHeight;
    return currentHeight;
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final runId = status.activeRunId ?? 'inactive';
    _syncProgressRun(runId);

    final parts = [..._displayMigrationParts(status)]
      ..sort(_compareMigrationPartsByExpectedProcessingOrder);
    var values = parts.isNotEmpty
        ? [for (final part in parts) part.valueZatoshi]
        : [for (final value in status.targetValuesZatoshi) value];
    if (values.isEmpty && status.phase != kIronwoodMigrationCompletePhase) {
      values = [BigInt.zero];
    }
    final readyHasMigrationProgress =
        status.pendingTxCount > 0 ||
        status.broadcastedTxCount > 0 ||
        status.confirmedTxCount > 0 ||
        status.signedChildPcztCount > 0;
    final statuses = status.phase == kIronwoodMigrationCompletePhase
        ? List<_MigrationBatchStatus>.filled(
            values.length,
            _MigrationBatchStatus.complete,
          )
        // A completed denomination split only means the notes are ready to
        // migrate. It must not paint the transfer ring green before any
        // migration note has actually been signed and confirmed.
        : status.phase == kIronwoodMigrationReadyToMigratePhase &&
              !readyHasMigrationProgress
        ? List<_MigrationBatchStatus>.filled(
            values.length,
            _MigrationBatchStatus.scheduled,
          )
        : parts.isNotEmpty
        ? [for (final part in parts) _migrationBatchStatus(part.state)]
        : _legacyMigrationBatchStatuses(status, values.length);
    final signingPartIndices =
        status.currentSigningPartIndices?.toSet() ?? const <int>{};
    final signingSegmentIndices = <int>[];
    if (widget.action == _StatusAction.needsInput) {
      for (var index = 0; index < statuses.length; index++) {
        final partIndex = parts.isNotEmpty && index < parts.length
            ? parts[index].partIndex
            : index;
        if (signingPartIndices.contains(partIndex)) {
          statuses[index] = _MigrationBatchStatus.needsInput;
          signingSegmentIndices.add(index);
        }
      }
      if (signingSegmentIndices.isEmpty) {
        final inputIndex = statuses.indexWhere(
          (status) => status != _MigrationBatchStatus.complete,
        );
        if (inputIndex >= 0) {
          statuses[inputIndex] = _MigrationBatchStatus.needsInput;
          signingSegmentIndices.add(inputIndex);
        }
      }
    }
    final total = values.fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
    final displayCurrentHeight = _displayCurrentHeight(widget.currentHeight);
    final isPreparing = _shouldShowPreparingStatusContent(status, statuses);
    final content = status.phase == kIronwoodMigrationCompletePhase
        ? _MigrationCompleteStatusContent(
            key: const ValueKey('ironwood_migration_status_complete'),
            totalZatoshi: total,
            onDone: widget.onAction,
          )
        : _MigrationLiveStatusContent(
            key: const ValueKey('ironwood_migration_active_status'),
            isPreparing: isPreparing,
            preparationProgressLabel: migrationPreparationProgressLabel(status),
            values: values,
            totalZatoshi: total,
            statuses: statuses,
            signingSegmentIndices: signingSegmentIndices,
            action: widget.action,
            isAdvancing: widget.isAdvancing,
            onAction: widget.onAction,
            waitingForAnchor:
                status.phase == kIronwoodMigrationReadyToMigratePhase &&
                status.proofReady == false,
            estimatedTime: _transferEstimatedCompletion(
              status,
              currentHeight: displayCurrentHeight,
              needsInput: widget.action == _StatusAction.needsInput,
              parts: parts,
            ),
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 680),
      reverseDuration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.965,
            end: 1,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: content,
    );
  }
}

class _MigrationCompleteStatusContent extends StatelessWidget {
  const _MigrationCompleteStatusContent({
    super.key,
    required this.totalZatoshi,
    required this.onDone,
  });

  final BigInt totalZatoshi;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 70,
            top: 54,
            width: 280,
            height: 210,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _MigrationCompleteRibbonPainter()),
                Image.asset(
                  'assets/illustrations/ironwood_migration_done_coins.png',
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
          Positioned(
            left: 40,
            top: 270,
            width: 340,
            child: Column(
              children: [
                Text(
                  'Your\n${_formatZecAmountCompact(totalZatoshi)} ZEC\n'
                  'are on Ironwood!',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Migration completed successfully and you can\n'
                  'spend your funds as usual.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 162,
            top: 510,
            width: 96,
            child: AppButton(
              key: const ValueKey('ironwood_migration_status_action_button'),
              onPressed: onDone,
              variant: AppButtonVariant.secondary,
              height: 36,
              minWidth: 96,
              expand: true,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationCompleteRibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF009C5D)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.38)
      ..lineTo(size.width * 0.43, size.height * 0.20)
      ..lineTo(size.width * 0.72, size.height * 0.31)
      ..lineTo(size.width * 0.72, size.height * 0.52)
      ..lineTo(size.width * 0.88, size.height * 0.60)
      ..lineTo(size.width * 0.62, size.height * 0.80)
      ..lineTo(size.width * 0.34, size.height * 0.69)
      ..lineTo(size.width * 0.34, size.height * 0.52)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MigrationCompleteRibbonPainter oldDelegate) =>
      false;
}

class _MigrationLiveStatusContent extends StatelessWidget {
  const _MigrationLiveStatusContent({
    super.key,
    required this.isPreparing,
    required this.preparationProgressLabel,
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.signingSegmentIndices,
    required this.action,
    required this.isAdvancing,
    required this.onAction,
    required this.estimatedTime,
    required this.waitingForAnchor,
  });

  final bool isPreparing;
  final String preparationProgressLabel;
  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<int> signingSegmentIndices;
  final _StatusAction action;
  final bool isAdvancing;
  final VoidCallback? onAction;
  final String estimatedTime;
  final bool waitingForAnchor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSigning = action == _StatusAction.needsInput;
    final isComplete = action == _StatusAction.backHome;
    final completedAmount = _migrationCompletedAmount(values, statuses);
    final noteCount = values.length;
    final signIndex = signingSegmentIndices.isNotEmpty
        ? signingSegmentIndices.first
        : statuses.indexOf(_MigrationBatchStatus.needsInput);
    final batchIndex = signIndex < 0 ? 0 : signIndex;
    final batchValue = signingSegmentIndices.fold<BigInt>(
      BigInt.zero,
      (sum, index) => index < values.length ? sum + values[index] : sum,
    );
    final batchNumber = (batchIndex ~/ 8) + 1;
    final completedNotes = statuses
        .where((status) => status == _MigrationBatchStatus.complete)
        .length;
    final percentage = _migrationPercentage(batchValue, totalZatoshi);

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 420,
            bottom: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 360),
              opacity: !isSigning && !isPreparing ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                  // Figma's wide radial gradient is effectively vertical at
                  // this 420 px width. Keep its exact stop colors/opacity so
                  // the bottom panel, including its two rounded corners,
                  // reads as one surface instead of a separate glow.
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.69843, 0.84922, 0.92461, 1],
                    colors: [
                      Color(0x05141818),
                      Color(0x350A5E3C),
                      Color(0x4E05814E),
                      Color(0x6600A460),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Stack(
            children: [
              Positioned(
                left: 12,
                top: 16,
                width: 396,
                child: Text(
                  'Ironwood Migration',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 54,
                width: 396,
                child: _MigrationStageHeader(
                  stage: isPreparing
                      ? _MigrationStage.preparation
                      : isComplete
                      ? _MigrationStage.finish
                      : _MigrationStage.migration,
                ),
              ),
              Positioned(
                left: 82,
                top: 108,
                width: 256,
                height: 256,
                child: _MigrationMorphingRing(
                  key: const ValueKey('ironwood_migration_morphing_ring'),
                  preparing: isPreparing,
                  preparationColor: colors.text.accent.withValues(alpha: 0.20),
                  values: values,
                  totalZatoshi: totalZatoshi,
                  statuses: statuses,
                  child: _MigrationRingCenterTransition(
                    key: const ValueKey('ironwood_migration_ring_center'),
                    preparing: isPreparing,
                    child: isPreparing
                        ? Column(
                            key: const ValueKey('preparing-ring-label'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: 0.72,
                                  strokeWidth: 2,
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Preparing your notes',
                                textAlign: TextAlign.center,
                                style: AppTypography.bodySmall,
                              ),
                            ],
                          )
                        : Column(
                            key: const ValueKey('migration-ring-label'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                completedAmount > BigInt.zero
                                    ? 'Migrated'
                                    : 'Amount to migrate',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                completedAmount > BigInt.zero
                                    ? '${_formatZecAmountCompact(completedAmount)}/'
                                          '${_formatZecAmountCompact(totalZatoshi)} ZEC'
                                    : '${_formatZecAmountCompact(totalZatoshi)} ZEC',
                                style: AppTypography.headlineSmall.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (completedAmount > BigInt.zero)
                                Text(
                                  '$completedNotes/$noteCount notes',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: colors.text.accent,
                                  ),
                                ),
                              if (!isComplete) ...[
                                const SizedBox(height: 6),
                                AppButton(
                                  onPressed: () =>
                                      context.go('/migration/private/schedule'),
                                  variant: AppButtonVariant.ghost,
                                  height: 28,
                                  minWidth: 124,
                                  expand: false,
                                  constrainContent: true,
                                  trailing: const AppIcon(
                                    AppIcons.chevronForward,
                                    size: 14,
                                  ),
                                  child: const Text('View Schedule'),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
              Positioned(
                left: 28,
                top: isPreparing ? 382 : 390,
                width: 364,
                child: isPreparing
                    ? _MigrationLiveMetric(
                        icon: AppIcons.wrench,
                        label: 'Status',
                        value: preparationProgressLabel,
                      )
                    : Column(
                        children: [
                          _MigrationLiveMetric(
                            icon: AppIcons.shieldKeyhole,
                            label: 'Available in Ironwood',
                            value:
                                '${_formatZecAmountCompact(completedAmount)} ZEC',
                            accent: true,
                          ),
                          const SizedBox(height: 16),
                          _MigrationLiveMetric(
                            icon: AppIcons.wrench,
                            label: 'Status',
                            value: isComplete
                                ? 'Migration complete'
                                : isSigning
                                ? 'Waiting for your approval'
                                : waitingForAnchor
                                ? 'Waiting for anchor block'
                                : 'Migration in progress',
                          ),
                        ],
                      ),
              ),
              if (isPreparing)
                const Positioned(
                  left: 12,
                  top: 426,
                  width: 396,
                  height: 127,
                  child: _MigrationPreparationInfoCard(),
                )
              else if (isSigning)
                Positioned(
                  left: 12,
                  top: 511,
                  width: 396,
                  child: Column(
                    children: [
                      _MigrationSigningBatchCard(
                        batchNumber: batchNumber,
                        value: batchValue,
                        percentage: percentage,
                        noteCount: signingSegmentIndices.length,
                      ),
                      const SizedBox(height: 14),
                      AppButton(
                        key: const ValueKey(
                          'ironwood_migration_status_action_button',
                        ),
                        onPressed: isAdvancing ? null : onAction,
                        height: 44,
                        minWidth: 230,
                        expand: false,
                        child: Text(
                          isAdvancing
                              ? 'Preparing batch...'
                              : 'Sign Batch #$batchNumber',
                        ),
                      ),
                    ],
                  ),
                )
              else if (action == _StatusAction.backHome)
                Positioned(
                  left: 95,
                  top: 596,
                  width: 230,
                  child: Center(
                    child: AppButton(
                      key: const ValueKey(
                        'ironwood_migration_status_action_button',
                      ),
                      onPressed: onAction,
                      variant: AppButtonVariant.secondary,
                      height: 36,
                      minWidth: 96,
                      expand: false,
                      child: const Text('Go home'),
                    ),
                  ),
                )
              else
                Positioned(
                  left: 12,
                  top: 502,
                  width: 396,
                  height: 150,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(
                        AppIcons.bell,
                        size: 20,
                        color: const Color(0xFF00D084),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        estimatedTime,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The next signing window will open around this time.\n'
                        'Keep Vizor open to continue your migration.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MigrationLiveMetric extends StatelessWidget {
  const _MigrationLiveMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = accent ? colors.text.accent : colors.text.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        SizedBox(
          width: 132,
          child: Text(
            label,
            maxLines: 2,
            style: AppTypography.labelLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            softWrap: true,
            textAlign: TextAlign.right,
            style: AppTypography.labelLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _MigrationSigningBatchCard extends StatelessWidget {
  const _MigrationSigningBatchCard({
    required this.batchNumber,
    required this.value,
    required this.percentage,
    required this.noteCount,
  });

  final int batchNumber;
  final BigInt value;
  final String percentage;
  final int noteCount;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.background.ground,
      borderRadius: BorderRadius.circular(AppRadii.large),
      border: Border.all(color: context.colors.border.subtle),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(
        children: [
          const AppIcon(AppIcons.checkCircle, size: 16),
          const SizedBox(width: 8),
          Text(
            'Batch #$batchNumber ($noteCount notes)',
            style: AppTypography.labelLarge,
          ),
          const Spacer(),
          Text.rich(
            TextSpan(
              text: '${_formatZecAmountCompact(value)} ZEC ',
              style: AppTypography.labelLarge,
              children: [
                TextSpan(
                  text: '($percentage)',
                  style: AppTypography.labelLarge.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

BigInt _migrationCompletedAmount(
  List<BigInt> values,
  List<_MigrationBatchStatus> statuses,
) => values.indexed.fold<BigInt>(BigInt.zero, (sum, entry) {
  final (index, value) = entry;
  return index < statuses.length &&
          statuses[index] == _MigrationBatchStatus.complete
      ? sum + value
      : sum;
});

bool _shouldShowPreparingStatusContent(
  rust_sync.MigrationStatus status,
  List<_MigrationBatchStatus> statuses,
) {
  // Note-split preparation is represented by one intentionally indeterminate
  // visual, even while individual split transactions are confirming.
  return status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase;
}

class _MigrationPreparationInfoCard extends StatelessWidget {
  const _MigrationPreparationInfoCard();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.background.ground,
      borderRadius: BorderRadius.circular(AppRadii.large),
      boxShadow: appSurfaceShadow(context.colors),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _MigrationPreparationInfoRow(
              icon: AppIcons.wallet,
              message:
                  'We’re organizing your balance into common-sized parts. '
                  'This makes your migration harder to link.',
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: _MigrationPreparationInfoRow(
              icon: AppIcons.history,
              message:
                  'Once preparation finishes, your migration can begin '
                  'automatically.',
            ),
          ),
        ],
      ),
    ),
  );
}

class _MigrationPreparationInfoRow extends StatelessWidget {
  const _MigrationPreparationInfoRow({
    required this.icon,
    required this.message,
  });

  final String icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(icon, size: 20, color: context.colors.icon.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            maxLines: 3,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _MigrationRingCenterTransition extends StatefulWidget {
  const _MigrationRingCenterTransition({
    super.key,
    required this.preparing,
    required this.child,
  });

  final bool preparing;
  final Widget child;

  @override
  State<_MigrationRingCenterTransition> createState() =>
      _MigrationRingCenterTransitionState();
}

class _MigrationRingCenterTransitionState
    extends State<_MigrationRingCenterTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Widget? _preparingChild;
  Widget? _liveChild;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
      value: widget.preparing ? 0 : 1,
    );
    if (widget.preparing) {
      _preparingChild = widget.child;
    } else {
      _liveChild = widget.child;
    }
  }

  @override
  void didUpdateWidget(covariant _MigrationRingCenterTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preparing) {
      _preparingChild = widget.child;
    } else {
      _liveChild = widget.child;
    }
    if (oldWidget.preparing == widget.preparing) return;
    if (widget.preparing) {
      _controller.reverse(from: 1);
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preparing && _liveChild == null) return widget.child;
    if (!widget.preparing && _preparingChild == null) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = Curves.easeInOutCubic.transform(_controller.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            if (_preparingChild != null)
              Opacity(
                opacity: (1 - progress * 2).clamp(0, 1),
                child: _preparingChild,
              ),
            if (_liveChild != null)
              Opacity(
                opacity: ((progress - 0.5) * 2).clamp(0, 1),
                child: _liveChild,
              ),
          ],
        );
      },
    );
  }
}

class _MigrationMorphingRing extends StatefulWidget {
  const _MigrationMorphingRing({
    super.key,
    required this.preparing,
    required this.preparationColor,
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.child,
  });

  final bool preparing;
  final Color preparationColor;
  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final Widget child;

  @override
  State<_MigrationMorphingRing> createState() => _MigrationMorphingRingState();
}

class _MigrationMorphingRingState extends State<_MigrationMorphingRing>
    with TickerProviderStateMixin {
  static const _minimumWeight = 0.035;
  static const _maximumWeight = 0.22;
  static const _stepDuration = Duration(milliseconds: 390);
  static const _stepBreather = Duration(milliseconds: 105);
  static const _spinDuration = Duration(milliseconds: 1800);
  static const _restBetweenBlocks = Duration(milliseconds: 900);

  final math.Random _random = math.Random(704075305);
  late final AnimationController _stepController = AnimationController(
    vsync: this,
    duration: _stepDuration,
  );
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: _spinDuration,
  );
  late final AnimationController _morphController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
  );
  late List<double> _weights;
  late List<double> _fromWeights;
  late List<double> _toWeights;
  Timer? _idleTimer;
  bool _reduceMotion = false;
  List<_MigrationRingVisualSegment> _morphFrom = const [];
  List<_MigrationRingVisualSegment> _morphTo = const [];
  List<_MigrationRingVisualSegment> _lastPreparationSegments = const [];

  @override
  void initState() {
    super.initState();
    _weights = List.of(_MigrationPreparationRingPainter.initialSegmentRatios);
    _fromWeights = List.of(_weights);
    _toWeights = List.of(_weights);
    _lastPreparationSegments = _preparationSegments(_weights);
    if (widget.preparing) {
      _morphFrom = _lastPreparationSegments;
      _morphTo = _lastPreparationSegments;
      _runIdleLoop();
    } else {
      _morphFrom = _liveSegments(
        values: widget.values,
        totalZatoshi: widget.totalZatoshi,
        statuses: widget.statuses,
      );
      _morphTo = _morphFrom;
      _morphController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _MigrationMorphingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preparing) return;

    final next = _liveSegments(
      values: widget.values,
      totalZatoshi: widget.totalZatoshi,
      statuses: widget.statuses,
    );
    if (_sameVisualSegments(_morphTo, next)) return;

    final current = oldWidget.preparing
        ? _lastPreparationSegments
        : _interpolateVisualSegments(
            _morphFrom,
            _morphTo,
            Curves.easeInOutCubic.transform(_morphController.value),
          );
    _morphFrom = current;
    _morphTo = next;
    _idleTimer?.cancel();
    _stepController.stop();
    _spinController.stop();
    if (_reduceMotion) {
      _morphController.value = 1;
    } else {
      _morphController.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  Future<void> _runIdleLoop() async {
    // Keep the Figma-comparison first frame stable before starting idle motion.
    await _wait(const Duration(milliseconds: 400));
    try {
      while (mounted) {
        if (!widget.preparing) return;
        if (_reduceMotion) {
          await _wait(const Duration(seconds: 1));
          continue;
        }
        for (var cycle = 0; cycle < 3 && mounted; cycle++) {
          await _adjustSegmentWeights();
          if (!mounted) return;
          await _spinController.forward(from: 0);
        }
        await _wait(_restBetweenBlocks);
      }
    } on TickerCanceled {
      // Disposal can stop either controller while an idle cycle is running.
    }
  }

  Future<void> _adjustSegmentWeights() async {
    final steps = 3 + _random.nextInt(3);
    for (var step = 0; step < steps; step++) {
      if (!mounted) return;
      final fromIndex = _random.nextInt(_weights.length);
      var toIndex = _random.nextInt(_weights.length - 1);
      if (toIndex >= fromIndex) toIndex++;

      final availableToGive = math.min(
        _weights[fromIndex] - _minimumWeight,
        _maximumWeight - _weights[toIndex],
      );
      final availableToTake = math.min(
        _maximumWeight - _weights[fromIndex],
        _weights[toIndex] - _minimumWeight,
      );
      final gives = availableToGive >= availableToTake;
      final available = gives ? availableToGive : availableToTake;
      if (available <= 0.005) continue;
      final amount = available * (0.4 + _random.nextDouble() * 0.6);

      setState(() {
        _fromWeights = List.of(_weights);
        _toWeights = List.of(_weights);
        _toWeights[fromIndex] += gives ? -amount : amount;
        _toWeights[toIndex] += gives ? amount : -amount;
      });
      await _stepController.forward(from: 0);
      _weights = List.of(_toWeights);
      await _wait(_stepBreather);
    }
  }

  Future<void> _wait(Duration duration) {
    final completer = Completer<void>();
    _idleTimer?.cancel();
    _idleTimer = Timer(duration, completer.complete);
    return completer.future;
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _stepController.dispose();
    _spinController.dispose();
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = widget.preparing
        ? 'Preparing migration notes.'
        : [
            'Migration notes in expected processing order.',
            for (var index = 0; index < widget.values.length; index++)
              'Note ${index + 1}: '
                  '${_formatZecAmountCompact(widget.values[index])} ZEC, '
                  '${_migrationRingStatusSemantics(index < widget.statuses.length ? widget.statuses[index] : _MigrationBatchStatus.scheduled)}.',
          ].join(' ');
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semanticsLabel,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _stepController,
          _spinController,
          _morphController,
        ]),
        builder: (context, _) {
          final eased = Curves.easeOutBack.transform(_stepController.value);
          final weights = List.generate(
            _weights.length,
            (index) =>
                _fromWeights[index] +
                ((_toWeights[index] - _fromWeights[index]) * eased),
          );
          final preparationSegments = _preparationSegments(weights);
          _lastPreparationSegments = preparationSegments;
          final visualSegments = widget.preparing
              ? preparationSegments
              : _interpolateVisualSegments(
                  _morphFrom,
                  _morphTo,
                  Curves.easeInOutCubic.transform(_morphController.value),
                );
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.preparing)
                const SizedBox.shrink(
                  key: ValueKey('ironwood_migration_preparation_ring'),
                ),
              CustomPaint(
                size: const Size.square(256),
                painter: _MigrationRingVisualPainter(
                  segments: visualSegments,
                  rotation: widget.preparing
                      ? Curves.easeInOutCubic.transform(_spinController.value)
                      : 0,
                ),
              ),
              widget.child,
            ],
          );
        },
      ),
    );
  }

  List<_MigrationRingVisualSegment> _preparationSegments(
    List<double> weights,
  ) => [
    for (final weight in weights)
      _MigrationRingVisualSegment(
        weight: weight,
        color: widget.preparationColor,
      ),
  ];
}

class _MigrationRingVisualSegment {
  const _MigrationRingVisualSegment({
    required this.weight,
    required this.color,
  });

  final double weight;
  final Color color;
}

List<_MigrationRingVisualSegment> _liveSegments({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required List<_MigrationBatchStatus> statuses,
}) {
  if (values.isEmpty || totalZatoshi <= BigInt.zero) return const [];
  return [
    for (var index = 0; index < values.length; index++)
      _MigrationRingVisualSegment(
        weight: (values[index] / totalZatoshi).toDouble(),
        color: _migrationRingStatusColor(
          index < statuses.length
              ? statuses[index]
              : _MigrationBatchStatus.scheduled,
        ),
      ),
  ];
}

Color _migrationRingStatusColor(_MigrationBatchStatus status) =>
    switch (status) {
      _MigrationBatchStatus.none => const Color(0xFF3F4040),
      _MigrationBatchStatus.preparing => const Color(0xFF00D084),
      _MigrationBatchStatus.scheduled => const Color(0xFF0B4631),
      _MigrationBatchStatus.migrating => const Color(0xFF00D084),
      _MigrationBatchStatus.confirming => const Color(0xFF0EA76C),
      _MigrationBatchStatus.complete => const Color(0xFF00C875),
      _MigrationBatchStatus.needsInput => const Color(0xFFF7F7F7),
    };

String _migrationRingStatusSemantics(_MigrationBatchStatus status) =>
    switch (status) {
      _MigrationBatchStatus.none => 'not started',
      _MigrationBatchStatus.preparing => 'preparing',
      _MigrationBatchStatus.scheduled => 'scheduled',
      _MigrationBatchStatus.migrating => 'migrating',
      _MigrationBatchStatus.confirming => 'confirming',
      _MigrationBatchStatus.complete => 'completed',
      _MigrationBatchStatus.needsInput => 'needs input',
    };

List<_MigrationRingVisualSegment> _interpolateVisualSegments(
  List<_MigrationRingVisualSegment> from,
  List<_MigrationRingVisualSegment> to,
  double t,
) {
  final count = math.max(from.length, to.length);
  if (count == 0) return const [];
  const transparent = _MigrationRingVisualSegment(
    weight: 0,
    color: Color(0x003F4040),
  );
  return [
    for (var index = 0; index < count; index++)
      _MigrationRingVisualSegment(
        weight:
            (index < from.length ? from[index].weight : transparent.weight) +
            ((index < to.length ? to[index].weight : transparent.weight) -
                    (index < from.length
                        ? from[index].weight
                        : transparent.weight)) *
                t,
        color: Color.lerp(
          index < from.length ? from[index].color : transparent.color,
          index < to.length ? to[index].color : transparent.color,
          t,
        )!,
      ),
  ];
}

bool _sameVisualSegments(
  List<_MigrationRingVisualSegment> left,
  List<_MigrationRingVisualSegment> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].weight != right[index].weight ||
        left[index].color != right[index].color) {
      return false;
    }
  }
  return true;
}

class _MigrationRingVisualPainter extends CustomPainter {
  const _MigrationRingVisualPainter({
    required this.segments,
    required this.rotation,
  });

  final List<_MigrationRingVisualSegment> segments;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
    const strokeWidth = 12.0;
    final positiveWeight = segments.fold<double>(
      0,
      (sum, segment) => sum + math.max(0, segment.weight),
    );
    if (positiveWeight <= 0) return;

    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 208,
      height: 208,
    );
    // A disappearing morph segment must also surrender its gap gradually.
    // Otherwise the final live ring keeps the preparation ring's gap count,
    // and the remaining notes visibly jump when zero-sized segments vanish.
    final presences = [
      for (final segment in segments)
        (math.max(0, segment.weight) / 0.02).clamp(0.0, 1.0) * segment.color.a,
    ];
    final effectiveCount = presences.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    if (effectiveCount <= 0) return;
    final gap = math.min(0.17, math.pi * 2 / effectiveCount * 0.32).toDouble();
    final drawableSweep = math.pi * 2 - effectiveCount * gap;
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final roundedCapAngularWidth = strokeWidth / (rect.width / 2);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotation * math.pi * 2);
    canvas.translate(-size.width / 2, -size.height / 2);
    var angle = -math.pi / 2;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final presence = presences[index];
      final sweep =
          math.max(0, segment.weight) / positiveWeight * drawableSweep;
      paint.color = segment.color;
      if (sweep > 0.001 && paint.color.a > 0) {
        // Very small/many notes use flat caps. Rounded caps are wider than
        // their arc in that case and would overlap adjacent note segments.
        paint.strokeCap = sweep > roundedCapAngularWidth
            ? StrokeCap.round
            : StrokeCap.butt;
        canvas.drawArc(rect, angle + gap * presence / 2, sweep, false, paint);
      }
      angle += sweep + gap * presence;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MigrationRingVisualPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      !_sameVisualSegments(oldDelegate.segments, segments);
}

class _MigrationPreparationRingPainter extends CustomPainter {
  const _MigrationPreparationRingPainter({
    required this.color,
    required this.weights,
    required this.rotation,
  });

  final Color color;
  final List<double> weights;
  final double rotation;

  static const _ringOuterDiameter = 220.0;

  // Decorative only: the ratios intentionally do not represent note value or
  // confirmation progress, but they still form one complete ring.
  static const initialSegmentRatios = <double>[
    0.11,
    0.08,
    0.12,
    0.07,
    0.10,
    0.11,
    0.09,
    0.10,
    0.08,
    0.14,
  ];
  static const _visibleGap = 0.055;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: _ringOuterDiameter - paint.strokeWidth,
      height: _ringOuterDiameter - paint.strokeWidth,
    );
    final fullSweep = math.pi * 2;
    final radius = rect.width / 2;
    // Include round-cap length in the angular gap so adjacent pills never
    // overlap, while keeping an approximately 6 px empty space between them.
    final gap = (paint.strokeWidth / radius) + _visibleGap;
    final drawableSweep = fullSweep - (weights.length * gap);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotation * fullSweep);
    canvas.translate(-size.width / 2, -size.height / 2);

    var angle = -math.pi / 2;
    for (final weight in weights) {
      final sweep = math.max(0.01, weight * drawableSweep);
      canvas.drawArc(rect, angle + (gap / 2), sweep, false, paint);
      angle += sweep + gap;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MigrationPreparationRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.rotation != rotation ||
      !_sameWeights(oldDelegate.weights, weights);

  bool _sameWeights(List<double> otherWeights, List<double> currentWeights) {
    if (otherWeights.length != currentWeights.length) return false;
    for (var index = 0; index < otherWeights.length; index++) {
      if (otherWeights[index] != currentWeights[index]) return false;
    }
    return true;
  }
}

_MigrationBatchStatus _migrationBatchStatus(
  rust_sync.MigrationPartState state,
) => switch (state) {
  rust_sync.MigrationPartState.preparing => _MigrationBatchStatus.preparing,
  rust_sync.MigrationPartState.scheduled => _MigrationBatchStatus.scheduled,
  rust_sync.MigrationPartState.migrating => _MigrationBatchStatus.migrating,
  rust_sync.MigrationPartState.confirming => _MigrationBatchStatus.confirming,
  rust_sync.MigrationPartState.completed => _MigrationBatchStatus.complete,
  rust_sync.MigrationPartState.needsInput => _MigrationBatchStatus.needsInput,
};

List<_MigrationBatchStatus> _legacyMigrationBatchStatuses(
  rust_sync.MigrationStatus status,
  int count,
) {
  if (status.phase == kIronwoodMigrationCompletePhase) {
    return List<_MigrationBatchStatus>.filled(
      count,
      _MigrationBatchStatus.complete,
    );
  }

  final hasBroadcastSchedule =
      status.scheduledBroadcasts.isNotEmpty ||
      status.phase == kIronwoodMigrationBroadcastScheduledPhase ||
      status.phase == kIronwoodMigrationBroadcastingPhase ||
      status.phase == kIronwoodMigrationWaitingConfirmationsPhase;
  final submittedCount = status.confirmedTxCount + status.broadcastedTxCount;
  return [
    for (var i = 0; i < count; i++)
      if (i < status.confirmedTxCount)
        _MigrationBatchStatus.confirming
      else if (i < submittedCount)
        _MigrationBatchStatus.migrating
      else if (hasBroadcastSchedule)
        _MigrationBatchStatus.scheduled
      else
        _MigrationBatchStatus.preparing,
  ];
}

int _currentMigrationHeight(SyncState? syncState) {
  if (syncState == null) return 0;
  final scannedHeight = syncState.scannedHeight;
  final chainTipHeight = syncState.chainTipHeight;
  if (scannedHeight > 0 && chainTipHeight > 0) {
    return math.min(scannedHeight, chainTipHeight);
  }
  return math.max(scannedHeight, chainTipHeight);
}

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
