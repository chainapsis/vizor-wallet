import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Divider, Scaffold, VerticalDivider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/network_config.dart';
import '../../../../core/formatting/sync_status_label.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../models/ironwood_migration_presentation.dart';
import '../../providers/ironwood_migration_announcement_provider.dart';
import '../../providers/ironwood_migration_coordinator_provider.dart';
import '../../services/ironwood_migration_service.dart';
import '../../widgets/ironwood_migration_shimmer_text.dart';
import '../ironwood_migration_flow_screen.dart';

part 'mobile_ironwood_migration_status_widgets.dart';
part 'mobile_ironwood_migration_step_widgets.dart';

enum MobileIronwoodMigrationStep {
  intro,
  howItWorks,
  options,
  privateReview,
  fastReview,
  preparing,
  migrating,
}

enum MobileIronwoodMigrationReviewPreviewStage {
  analyzing,
  animatedAnalyzing,
  review,
}

const _migrationProgress = 60 / 196;
const _migrationAnalysisPreviewProgress = 72 / 196;
const _migrationAnalysisProgressDuration = Duration(milliseconds: 2745);
const _migrationAnalysisCompletionDuration = Duration(milliseconds: 575);
const _migrationAnalysisTransitionDuration = Duration(milliseconds: 420);
const _migrationAnalysisEaseOut = Cubic(0.23, 1, 0.32, 1);

class _MigrationAnalysisProgressStep {
  const _MigrationAnalysisProgressStep({
    required this.target,
    required this.rampMilliseconds,
    required this.pauseMilliseconds,
  });

  final double target;
  final int rampMilliseconds;
  final int pauseMilliseconds;
}

const _migrationAnalysisProgressSteps = [
  _MigrationAnalysisProgressStep(
    target: 0.15,
    rampMilliseconds: 300,
    pauseMilliseconds: 75,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.40,
    rampMilliseconds: 285,
    pauseMilliseconds: 45,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.47,
    rampMilliseconds: 165,
    pauseMilliseconds: 225,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.63,
    rampMilliseconds: 315,
    pauseMilliseconds: 90,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.71,
    rampMilliseconds: 150,
    pauseMilliseconds: 255,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.86,
    rampMilliseconds: 270,
    pauseMilliseconds: 120,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.97,
    rampMilliseconds: 285,
    pauseMilliseconds: 165,
  ),
];

class MobileIronwoodMigrationFlowScreen extends ConsumerWidget {
  const MobileIronwoodMigrationFlowScreen({
    required this.step,
    this.previewData,
    this.previewPrivatePlan,
    this.previewStatus,
    this.previewReviewStage = MobileIronwoodMigrationReviewPreviewStage.review,
    this.previewParts,
    this.previewRecoveryRequired = false,
    super.key,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData? previewData;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final rust_sync.MigrationStatus? previewStatus;
  final MobileIronwoodMigrationReviewPreviewStage previewReviewStage;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final bool previewRecoveryRequired;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewData;
    if (preview != null) {
      return _MobileIronwoodMigrationContent(
        step: step,
        data: preview,
        previewMode: true,
        previewPrivatePlan: previewPrivatePlan,
        previewReviewStage: previewReviewStage,
        previewParts: previewParts,
        previewRecoveryRequired: previewRecoveryRequired,
        status: previewStatus,
      );
    }

    final data = ref.watch(ironwoodMigrationFlowDataProvider);
    if (data == null) return const _MobileMigrationRedirectHome();
    return _MobileIronwoodMigrationContent(
      step: step,
      data: data,
      previewMode: false,
      previewPrivatePlan: previewPrivatePlan,
      previewReviewStage: previewReviewStage,
      previewParts: previewParts,
      previewRecoveryRequired: false,
      status: null,
    );
  }
}

class _MobileIronwoodMigrationContent extends ConsumerWidget {
  const _MobileIronwoodMigrationContent({
    required this.step,
    required this.data,
    required this.previewMode,
    required this.previewPrivatePlan,
    required this.previewReviewStage,
    required this.previewParts,
    required this.previewRecoveryRequired,
    this.status,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData data;
  final bool previewMode;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final MobileIronwoodMigrationReviewPreviewStage previewReviewStage;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final bool previewRecoveryRequired;
  final rust_sync.MigrationStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHardware =
        !previewMode &&
        (ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false);
    return switch (step) {
      MobileIronwoodMigrationStep.intro => _MobileMigrationIntro(data: data),
      MobileIronwoodMigrationStep.howItWorks =>
        const _MobileMigrationHowItWorks(),
      MobileIronwoodMigrationStep.options => _MobileMigrationOptions(
        allowPreviewSelection: previewMode,
      ),
      MobileIronwoodMigrationStep.privateReview =>
        _MobileMigrationPrivateReview(
          data: data,
          previewPlan: previewPrivatePlan,
          isHardware: isHardware,
          previewStage: previewReviewStage,
        ),
      MobileIronwoodMigrationStep.fastReview => _MobileMigrationFastReview(
        data: data,
        previewMode: previewMode,
      ),
      MobileIronwoodMigrationStep.preparing => _MobileMigrationPreparing(
        data: data,
        status: status,
        previewPlan: previewPrivatePlan,
        isHardware: isHardware,
      ),
      MobileIronwoodMigrationStep.migrating => _MobileMigrationMigrating(
        data: data,
        status: status,
        previewPlan: previewPrivatePlan,
        previewParts: previewParts,
        enableRecovery: !previewMode,
        forceRecoveryPreview: previewMode && previewRecoveryRequired,
      ),
    };
  }
}

class MobileIronwoodMigrationPrivateStatusScreen extends ConsumerWidget {
  const MobileIronwoodMigrationPrivateStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctaAsync = ref.watch(ironwoodMigrationRouteCtaProvider);
    final data = ref.watch(ironwoodMigrationFlowDataProvider);

