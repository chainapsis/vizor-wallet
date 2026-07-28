part of '../ironwood_migration_flow_screen.dart';

const _migrationCarouselPurple = Color(0xFF9667E2);
const _migrationCarouselGreen = Color(0xFF00A460);
const _migrationCarouselCrimson = Color(0xFFB90A4A);

const _migrationPreparationCarouselItems = [
  AppCarouselItem.icon(
    message:
        'Once preparation finishes, your migration will begin automatically '
        'after a long intentional delay.',
    tileColor: _migrationCarouselPurple,
    icon: AppIcons.history,
    iconSize: 18,
  ),
  AppCarouselItem.icon(
    message:
        'We’re organizing your balance into common-sized parts. This makes '
        'your migration harder to link.',
    tileColor: _migrationCarouselGreen,
    icon: AppIcons.wallet,
  ),
  AppCarouselItem.image(
    message:
        'We may have to do multiple rounds of note splitting depending on '
        'your balance.',
    tileColor: _migrationCarouselCrimson,
    imageAsset: _ironwoodMigrationExpectationRunningAsset,
  ),
];

final _migrationInProgressCarouselItems = [
  const AppCarouselItem.icon(
    message:
        'You can close Vizor anytime. Migration will pause, and you can '
        'restart it when you return.',
    tileColor: _migrationCarouselPurple,
    icon: AppIcons.pause,
  ),
  AppCarouselItem.icon(
    message:
        'Each Zcash block takes about $_migrationEstimatedSecondsPerBlock '
        'seconds to create, but timing can vary with network conditions.',
    tileColor: _migrationCarouselGreen,
    icon: AppIcons.migrationTimer,
    iconSize: 24,
  ),
  const AppCarouselItem.image(
    message:
        'Keep Vizor running and the migration will automatically run in the '
        'background.',
    tileColor: _migrationCarouselCrimson,
    imageAsset: _ironwoodMigrationExpectationRunningAsset,
  ),
];

int _compareMigrationPartsByExpectedProcessingOrder(
  rust_sync.MigrationPartStatus left,
  rust_sync.MigrationPartStatus right,
) {
  // The approved schedule order is immutable, but an overdue transaction can
  // be assigned a new height while migration is running. The ring and schedule
  // must follow that current expected chronology rather than leaving completed
  // colors scattered according to the stale original order.
  final leftHeight = left.scheduledHeight;
  final rightHeight = right.scheduledHeight;
  if (leftHeight != null || rightHeight != null) {
    final comparison = (leftHeight ?? 1 << 30).compareTo(
      rightHeight ?? 1 << 30,
    );
    if (comparison != 0) return comparison;
  }

  final leftOrder = left.scheduleOrder;
  final rightOrder = right.scheduleOrder;
  if (leftOrder != null || rightOrder != null) {
    final comparison = (leftOrder ?? 1 << 30).compareTo(rightOrder ?? 1 << 30);
    if (comparison != 0) return comparison;
  }
  return left.partIndex.compareTo(right.partIndex);
}

class _MigrationStatusContent extends StatelessWidget {
  const _MigrationStatusContent({
    required this.status,
    required this.currentHeight,
    required this.action,
    required this.isAdvancing,
    required this.onAction,
  });

