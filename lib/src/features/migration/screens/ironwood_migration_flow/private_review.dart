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
        context.go(
          '/migration/private/keystone/denominations/sign',
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
    if (planAsync.isLoading) return const _MigrationAnalyzingContent();
    return FutureBuilder<void>(
      future: _minimumAnalyzingDelay,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
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
  const _MigrationAnalyzingContent();

  @override
  State<_MigrationAnalyzingContent> createState() =>
      _MigrationAnalyzingContentState();
}

class _MigrationAnalyzingContentState extends State<_MigrationAnalyzingContent>
    with SingleTickerProviderStateMixin {
  static const _messages = [
    'Analyzing your balance...',
    'Finding private batches...',
    'Preparing your migration plan...',
  ];
  static const _switchDuration = Duration(milliseconds: 320);

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: _MigrationAnalyzingMotion.period,
  );
  Timer? _reducedMotionMessageTimer;
  var _messageIndex = 0;
  var _advancedMessageThisCycle = false;

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
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      _reducedMotionMessageTimer?.cancel();
      _reducedMotionMessageTimer = null;
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer
        ..stop()
        ..value = 0;
      _reducedMotionMessageTimer ??= Timer.periodic(
        _MigrationAnalyzingMotion.period,
        (_) => _advanceMessage(),
      );
    }
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
      child: Column(
        children: [
          const SizedBox(height: 178),
          const _MigrationAnalyzingProgressBar(),
          const SizedBox(height: 72),
          AnimatedBuilder(
            animation: _shimmer,
            builder: (context, _) {
              return AnimatedSwitcher(
                duration: _shouldAnimate ? _switchDuration : Duration.zero,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
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
          const SizedBox(height: 16),
          SizedBox(
            width: 298,
            child: Text(
              'Vizor is working hard to find a perfect balance of safety, '
              'privacy, and speed for your migration',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationAnalyzingProgressBar extends StatefulWidget {
  const _MigrationAnalyzingProgressBar();

  @override
  State<_MigrationAnalyzingProgressBar> createState() =>
      _MigrationAnalyzingProgressBarState();
}

class _MigrationAnalyzingProgressBarState
    extends State<_MigrationAnalyzingProgressBar>
    with SingleTickerProviderStateMixin {
  static const _barWidth = 196.0;
  static const _segmentWidth = 72.0;
  static const _initialProgress = _segmentWidth / (_barWidth + _segmentWidth);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool get _shouldAnimate =>
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  void initState() {
    super.initState();
    _controller.value = _initialProgress;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = _initialProgress;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: _barWidth,
      height: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.overlay),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = _shouldAnimate
                  ? _controller.value
                  : _initialProgress;
              final left =
                  -_segmentWidth + progress * (_barWidth + _segmentWidth);
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: _segmentWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.background.inverse,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

abstract final class _MigrationAnalyzingMotion {
  static const period = Duration(seconds: 2);
  static const messageAdvanceProgress = 0.96;
  static const cycleResetProgress = 0.2;
  static const _bandHalf = 0.18;
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
        style: AppTypography.headlineSmall.copyWith(
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

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
    final values = [for (final value in plan.targetValuesZatoshi) value];
    final rows = values.isEmpty
        ? <BigInt>[plan.totalMigratableZatoshi]
        : values;
    return SizedBox(
      key: const ValueKey('ironwood_migration_review_screen'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            top: 46,
            left: 12,
            width: 396,
            child: Column(
              children: [
                Text(
                  'Review migration plan',
                  style: AppTypography.headlineSmall.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 160,
            width: 396,
            height: 378,
            child: _MigrationBatchOverview(
              values: rows,
              totalZatoshi: plan.totalMigratableZatoshi,
              feeZatoshi: plan.estimatedTotalFeeZatoshi,
              completionLabel: _estimatedMigrationArrivalLabel(plan),
            ),
          ),
          if (error != null)
            Positioned(
              left: 45,
              top: 545,
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
            top: 596,
            width: 230,
            child: Center(
              child: AppButton(
                key: const ValueKey(
                  'ironwood_migration_authorize_start_button',
                ),
                onPressed: isStarting ? null : onContinue,
                height: 36,
                minWidth: 130,
                expand: false,
                child: SizedBox(
                  width: 98,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(isStarting ? 'Starting...' : 'Start migration'),
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
