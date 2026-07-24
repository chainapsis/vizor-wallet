part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationAnalyzing extends StatefulWidget {
  const _MobileMigrationAnalyzing({
    required this.preview,
    required this.ready,
    required this.completionSucceeded,
    this.onCompleted,
    super.key,
  });

  final bool preview;
  final bool ready;
  final bool completionSucceeded;
  final VoidCallback? onCompleted;

  @override
  State<_MobileMigrationAnalyzing> createState() =>
      _MobileMigrationAnalyzingState();
}

class _MobileMigrationAnalyzingState extends State<_MobileMigrationAnalyzing>
    with TickerProviderStateMixin {
  static const _messages = [
    'Analyzing your balance...',
    'Finding private batches...',
    'Preparing your migration plan...',
    'Your migration plan is ready',
  ];

  late final AnimationController _progressController = AnimationController(
    vsync: this,
    duration: _migrationAnalysisProgressDuration,
  );
  late final AnimationController _completionController = AnimationController(
    vsync: this,
    duration: _migrationAnalysisCompletionDuration,
  );
  late final Animation<double> _progress = _buildProgressAnimation();
  late final Animation<double> _completionProgress =
      Tween<double>(begin: 0.97, end: 1).animate(
        CurvedAnimation(
          parent: _completionController,
          curve: const Interval(0, 255 / 575, curve: Curves.easeInOutQuad),
        ),
      );
  late final Animation<double> _completionScale =
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1,
            end: 1.12,
          ).chain(CurveTween(curve: _migrationAnalysisEaseOut)),
          weight: 45,
        ),
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1.12,
            end: 1,
          ).chain(CurveTween(curve: _migrationAnalysisEaseOut)),
          weight: 55,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _completionController,
          curve: const Interval(255 / 575, 1),
        ),
      );

  bool _progressFinished = false;
  bool _completionStarted = false;
  bool _completionNotified = false;

  bool get _shouldAnimate =>
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  Animation<double> _buildProgressAnimation() {
    final items = <TweenSequenceItem<double>>[];
    var from = 0.0;
    for (final step in _migrationAnalysisProgressSteps) {
      items.add(
        TweenSequenceItem(
          tween: Tween<double>(
            begin: from,
            end: step.target,
          ).chain(CurveTween(curve: Curves.easeInOutQuad)),
          weight: step.rampMilliseconds.toDouble(),
        ),
      );
      if (step.pauseMilliseconds > 0) {
        items.add(
          TweenSequenceItem(
            tween: ConstantTween<double>(step.target),
            weight: step.pauseMilliseconds.toDouble(),
          ),
        );
      }
      from = step.target;
    }
    return TweenSequence<double>(items).animate(_progressController);
  }

  @override
  void initState() {
    super.initState();
    _progressController.addStatusListener(_handleProgressStatus);
    _completionController.addStatusListener(_handleCompletionStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _MobileMigrationAnalyzing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.ready && widget.ready) _tryStartCompletion();
  }

  void _syncMotion() {
    if (widget.preview) {
      _progressController.stop();
      _completionController.stop();
      return;
    }
    if (!_shouldAnimate) {
      _progressController
        ..stop()
        ..value = 1;
      _completionController
        ..stop()
        ..value = 1;
      _progressFinished = true;
      if (widget.ready) _notifyCompleted();
      return;
    }
    if (!_progressFinished && !_progressController.isAnimating) {
      _progressController.forward();
    }
    _tryStartCompletion();
  }

  void _handleProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _progressFinished = true;
    _tryStartCompletion();
  }

  void _tryStartCompletion() {
    if (!mounted ||
        widget.preview ||
        !widget.ready ||
        !_progressFinished ||
        _completionStarted ||
        _completionNotified) {
      return;
    }
    if (!_shouldAnimate) {
      _notifyCompleted();
      return;
    }
    _completionStarted = true;
    _completionController.forward();
  }

  void _handleCompletionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _notifyCompleted();
  }

  void _notifyCompleted() {
    if (_completionNotified) return;
    _completionNotified = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCompleted?.call();
    });
  }

  String _messageFor(double progress) {
    if (widget.preview || progress < 0.33) return _messages[0];
    if (progress < 0.66) return _messages[1];
    if (progress < 1) return _messages[2];
    return widget.completionSucceeded
        ? _messages[3]
        : "Couldn't prepare your migration plan";
  }

  @override
  void dispose() {
    _progressController
      ..removeStatusListener(_handleProgressStatus)
      ..dispose();
    _completionController
      ..removeStatusListener(_handleCompletionStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = Listenable.merge([
      _progressController,
      _completionController,
    ]);

    return Scaffold(
      key: const ValueKey('mobile_ironwood_migration_analyzing'),
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final progressTop = constraints.maxHeight * 0.273;
            final messageTop = constraints.maxHeight * 0.46;
            return Stack(
              children: [
                Positioned(
                  top: progressTop,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: motion,
                      builder: (context, _) {
                        final value = widget.preview
                            ? _migrationAnalysisPreviewProgress
                            : _completionStarted ||
                                  _completionController.value > 0
                            ? _completionProgress.value
                            : _progress.value;
                        final scale = widget.preview
                            ? 1.0
                            : _completionScale.value;
                        return Transform.scale(
                          scaleY: scale,
                          child: _MobileMigrationProgressTrack(
                            key: const ValueKey(
                              'mobile_ironwood_migration_analysis_progress',
                            ),
                            value: value,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: messageTop,
                  left: 28,
                  right: 28,
                  child: AnimatedBuilder(
                    animation: motion,
                    builder: (context, _) {
                      final progress = widget.preview
                          ? _migrationAnalysisPreviewProgress
                          : _completionStarted ||
                                _completionController.value > 0
                          ? _completionProgress.value
                          : _progress.value;
                      final title = _messageFor(progress);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: AnimatedSwitcher(
                              duration: widget.preview || !_shouldAnimate
                                  ? Duration.zero
                                  : const Duration(milliseconds: 350),
                              switchInCurve: _migrationAnalysisEaseOut,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                final offset = Tween<Offset>(
                                  begin: const Offset(0, 0.35),
                                  end: Offset.zero,
                                ).animate(animation);
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: offset,
                                    child: child,
                                  ),
                                );
                              },
                              child: IronwoodMigrationShimmerText(
                                key: ValueKey(title),
                                text: title,
                                style: AppTypography.headlineSmall.copyWith(
                                  letterSpacing: 0,
                                  fontWeight: FontWeight.w500,
                                ),
                                baseColor: colors.text.secondary,
                                highlightColor: colors.text.accent,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Vizor is working hard to find a perfect balance of '
                            'safety, privacy, and speed for your migration',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.secondary,
                              height: 25 / 16,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