  final rust_sync.MigrationStatus status;
  final int currentHeight;
  final _StatusAction action;
  final bool isAdvancing;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
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
    if (action == _StatusAction.needsInput) {
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
    final isPreparing = _shouldShowPreparingStatusContent(status, statuses);
    final content = status.phase == kIronwoodMigrationCompletePhase
        ? _MigrationCompleteStatusContent(
            key: const ValueKey('ironwood_migration_status_complete'),
            totalZatoshi: total,
            onDone: onAction,
          )
        : _MigrationLiveStatusContent(
            key: const ValueKey('ironwood_migration_active_status'),
            isPreparing: isPreparing,
            status: status,
            parts: parts,
            currentHeight: currentHeight,
            values: values,
            totalZatoshi: total,
            statuses: statuses,
            signingSegmentIndices: signingSegmentIndices,
            action: action,
            isAdvancing: isAdvancing,
            onAction: onAction,
            waitingForAnchor:
                status.phase == kIronwoodMigrationReadyToMigratePhase &&
                status.proofReady == false,
          );
    return SizedBox(
      width: 560,
      height: 656,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 680),
        reverseDuration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.965, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        ),
        child: content,
      ),
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
    required this.status,
    required this.parts,
    required this.currentHeight,
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.signingSegmentIndices,
    required this.action,
    required this.isAdvancing,
    required this.onAction,
    required this.waitingForAnchor,
  });

  final bool isPreparing;
  final rust_sync.MigrationStatus status;
  final List<rust_sync.MigrationPartStatus> parts;
  final int currentHeight;
  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<int> signingSegmentIndices;
  final _StatusAction action;
  final bool isAdvancing;
  final VoidCallback? onAction;
  final bool waitingForAnchor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSigning = action == _StatusAction.needsInput;
    final isComplete = action == _StatusAction.backHome;
    final completedAmount = _migrationCompletedAmount(values, statuses);
    final leftToMigrate = totalZatoshi - completedAmount;
    final ringPresentation = _migrationRingPresentation(
      status: status,
      parts: parts,
      values: values,
      statuses: statuses,
      totalZatoshi: totalZatoshi,
      waitingForAnchor: waitingForAnchor,
      currentHeight: currentHeight,
    );
    final preparationPresentation = _preparationRingPresentation(status);
    final signIndex = signingSegmentIndices.isNotEmpty
        ? signingSegmentIndices.first
        : statuses.indexOf(_MigrationBatchStatus.needsInput);
    final batchIndex = signIndex < 0 ? 0 : signIndex;
    final batchValue = signingSegmentIndices.fold<BigInt>(
      BigInt.zero,
      (sum, index) => index < values.length ? sum + values[index] : sum,
    );
    final batchNumber = (batchIndex ~/ 8) + 1;
    final percentage = _migrationPercentage(batchValue, totalZatoshi);

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
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
                  palette: _migrationRingPalette(colors),
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
                              Text(
                                preparationPresentation.label,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 208,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    preparationPresentation.splitLabel,
                                    maxLines: 1,
                                    softWrap: false,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.labelLarge.copyWith(
                                      color: colors.text.primary,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '~${_formatZecAmountCompact(preparationPresentation.amount)} ZEC',
                                textAlign: TextAlign.center,
                                style: AppTypography.headlineSmall.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _PreparationRingDetail(
                                presentation: preparationPresentation,
                              ),
                              const SizedBox(height: 6),
                              AppButton(
                                key: const ValueKey(
                                  'ironwood_migration_view_preparation_schedule_button',
                                ),
                                onPressed: () => context.go(
                                  '/migration/private/preparation-schedule',
                                ),
                                variant: AppButtonVariant.ghost,
                                height: 28,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xxs,
                                ),
                                expand: false,
                                trailing: const AppIcon(
                                  AppIcons.chevronForward,
                                  size: 14,
                                ),
                                child: const Text(
                                  'View Schedule',
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            key: const ValueKey('migration-ring-label'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ringPresentation.label,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_formatZecAmountCompact(ringPresentation.amount)} ZEC',
                                style: AppTypography.headlineSmall.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _MigrationRingDetail(
                                presentation: ringPresentation,
                              ),
                              if (!isComplete) ...[
                                const SizedBox(height: 8),
                                AppButton(
                                  key: const ValueKey(
                                    'ironwood_migration_view_schedule_button',
                                  ),
                                  onPressed: () =>
                                      context.go('/migration/private/schedule'),
                                  variant: AppButtonVariant.ghost,
                                  height: 28,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xxs,
                                  ),
                                  expand: false,
                                  trailing: const AppIcon(
                                    AppIcons.chevronForward,
                                    size: 14,
                                  ),
                                  child: const Text(
                                    'View Schedule',
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
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
                    ? Column(
                        children: [
                          _MigrationSummaryMetric(
                            label: 'Overall progress',
                            value: _overallPreparationProgressDisplay(status),
                          ),
                          const SizedBox(height: 16),
                          _MigrationSummaryMetric(
                            label: 'Est. completion',
                            value: _preparationCompletionEstimateDisplay(
                              status,
                              currentHeight,
                            ),
                            secondary: true,
                          ),
                          const SizedBox(height: 16),
                          _MigrationSummaryMetric(
                            label: 'Current block',
                            value: formatGroupedInteger(currentHeight),
                            valueIcon: AppIcons.block,
                            secondary: true,
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _MigrationSummaryMetric(
                            label: 'Left to migrate',
                            value:
                                '${_formatZecAmountCompact(leftToMigrate > BigInt.zero ? leftToMigrate : BigInt.zero)} ZEC',
                          ),
                          const SizedBox(height: 16),
                          _MigrationSummaryMetric(
                            label: 'Est. completion',
                            value: _migrationCompletionEstimateDisplay(
                              status,
                              currentHeight: currentHeight,
                              needsInput: isSigning,
                              parts: parts,
                            ),
                            secondary: true,
                          ),
                        ],
                      ),
              ),
              if (!isPreparing && isSigning)
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
                ),
            ],
          ),
          if (action == _StatusAction.none)
            Positioned(
              left: -70,
              bottom: 16,
              width: 560,
              height: 116,
              child: AppCarousel(
                key: ValueKey(
                  'ironwood_migration_status_carousel_'
                  '${isPreparing ? 'preparation' : 'migration'}',
                ),
                items: isPreparing
                    ? _migrationPreparationCarouselItems
                    : _migrationInProgressCarouselItems,
                semanticLabel: isPreparing
                    ? 'Migration preparation information'
                    : 'Migration information',
              ),
            ),
        ],
      ),
    );
  }
}

class _MigrationRingPresentation {
  const _MigrationRingPresentation({
    required this.label,
    required this.amount,
    required this.detail,
    this.scheduledHeight,
  });

  final String label;
  final BigInt amount;
  final String detail;
  final int? scheduledHeight;
}

class _PreparationRingPresentation {
  const _PreparationRingPresentation({
    required this.label,
    required this.splitLabel,
    required this.amount,
    required this.detail,
    this.height,
    this.active = false,
  });

