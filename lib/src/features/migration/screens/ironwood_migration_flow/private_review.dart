part of '../ironwood_migration_flow_screen.dart';

class _IronwoodMigrationPrivateReviewContent extends ConsumerStatefulWidget {
  const _IronwoodMigrationPrivateReviewContent({
    required this.data,
    this.previewPlan,
    this.forceAnalyzing = false,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final bool forceAnalyzing;

  @override
  ConsumerState<_IronwoodMigrationPrivateReviewContent> createState() =>
      _IronwoodMigrationPrivateReviewContentState();
}

class _IronwoodMigrationPrivateReviewContentState
    extends ConsumerState<_IronwoodMigrationPrivateReviewContent> {
  bool _isStarting = false;
  bool _hasCompletedAnalyzingTransition = false;
  String? _startError;
  late final Future<void> _minimumAnalyzingDelay;

  @override
  void initState() {
    super.initState();
    _minimumAnalyzingDelay = widget.forceAnalyzing
        ? Future<void>.value()
        : _createMinimumAnalyzingDelay();
  }

  Future<void> _createMinimumAnalyzingDelay() {
    final duration = ref.read(
      ironwoodMigrationAnalyzingMinimumDurationProvider,
    );
    if (duration <= Duration.zero) return Future<void>.value();
    return Future<void>.delayed(duration);
  }

  Future<void> _startMigration(
    rust_sync.OrchardMigrationPrivatePlan plan,
  ) async {
    if (_isStarting) return;

    IronwoodMigrationStatusRequest? statusRequest;
    var softwareStartAttempted = false;
    setState(() {
      _isStarting = true;
      _startError = null;
    });

    try {
      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      statusRequest = IronwoodMigrationStatusRequest(
        network: ref.read(ironwoodMigrationInputsProvider).network,
        accountUuid: accountUuid,
      );
      if (accountState.activeAccount?.isHardware ?? false) {
        // A fully direct plan has no split stages, so the combined request
        // would carry zero messages, which Rust rejects. It signs nothing up
        // front: the legacy denomination completion accepts the empty set and
        // the children are signed from the status screen.
        context.go(
          plan.denominationSplitStageCount > 0
              ? '/migration/private/keystone/sign'
              : '/migration/private/keystone/denominations/sign',
          extra: plan.scheduledTransfers,
        );
        return;
      }
      softwareStartAttempted = true;
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .startSoftwareMigration(
            accountUuid: accountUuid,
            approvedSchedule: plan.scheduledTransfers,
          );
      if (!mounted) return;
      await _refreshMigrationStatusBestEffort(statusRequest);
      if (!mounted) return;
      _openMigrationStatus();
    } catch (e) {
      if (!mounted) return;
      final request = statusRequest;
      if (softwareStartAttempted &&
          request != null &&
          await _migrationMayHaveStarted(request)) {
        if (!mounted) return;
        _openMigrationStatus();
        return;
      }
      if (!mounted) return;
      setState(() {
        _startError = _privateMigrationStartErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<bool> _migrationMayHaveStarted(
    IronwoodMigrationStatusRequest request,
  ) async {
    ref.invalidate(ironwoodMigrationStatusProvider(request));
    try {
      final status = await ref
          .read(ironwoodMigrationStatusProvider(request).future)
          .timeout(_privateStatusStartVerificationTimeout);
      return status.activeRunId != null;
    } catch (_) {
      // The start operation may already have persisted a run. An unavailable
      // status is not sufficient evidence that retrying start is safe.
      return true;
    }
  }

  Future<void> _refreshMigrationStatusBestEffort(
    IronwoodMigrationStatusRequest request,
  ) async {
    ref.invalidate(ironwoodMigrationStatusProvider(request));
    try {
      await ref
          .read(ironwoodMigrationStatusProvider(request).future)
          .timeout(_privateStatusStartVerificationTimeout);
    } catch (_) {
      // The status route owns unavailable-state rendering after start.
    }
  }

  void _openMigrationStatus() {
    _invalidateIronwoodMigrationStatusState(ref);
    context.go('/migration/private/status');
  }

  @override
  Widget build(BuildContext context) {
    final previewPlan = widget.previewPlan;
    final planAsync = widget.forceAnalyzing
        ? const AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.loading()
        : previewPlan == null
        ? ref.watch(ironwoodMigrationPrivatePlanProvider)
        : AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.data(previewPlan);
    final plan = planAsync.asData?.value;
    return FutureBuilder<void>(
      future: _minimumAnalyzingDelay,
      builder: (context, snapshot) {
        if (planAsync.isLoading ||
            snapshot.connectionState != ConnectionState.done) {
          return const _MigrationAnalyzingContent();
        }
        if (planAsync.hasError || plan == null) {
          return const SizedBox(
            width: 420,
            height: 656,
            child: Center(
              child: _PrivateReviewUnavailable(
                title: "Couldn't analyze this balance",
                body: 'Wait for sync to finish, then try again.',
              ),
            ),
          );
        }

        if (!_hasCompletedAnalyzingTransition) {
          return _MigrationAnalyzingContent(
            isReady: true,
            onCompleted: () {
              if (!mounted) return;
              setState(() {
                _hasCompletedAnalyzingTransition = true;
              });
            },
          );
        }

        return _MigrationReviewContent(
          plan: plan,
          isStarting: _isStarting,
          error: _startError,
          onContinue: () => unawaited(_startMigration(plan)),
        );
      },
    );
  }
}

class _MigrationAnalyzingContent extends StatefulWidget {
  const _MigrationAnalyzingContent({this.isReady = false, this.onCompleted});

  final bool isReady;
  final VoidCallback? onCompleted;

  @override
  State<_MigrationAnalyzingContent> createState() =>
      _MigrationAnalyzingContentState();
}

class _MigrationAnalyzingContentState extends State<_MigrationAnalyzingContent>
    with TickerProviderStateMixin {
  static const _messages = [
    'Analyzing your balance...',
    'Finding private batches...',
    'Preparing your migration plan...',
  ];
  static const _switchDuration = Duration(milliseconds: 240);

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: _MigrationAnalyzingMotion.period,
  );
  late final AnimationController _donutController = AnimationController(
    vsync: this,
    duration: _MigrationAnalyzingMotion.preparationPeriod,
  );
  late final Animation<double> _donutProgress = _MigrationAnalyzingMotion
      .donutProgress
      .animate(_donutController);
  late final AnimationController _completionController = AnimationController(
    vsync: this,
    duration: _MigrationAnalyzingMotion.completionPeriod,
  )..addStatusListener(_handleCompletionStatus);
  Animation<double> _completionProgress = const AlwaysStoppedAnimation(0);
  Timer? _reducedMotionMessageTimer;
  var _messageIndex = 0;
  var _advancedMessageThisCycle = false;
  var _completionStarted = false;
  var _completionDispatched = false;

  bool get _shouldAnimate =>
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  void initState() {
    super.initState();
    _shimmer.addListener(_handleShimmerTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
    if (widget.isReady) _beginCompletion();
  }

  @override
  void didUpdateWidget(covariant _MigrationAnalyzingContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isReady && widget.isReady) _beginCompletion();
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      _reducedMotionMessageTimer?.cancel();
      _reducedMotionMessageTimer = null;
      if (!_shimmer.isAnimating) _shimmer.repeat();
      if (_donutController.status == AnimationStatus.dismissed) {
        _donutController.forward();
      }
    } else {
      _shimmer
        ..stop()
        ..value = 0;
      _donutController
        ..stop()
        ..value = 0;
      if (widget.isReady) {
        _completionController.value = 1;
      }
      _reducedMotionMessageTimer ??= Timer.periodic(
        _MigrationAnalyzingMotion.period,
        (_) => _advanceMessage(),
      );
    }
  }

  void _beginCompletion() {
    if (_completionStarted) return;
    _completionStarted = true;

    final startProgress = _shouldAnimate
        ? _donutProgress.value
        : _MigrationAnalyzingMotion.reducedMotionProgress;
    _donutController.stop();
    _completionProgress = Tween<double>(begin: startProgress, end: 1).animate(
      CurvedAnimation(parent: _completionController, curve: Curves.easeInOut),
    );

    if (_shouldAnimate) {
      _completionController.forward(from: 0);
    } else {
      _completionController.value = 1;
    }
    setState(() {});
  }

  void _handleCompletionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _completionDispatched) return;
    _completionDispatched = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCompleted?.call();
    });
  }

