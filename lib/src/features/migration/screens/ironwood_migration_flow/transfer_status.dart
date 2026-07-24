part of '../ironwood_migration_flow_screen.dart';

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
  final Map<String, double> _maxSeenProgress = {};

  void _syncProgressRun(String runId) {
    if (_progressRunId == runId) return;
    _progressRunId = runId;
    _maxSeenCurrentHeight = 0;
    _maxSeenProgress.clear();
  }

  int _displayCurrentHeight(int currentHeight) {
    if (currentHeight > _maxSeenCurrentHeight) {
      _maxSeenCurrentHeight = currentHeight;
    }
    if (_maxSeenCurrentHeight > 0) return _maxSeenCurrentHeight;
    return currentHeight;
  }

  List<String> _progressKeys({
    required String runId,
    required String progressScope,
    required List<rust_sync.MigrationPartStatus> parts,
    required int count,
  }) {
    return [
      for (var i = 0; i < count; i++)
        '$runId:$progressScope:part:${parts.isNotEmpty && i < parts.length ? parts[i].partIndex : i}',
    ];
  }

  List<double> _monotonicProgresses({
    required List<String> keys,
    required List<_MigrationBatchStatus> statuses,
    required List<double> rawProgresses,
  }) {
    return [
      for (var i = 0; i < keys.length; i++)
        _monotonicProgress(
          key: keys[i],
          status: i < statuses.length
              ? statuses[i]
              : _MigrationBatchStatus.none,
          rawProgress: i < rawProgresses.length ? rawProgresses[i] : 0.0,
        ),
    ];
  }

  double _monotonicProgress({
    required String key,
    required _MigrationBatchStatus status,
    required double rawProgress,
  }) {
    final clampedProgress = status == _MigrationBatchStatus.complete
        ? 1.0
        : rawProgress.clamp(0, 1).toDouble();
    final previous = _maxSeenProgress[key] ?? 0.0;
    final next = math.max(previous, clampedProgress);
    _maxSeenProgress[key] = next;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final runId = status.activeRunId ?? 'inactive';
    _syncProgressRun(runId);

    final parts = _displayMigrationParts(status);
    var values = parts.isNotEmpty
        ? [for (final part in parts) part.valueZatoshi]
        : [for (final value in status.targetValuesZatoshi) value];
    if (values.isEmpty && status.phase != kIronwoodMigrationCompletePhase) {
      values = [BigInt.zero];
    }
    final partNumbers = parts.isNotEmpty
        ? [for (final part in parts) part.partIndex + 1]
        : [for (var i = 0; i < values.length; i++) i + 1];
    final statuses = status.phase == kIronwoodMigrationCompletePhase
        ? List<_MigrationBatchStatus>.filled(
            values.length,
            _MigrationBatchStatus.complete,
          )
        : parts.isNotEmpty
        ? [for (final part in parts) _migrationBatchStatus(part.state)]
        : _legacyMigrationBatchStatuses(status, values.length);
    if (widget.action == _StatusAction.needsInput &&
        !statuses.contains(_MigrationBatchStatus.needsInput)) {
      final inputIndex = statuses.indexWhere(
        (status) => status != _MigrationBatchStatus.complete,
      );
      if (inputIndex >= 0) {
        statuses[inputIndex] = _MigrationBatchStatus.needsInput;
      }
    }
    final total = values.fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
    final displayCurrentHeight = _displayCurrentHeight(widget.currentHeight);
    final rawProgresses = _migrationBatchProgresses(
      status: status,
      parts: parts,
      statuses: statuses,
      currentHeight: displayCurrentHeight,
      isAdvancing: widget.isAdvancing,
    );
    final rawSegmentProgresses = [
      for (var i = 0; i < values.length; i++)
        _migrationSegmentProgress(
          values: values,
          totalZatoshi: total,
          statuses: statuses,
          progresses: rawProgresses,
          index: i,
        ),
    ];
    final progressKeys = _progressKeys(
      runId: runId,
      progressScope:
          status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase
          ? 'denomination'
          : 'transfer',
      parts: parts,
      count: values.length,
    );
    final progresses = _monotonicProgresses(
      keys: progressKeys,
      statuses: statuses,
      rawProgresses: rawSegmentProgresses,
    );
    if (_shouldShowPreparingStatusContent(status, statuses)) {
      return _MigrationPreparingStatusContent(
        key: ValueKey('ironwood_migration_preparing_${status.activeRunId}'),
      );
    }

    final spendableLabel = _migrationSpendableBalanceLabel(
      values: values,
      statuses: statuses,
    );
    final buttonLabel = switch (widget.action) {
      _StatusAction.needsInput => 'Sign with Keystone',
      _StatusAction.retry => 'Retry migration',
      _ => 'Go home',
    };
    final actionRequiresContinuation =
        widget.action == _StatusAction.needsInput ||
        widget.action == _StatusAction.retry;

    return SizedBox(
      key: ValueKey('ironwood_migration_status_${status.phase}'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            top: 37.5,
            left: 12,
            width: 396,
            child: Column(
              children: [
                Text(
                  'Migration in Progress',
                  style: AppTypography.headlineSmall.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 24,
            width: 396,
            height: 540,
            child: _MigrationStatusBatchPanel(
              values: values,
              partNumbers: partNumbers,
              totalZatoshi: total,
              statuses: statuses,
              progresses: progresses,
              progressKeys: progressKeys,
              completionLabel: _transferEstimatedCompletion(
                status,
                currentHeight: displayCurrentHeight,
                needsInput: widget.action == _StatusAction.needsInput,
                parts: parts,
              ),
              spendableLabel: spendableLabel,
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: Center(
              child: AppButton(
                key: const ValueKey('ironwood_migration_status_action_button'),
                onPressed: widget.isAdvancing && actionRequiresContinuation
                    ? null
                    : actionRequiresContinuation
                    ? widget.onAction
                    : () => context.go('/home'),
                variant: actionRequiresContinuation
                    ? AppButtonVariant.primary
                    : AppButtonVariant.secondary,
                height: 36,
                minWidth: widget.action == _StatusAction.needsInput ? 150 : 96,
                expand: false,
                child: SizedBox(
                  width: widget.action == _StatusAction.needsInput
                      ? 118
                      : widget.action == _StatusAction.retry
                      ? 92
                      : 64,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(buttonLabel),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _shouldShowPreparingStatusContent(
  rust_sync.MigrationStatus status,
  List<_MigrationBatchStatus> statuses,
) {
  // Note-split preparation is represented by one intentionally indeterminate
  // visual, even while individual split transactions are confirming.
  return status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase;
}

class _MigrationPreparingStatusContent extends StatelessWidget {
  const _MigrationPreparingStatusContent({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 78.5,
            width: 396,
            child: Text(
              'Preparing your migration',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            left: 82,
            top: 130.5,
            width: 256,
            height: 256,
            child: _MigrationPreparationRing(
              key: const ValueKey('ironwood_migration_preparation_ring'),
              color: colors.text.accent.withValues(alpha: 0.20),
            ),
          ),
          Positioned(
            left: 12,
            top: 418.5,
            width: 396,
            height: 127,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.large),
                boxShadow: appSurfaceShadow(colors),
              ),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MigrationPreparationInfoRow(
                      icon: AppIcons.wallet,
                      message:
                          'We’re organizing your balance into common-sized\n'
                          'parts. This makes your migration harder to link.',
                    ),
                    SizedBox(height: 16),
                    _MigrationPreparationInfoRow(
                      icon: AppIcons.history,
                      message:
                          'Once preparation finishes, your migration can begin.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _MigrationPreparationRing extends StatefulWidget {
  const _MigrationPreparationRing({super.key, required this.color});

  final Color color;

  @override
  State<_MigrationPreparationRing> createState() =>
      _MigrationPreparationRingState();
}

class _MigrationPreparationRingState extends State<_MigrationPreparationRing>
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
  late List<double> _weights;
  late List<double> _fromWeights;
  late List<double> _toWeights;
  Timer? _idleTimer;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _weights = List.of(_MigrationPreparationRingPainter.initialSegmentRatios);
    _fromWeights = List.of(_weights);
    _toWeights = List.of(_weights);
    _runIdleLoop();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Preparing migration. Estimated time: 10 to 20 minutes.',
      child: AnimatedBuilder(
        animation: Listenable.merge([_stepController, _spinController]),
        builder: (context, _) {
          final eased = Curves.easeOutBack.transform(_stepController.value);
          final weights = List.generate(
            _weights.length,
            (index) =>
                _fromWeights[index] +
                ((_toWeights[index] - _fromWeights[index]) * eased),
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(256),
                painter: _MigrationPreparationRingPainter(
                  color: widget.color,
                  weights: weights,
                  rotation: Curves.easeInOutCubic.transform(
                    _spinController.value,
                  ),
                ),
              ),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(AppIcons.time, size: 24),
                  SizedBox(height: 8),
                  Text(
                    'Preparation will\ntake 10-20 min',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
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

List<double> _migrationBatchProgresses({
  required rust_sync.MigrationStatus status,
  required List<rust_sync.MigrationPartStatus> parts,
  required List<_MigrationBatchStatus> statuses,
  required int currentHeight,
  required bool isAdvancing,
}) {
  if (statuses.isEmpty) return const [];

  if (status.phase == kIronwoodMigrationCompletePhase) {
    return List<double>.filled(statuses.length, 1);
  }

  if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
    final hasDenominationPartProgress =
        parts.isNotEmpty &&
        parts.any(
          (part) => part.state != rust_sync.MigrationPartState.preparing,
        );
    if (hasDenominationPartProgress) {
      return [
        for (var i = 0; i < parts.length; i++)
          _migrationPartStatusProgress(
            part: parts[i],
            visualStatus: i < statuses.length
                ? statuses[i]
                : _migrationBatchStatus(parts[i].state),
            currentHeight: currentHeight,
            isAdvancing: isAdvancing,
            preparePhase: true,
          ),
      ];
    }

    final progress = _prepareMigrationProgress(
      status,
      isAdvancing: isAdvancing,
    );
    return List<double>.filled(statuses.length, progress);
  }

  if (parts.isNotEmpty) {
    return [
      for (var i = 0; i < parts.length; i++)
        _migrationPartStatusProgress(
          part: parts[i],
          visualStatus: i < statuses.length
              ? statuses[i]
              : _migrationBatchStatus(parts[i].state),
          currentHeight: currentHeight,
          isAdvancing: isAdvancing,
        ),
    ];
  }

  return [
    for (var i = 0; i < statuses.length; i++)
      _legacyMigrationBatchProgress(
        status: status,
        visualStatus: statuses[i],
        index: i,
        currentHeight: currentHeight,
        isAdvancing: isAdvancing,
      ),
  ];
}

double _prepareMigrationProgress(
  rust_sync.MigrationStatus status, {
  required bool isAdvancing,
}) {
  final totalStages = status.denominationSplitTotalCount;
  final stageProgress = totalStages > 0
      ? (status.denominationSplitCompletedCount / totalStages).clamp(0, 1)
      : 0.0;

  if (status.pendingSplitStageCount > 0) {
    return math.max(stageProgress.toDouble(), isAdvancing ? 0.18 : 0.12);
  }

  final confirmationTarget = status.denominationConfirmationTarget;
  if (confirmationTarget > 0) {
    final confirmationProgress =
        (status.denominationConfirmationCount / confirmationTarget).clamp(0, 1);
    final combined =
        _prepareBroadcastCommitProgress +
        (1 - _prepareBroadcastCommitProgress) * confirmationProgress;
    return math.max(stageProgress.toDouble(), combined);
  }

  return math.max(stageProgress.toDouble(), isAdvancing ? 0.24 : 0.16);
}

double _prepareConfirmationProgress({
  required int confirmationCount,
  required int confirmationTarget,
}) {
  if (confirmationTarget <= 0) return _prepareBroadcastCommitProgress;
  final confirmationProgress = (confirmationCount / confirmationTarget)
      .clamp(0, 1)
      .toDouble();
  return _prepareBroadcastCommitProgress +
      (1 - _prepareBroadcastCommitProgress) * confirmationProgress;
}

double _migrationPartStatusProgress({
  required rust_sync.MigrationPartStatus part,
  required _MigrationBatchStatus visualStatus,
  required int currentHeight,
  required bool isAdvancing,
  bool preparePhase = false,
}) {
  if (visualStatus == _MigrationBatchStatus.needsInput) {
    return math.max(
      _scheduledBlockProgress(
        startHeight: part.scheduleStartHeight,
        targetHeight: part.scheduledHeight,
        currentHeight: currentHeight,
      ),
      _scheduledBlockProgressCap,
    );
  }

  return switch (part.state) {
    rust_sync.MigrationPartState.preparing => 0.12,
    rust_sync.MigrationPartState.scheduled => _scheduledBlockProgress(
      startHeight: part.scheduleStartHeight,
      targetHeight: part.scheduledHeight,
      currentHeight: currentHeight,
    ),
    rust_sync.MigrationPartState.migrating =>
      preparePhase
          ? _prepareBroadcastCommitProgress
          : isAdvancing
          ? _broadcastCommitProgressCap
          : _scheduledBlockProgressCap,
    rust_sync.MigrationPartState.confirming =>
      preparePhase
          ? _prepareConfirmationProgress(
              confirmationCount: part.confirmationCount,
              confirmationTarget: part.confirmationTarget,
            )
          : _confirmationProgress(
              confirmationCount: part.confirmationCount,
              confirmationTarget: part.confirmationTarget,
            ),
    rust_sync.MigrationPartState.completed => 1,
    rust_sync.MigrationPartState.needsInput => _scheduledBlockProgressCap,
  };
}

double _legacyMigrationBatchProgress({
  required rust_sync.MigrationStatus status,
  required _MigrationBatchStatus visualStatus,
  required int index,
  required int currentHeight,
  required bool isAdvancing,
}) {
  return switch (visualStatus) {
    _MigrationBatchStatus.none => 1,
    _MigrationBatchStatus.preparing => isAdvancing ? 0.18 : 0.12,
    _MigrationBatchStatus.scheduled => _legacyScheduledProgress(
      status,
      index,
      currentHeight: currentHeight,
    ),
    _MigrationBatchStatus.migrating =>
      isAdvancing ? _broadcastCommitProgressCap : _scheduledBlockProgressCap,
    _MigrationBatchStatus.confirming =>
      status.totalCount > 0
          ? _confirmationProgress(
              confirmationCount: status.confirmedTxCount,
              confirmationTarget: status.totalCount,
            )
          : _broadcastCommitProgressCap,
    _MigrationBatchStatus.complete => 1,
    _MigrationBatchStatus.needsInput => _scheduledBlockProgressCap,
  };
}

double _legacyScheduledProgress(
  rust_sync.MigrationStatus status,
  int index, {
  required int currentHeight,
}) {
  final scheduled = [...status.scheduledBroadcasts]
    ..sort((a, b) => a.scheduledHeight.compareTo(b.scheduledHeight));
  if (index >= scheduled.length) return 0;
  final broadcast = scheduled[index];
  return _scheduledBlockProgress(
    startHeight: broadcast.scheduleStartHeight,
    targetHeight: broadcast.scheduledHeight,
    currentHeight: currentHeight,
  );
}

double _scheduledBlockProgress({
  required int? startHeight,
  required int? targetHeight,
  required int currentHeight,
}) {
  if (targetHeight == null || currentHeight <= 0) return 0;
  final effectiveStart = startHeight ?? math.max(0, targetHeight - 1);
  if (targetHeight <= effectiveStart) {
    return currentHeight >= targetHeight ? _scheduledBlockProgressCap : 0;
  }
  final elapsed = (currentHeight - effectiveStart).clamp(
    0,
    targetHeight - effectiveStart,
  );
  return _scheduledBlockProgressCap *
      (elapsed / (targetHeight - effectiveStart));
}

double _confirmationProgress({
  required int confirmationCount,
  required int confirmationTarget,
}) {
  if (confirmationTarget <= 0) return _broadcastCommitProgressCap;
  final confirmationRatio = (confirmationCount / confirmationTarget).clamp(
    0,
    1,
  );
  return _broadcastCommitProgressCap +
      (1 - _broadcastCommitProgressCap) * confirmationRatio;
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