  final String label;
  final String splitLabel;
  final BigInt amount;
  final String detail;
  final int? height;
  final bool active;
}

_PreparationRingPresentation _preparationRingPresentation(
  rust_sync.MigrationStatus status,
) {
  final transactions = _orderedPreparationTransactions(status);
  final preparationTotal = _preparationTotalCount(status);
  final overallTotal = _overallTransactionTotalCount(status);
  final completed = _preparationCompletedCount(status);
  rust_sync.MigrationPreparationTransactionStatus? selected;
  for (final state in const [
    rust_sync.MigrationPreparationTransactionState.scheduled,
    rust_sync.MigrationPreparationTransactionState.broadcasted,
    rust_sync.MigrationPreparationTransactionState.confirming,
    rust_sync.MigrationPreparationTransactionState.awaitingInputs,
  ]) {
    final matches = transactions.where((item) => item.state == state).toList()
      ..sort((a, b) {
        final heightCompare = (a.scheduledHeight ?? 0x7fffffff).compareTo(
          b.scheduledHeight ?? 0x7fffffff,
        );
        return heightCompare != 0
            ? heightCompare
            : a.stageIndex.compareTo(b.stageIndex);
      });
    if (matches.isNotEmpty) {
      selected = matches.first;
      break;
    }
  }

  if (selected == null) {
    return _PreparationRingPresentation(
      label: completed >= preparationTotal && preparationTotal > 0
          ? 'Preparation complete'
          : 'Next split',
      splitLabel: preparationTotal > 0
          ? _overallTransactionOrdinalDisplay(
              math.min(completed + 1, preparationTotal),
              overallTotal,
            )
          : 'Preparing schedule',
      amount: _sumTargetValues(status),
      detail: completed >= preparationTotal && preparationTotal > 0
          ? 'All splits completed'
          : 'Schedule pending',
    );
  }

  final ordinal = transactions.indexOf(selected) + 1;
  final amount = selected.approximateValueZatoshi;
  return switch (selected.state) {
    rust_sync.MigrationPreparationTransactionState.scheduled =>
      _PreparationRingPresentation(
        label: 'Next split',
        splitLabel: _overallTransactionOrdinalDisplay(ordinal, overallTotal),
        amount: amount,
        detail: selected.scheduledHeight == null ? 'Due now' : 'Scheduled',
        height: selected.scheduledHeight,
      ),
    rust_sync.MigrationPreparationTransactionState.broadcasted =>
      _PreparationRingPresentation(
        label: 'Split in progress',
        splitLabel: _overallTransactionOrdinalDisplay(ordinal, overallTotal),
        amount: amount,
        detail: 'Waiting for block',
        height: selected.scheduledHeight,
        active: true,
      ),
    rust_sync.MigrationPreparationTransactionState.confirming =>
      _PreparationRingPresentation(
        label: 'Confirming split',
        splitLabel: _overallTransactionOrdinalDisplay(ordinal, overallTotal),
        amount: amount,
        detail:
            '${selected.confirmationCount} of ${selected.confirmationTarget} confirmations',
        height: selected.minedHeight,
        active: true,
      ),
    rust_sync.MigrationPreparationTransactionState.awaitingInputs =>
      _PreparationRingPresentation(
        label: 'Next split',
        splitLabel: _overallTransactionOrdinalDisplay(ordinal, overallTotal),
        amount: amount,
        detail: 'Waiting for previous split',
      ),
    rust_sync.MigrationPreparationTransactionState.completed =>
      _PreparationRingPresentation(
        label: 'Preparation complete',
        splitLabel: _overallTransactionOrdinalDisplay(ordinal, overallTotal),
        amount: amount,
        detail: 'All splits completed',
        height: selected.minedHeight,
      ),
  };
}

int _preparationTotalCount(rust_sync.MigrationStatus status) =>
    _preparationTransactions(status).isNotEmpty
    ? _preparationTransactions(status).length
    : status.denominationSplitTotalCount;

int _preparationCompletedCount(rust_sync.MigrationStatus status) =>
    _preparationTransactions(status).isNotEmpty
    ? _preparationTransactions(status)
          .where(
            (item) =>
                item.state ==
                rust_sync.MigrationPreparationTransactionState.completed,
          )
          .length
    : status.denominationSplitCompletedCount;

List<rust_sync.MigrationPreparationTransactionStatus> _preparationTransactions(
  rust_sync.MigrationStatus status,
) => status.preparationTransactions ?? const [];

List<rust_sync.MigrationPreparationTransactionStatus>
_orderedPreparationTransactions(rust_sync.MigrationStatus status) {
  final transactions = [..._preparationTransactions(status)];
  transactions.sort((a, b) {
    final roundCompare = a.round.compareTo(b.round);
    if (roundCompare != 0) return roundCompare;
    final heightCompare = a.projectedHeight.compareTo(b.projectedHeight);
    return heightCompare != 0
        ? heightCompare
        : a.stageIndex.compareTo(b.stageIndex);
  });
  return transactions;
}

int _preparationRemainingCount(rust_sync.MigrationStatus status) => math.max(
  0,
  _preparationTotalCount(status) - _preparationCompletedCount(status),
);