    return ctaAsync.when(
      skipLoadingOnReload: true,
      loading: () => const _MobileMigrationLoadingScreen(),
      error: (_, _) => const _MobileMigrationRedirectHome(),
      data: (cta) {
        if (cta.mode == IronwoodHomeMigrationCtaMode.start) {
          return const _MobileMigrationRedirectTo('/migration/intro');
        }
        final status = cta.status;
        final accountUuid = cta.accountUuid;
        if (cta.mode != IronwoodHomeMigrationCtaMode.resume ||
            status == null ||
            accountUuid == null ||
            !_hasMobileMigrationStatusDesign(status.phase)) {
          return const _MobileMigrationRedirectHome();
        }

        if (data == null) return const _MobileMigrationRedirectHome();
        return _MobileMigrationLiveStatus(
          data: data,
          status: status,
          isHardware:
              ref.watch(accountProvider).value?.activeAccount?.isHardware ??
              false,
        );
      },
    );
  }
}

bool _hasMobileMigrationStatusDesign(String phase) {
  return phase == kIronwoodMigrationWaitingDenomConfirmationsPhase ||
      phase == kIronwoodMigrationReadyToMigratePhase ||
      phase == kIronwoodMigrationBroadcastScheduledPhase ||
      phase == kIronwoodMigrationBroadcastingPhase ||
      phase == kIronwoodMigrationWaitingConfirmationsPhase;
}

class _MobileMigrationLiveStatus extends StatelessWidget {
  const _MobileMigrationLiveStatus({
    required this.data,
    required this.status,
    required this.isHardware,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;
  final bool isHardware;

  @override
  Widget build(BuildContext context) {
    if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return _MobileMigrationPreparing(
        data: data,
        status: status,
        isHardware: isHardware,
      );
    }
    if (status.phase == kIronwoodMigrationReadyToMigratePhase && isHardware) {
      return _MobileKeystoneMigrationReady(data: data, status: status);
    }
    return _MobileMigrationMigrating(
      data: data,
      status: status,
      previewPlan: null,
      previewParts: null,
      enableRecovery: true,
    );
  }
}

class _MobileMigrationIntro extends StatelessWidget {
  const _MobileMigrationIntro({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Transform.translate(
              offset: const Offset(0, 20),
              child: MobileTopNav.back(
                title: 'Zcash Network Update',
                titleStyle: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                ),
                onBack: () => context.go('/home'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  30,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 172,
                      child: _MobilePoolMigrationHero(data: data),
                    ),
                    const SizedBox(height: 46),
                    SvgPicture.asset(
                      'assets/illustrations/ironwood_wordmark.svg',
                      key: const ValueKey('mobile_ironwood_wordmark'),
                      width: 273,
                      height: 37,
                      colorFilter: ColorFilter.mode(
                        colors.text.accent,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'A new shielded pool for Zcash.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Your ${data.amountText} ZEC is currently in Orchard. '
                      'To keep using these funds for shielded payments, '
                      "you'll need to move them to Ironwood. You'll review "
                      'the migration plan before any funds move.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.muted,
                        height: 24 / 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    expand: true,
                    height: 50,
                    onPressed: () => _openIronwoodReleaseNotes(),
                    leading: const AppIcon(AppIcons.link, size: 18),
                    child: const Text('Official release note'),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppButton(
                    key: const ValueKey(
                      'mobile_ironwood_intro_continue_button',
                    ),
                    expand: true,
                    height: 50,
                    onPressed: () => context.go('/migration/how-it-works'),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationHowItWorks extends StatelessWidget {
  const _MobileMigrationHowItWorks();

  @override
  Widget build(BuildContext context) {
    return _MobileMigrationStepScaffold(
      onBack: () => context.go('/migration/intro'),
      topGap: 31,
      childGap: 32,
      title: 'How Migration Works',
      bottom: _MobileMigrationPrimaryButton(
        key: const ValueKey('mobile_ironwood_steps_continue_button'),
        label: 'Continue',
        onPressed: () => context.go('/migration/options'),
      ),
      child: const _MobileMigrationProcessCard(),
    );
  }
}

enum _MobileMigrationOption { private, immediate }

class _MobileMigrationOptions extends StatefulWidget {
  const _MobileMigrationOptions({required this.allowPreviewSelection});

  final bool allowPreviewSelection;

  @override
  State<_MobileMigrationOptions> createState() =>
      _MobileMigrationOptionsState();
}

class _MobileMigrationOptionsState extends State<_MobileMigrationOptions> {
  var _selectedOption = _MobileMigrationOption.private;

  void _select(_MobileMigrationOption option) {
    if (!widget.allowPreviewSelection || _selectedOption == option) return;
    setState(() => _selectedOption = option);
  }

  @override
  Widget build(BuildContext context) {
    final privateSelected = _selectedOption == _MobileMigrationOption.private;
    final immediateSelected =
        _selectedOption == _MobileMigrationOption.immediate;
    return _MobileMigrationStepScaffold(
      onBack: () => context.go('/migration/how-it-works'),
      topGap: 91,
      childGap: 24,
      title: 'Choose How to Migrate',
      subtitle:
          'Choose between more privacy over time or a faster migration. '
          'You can review the details before anything moves.',
      bottom: _MobileMigrationPrimaryButton(
        key: const ValueKey('mobile_ironwood_options_continue_button'),
        label: 'Continue',
        onPressed: () => context.go('/migration/private/review'),
      ),
      child: Column(
        children: [
          _MobileMigrationOptionCard(
            key: const ValueKey('mobile_ironwood_private_option'),
            title: 'Private',
            body: 'Sends independent parts over time',
            selected: privateSelected,
            icon: _MigrationChoiceIcon.private,
            recommended: true,
            onTap: widget.allowPreviewSelection
                ? () => _select(_MobileMigrationOption.private)
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileMigrationOptionCard(
            key: const ValueKey('mobile_ironwood_immediate_unavailable'),
            title: 'Immediate',
            body: 'Sends now in one step.',
            selected: immediateSelected,
            icon: _MigrationChoiceIcon.immediate,
            enabled: widget.allowPreviewSelection,
            onTap: widget.allowPreviewSelection
                ? () => _select(_MobileMigrationOption.immediate)
                : null,
          ),
        ],
      ),
    );
  }
}

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

class _MobileMigrationPrivateReview extends ConsumerStatefulWidget {
  const _MobileMigrationPrivateReview({
    required this.data,
    required this.previewPlan,
    required this.isHardware,
    required this.previewStage,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final bool isHardware;
  final MobileIronwoodMigrationReviewPreviewStage previewStage;

  @override
  ConsumerState<_MobileMigrationPrivateReview> createState() =>
      _MobileMigrationPrivateReviewState();
}

class _MobileMigrationPrivateReviewState
    extends ConsumerState<_MobileMigrationPrivateReview> {
  bool _analysisComplete = false;
  bool _isStarting = false;
  String? _startError;

  void _handleAnalysisCompleted() {
    if (_analysisComplete || !mounted) return;
    setState(() => _analysisComplete = true);
  }

  Future<void> _startMigration(
    rust_sync.OrchardMigrationPrivatePlan plan,
  ) async {
    if (_isStarting) return;
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
      final statusRequest = IronwoodMigrationStatusRequest(
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

      await ref
          .read(ironwoodMigrationServiceProvider)
          .startSoftwarePrivateMigration(
            accountUuid: accountUuid,
            approvedSchedule: plan.scheduledTransfers,
          );
      if (!mounted) return;
      ref.invalidate(ironwoodMigrationStatusProvider(statusRequest));
      final startedStatus = await ref.read(
        ironwoodMigrationStatusProvider(statusRequest).future,
      );
      if (!mounted) return;
      if (startedStatus.activeRunId == null) {
        throw StateError('Migration did not create an active run.');
      }
      ref.invalidate(ironwoodMigrationRouteCtaProvider);
      ref.invalidate(ironwoodHomeMigrationCtaProvider);
      ref.invalidate(ironwoodMigrationFlowDataProvider);
      ref.invalidate(ironwoodMigrationPrivatePlanProvider);
      context.go('/migration/private/status');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startError = _mobilePrivateMigrationStartErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.previewPlan;
    final planAsync = preview != null
        ? AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.data(preview)
        : ref.watch(ironwoodMigrationPrivatePlanProvider);
    final staticAnalysisPreview =
        widget.previewStage ==
        MobileIronwoodMigrationReviewPreviewStage.analyzing;
    final animatedAnalysisPreview =
        widget.previewStage ==
        MobileIronwoodMigrationReviewPreviewStage.animatedAnalyzing;
    final awaitingInitialPlan = planAsync.isLoading && !planAsync.hasValue;
    final plan = planAsync.hasValue ? planAsync.value : null;
    final showAnalyzing =
        staticAnalysisPreview ||
        (animatedAnalysisPreview && !_analysisComplete) ||
        (preview == null && (!_analysisComplete || awaitingInitialPlan));
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final Widget child;
    if (showAnalyzing) {
      child = _MobileMigrationAnalyzing(
        key: const ValueKey('mobile_ironwood_migration_analysis_stage'),
        preview: staticAnalysisPreview,
        ready: !awaitingInitialPlan,
        completionSucceeded: plan != null,
        onCompleted: staticAnalysisPreview ? null : _handleAnalysisCompleted,
      );
    } else {
      final keystonePlanSupported =
          !widget.isHardware ||
          plan == null ||
          _keystoneTwoRoundPlanSupported(plan);
      final canStart = plan != null && !_isStarting && keystonePlanSupported;

      child = KeyedSubtree(
        key: const ValueKey('mobile_ironwood_migration_review_stage'),
        child: _MobilePrivateReviewScaffold(
          onBack: () => context.go('/migration/options'),
          bottom: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_startError != null) ...[
                Text(
                  _startError!,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: context.colors.text.destructive,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              if (!keystonePlanSupported) ...[
                Text(
                  'This migration needs more transactions than one Keystone '
                  'signing request supports.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: context.colors.text.destructive,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              _MobileMigrationPrimaryButton(
                key: const ValueKey('mobile_ironwood_authorize_start_button'),
                label: _isStarting
                    ? 'Preparing...'
                    : widget.isHardware
                    ? 'Continue with Keystone'
                    : 'Start migration',
                onPressed: canStart
                    ? preview != null
                          ? () {}
                          : () => _startMigration(plan)
                    : null,
              ),
            ],
          ),
          child: plan == null
              ? const _MobileMigrationUnavailable()
              : _MobilePrivatePlan(
                  plan: plan,
                  arrivalLabel: _migrationArrivalLabel(plan),
                ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: disableAnimations
          ? Duration.zero
          : _migrationAnalysisTransitionDuration,
      reverseDuration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 280),
      switchInCurve: _migrationAnalysisEaseOut,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: child,
    );
  }
}

bool _keystoneTwoRoundPlanSupported(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final limit = plan.signingBatchLimit;
  if (limit <= 0) return false;
  return plan.denominationSplitStageCount <= limit &&
      plan.plannedBatchCount <= limit;
}

String _mobilePrivateMigrationStartErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('mnemonic')) {
    return "Secret Passphrase isn't available for this account.";
  }
  if (message.contains('secret storage') ||
      message.contains('unlocked session')) {
    return 'Unlock Vizor before starting migration.';
  }
  if (message.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (message.contains('broadcast') || message.contains('sendtransaction')) {
    return "Couldn't broadcast the migration transaction. Try again.";
  }
  return "Couldn't start migration. Try again.";
}

class _MobileMigrationFastReview extends StatefulWidget {
  const _MobileMigrationFastReview({
    required this.data,
    required this.previewMode,
  });

  final IronwoodMigrationFlowData data;
  final bool previewMode;

  @override
  State<_MobileMigrationFastReview> createState() =>
      _MobileMigrationFastReviewState();
}

class _MobileMigrationFastReviewState
    extends State<_MobileMigrationFastReview> {
  late bool _acknowledged = widget.previewMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _MobileMigrationReviewScaffold(
      onBack: () => context.go('/migration/options'),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            variant: AppButtonVariant.ghost,
            expand: true,
            height: 44,
            onPressed: () => context.go('/migration/options'),
            leading: const AppIcon(AppIcons.chevronBackward, size: 20),
            child: const Text('Consider another option'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            variant: AppButtonVariant.destructive,
            expand: true,
            height: 50,
            onPressed: _acknowledged && widget.previewMode ? () {} : null,
            leading: const AppIcon(AppIcons.warning, size: 20),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 153,
            child: _MobileReviewCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  _ReviewRow(
                    label: 'Amount',
                    value: '${widget.data.amountText} ZEC',
                    height: 32,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const _ReviewRow(
                    label: 'Fees (estimate)',
                    value: 'shown before send',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const _ReviewRow(
                    label: 'Migration complete in',
                    value: '~5 mins',
                    showInfo: true,
                    height: 32,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            key: const ValueKey('mobile_ironwood_fast_privacy_card'),
            height: 189,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.homeCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colors.border.inverseOpacity,
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.base,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(
                      AppIcons.transparentBalance,
                      key: const ValueKey('mobile_ironwood_fast_privacy_icon'),
                      size: 20,
                      color: colors.text.homeCard,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Privacy trade-off',
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.homeCard,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text.rich(
                            TextSpan(
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.homeCard,
                                letterSpacing: 0,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      'Crosses in one visible step — your '
                                      '${widget.data.amountText} ZEC and '
                                      'timing are ',
                                ),
                                const TextSpan(
                                  text: 'easier to associate with your wallet',
                                  style: TextStyle(color: Color(0xFFC06ECE)),
                                ),
                                const TextSpan(text: '. '),
                                const TextSpan(
                                  text:
                                      'Consider choosing a Private Migration '
                                      'option.',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            checked: _acknowledged,
            button: true,
            child: GestureDetector(
              key: const ValueKey('mobile_ironwood_fast_acknowledgement'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _acknowledged = !_acknowledged),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _acknowledged
                          ? colors.button.destructive.bg
                          : colors.background.ground,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _acknowledged
                            ? colors.button.destructive.bg
                            : colors.border.regular,
                      ),
                    ),
                    child: _acknowledged
                        ? AppIcon(
                            AppIcons.check,
                            size: 14,
                            color: colors.button.destructive.label,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      'I understand that this migration’s amount and timing '
                      'will be visible on the Zcash network.',
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationPreparing extends StatelessWidget {
  const _MobileMigrationPreparing({
    required this.data,
    required this.isHardware,
    this.status,
    this.previewPlan,
  });

  final IronwoodMigrationFlowData data;
  final bool isHardware;
  final rust_sync.MigrationStatus? status;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final partCount = _mobilePlannedBatchCount(
      status,
      previewPlan: previewPlan,
    );
    final confirmationCount = status?.denominationConfirmationCount ?? 0;
    final confirmationTarget = status?.denominationConfirmationTarget ?? 0;
    final parts = _mobilePreparingPartPresentations(
      status: status,
      previewPlan: previewPlan,
    );
    final totalAmount = _mobileMigrationTotalAmountText(
      status,
      previewPlan: previewPlan,
      fallback: data.amountText,
    );
    final compact = MediaQuery.sizeOf(context).height < 650;
    return _MobileMigrationStatusScaffold(
      key: const ValueKey('mobile_ironwood_migration_status_preparing'),
      data: data,
      showAccountNav: false,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.s,
      ),
      child: Column(
        children: [
          SizedBox(height: compact ? 28 : 81),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  Text(
                    'Migration in Progress',
                    key: const ValueKey(
                      'mobile_ironwood_migration_preparing_title',
                    ),
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 300,
                    child: Text(
                      'Preparing your balance for migration. This step usually '
                      'takes 10-20 mins.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 39),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: AppTypography.bodyLarge.copyWith(
                              color: colors.text.accent,
                              fontWeight: FontWeight.w600,
                            ),
                            children: [
                              const TextSpan(text: 'Migration '),
                              TextSpan(
                                text: '$partCount notes',
                                style: TextStyle(color: colors.text.secondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xxs),
                        child: Text(
                          '$totalAmount ZEC',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MobileMigrationStatusRail(parts: parts),
                  const SizedBox(height: AppSpacing.base),
                  _MobileIronwoodWaitingStatusCard(
                    partCount: partCount,
                    confirmedConfirmations: confirmationCount,
                    confirmationTarget: confirmationTarget,
                    requiresKeystoneApproval: isHardware,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _MobileStatusBackHomeButton(
            label: 'Go home',
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
    );
  }
}

class _MobileKeystoneMigrationReady extends StatelessWidget {
  const _MobileKeystoneMigrationReady({
    required this.data,
    required this.status,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final batchCount = _mobilePlannedBatchCount(status);
    final transactionLabel = batchCount == 1
        ? '1 migration transaction'
        : '$batchCount migration transactions';
    return _MobileMigrationStatusScaffold(
      key: const ValueKey('mobile_ironwood_keystone_ready'),
      data: data,
      child: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.s),
                const AppIcon(AppIcons.qr, size: 40),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Ready for Keystone',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'The split transactions are confirmed. Use Keystone again to '
                  'approve the Ironwood migration transactions.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                _MobileStatusCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF00A460),
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(
                              dimension: 20,
                              child: Center(
                                child: AppIcon(
                                  AppIcons.check,
                                  size: 14,
                                  color: Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          const Expanded(
                            child: Text('Split transactions confirmed'),
                          ),
                        ],
                      ),
                      const Divider(height: AppSpacing.lg),
                      Text(
                        'Keystone approval',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '$transactionLabel ready to sign',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                AppButton(
                  key: const ValueKey(
                    'mobile_ironwood_keystone_batch_sign_button',
                  ),
                  expand: true,
                  onPressed: () =>
                      context.go('/migration/private/keystone/batch/sign'),
                  child: const Text('Continue'),
                ),
                const SizedBox(height: AppSpacing.xs),
                _MobileStatusBackHomeButton(
                  onPressed: () => context.go('/home'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationMigrating extends ConsumerStatefulWidget {
  const _MobileMigrationMigrating({
    required this.data,
    required this.previewPlan,
    required this.previewParts,
    this.enableRecovery = false,
    this.forceRecoveryPreview = false,
    this.status,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final rust_sync.MigrationStatus? status;
  final bool enableRecovery;
  final bool forceRecoveryPreview;

  @override
  ConsumerState<_MobileMigrationMigrating> createState() =>
      _MobileMigrationMigratingState();
}

class _MobileMigrationMigratingState
    extends ConsumerState<_MobileMigrationMigrating> {
  bool _schedulingBackgroundRetry = false;
  bool _backgroundRetryScheduled = false;
  String? _recoveryError;

  Future<void> _sendOneDue(String accountUuid) async {
    setState(() => _recoveryError = null);
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .sendOneDue(accountUuid);
    } catch (_) {
      if (mounted) {
        setState(() {
          _recoveryError = "Couldn't send the transfer. Try again.";
        });
      }
    }
  }

  Future<void> _retryInBackground(String accountUuid) async {
    setState(() {
      _schedulingBackgroundRetry = true;
      _recoveryError = null;
    });
    try {
      final scheduled = await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retryInBackground(accountUuid);
      if (!mounted) return;
      setState(() {
        _backgroundRetryScheduled = scheduled;
        if (!scheduled) {
          _recoveryError = "Couldn't schedule a background retry.";
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _recoveryError = "Couldn't schedule a background retry.";
        });
      }
    } finally {
      if (mounted) setState(() => _schedulingBackgroundRetry = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final colors = context.colors;
    final totalAmount = _mobileMigrationTotalAmountText(
      status,
      previewPlan: widget.previewPlan,
      fallback: widget.data.amountText,
    );
    final parts = _mobileMigrationPartPresentations(
      status: status,
      previewPlan: widget.previewPlan,
      explicitParts: widget.previewParts,
    );
    final partCount = parts.isNotEmpty
        ? parts.length
        : _mobilePlannedBatchCount(status, previewPlan: widget.previewPlan);
    final completion = status == null
        ? widget.previewPlan == null
              ? 'Schedule pending'
              : _migrationArrivalLabel(widget.previewPlan!)
        : migrationCompletionTimingLabel(status);
    final spendable = _mobileSpendableAmountText(status);
    final compact = MediaQuery.sizeOf(context).height < 650;
    final syncState = widget.enableRecovery
        ? ref.watch(syncProvider).value
        : null;
    final accountUuid = widget.enableRecovery
        ? ref.watch(accountProvider).value?.activeAccountUuid
        : null;
    final recoveryRequired =
        widget.forceRecoveryPreview ||
        (status != null &&
            _hasDueMobileMigrationTransfer(
              status,
              currentHeight: _mobileMigrationHeight(syncState),
            ));
    final coordinator = widget.enableRecovery
        ? ref.watch(ironwoodMigrationCoordinatorProvider)
        : const IronwoodMigrationCoordinatorState();
    final supportsBackgroundRetry =
        widget.forceRecoveryPreview ||
        (widget.enableRecovery &&
            ref
                .read(ironwoodMigrationServiceProvider)
                .supportsBackgroundMigrationRetry);
    final sending =
        accountUuid != null &&
        coordinator.advancingAccounts.contains(accountUuid);
    final partsContent = parts.isEmpty
        ? Center(
            child: Text(
              'Migration parts will appear as transactions are prepared.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          )
        : _MobileIronwoodActiveStatus(parts: parts);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: compact ? 20 : 46),
        Text(
          'Migration in Progress',
          textAlign: TextAlign.center,
          style: AppTypography.headlineLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: compact ? AppSpacing.md : 44),
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    const TextSpan(text: 'Migration '),
                    TextSpan(
                      text: '$partCount notes',
                      style: TextStyle(color: colors.text.secondary),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xxs),
              child: Text(
                '$totalAmount ZEC',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? AppSpacing.xs : 3),
        if (compact)
          SizedBox(
            height: math.min(156, math.max(72, parts.length * 52).toDouble()),
            child: partsContent,
          )
        else
          SizedBox(height: recoveryRequired ? 180 : 331, child: partsContent),
        SizedBox(height: compact || recoveryRequired ? AppSpacing.s : 52),
        _ReviewRow(label: 'Est. completion', value: completion),
        const SizedBox(height: AppSpacing.xs),
        _ReviewRow(
          label: 'Currently spendable balance',
          value: spendable == '-' ? spendable : '$spendable ZEC',
        ),
        const SizedBox(height: AppSpacing.md),
        if (recoveryRequired &&
            (widget.forceRecoveryPreview || accountUuid != null))
          _MobileMigrationRecoveryCard(
            sending: sending,
            schedulingBackground: _schedulingBackgroundRetry,
            backgroundRetryScheduled: _backgroundRetryScheduled,
            error: _recoveryError ?? coordinator.errors[accountUuid],
            supportsBackgroundRetry: supportsBackgroundRetry,
            onSendOne: widget.forceRecoveryPreview
                ? () {}
                : () => unawaited(_sendOneDue(accountUuid!)),
            onRetryInBackground: widget.forceRecoveryPreview
                ? () {}
                : () => unawaited(_retryInBackground(accountUuid!)),
          )
        else
          const _MigrationCanLeaveMessage(),
        SizedBox(height: compact || recoveryRequired ? AppSpacing.md : 38),
        Transform.translate(
          offset: Offset(0, compact || recoveryRequired ? 0 : 14),
          child: _MobileStatusBackHomeButton(
            key: const ValueKey('mobile_ironwood_status_back_home_button'),
            label: 'Go home',
            onPressed: () => context.go('/home'),
          ),
        ),
      ],
    );
    return _MobileMigrationStatusScaffold(
      key: const ValueKey('mobile_ironwood_migration_status_migrating'),
      data: widget.data,
      showAccountNav: false,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.s,
      ),
      child: compact || recoveryRequired
          ? SingleChildScrollView(child: body)
          : body,
    );
  }
}

int _mobileMigrationHeight(SyncState? syncState) {
  if (syncState == null) return 0;
  if (syncState.scannedHeight > 0 && syncState.chainTipHeight > 0) {
    return math.min(syncState.scannedHeight, syncState.chainTipHeight);
  }
  return math.max(syncState.scannedHeight, syncState.chainTipHeight);
}

bool _hasDueMobileMigrationTransfer(
  rust_sync.MigrationStatus status, {
  required int currentHeight,
}) {
  if (currentHeight <= 0) return false;
  return status.scheduledBroadcasts.any((broadcast) {
    if (broadcast.status.toLowerCase() != 'scheduled') return false;
    if (broadcast.scheduledHeight <= 0) return false;
    return broadcast.scheduledHeight + kIronwoodMigrationLateGraceBlocks <=
        currentHeight;
  });
}

class _MobileMigrationUnavailable extends StatelessWidget {
  const _MobileMigrationUnavailable();

  @override
  Widget build(BuildContext context) {
    return _MobileReviewCard(
      child: Text(
        'Migration review is not available yet. Wait for sync to finish and '
        'try again.',
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}

class _MobileMigrationLoadingScreen extends StatelessWidget {
  const _MobileMigrationLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: const SafeArea(
        child: Column(
          children: [
            MobileTopNav.steps(
              progress: _migrationProgress,
              showBackButton: false,
            ),
            Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationRedirectTo extends StatefulWidget {
  const _MobileMigrationRedirectTo(this.location);

  final String location;

  @override
  State<_MobileMigrationRedirectTo> createState() =>
      _MobileMigrationRedirectToState();
}

class _MobileMigrationRedirectToState
    extends State<_MobileMigrationRedirectTo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(widget.location);
    });
  }

  @override
  Widget build(BuildContext context) => const _MobileMigrationLoadingScreen();
}

class _MobileMigrationRedirectHome extends StatefulWidget {
  const _MobileMigrationRedirectHome();

  @override
  State<_MobileMigrationRedirectHome> createState() =>
      _MobileMigrationRedirectHomeState();
}

class _MobileMigrationRedirectHomeState
    extends State<_MobileMigrationRedirectHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) => const _MobileMigrationLoadingScreen();
}

String _compactZec(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(zatoshi).balance.amountText;
}

String _migrationArrivalLabel(rust_sync.OrchardMigrationPrivatePlan plan) {
  return migrationPlanCompletionLabel(plan);
}

Future<void> _openIronwoodReleaseNotes() async {
  await launchUrl(
    Uri.parse(kIronwoodMigrationReleaseNotesUrl),
    mode: LaunchMode.externalApplication,
  );
}