  void _handleShimmerTick() {
    if (!mounted || !_shouldAnimate) return;
    final progress = _shimmer.value;
    if (progress < _MigrationAnalyzingMotion.cycleResetProgress) {
      _advancedMessageThisCycle = false;
      return;
    }
    if (!_advancedMessageThisCycle &&
        progress >= _MigrationAnalyzingMotion.messageAdvanceProgress) {
      _advancedMessageThisCycle = true;
      _advanceMessage();
    }
  }

  void _advanceMessage() {
    if (!mounted) return;
    setState(() {
      _messageIndex = (_messageIndex + 1) % _messages.length;
    });
  }

  @override
  void dispose() {
    _reducedMotionMessageTimer?.cancel();
    _shimmer.removeListener(_handleShimmerTick);
    _shimmer.dispose();
    _donutController.dispose();
    _completionController
      ..removeStatusListener(_handleCompletionStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = _messages[_messageIndex];
    return SizedBox(
      key: const ValueKey('ironwood_migration_analyzing_screen'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: _migrationPlanDonutLeft,
            top: _migrationPlanDonutTop,
            width: _migrationPlanDonutSize,
            height: _migrationPlanDonutSize,
            child: _MigrationAnalyzingDonut(
              progress: _completionStarted
                  ? _completionProgress
                  : _shouldAnimate
                  ? _donutProgress
                  : const AlwaysStoppedAnimation(
                      _MigrationAnalyzingMotion.reducedMotionProgress,
                    ),
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (context, _) {
                  return AnimatedSwitcher(
                    duration: _shouldAnimate ? _switchDuration : Duration.zero,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: _MigrationAnalyzingShimmerText(
                      key: ValueKey(title),
                      label: title,
                      baseColor: colors.text.muted,
                      highlightColor: colors.text.accent,
                      progress: _shimmer.value,
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 60,
            top: 424,
            width: 300,
            child: Text(
              'Vizor is working hard to find a perfect balance\n'
              'of safety, privacy, and speed for your migration',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationAnalyzingDonut extends StatelessWidget {
  const _MigrationAnalyzingDonut({required this.progress, required this.child});

  final Animation<double> progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.square(
      key: const ValueKey('ironwood_migration_analyzing_donut'),
      dimension: _migrationPlanDonutSize,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, child) => Semantics(
          label: 'Preparing private migration plan',
          value: '${(progress.value * 100).round()}%',
          child: CustomPaint(
            painter: _MigrationAnalyzingDonutPainter(
              progress: progress.value,
              trackColor: colors.text.accent.withValues(alpha: 0.15),
              progressColor: colors.text.accent,
            ),
            child: child,
          ),
        ),
        child: Center(
          child: SizedBox(width: 200, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _MigrationAnalyzingDonutPainter extends CustomPainter {
  const _MigrationAnalyzingDonutPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  static const _strokeWidth = 12.8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - _strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MigrationAnalyzingDonutPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}

abstract final class _MigrationAnalyzingMotion {
  static const period = Duration(seconds: 2);
  static const preparationPeriod = Duration(milliseconds: 9500);
  static const completionPeriod = Duration(milliseconds: 250);
  static const reducedMotionProgress = 0.28;
  static const messageAdvanceProgress = 0.96;
  static const cycleResetProgress = 0.2;
  static const _bandHalf = 0.18;

  static final donutProgress = TweenSequence<double>([
    _hold(0, 350),
    _ramp(0, 0.15, 1000),
    _hold(0.15, 250),
    _ramp(0.15, 0.40, 950),
    _hold(0.40, 150),
    _ramp(0.40, 0.47, 550),
    _hold(0.47, 750),
    _ramp(0.47, 0.63, 1050),
    _hold(0.63, 300),
    _ramp(0.63, 0.71, 500),
    _hold(0.71, 850),
    _ramp(0.71, 0.86, 900),
    _hold(0.86, 400),
    _ramp(0.86, 0.97, 950),
    _hold(0.97, 550),
  ]);

  static TweenSequenceItem<double> _ramp(
    double begin,
    double end,
    double milliseconds,
  ) {
    return TweenSequenceItem(
      tween: Tween<double>(
        begin: begin,
        end: end,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: milliseconds,
    );
  }

  static TweenSequenceItem<double> _hold(double value, double milliseconds) {
    return TweenSequenceItem(
      tween: ConstantTween<double>(value),
      weight: milliseconds,
    );
  }
}

class _MigrationAnalyzingShimmerText extends StatelessWidget {
  const _MigrationAnalyzingShimmerText({
    required this.label,
    required this.baseColor,
    required this.highlightColor,
    required this.progress,
    super.key,
  });

  final String label;
  final Color baseColor;
  final Color highlightColor;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final shift = (progress * 2 - 1) * bounds.width;
        final rect = Rect.fromLTWH(
          bounds.left + shift,
          bounds.top,
          bounds.width,
          bounds.height,
        );
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [baseColor, highlightColor, highlightColor, baseColor],
          stops: const [
            0.5 - _MigrationAnalyzingMotion._bandHalf,
            0.5 - _MigrationAnalyzingMotion._bandHalf / 4,
            0.5 + _MigrationAnalyzingMotion._bandHalf / 4,
            0.5 + _MigrationAnalyzingMotion._bandHalf,
          ],
          tileMode: TileMode.clamp,
        ).createShader(rect);
      },
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTypography.labelLarge.copyWith(
          color: const Color(0xFFFFFFFF),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

const _migrationPlanDonutLeft = 82.0;
const _migrationPlanDonutTop = 108.0;
const _migrationPlanDonutSize = 256.0;

class _MigrationReviewContent extends StatelessWidget {
  const _MigrationReviewContent({
    required this.plan,
    required this.isStarting,
    required this.onContinue,
    this.error,
  });

  final rust_sync.OrchardMigrationPrivatePlan plan;
  final bool isStarting;
  final VoidCallback onContinue;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final completionEstimate = migrationPlanCompletionDurationLabel(plan);
    return SizedBox(
      key: const ValueKey('ironwood_migration_review_screen'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 12,
            width: 396,
            child: Text(
              key: const ValueKey('ironwood_migration_review_title'),
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
            child: const _MigrationStageHeader(
              key: ValueKey('ironwood_migration_stage_header'),
              stage: _MigrationStage.preparation,
            ),
          ),
          Positioned(
            left: _migrationPlanDonutLeft,
            top: _migrationPlanDonutTop,
            width: _migrationPlanDonutSize,
            height: _migrationPlanDonutSize,
            child: CustomPaint(
              key: const ValueKey('ironwood_migration_review_donut'),
              painter: _MigrationStartRingPainter(
                color: colors.text.muted.withValues(alpha: 0.32),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Amount to migrate',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatZecAmountCompact(plan.totalMigratableZatoshi)}\nZEC',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 386,
            width: 396,
            child: _ImmediateReviewRow(
              key: const ValueKey('ironwood_migration_review_completion_row'),
              label: 'Migration complete in',
              value: completionEstimate,
            ),
          ),
          Positioned(
            left: 12,
            top: 442,
            width: 396,
            child: Row(
              key: const ValueKey('ironwood_migration_keep_running_content'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  key: const ValueKey(
                    'ironwood_migration_keep_running_icon_tile',
                  ),
                  decoration: BoxDecoration(
                    color: _migrationCarouselCrimson,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.square(
                      dimension: 48,
                      child: Image.asset(
                        _ironwoodMigrationExpectationRunningAsset,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keep Vizor running',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Preparation continues while the app is minimized, '
                        'then migration starts automatically.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (error != null)
            Positioned(
              left: 45,
              top: 516,
              width: 330,
              child: Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.warning,
                ),
              ),
            ),
          Positioned(
            left: 95,
            top: 584,
            width: 230,
            child: Center(
              child: AppButton(
                key: const ValueKey(
                  'ironwood_migration_authorize_start_button',
                ),
                onPressed: isStarting ? null : onContinue,
                height: 44,
                minWidth: 230,
                expand: true,
                child: Text(isStarting ? 'Starting…' : 'Start migration'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationStartRingPainter extends CustomPainter {
  const _MigrationStartRingPainter({required this.color});

  final Color color;

  double get outerDiameter => _migrationStatusRingOuterDiameter;

  static const _weights = [0.14, 0.08, 0.09, 0.12, 0.08, 0.15, 0.1, 0.12, 0.12];
  static const _visibleGap = 0.055;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _migrationStatusRingMaxStrokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final availableOuterDiameter = math.min(
      outerDiameter,
      math.min(size.width, size.height),
    );
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: availableOuterDiameter - paint.strokeWidth,
      height: availableOuterDiameter - paint.strokeWidth,
    );
    const fullSweep = math.pi * 2;
    final radius = rect.width / 2;
    // A round cap extends half a stroke beyond both ends of an arc. Include
    // that full stroke in the center-line gap before adding visible spacing,
    // otherwise the static frame shown while "Starting…" is active overlaps
    // before the animated preparation ring replaces it.
    final gap = (paint.strokeWidth / radius) + _visibleGap;
    final drawable = fullSweep - gap * _weights.length;
    var angle = -math.pi / 2;
    for (final weight in _weights) {
      final sweep = drawable * weight;
      canvas.drawArc(rect, angle + gap / 2, sweep, false, paint);
      angle += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MigrationStartRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MigrationBatchOverview extends StatelessWidget {
  const _MigrationBatchOverview({
    required this.values,
    required this.totalZatoshi,
    required this.feeZatoshi,
    required this.completionLabel,
  });

  final List<BigInt> values;
  final BigInt totalZatoshi;
  final BigInt feeZatoshi;
  final String completionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Migration',
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                  children: [
                    TextSpan(
                      text: values.length == 1
                          ? '  1 note'
                          : '  ${values.length} notes',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_formatMigrationTotal(totalZatoshi)} ZEC',
              maxLines: 1,
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        _MigrationProgressSegmentRow(
          values: values,
          totalZatoshi: totalZatoshi,
          statuses: const [],
          progresses: const [],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: values.length,
            itemBuilder: (context, index) => _MigrationBatchRow(
              key: ValueKey('ironwood_migration_batch_$index'),
              index: index,
              value: values[index],
              totalZatoshi: totalZatoshi,
              status: _MigrationBatchStatus.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _MigrationBatchFooter(
          completionLabel: completionLabel,
          secondLabel: 'Fees (estimate)',
          secondValue: '~${_formatZecAmountCompact(feeZatoshi)} ZEC',
        ),
      ],
    );
  }
}

class _MigrationBatchFooter extends StatelessWidget {
  const _MigrationBatchFooter({
    required this.completionLabel,
    required this.secondLabel,
    required this.secondValue,
  });

  final String completionLabel;
  final String secondLabel;
  final String secondValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MigrationBatchFooterRow(
          label: 'Est. completion',
          value: completionLabel,
        ),
        const SizedBox(height: 4),
        _MigrationBatchFooterRow(label: secondLabel, value: secondValue),
      ],
    );
  }
}

class _MigrationBatchFooterRow extends StatelessWidget {
  const _MigrationBatchFooterRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textColor = context.colors.text.primary;
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: textColor,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.labelLarge.copyWith(color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