int? _overallTransactionTotalCount(rust_sync.MigrationStatus status) {
  final migrationTotal = status.totalCount;
  if (migrationTotal <= 0) return null;
  return _preparationTotalCount(status) + migrationTotal;
}

String _overallTransactionOrdinalDisplay(int ordinal, int? total) =>
    total == null ? 'Transaction $ordinal' : 'Transaction $ordinal of $total';

String _overallPreparationProgressDisplay(rust_sync.MigrationStatus status) {
  final total = _overallTransactionTotalCount(status);
  if (total == null) return 'Calculating total';
  // During preparation, completed parts are prepared Orchard notes rather
  // than completed Orchard-to-Ironwood transfers.
  final completed = math.min(total, _preparationCompletedCount(status));
  return '$completed of $total complete';
}

String _preparationCompletionEstimateDisplay(
  rust_sync.MigrationStatus status,
  int currentHeight,
) {
  final remaining = _preparationRemainingCount(status);
  if (remaining == 0) return 'Complete';
  final transactions = _preparationTransactions(status);
  final confirmationTarget = status.denominationConfirmationTarget;
  final meanDelay =
      status.preparationMeanDelayBlocks ?? status.scheduleMeanDelayBlocks;
  if (transactions.isEmpty) {
    final remainingBlocks = math.max(
      1,
      remaining * meanDelay + confirmationTarget,
    );
    return _formatMigrationBlockDurationEstimate(remainingBlocks);
  }

  final projectedHeight = transactions.fold<int>(
    currentHeight,
    (height, transaction) =>
        math.max(height, transaction.projectedCompletionHeight),
  );
  final remainingBlocks = math.max(1, projectedHeight - currentHeight);
  return _formatMigrationBlockDurationEstimate(remainingBlocks);
}

class _PreparationRingDetail extends StatelessWidget {
  const _PreparationRingDetail({required this.presentation});

  final _PreparationRingPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.labelLarge.copyWith(
      color: colors.text.primary,
      fontWeight: FontWeight.w400,
    );
    if (presentation.height == null) {
      return Text(
        presentation.detail,
        textAlign: TextAlign.center,
        style: style,
      );
    }
    final height = formatGroupedInteger(presentation.height!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (presentation.active)
          IronwoodMigrationShimmerText(
            text: height,
            style: style,
            baseColor: colors.text.secondary,
            highlightColor: colors.text.accent,
            textAlign: TextAlign.right,
          )
        else ...[
          Text('at', style: style),
          const SizedBox(width: 4),
          AppIcon(AppIcons.block, size: 16, color: colors.icon.success),
          const SizedBox(width: 4),
          Text(height, style: style),
        ],
        if (presentation.active) ...[
          const SizedBox(width: 4),
          AppIcon(AppIcons.loader, size: 16, color: colors.icon.accent),
        ],
      ],
    );
  }
}

_MigrationRingPresentation _migrationRingPresentation({
  required rust_sync.MigrationStatus status,
  required List<rust_sync.MigrationPartStatus> parts,
  required List<BigInt> values,
  required List<_MigrationBatchStatus> statuses,
  required BigInt totalZatoshi,
  required bool waitingForAnchor,
  required int currentHeight,
}) {
  final needsInputIndex = statuses.indexOf(_MigrationBatchStatus.needsInput);
  if (needsInputIndex >= 0) {
    return _MigrationRingPresentation(
      label: 'Next migration',
      amount: values[needsInputIndex],
      detail: 'Ready to sign',
    );
  }

  final nextProofWindowHeight = status.nextProofWindowHeight;
  final proofWindowPartIndices =
      status.nextProofWindowPartIndices?.toSet() ?? const <int>{};
  final earliestScheduledHeight = parts
      .where(
        (part) =>
            part.state == rust_sync.MigrationPartState.scheduled &&
            part.scheduledHeight != null,
      )
      .map((part) => part.scheduledHeight!)
      .fold<int?>(null, (earliest, height) {
        return earliest == null ? height : math.min(earliest, height);
      });
  final proofWindowIsNext =
      nextProofWindowHeight != null &&
      proofWindowPartIndices.isNotEmpty &&
      (earliestScheduledHeight == null ||
          nextProofWindowHeight < earliestScheduledHeight);
  if (proofWindowIsNext) {
    final windowAmount = parts
        .where((part) => proofWindowPartIndices.contains(part.partIndex))
        .fold<BigInt>(BigInt.zero, (sum, part) => sum + part.valueZatoshi);
    final displayAmount = windowAmount > BigInt.zero
        ? windowAmount
        : totalZatoshi;
    if (status.proofReady == false &&
        currentHeight > 0 &&
        currentHeight >= nextProofWindowHeight) {
      return _MigrationRingPresentation(
        label: 'Opening migration window',
        amount: displayAmount,
        detail: 'Waiting for wallet sync',
      );
    }
    if (status.proofReady == true) {
      return _MigrationRingPresentation(
        label: 'Migration window ready',
        amount: displayAmount,
        detail: 'Preparing migration',
      );
    }
    return _MigrationRingPresentation(
      label: 'Next migration window',
      amount: displayAmount,
      detail: 'Expected at',
      scheduledHeight: nextProofWindowHeight,
    );
  }

  final scheduledIndex = statuses.indexOf(_MigrationBatchStatus.scheduled);
  if (scheduledIndex >= 0) {
    final part = scheduledIndex < parts.length ? parts[scheduledIndex] : null;
    final legacyBroadcast = part == null
        ? _nextScheduledBroadcast(status)
        : null;
    final scheduledHeight =
        part?.scheduledHeight ?? legacyBroadcast?.scheduledHeight;
    final isDue =
        scheduledHeight != null &&
        currentHeight > 0 &&
        scheduledHeight <= currentHeight;
    return _MigrationRingPresentation(
      label: isDue ? 'Sending migration' : 'Next migration',
      amount: legacyBroadcast?.valueZatoshi ?? values[scheduledIndex],
      detail: isDue
          ? 'Sending now'
          : scheduledHeight == null
          ? 'Schedule pending'
          : 'at',
      scheduledHeight: isDue ? null : scheduledHeight,
    );
  }

  final preparingIndex = statuses.indexOf(_MigrationBatchStatus.preparing);
  if (preparingIndex >= 0) {
    return _MigrationRingPresentation(
      label: 'Next migration',
      amount: values[preparingIndex],
      detail: 'Schedule pending',
    );
  }

  final migratingCount = statuses
      .where((status) => status == _MigrationBatchStatus.migrating)
      .length;
  final confirmingCount = statuses
      .where((status) => status == _MigrationBatchStatus.confirming)
      .length;
  final remainingCount = migratingCount + confirmingCount;
  final remainingAmount = values.indexed.fold<BigInt>(BigInt.zero, (
    sum,
    entry,
  ) {
    final (index, value) = entry;
    if (index >= statuses.length) return sum;
    return switch (statuses[index]) {
      _MigrationBatchStatus.migrating ||
      _MigrationBatchStatus.confirming => sum + value,
      _ => sum,
    };
  });

  if (migratingCount > 0 && confirmingCount == 0) {
    return _MigrationRingPresentation(
      label: 'Awaiting mining',
      amount: remainingAmount,
      detail: _migrationNoteCountLabel(migratingCount, 'broadcast'),
    );
  }
  if (confirmingCount > 0 && migratingCount == 0) {
    return _MigrationRingPresentation(
      label: 'Confirming',
      amount: remainingAmount,
      detail: _migrationNoteCountLabel(
        confirmingCount,
        'awaiting confirmation',
      ),
    );
  }
  if (remainingCount > 0) {
    return _MigrationRingPresentation(
      label: 'Finalizing migration',
      amount: remainingAmount,
      detail: _migrationNoteCountLabel(remainingCount, 'remaining'),
    );
  }
  if (waitingForAnchor) {
    return _MigrationRingPresentation(
      label: 'Next migration',
      amount: totalZatoshi,
      detail: 'Schedule pending',
    );
  }
  return _MigrationRingPresentation(
    label: 'Migration complete',
    amount: totalZatoshi,
    detail: 'All notes completed',
  );
}

String _migrationNoteCountLabel(int count, String state) =>
    '$count ${count == 1 ? 'note' : 'notes'} $state';

class _MigrationRingDetail extends StatelessWidget {
  const _MigrationRingDetail({required this.presentation});

  final _MigrationRingPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.text.primary;
    final style = AppTypography.labelLarge.copyWith(
      color: color,
      fontWeight: FontWeight.w400,
    );
    final scheduledHeight = presentation.scheduledHeight;
    if (scheduledHeight == null) {
      return Text(
        presentation.detail,
        textAlign: TextAlign.center,
        style: style,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(presentation.detail, style: style),
        const SizedBox(width: 4),
        AppIcon(AppIcons.block, size: 16, color: context.colors.icon.success),
        const SizedBox(width: 4),
        Text(formatGroupedInteger(scheduledHeight), style: style),
      ],
    );
  }
}

class _MigrationSummaryMetric extends StatelessWidget {
  const _MigrationSummaryMetric({
    required this.label,
    required this.value,
    this.secondary = false,
    this.valueIcon,
  });

  final String label;
  final String value;
  final bool secondary;
  final String? valueIcon;

  @override
  Widget build(BuildContext context) {
    final color = secondary
        ? context.colors.text.primary
        : context.colors.text.accent;
    final style = AppTypography.labelLarge.copyWith(
      color: color,
      fontWeight: FontWeight.w400,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 16),
        if (valueIcon != null) ...[
          AppIcon(valueIcon!, size: 16, color: context.colors.icon.regular),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: style,
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
    required this.palette,
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.child,
  });

  final bool preparing;
  final Color preparationColor;
  final _MigrationRingPalette palette;
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
  static const _motionDuration = Duration(milliseconds: 1600);

  final math.Random _random = math.Random(704075305);
  late final AnimationController _stepController = AnimationController(
    vsync: this,
    duration: _stepDuration,
  );
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: _spinDuration,
  );
  late final CurvedAnimation _spinAnimation = CurvedAnimation(
    parent: _spinController,
    curve: Curves.easeInOutCubic,
  );
  late final AnimationController _morphController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
  );
  late final AnimationController _motionController = AnimationController(
    vsync: this,
    duration: _motionDuration,
  );
  late List<double> _weights;
  late List<double> _fromWeights;
  late List<double> _toWeights;
  Timer? _idleTimer;
  bool _reduceMotion = false;
  List<_MigrationRingVisualSegment> _morphFrom = const [];
  List<_MigrationRingVisualSegment> _morphTo = const [];

  @override
  void initState() {
    super.initState();
    _morphController.addStatusListener(_handleMorphStatus);
    _weights = List.of(_MigrationPreparationRingPainter.initialSegmentRatios);
    _fromWeights = List.of(_weights);
    _toWeights = List.of(_weights);
    final initialPreparationSegments = _preparationSegments(_weights);
    if (widget.preparing) {
      _morphFrom = initialPreparationSegments;
      _morphTo = initialPreparationSegments;
      _runIdleLoop();
    } else {
      _morphFrom = _liveSegments(
        values: widget.values,
        totalZatoshi: widget.totalZatoshi,
        statuses: widget.statuses,
        palette: widget.palette,
      );
      _morphTo = _morphFrom;
      _morphController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _MigrationMorphingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preparing) {
      _syncMotionController();
      return;
    }

    final next = _liveSegments(
      values: widget.values,
      totalZatoshi: widget.totalZatoshi,
      statuses: widget.statuses,
      palette: widget.palette,
    );
    if (_sameVisualSegments(_morphTo, next)) {
      _syncMotionController();
      return;
    }

    final current = oldWidget.preparing
        ? _preparationSegments(_currentPreparationWeights())
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
    _syncMotionController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncMotionController();
  }

  void _handleMorphStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _morphFrom = _morphTo;
    _syncMotionController();
  }

  void _syncMotionController() {
    final shouldRun =
        !_reduceMotion &&
        !widget.preparing &&
        (_segmentsNeedMotion(_morphFrom) || _segmentsNeedMotion(_morphTo));
    if (shouldRun) {
      if (!_motionController.isAnimating) {
        _motionController.repeat();
      }
    } else {
      _motionController.stop();
    }
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

  List<double> _currentPreparationWeights() {
    final eased = Curves.easeOutBack.transform(_stepController.value);
    return List.generate(
      _weights.length,
      (index) =>
          _fromWeights[index] +
          ((_toWeights[index] - _fromWeights[index]) * eased),
    );
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
    _spinAnimation.dispose();
    _spinController.dispose();
    _morphController.dispose();
    _motionController.dispose();
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
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.preparing)
            RotationTransition(
              key: const ValueKey(
                'ironwood_migration_preparation_ring_rotation',
              ),
              turns: _spinAnimation,
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('ironwood_migration_ring_paint'),
                  size: const Size.square(256),
                  painter: _MigrationPreparationAnimatedRingPainter(
                    fromWeights: _fromWeights,
                    toWeights: _toWeights,
                    color: widget.preparationColor,
                    progress: _stepController,
                    reduceMotion: _reduceMotion,
                  ),
                ),
              ),
            )
          else
            AnimatedBuilder(
              animation: Listenable.merge([
                _morphController,
                _motionController,
              ]),
              builder: (context, _) => CustomPaint(
                key: const ValueKey('ironwood_migration_ring_paint'),
                size: const Size.square(256),
                painter: _MigrationRingVisualPainter(
                  segments: _interpolateVisualSegments(
                    _morphFrom,
                    _morphTo,
                    Curves.easeInOutCubic.transform(_morphController.value),
                  ),
                  rotation: 0,
                  motionPhase: _motionController.value,
                  reduceMotion: _reduceMotion,
                ),
              ),
            ),
          if (widget.preparing)
            const SizedBox.shrink(
              key: ValueKey('ironwood_migration_preparation_ring'),
            ),
          widget.child,
        ],
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
        highlightColor: widget.preparationColor,
      ),
  ];
}

class _MigrationPreparationAnimatedRingPainter extends CustomPainter {
  _MigrationPreparationAnimatedRingPainter({
    required this.fromWeights,
    required this.toWeights,
    required this.color,
    required this.progress,
    required this.reduceMotion,
  }) : super(repaint: progress);

  final List<double> fromWeights;
  final List<double> toWeights;
  final Color color;
  final Animation<double> progress;
  final bool reduceMotion;

  List<_MigrationRingVisualSegment> get segments {
    final eased = Curves.easeOutBack.transform(progress.value);
    return [
      for (var index = 0; index < fromWeights.length; index++)
        _MigrationRingVisualSegment(
          weight:
              fromWeights[index] +
              ((toWeights[index] - fromWeights[index]) * eased),
          color: color,
          highlightColor: color,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    _MigrationRingVisualPainter(
      segments: segments,
      rotation: 0,
      motionPhase: 0,
      reduceMotion: reduceMotion,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(
    covariant _MigrationPreparationAnimatedRingPainter oldDelegate,
  ) =>
      oldDelegate.fromWeights != fromWeights ||
      oldDelegate.toWeights != toWeights ||
      oldDelegate.color != color ||
      oldDelegate.reduceMotion != reduceMotion;
}

typedef _MigrationRingPalette = ({
  Color scheduled,
  Color needsInput,
  Color complete,
});

_MigrationRingPalette _migrationRingPalette(AppColors colors) => (
  scheduled: colors.text.positiveStrong.withValues(alpha: 0.20),
  needsInput: colors.background.inverse,
  complete: const Color(0xFF00C875),
);

enum _MigrationRingMotion { none, shimmer, blink }

class _MigrationRingVisualSegment {
  const _MigrationRingVisualSegment({
    required this.weight,
    required this.color,
    required this.highlightColor,
    this.motion = _MigrationRingMotion.none,
    this.motionStrength = 0,
    this.presence = 1,
  });

  final double weight;
  final Color color;
  final Color highlightColor;
  final _MigrationRingMotion motion;
  final double motionStrength;
  final double presence;
}

// At the ring's 104 px radius this produces roughly one logical pixel of
// center-line arc. With rounded 12 px caps it reads as a single dot instead of
// disappearing, while remaining small enough not to distort normal notes.
const _migrationRingMinimumSegmentWeight = 0.0025;

List<_MigrationRingVisualSegment> _liveSegments({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required List<_MigrationBatchStatus> statuses,
  required _MigrationRingPalette palette,
}) {
  if (values.isEmpty || totalZatoshi <= BigInt.zero) return const [];
  final weights = _normalizedMigrationRingWeights(values);
  return [
    for (var index = 0; index < values.length; index++)
      _migrationRingStatusSegment(
        weight: weights[index],
        status: index < statuses.length
            ? statuses[index]
            : _MigrationBatchStatus.scheduled,
        palette: palette,
      ),
  ];
}

List<double> _normalizedMigrationRingWeights(List<BigInt> values) {
  final positiveIndices = [
    for (var index = 0; index < values.length; index++)
      if (values[index] > BigInt.zero) index,
  ];
  if (positiveIndices.isEmpty) {
    return List<double>.filled(values.length, 0);
  }

  final positiveTotal = positiveIndices.fold<BigInt>(
    BigInt.zero,
    (sum, index) => sum + values[index],
  );
  final minimumWeight = math.min(
    _migrationRingMinimumSegmentWeight,
    1 / positiveIndices.length,
  );
  final weights = List<double>.filled(values.length, 0);
  var remainingIndices = List<int>.of(positiveIndices);
  var remainingWeight = 1.0;
  var remainingValue = positiveTotal;

  // Water-fill the smallest notes to the visual floor, then distribute the
  // remaining ring among larger notes in their original value proportions.
  // Unlike max(weight, floor) followed by normalization, this guarantees both
  // the floor and an exact total weight of one.
  while (remainingIndices.isNotEmpty) {
    final belowFloor = [
      for (final index in remainingIndices)
        if ((values[index] / remainingValue).toDouble() * remainingWeight <
            minimumWeight)
          index,
    ];
    if (belowFloor.isEmpty) {
      for (final index in remainingIndices) {
        weights[index] =
            (values[index] / remainingValue).toDouble() * remainingWeight;
      }
      break;
    }

    for (final index in belowFloor) {
      weights[index] = minimumWeight;
      remainingValue -= values[index];
    }
    remainingWeight -= minimumWeight * belowFloor.length;
    remainingIndices.removeWhere(belowFloor.contains);
  }

  // Absorb floating-point residue into the largest note so callers can rely
  // on the invariant that the represented proportions sum to exactly one.
  final largestIndex = positiveIndices.reduce(
    (left, right) => values[left] >= values[right] ? left : right,
  );
  final sum = weights.fold<double>(0, (total, weight) => total + weight);
  weights[largestIndex] += 1 - sum;
  return weights;
}

_MigrationRingVisualSegment _migrationRingStatusSegment({
  required double weight,
  required _MigrationBatchStatus status,
  required _MigrationRingPalette palette,
}) {
  final (color, highlightColor, motion) = switch (status) {
    _MigrationBatchStatus.none => (
      const Color(0xFF3F4040),
      const Color(0xFF3F4040),
      _MigrationRingMotion.none,
    ),
    _MigrationBatchStatus.preparing => (
      palette.scheduled,
      palette.scheduled,
      _MigrationRingMotion.none,
    ),
    _MigrationBatchStatus.scheduled => (
      palette.scheduled,
      palette.scheduled,
      _MigrationRingMotion.none,
    ),
    _MigrationBatchStatus.migrating || _MigrationBatchStatus.confirming => (
      palette.scheduled,
      palette.complete,
      _MigrationRingMotion.shimmer,
    ),
    _MigrationBatchStatus.complete => (
      palette.complete,
      palette.complete,
      _MigrationRingMotion.none,
    ),
    _MigrationBatchStatus.needsInput => (
      palette.needsInput,
      palette.needsInput,
      _MigrationRingMotion.blink,
    ),
  };
  return _MigrationRingVisualSegment(
    weight: weight,
    color: color,
    highlightColor: highlightColor,
    motion: motion,
    motionStrength: motion == _MigrationRingMotion.none ? 0 : 1,
  );
}

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
    highlightColor: Color(0x003F4040),
    presence: 0,
  );
  return [
    for (var index = 0; index < count; index++)
      _interpolateVisualSegment(
        index < from.length ? from[index] : transparent,
        index < to.length ? to[index] : transparent,
        t,
      ),
  ];
}

_MigrationRingVisualSegment _interpolateVisualSegment(
  _MigrationRingVisualSegment from,
  _MigrationRingVisualSegment to,
  double t,
) {
  final motion = from.motion == to.motion
      ? from.motion
      : to.motion != _MigrationRingMotion.none
      ? to.motion
      : from.motion;
  return _MigrationRingVisualSegment(
    weight: from.weight + (to.weight - from.weight) * t,
    color: Color.lerp(from.color, to.color, t)!,
    highlightColor: Color.lerp(from.highlightColor, to.highlightColor, t)!,
    motion: motion,
    motionStrength:
        from.motionStrength + (to.motionStrength - from.motionStrength) * t,
    presence: from.presence + (to.presence - from.presence) * t,
  );
}

bool _segmentsNeedMotion(List<_MigrationRingVisualSegment> segments) =>
    segments.any(
      (segment) =>
          segment.motion != _MigrationRingMotion.none &&
          segment.motionStrength > 0.0001,
    );

bool _sameVisualSegments(
  List<_MigrationRingVisualSegment> left,
  List<_MigrationRingVisualSegment> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].weight != right[index].weight ||
        left[index].color != right[index].color ||
        left[index].highlightColor != right[index].highlightColor ||
        left[index].motion != right[index].motion ||
        left[index].motionStrength != right[index].motionStrength ||
        left[index].presence != right[index].presence) {
      return false;
    }
  }
  return true;
}

class _MigrationRingVisualPainter extends CustomPainter {
  const _MigrationRingVisualPainter({
    required this.segments,
    required this.rotation,
    required this.motionPhase,
    required this.reduceMotion,
  });

  final List<_MigrationRingVisualSegment> segments;
  final double rotation;
  final double motionPhase;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
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
    // Presence is animated separately from value. A tiny live note must keep
    // its full gap, while a segment that is actually entering or leaving the
    // morph gradually acquires or surrenders that gap.
    final presences = [
      for (final segment in segments) segment.presence.clamp(0.0, 1.0),
    ];
    final effectiveCount = presences.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    if (effectiveCount <= 0) return;
    final radius = rect.width / 2;
    final availablePerSegment = math.pi * 2 * radius / effectiveCount;
    final strokeWidth = math.min(12.0, math.max(1.0, availablePerSegment - 1));
    final dotCenterLineSweep = 1 / radius;
    final gap = math.min(
      0.17,
      math.max(0, math.pi * 2 / effectiveCount - dotCenterLineSweep),
    );
    final drawableSweep = math.max(0, math.pi * 2 - effectiveCount * gap);
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

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
      paint.shader = null;
      paint.color = _migrationRingAnimatedColor(
        segment,
        motionPhase: motionPhase,
        reduceMotion: reduceMotion,
      );
      if (segment.motion == _MigrationRingMotion.shimmer &&
          segment.motionStrength > 0) {
        final highlight = Color.lerp(
          segment.color,
          segment.highlightColor,
          segment.motionStrength,
        )!;
        if (reduceMotion) {
          paint.color = Color.lerp(segment.color, highlight, 0.5)!;
        } else {
          paint.shader = SweepGradient(
            colors: [
              segment.color,
              segment.color,
              highlight,
              segment.color,
              segment.color,
            ],
            stops: const [0, 0.35, 0.5, 0.65, 1],
            transform: GradientRotation(
              motionPhase * math.pi * 2 - math.pi / 2,
            ),
          ).createShader(rect);
          // A shader supplies its own alpha. Keep Paint fully opaque so its
          // color does not attenuate the completed-color highlight.
          paint.color = const Color(0xFFFFFFFF);
        }
      }
      if (sweep > 0.001 && paint.color.a > 0) {
        canvas.drawArc(rect, angle + gap * presence / 2, sweep, false, paint);
      }
      angle += sweep + gap * presence;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MigrationRingVisualPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.motionPhase != motionPhase ||
      oldDelegate.reduceMotion != reduceMotion ||
      !_sameVisualSegments(oldDelegate.segments, segments);
}

Color _migrationRingAnimatedColor(
  _MigrationRingVisualSegment segment, {
  required double motionPhase,
  required bool reduceMotion,
}) {
  if (segment.motion != _MigrationRingMotion.blink ||
      segment.motionStrength <= 0) {
    return segment.color;
  }
  final blink = reduceMotion ? 0.5 : _triangleWave((motionPhase * 2) % 1);
  final targetAlpha = segment.color.a * (0.2 + 0.8 * blink);
  final blinkColor = segment.color.withValues(alpha: targetAlpha);
  return Color.lerp(segment.color, blinkColor, segment.motionStrength)!;
}

double _triangleWave(double value) => value < 0.5 ? value * 2 : (1 - value) * 2;

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
