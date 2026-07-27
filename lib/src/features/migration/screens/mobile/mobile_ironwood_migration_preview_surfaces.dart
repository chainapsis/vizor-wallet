part of 'mobile_ironwood_migration_flow_screen.dart';

void _noopMigrationPreviewAction() {}

const _keystonePreparationSignatureMessage =
    'Sign the preparation transaction on Keystone.';

class _MobileIronwoodMigrationPreviewSurface extends StatelessWidget {
  const _MobileIronwoodMigrationPreviewSurface({
    required this.surface,
    required this.data,
  });

  final MobileIronwoodMigrationPreviewSurface surface;
  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    return switch (surface) {
      MobileIronwoodMigrationPreviewSurface.notificationsPrompt =>
        const _MigrationNotificationPromptPreview(),
      MobileIronwoodMigrationPreviewSurface.notificationsConfirmation =>
        const _MigrationNotificationPromptPreview(showConfirmation: true),
      MobileIronwoodMigrationPreviewSurface.preparationActive =>
        const _MigrationPreparationPreview(
          state: _MigrationPreparationState.active,
        ),
      MobileIronwoodMigrationPreviewSurface.preparationPaused =>
        _MigrationPreparationPreview(
          state: _MigrationPreparationState.paused,
          onContinue: _noopMigrationPreviewAction,
        ),
      MobileIronwoodMigrationPreviewSurface.preparationPausedKeystone =>
        _MigrationPreparationPreview(
          state: _MigrationPreparationState.paused,
          isKeystone: true,
          pausedMessage: _keystonePreparationSignatureMessage,
          onContinue: _noopMigrationPreviewAction,
        ),
      MobileIronwoodMigrationPreviewSurface.preparationSyncing =>
        const _MigrationPreparationPreview(
          state: _MigrationPreparationState.syncing,
        ),
      MobileIronwoodMigrationPreviewSurface.syncing =>
        const _MigrationProgressPreview(state: _MigrationProgressState.syncing),
      MobileIronwoodMigrationPreviewSurface.preparationCompleteModal =>
        const _MigrationProgressPreview(
          state: _MigrationProgressState.waitingNotificationsOn,
          showPreparationCompleteModal: true,
        ),
      MobileIronwoodMigrationPreviewSurface.migrationWaitingNotificationsOn =>
        const _MigrationProgressPreview(
          state: _MigrationProgressState.waitingNotificationsOn,
        ),
      MobileIronwoodMigrationPreviewSurface.migrationWaitingNotificationsOff =>
        const _MigrationProgressPreview(
          state: _MigrationProgressState.waitingNotificationsOff,
        ),
      MobileIronwoodMigrationPreviewSurface.migrationNeedsInput =>
        _MigrationProgressPreview(
          state: _MigrationProgressState.needsInput,
          currentSigningPartIndices: {
            for (var index = 0; index < _migrationPartsPerBatch; index++) index,
          },
          migratedAmountText: '777.888 ZEC',
          totalAmountText: '999.999 ZEC',
        ),
      MobileIronwoodMigrationPreviewSurface.migrationKeystoneSignAll =>
        _MigrationProgressPreview(
          state: _MigrationProgressState.needsInput,
          totalParts: 50,
          currentSigningPartIndices: {
            for (var index = 0; index < 50; index++) index,
          },
          migratedAmountText: '0 ZEC',
          totalAmountText: '50 ZEC',
          actionLabel: 'Sign migration transactions',
          actionBatchLabel: 'All transactions',
          actionBatchValue: '50 ZEC (100%)',
        ),
      MobileIronwoodMigrationPreviewSurface.migrationBroadcasting =>
        _MigrationProgressPreview(
          state: _MigrationProgressState.broadcasting,
          totalParts: 8,
          segmentValuesZatoshi: [
            for (final value in const [1, 3, 2, 5, 1, 4, 2, 6])
              BigInt.from(value),
          ],
        ),
      MobileIronwoodMigrationPreviewSurface.migrationComplete =>
        const _MigrationCompletePreview(amountText: '142.992 ZEC'),
      MobileIronwoodMigrationPreviewSurface.homeAttention =>
        const _MigrationHomeAttentionPreview(),
      MobileIronwoodMigrationPreviewSurface.homeAttentionModal =>
        const _MigrationHomeAttentionPreview(showModal: true),
      MobileIronwoodMigrationPreviewSurface.keystoneScanHelp =>
        const _MigrationKeystoneHelpPreview(),
    };
  }
}

class _MigrationPreviewPage extends StatelessWidget {
  const _MigrationPreviewPage({
    required this.navTitle,
    required this.child,
    this.bottom,
    this.contentGap = AppSpacing.sm,
    this.backgroundColor,
    this.backgroundDecoration,
    this.navForegroundColor,
    this.onBack,
    this.scrollableContent = false,
  });

  final String navTitle;
  final Widget child;
  final Widget? bottom;
  final double contentGap;
  final Color? backgroundColor;
  final Decoration? backgroundDecoration;
  final Color? navForegroundColor;
  final VoidCallback? onBack;
  final bool scrollableContent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? context.colors.background.window,
      body: DecoratedBox(
        decoration: backgroundDecoration ?? const BoxDecoration(),
        child: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: navTitle,
                titleStyle: AppTypography.headlineSmall.copyWith(
                  color: navForegroundColor ?? context.colors.text.accent,
                ),
                foregroundColor: navForegroundColor,
                onBack: onBack ?? () {},
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    AppSpacing.s,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: contentGap),
                      Expanded(
                        child: scrollableContent
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  return SingleChildScrollView(
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: IntrinsicHeight(child: child),
                                    ),
                                  );
                                },
                              )
                            : child,
                      ),
                      if (bottom != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        bottom!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileMigrationNotificationPermissionScreen
    extends ConsumerStatefulWidget {
  const _MobileMigrationNotificationPermissionScreen({this.privatePlan});

  final rust_sync.OrchardMigrationPrivatePlan? privatePlan;

  @override
  ConsumerState<_MobileMigrationNotificationPermissionScreen> createState() =>
      _MobileMigrationNotificationPermissionScreenState();
}

class _MobileMigrationNotificationPermissionScreenState
    extends ConsumerState<_MobileMigrationNotificationPermissionScreen> {
  AppLifecycleListener? _lifecycleListener;
  var _busy = false;
  String? _continueError;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _refreshAfterSettings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshAfterSettings());
    });
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  Future<void> _refreshAfterSettings() async {
    if (_busy) return;
    try {
      final status = await ref
          .read(ironwoodMigrationServiceProvider)
          .notificationAuthorizationStatus();
      if (!mounted) return;
      if (status.allowsBackgroundMigration) {
        await _continueAfterNotificationGate();
      }
    } catch (_) {
      // Native status is fail-closed; keep the explanatory screen visible.
    }
  }

  Future<void> _allowNotifications() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(ironwoodMigrationServiceProvider);
      final current = await service.notificationAuthorizationStatus();
      if (!mounted) return;
      final wasDenied =
          current == IronwoodMigrationNotificationAuthorizationStatus.denied;
      final status = wasDenied
          ? current
          : await service.requestNotificationPermission();
      if (!mounted) return;
      if (status.allowsBackgroundMigration) {
        await _continueAfterNotificationGate();
        return;
      }
      if (status == IronwoodMigrationNotificationAuthorizationStatus.denied) {
        if (wasDenied) {
          await service.openNotificationSystemSettings();
        }
      }
    } catch (_) {
      // Keep the Figma surface unchanged when native permission lookup fails.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmNotNow() async {
    if (_busy) return;
    final action = await showAppMobileSheet<_NotificationConfirmationAction>(
      context: context,
      builder: (sheetContext) => MobileModalScaffold(
        title: '',
        showTitle: false,
        showClose: false,
        bottomPadding: AppSpacing.base,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: _MigrationNotificationConfirmationContent(
          busy: _busy,
          onAllow: () => Navigator.of(
            sheetContext,
          ).pop(_NotificationConfirmationAction.allow),
          onContinueWithoutNotifications: () => Navigator.of(
            sheetContext,
          ).pop(_NotificationConfirmationAction.continueWithout),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _NotificationConfirmationAction.allow:
        await _allowNotifications();
        return;
      case _NotificationConfirmationAction.continueWithout:
        await _continueAfterNotificationGate();
        return;
    }
  }

  Future<void> _continueAfterNotificationGate() async {
    final plan = widget.privatePlan;
    if (mounted) {
      setState(() {
        _busy = true;
        _continueError = null;
      });
    }
    var draftSaved = false;
    try {
      if (plan == null) {
        throw StateError('Migration plan is unavailable.');
      }
      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      await ref
          .read(ironwoodMigrationServiceProvider)
          .savePrivateMigrationDraft(
            accountUuid: accountUuid,
            approvedSchedule: plan.scheduledTransfers,
          );
      draftSaved = true;
      if (!mounted) return;
      await _refreshPrivateMigrationDraftPresentation(ref);
      if (!mounted) return;
      final destination = await _continuePrivateMigrationAfterNotificationGate(
        ref,
        plan,
      );
      if (!mounted) return;
      _openPrivateMigrationDestination(context, destination, plan);
    } catch (error) {
      debugPrint('Failed to activate direct-note migration: $error');
      if (!mounted) return;
      if (draftSaved || await _hasDurablePrivateMigrationRun(ref)) {
        if (!mounted) return;
        context.go(
          '/migration/private/status',
          extra: MobileIronwoodMigrationStatusEntry(approvedPlan: plan),
        );
        return;
      }
      setState(() {
        _continueError = "Couldn't start the migration. Try again.";
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _MigrationNotificationPromptPreview(
      busy: _busy,
      errorMessage: _continueError,
      onBack: () => context.go('/migration/options'),
      onAllow: () => unawaited(_allowNotifications()),
      onNotNow: () => unawaited(_confirmNotNow()),
    );
  }
}

enum _NotificationConfirmationAction { allow, continueWithout }

class _MigrationNotificationPromptPreview extends StatelessWidget {
  const _MigrationNotificationPromptPreview({
    this.showConfirmation = false,
    this.onBack,
    this.onAllow,
    this.onNotNow,
    this.busy = false,
    this.errorMessage,
  });

  final bool showConfirmation;
  final VoidCallback? onBack;
  final VoidCallback? onAllow;
  final VoidCallback? onNotNow;
  final bool busy;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final base = _MigrationPreviewPage(
      navTitle: 'Enable notifications',
      backgroundColor: const Color(0xFF007F49),
      navForegroundColor: const Color(0xFFFFFFFF),
      onBack: onBack,
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (errorMessage != null) ...[
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: const Color(0xFFFFFFFF),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          AppButton(
            key: const ValueKey('migration_preview_not_now'),
            variant: AppButtonVariant.ghost,
            expand: true,
            height: 50,
            onPressed: busy ? null : onNotNow ?? () {},
            enabledBackgroundColor: const Color(0x00000000),
            pressedBackgroundColor: const Color(0x1A052C1B),
            enabledLabelColor: const Color(0xFF052C1B),
            pressedLabelColor: const Color(0xFF052C1B),
            child: const Text('Not now'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('migration_preview_allow_notifications'),
            variant: AppButtonVariant.primary,
            expand: true,
            constrainContent: true,
            height: 50,
            onPressed: busy ? null : onAllow ?? () {},
            enabledBackgroundColor: const Color(0xFF052C1B),
            pressedBackgroundColor: GreenPrimitives.p50Dark,
            enabledLabelColor: const Color(0xFFDDEAE4),
            pressedLabelColor: const Color(0xFFDDEAE4),
            enabledBorderColor: const Color(0x1AFFFFFF),
            leading: const AppIcon(AppIcons.notificationBell, size: 20),
            child: Text(busy ? 'Checking...' : 'Allow notifications'),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 480;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  SizedBox(
                    height: compact ? 190 : 280,
                    child: _MigrationNotificationIllustration(
                      size: compact ? 180 : 256,
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: 310,
                      child: Text(
                        'Keep your migration on schedule',
                        textAlign: TextAlign.center,
                        style: AppTypography.displayLarge.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: SizedBox(
                      width: 320,
                      child: Text(
                        'Some migration steps require approval. We’ll notify '
                        'you when it’s time, so you can respond quickly and '
                        'avoid unnecessary delays.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!showConfirmation) return base;
    return _MigrationModalPreview(
      background: base,
      child: _MigrationNotificationConfirmationContent(
        busy: busy,
        onAllow: onAllow ?? () {},
        onContinueWithoutNotifications: () {},
      ),
    );
  }
}

class _MigrationNotificationConfirmationContent extends StatelessWidget {
  const _MigrationNotificationConfirmationContent({
    required this.busy,
    required this.onAllow,
    required this.onContinueWithoutNotifications,
  });

  final bool busy;
  final VoidCallback onAllow;
  final VoidCallback onContinueWithoutNotifications;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AppIcon(
            AppIcons.notificationBell,
            size: 40,
            color: context.colors.icon.success,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Center(
          child: SizedBox(
            width: 260,
            child: Text(
              'Continue without notifications?',
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: context.colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: SizedBox(
            width: 280,
            child: Text(
              'Without notifications, you’ll need to remember to open Vizor '
              'regularly and approve the next migration step when it’s ready.',
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Otherwise, your migration may take longer.',
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        AppButton(
          expand: true,
          constrainContent: true,
          height: 50,
          onPressed: busy ? null : onAllow,
          child: const Text('Allow notifications'),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          expand: true,
          constrainContent: true,
          height: 50,
          variant: AppButtonVariant.ghost,
          onPressed: busy ? null : onContinueWithoutNotifications,
          child: const Text('Continue without notifications'),
        ),
      ],
    );
  }
}

class _MigrationNotificationIllustration extends StatelessWidget {
  const _MigrationNotificationIllustration({this.size = 256});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          'assets/illustrations/ironwood_notification_bell.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

enum _MigrationPreparationState { active, paused, syncing }

class _MigrationPreparationPreview extends StatelessWidget {
  const _MigrationPreparationPreview({
    required this.state,
    this.isKeystone = false,
    this.pausedMessage,
    this.onBack,
    this.onContinue,
  });

  final _MigrationPreparationState state;
  final bool isKeystone;
  final String? pausedMessage;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final paused = state == _MigrationPreparationState.paused;
    return _MigrationPreviewPage(
      navTitle: 'Preparing your migration',
      onBack: onBack,
      contentGap: AppSpacing.base,
      bottom: paused
          ? SizedBox(
              width: double.infinity,
              child: AppButton(
                key: const ValueKey(
                  'mobile_ironwood_preparation_continue_button',
                ),
                expand: true,
                constrainContent: true,
                height: 50,
                onPressed: onContinue,
                leading: AppIcon(
                  isKeystone ? AppIcons.qr : AppIcons.play,
                  size: 20,
                ),
                child: const Text('Continue preparation'),
              ),
            )
          : null,
      child: Column(
        children: [
          _MigrationPreparationDial(state: state, pausedMessage: pausedMessage),
          const SizedBox(height: AppSpacing.base),
          Opacity(
            opacity: paused ? 0.4 : 1,
            child: const _MigrationPreparationInfoCard(),
          ),
        ],
      ),
    );
  }
}

class _MigrationPreparationDial extends StatelessWidget {
  const _MigrationPreparationDial({required this.state, this.pausedMessage});

  final _MigrationPreparationState state;
  final String? pausedMessage;

  @override
  Widget build(BuildContext context) {
    final paused = state == _MigrationPreparationState.paused;
    final syncing = state == _MigrationPreparationState.syncing;
    return SizedBox.square(
      dimension: 256,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _AnimatedMigrationPreparationRing(
            key: const ValueKey('mobile_ironwood_preparation_ring'),
            animate: state == _MigrationPreparationState.active,
            color: context.colors.border.subtle,
          ),
          SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (paused)
                  const _MigrationPauseIcon()
                else if (syncing)
                  AppIcon(
                    AppIcons.loader,
                    size: 20,
                    color: context.colors.icon.accent,
                  )
                else
                  AppIcon(
                    AppIcons.migrationTimer,
                    size: 20,
                    color: context.colors.text.accent,
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  paused
                      ? pausedMessage ??
                            'Preparation was paused because you left.'
                      : syncing
                      ? 'Syncing your wallet…'
                      : 'Preparation will\ntake 10–20 min',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedMigrationPreparationRing extends StatefulWidget {
  const _AnimatedMigrationPreparationRing({
    super.key,
    required this.animate,
    required this.color,
  });

  final bool animate;
  final Color color;

  @override
  State<_AnimatedMigrationPreparationRing> createState() =>
      _AnimatedMigrationPreparationRingState();
}

class _AnimatedMigrationPreparationRingState
    extends State<_AnimatedMigrationPreparationRing>
    with TickerProviderStateMixin {
  static const _minimumWeight = 0.035;
  static const _maximumWeight = 0.22;
  // The nine unequal sweeps from the Figma preparation ring, normalized to 1.
  static const _initialWeights = <double>[
    45 / 342,
    45 / 342,
    18 / 342,
    23 / 342,
    72 / 342,
    42 / 342,
    45 / 342,
    16 / 342,
    36 / 342,
  ];
  static const _stepDuration = Duration(milliseconds: 390);
  static const _stepBreather = Duration(milliseconds: 105);
  static const _spinDuration = Duration(milliseconds: 1800);
  static const _restBetweenBlocks = Duration(milliseconds: 900);

  late final AnimationController _stepController = AnimationController(
    vsync: this,
    duration: _stepDuration,
  );
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: _spinDuration,
  );
  // Keep captures and motion tests reproducible while the sequence stays varied.
  final math.Random _random = math.Random(697244909);

  late List<double> _weights = List.of(_initialWeights);
  late List<double> _fromWeights = List.of(_initialWeights);
  late List<double> _toWeights = List.of(_initialWeights);
  double _baseRotation = 0;
  bool _reducedMotion = false;
  bool _loopRunning = false;
  bool _initialDelayPending = true;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _AnimatedMigrationPreparationRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    if (widget.animate && !_reducedMotion) {
      _startLoop();
      return;
    }
    _stopLoop(resetToInitial: _reducedMotion);
  }

  void _startLoop() {
    if (_loopRunning) return;
    _loopRunning = true;
    final generation = ++_generation;
    unawaited(_runLoop(generation));
  }

  void _stopLoop({required bool resetToInitial}) {
    if (!_loopRunning &&
        !_stepController.isAnimating &&
        !_spinController.isAnimating &&
        !resetToInitial) {
      return;
    }
    _generation++;
    _loopRunning = false;
    if (resetToInitial) {
      _weights = List.of(_initialWeights);
      _fromWeights = List.of(_initialWeights);
      _toWeights = List.of(_initialWeights);
      _baseRotation = 0;
    } else {
      final easedStep = Curves.easeOutBack.transform(_stepController.value);
      _weights = List.generate(
        _fromWeights.length,
        (index) =>
            _fromWeights[index] +
            (_toWeights[index] - _fromWeights[index]) * easedStep,
      );
      _fromWeights = List.of(_weights);
      _toWeights = List.of(_weights);
      _baseRotation =
          (_baseRotation +
              Curves.easeInOutCubic.transform(_spinController.value)) %
          1;
    }
    _stepController.stop();
    _spinController.stop();
    _stepController.value = 0;
    _spinController.value = 0;
  }

  bool _shouldContinue(int generation) {
    return mounted &&
        generation == _generation &&
        widget.animate &&
        !_reducedMotion;
  }

  Future<void> _runLoop(int generation) async {
    try {
      if (_initialDelayPending) {
        _initialDelayPending = false;
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!_shouldContinue(generation)) return;
      }
      while (_shouldContinue(generation)) {
        for (var cycle = 0; cycle < 3; cycle++) {
          await _adjustSegments(generation);
          if (!_shouldContinue(generation)) return;
          await _spinController.forward(from: 0).orCancel;
          if (!_shouldContinue(generation)) return;
          setState(() {
            _baseRotation = (_baseRotation + 1) % 1;
            _spinController.value = 0;
          });
        }
        await Future<void>.delayed(_restBetweenBlocks);
      }
    } on TickerCanceled {
      // The screen paused, reduced motion was enabled, or the widget disposed.
    } finally {
      if (generation == _generation) {
        _loopRunning = false;
      }
    }
  }

  Future<void> _adjustSegments(int generation) async {
    final stepCount = 3 + _random.nextInt(3);
    for (var step = 0; step < stepCount; step++) {
      if (!_shouldContinue(generation)) return;
      final first = _random.nextInt(_weights.length);
      var second = _random.nextInt(_weights.length - 1);
      if (second >= first) second++;

      final canGive = _weights[first] - _minimumWeight;
      final canTake = _maximumWeight - _weights[first];
      final giveRoom = math.min(canGive, _maximumWeight - _weights[second]);
      final takeRoom = math.min(canTake, _weights[second] - _minimumWeight);
      final give = giveRoom >= takeRoom;
      final room = give ? giveRoom : takeRoom;
      if (room <= 0.005) continue;
      final amount = room * (0.4 + _random.nextDouble() * 0.6);

      setState(() {
        _fromWeights = List.of(_weights);
        _toWeights = List.of(_weights);
        _toWeights[first] += give ? -amount : amount;
        _toWeights[second] += give ? amount : -amount;
      });
      await _stepController.forward(from: 0).orCancel;
      if (!_shouldContinue(generation)) return;
      setState(() {
        _weights = List.of(_toWeights);
        _fromWeights = List.of(_weights);
        _toWeights = List.of(_weights);
        _stepController.value = 0;
      });
      await Future<void>.delayed(_stepBreather);
    }
  }

  @override
  void dispose() {
    _generation++;
    _stepController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_stepController, _spinController]),
      builder: (context, _) {
        final easedStep = Curves.easeOutBack.transform(_stepController.value);
        final weights = List.generate(
          _fromWeights.length,
          (index) =>
              _fromWeights[index] +
              (_toWeights[index] - _fromWeights[index]) * easedStep,
        );
        final rotation =
            _baseRotation +
            Curves.easeInOutCubic.transform(_spinController.value);
        return CustomPaint(
          key: const ValueKey('mobile_ironwood_preparation_idle_ring'),
          size: const Size.square(256),
          painter: _MigrationPreparationIdleRingPainter(
            weights: weights,
            rotation: rotation,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _MigrationPreparationIdleRingPainter extends CustomPainter {
  const _MigrationPreparationIdleRingPainter({
    required this.weights,
    required this.rotation,
    required this.color,
  });

  final List<double> weights;
  final double rotation;
  final Color color;
  final double visibleSegmentGap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 7;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const strokeWidth = 12.0;
    final gap = (strokeWidth + visibleSegmentGap) / radius;
    final sweepBudget = math.pi * 2 - weights.length * gap;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * math.pi * 2);
    canvas.translate(-center.dx, -center.dy);

    var cursor = -math.pi / 2;
    for (final weight in weights) {
      final sweep = math.max(0.01, weight * sweepBudget);
      canvas.drawArc(rect, cursor + gap / 2, sweep, false, paint);
      cursor += sweep + gap;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MigrationPreparationIdleRingPainter oldDelegate) {
    return color != oldDelegate.color ||
        rotation != oldDelegate.rotation ||
        visibleSegmentGap != oldDelegate.visibleSegmentGap ||
        !_sameWeights(weights, oldDelegate.weights);
  }

  static bool _sameWeights(List<double> first, List<double> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

class _MigrationPauseIcon extends StatelessWidget {
  const _MigrationPauseIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < 2; index++) ...[
            if (index > 0) const SizedBox(width: 4),
            Container(
              width: 5,
              height: 18,
              decoration: BoxDecoration(
                color: context.colors.icon.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MigrationPreparationInfoCard extends StatelessWidget {
  const _MigrationPreparationInfoCard();

  @override
  Widget build(BuildContext context) {
    return _MigrationPreviewCard(
      child: Column(
        children: [
          _MigrationIconTextRow(
            icon: AppIcons.wallet,
            text:
                'We’re organizing your balance into common-sized parts. '
                'This makes your migration harder to link.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _MigrationIconTextRow(
            icon: AppIcons.history,
            text: 'Once preparation finishes, your migration can begin.',
          ),
        ],
      ),
    );
  }
}

enum _MigrationProgressState {
  syncing,
  waitingNotificationsOn,
  waitingNotificationsOff,
  needsInput,
  readyToSubmit,
  broadcasting,
  confirming,
}

const _migrationPartsPerBatch = 8;

class _MigrationProgressPreview extends StatelessWidget {
  const _MigrationProgressPreview({
    required this.state,
    this.showPreparationCompleteModal = false,
    this.completedParts,
    this.totalParts = 24,
    this.completedBatches,
    this.totalBatches,
    this.completedRingSegments,
    this.awaitingRingSegments,
    this.currentSigningPartIndices = const {},
    this.segmentValuesZatoshi,
    this.migratedAmountText,
    this.totalAmountText,
    this.availableAmountText,
    this.nextActionText,
    this.statusValueOverride,
    this.actionMessage,
    this.actionLabel,
    this.actionBatchLabel,
    this.actionBatchValue,
    this.onAction,
    this.actionRunning = false,
    this.onBack,
    this.onPreparationCompleteDone,
  });

  final _MigrationProgressState state;
  final bool showPreparationCompleteModal;
  final int? completedParts;
  final int totalParts;
  final int? completedBatches;
  final int? totalBatches;
  final Set<int>? completedRingSegments;
  final Set<int>? awaitingRingSegments;
  final Set<int> currentSigningPartIndices;
  final List<BigInt>? segmentValuesZatoshi;
  final String? migratedAmountText;
  final String? totalAmountText;
  final String? availableAmountText;
  final String? nextActionText;
  final String? statusValueOverride;
  final String? actionMessage;
  final String? actionLabel;
  final String? actionBatchLabel;
  final String? actionBatchValue;
  final VoidCallback? onAction;
  final bool actionRunning;
  final VoidCallback? onBack;
  final VoidCallback? onPreparationCompleteDone;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 650;
    final resolvedCompletedParts =
        completedParts ??
        (state == _MigrationProgressState.broadcasting ? 1 : 0);
    final resolvedTotalBatches =
        totalBatches ??
        math.max(
          1,
          (math.max(1, totalParts) + _migrationPartsPerBatch - 1) ~/
              _migrationPartsPerBatch,
        );
    final resolvedCompletedBatches =
        completedBatches ??
        (resolvedCompletedParts >= totalParts
            ? resolvedTotalBatches
            : resolvedCompletedParts ~/ _migrationPartsPerBatch);
    final resolvedCompletedRingSegments =
        completedRingSegments ??
        {
          for (
            var index = 0;
            index < resolvedCompletedParts.clamp(0, totalParts);
            index++
          )
            index,
        };
    final resolvedSegmentWeights = _normalizedMigrationRingWeights(
      segments: math.max(1, totalParts),
      valuesZatoshi: segmentValuesZatoshi,
    );
    final body = _MigrationPreviewPage(
      navTitle: 'Migration in progress…',
      onBack: onBack,
      contentGap: AppSpacing.md,
      scrollableContent: state != _MigrationProgressState.syncing,
      backgroundDecoration: switch (state) {
        _MigrationProgressState.waitingNotificationsOn ||
        _MigrationProgressState.waitingNotificationsOff ||
        _MigrationProgressState.readyToSubmit ||
        _MigrationProgressState.broadcasting ||
        _MigrationProgressState.confirming => const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00007F49), Color(0x00007F49), Color(0x99005D37)],
            stops: [0, 0.65, 1],
          ),
        ),
        _MigrationProgressState.syncing => const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0x00232323), Color(0xCC292929)],
            stops: [0, 0.58, 1],
          ),
        ),
        _ => null,
      },
      child: state == _MigrationProgressState.syncing
          ? _MigrationSyncingContent(
              compact: compact,
              segmentWeights: resolvedSegmentWeights,
            )
          : Column(
              children: [
                _MigrationBatchDial(
                  state: state,
                  completedBatches: resolvedCompletedBatches,
                  totalBatches: resolvedTotalBatches,
                  totalParts: totalParts,
                  completedSegments: resolvedCompletedRingSegments,
                  awaitingSegments:
                      awaitingRingSegments?.difference(
                        resolvedCompletedRingSegments,
                      ) ??
                      const {},
                  highlightedSegments:
                      state == _MigrationProgressState.needsInput
                      ? currentSigningPartIndices
                      : const {},
                  segmentWeights: resolvedSegmentWeights,
                  dimension: compact ? 192 : 256,
                  migratedAmountText: migratedAmountText,
                  totalAmountText: totalAmountText,
                ),
                SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                _MigrationProgressSummary(
                  completedParts: resolvedCompletedParts,
                  state: state,
                  availableAmountText: availableAmountText,
                  statusValueOverride: statusValueOverride,
                ),
                const Spacer(),
                if (state == _MigrationProgressState.needsInput)
                  _MigrationNeedsInputCard(
                    message: actionMessage,
                    actionLabel: actionLabel,
                    batchLabel: actionBatchLabel,
                    batchValue: actionBatchValue,
                    onAction: onAction,
                    actionRunning: actionRunning,
                  )
                else
                  _MigrationProgressStatus(
                    state: state,
                    bodyOverride: nextActionText,
                  ),
              ],
            ),
    );
    if (!showPreparationCompleteModal) return body;
    return _MigrationModalPreview(
      background: body,
      animateEntry: true,
      child: _PreparationCompleteModalBody(onDone: onPreparationCompleteDone),
    );
  }
}

class _MigrationBatchDial extends StatelessWidget {
  const _MigrationBatchDial({
    required this.state,
    required this.completedBatches,
    required this.totalBatches,
    required this.totalParts,
    required this.completedSegments,
    this.awaitingSegments = const {},
    required this.highlightedSegments,
    required this.segmentWeights,
    this.dimension = 256,
    this.migratedAmountText,
    this.totalAmountText,
  });

  final _MigrationProgressState state;
  final int completedBatches;
  final int totalBatches;
  final int totalParts;
  final Set<int> completedSegments;
  final Set<int> awaitingSegments;
  final Set<int> highlightedSegments;
  final List<double> segmentWeights;
  final double dimension;
  final String? migratedAmountText;
  final String? totalAmountText;

  @override
  Widget build(BuildContext context) {
    final migrated = migratedAmountText?.replaceFirst(RegExp(r'\s+ZEC$'), '');
    final total = totalAmountText ?? '100 ZEC';
    final combinedAmount = migrated == null ? '0/100 ZEC' : '$migrated/$total';
    final amountStyle = AppTypography.headlineSmall.copyWith(
      color: context.colors.text.accent,
    );
    final amountPainter = TextPainter(
      text: TextSpan(text: combinedAmount, style: amountStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    final splitAmount =
        amountPainter.width > dimension * 0.75 || combinedAmount.length >= 18;
    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _AnimatedMigrationAttentionRing(
            dimension: dimension,
            segmentWeights: segmentWeights,
            completedSegments: completedSegments,
            awaitingSegments: awaitingSegments,
            highlightedSegments: highlightedSegments,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Migrated:',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: dimension * 0.68,
                child: splitAmount
                    ? Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              migrated ?? '777.888',
                              maxLines: 1,
                              style: amountStyle,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '/$total',
                              maxLines: 1,
                              style: amountStyle,
                            ),
                          ),
                        ],
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          combinedAmount,
                          maxLines: 1,
                          style: amountStyle,
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$completedBatches/$totalBatches Batch',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MigrationSyncingContent extends StatelessWidget {
  const _MigrationSyncingContent({
    required this.compact,
    required this.segmentWeights,
  });

  final bool compact;
  final List<double> segmentWeights;

  @override
  Widget build(BuildContext context) {
    final dialDimension = compact ? 192.0 : 256.0;
    return Column(
      children: [
        SizedBox.square(
          dimension: dialDimension,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                key: const ValueKey(
                  'mobile_ironwood_migration_sync_progress_ring',
                ),
                size: Size.square(dialDimension),
                painter: _MigrationRingPainter(
                  trackColor: context.colors.border.subtle,
                  activeColor: context.colors.border.subtle,
                  segmentWeights: segmentWeights,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Migrated:',
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const _MigrationSkeletonBar(width: 90, height: 16),
                  const SizedBox(height: AppSpacing.xs),
                  const _MigrationSkeletonBar(width: 90, height: 16),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        const _MigrationSummaryRows(
          first: _MigrationSkeletonValueRow(
            icon: AppIcons.shieldKeyhole,
            label: 'Available in Ironwood',
            valueWidth: 90,
            emphasized: true,
          ),
          second: _MigrationSkeletonValueRow(
            icon: AppIcons.wrench,
            label: 'Status',
            valueWidth: 184,
          ),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? AppSpacing.s : AppSpacing.base,
          ),
          child: Column(
            children: [
              AppIcon(
                AppIcons.loader,
                size: 24,
                color: context.colors.text.accent,
              ),
              SizedBox(height: compact ? AppSpacing.s : AppSpacing.md),
              Text(
                'Syncing the migration progress.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MigrationSkeletonValueRow extends StatelessWidget {
  const _MigrationSkeletonValueRow({
    required this.icon,
    required this.label,
    required this.valueWidth,
    this.emphasized = false,
  });

  final String icon;
  final String label;
  final double valueWidth;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTypography.labelLarge.copyWith(
      color: emphasized
          ? context.colors.text.accent
          : context.colors.text.primary,
      fontWeight: emphasized ? FontWeight.w500 : FontWeight.w400,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const fixedWidth = 20 + AppSpacing.xs;
        const minimumBarWidth = 48.0;
        final labelPainter = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final maxLabelWidth = math.max(
          0.0,
          constraints.maxWidth - fixedWidth - minimumBarWidth,
        );
        final labelWidth = math.min(labelPainter.width, maxLabelWidth);
        final barWidth = math.min(
          valueWidth,
          math.max(0.0, constraints.maxWidth - fixedWidth - labelWidth),
        );
        return SizedBox(
          height: 20,
          child: Row(
            children: [
              AppIcon(
                icon,
                size: 20,
                color: emphasized
                    ? context.colors.text.accent
                    : context.colors.text.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                width: labelWidth,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
              const Spacer(),
              _MigrationSkeletonBar(width: barWidth, height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _MigrationSkeletonBar extends StatefulWidget {
  const _MigrationSkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<_MigrationSkeletonBar> createState() => _MigrationSkeletonBarState();
}

class _MigrationSkeletonBarState extends State<_MigrationSkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.background.ground;
    final highlight = context.colors.border.subtle;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.full),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final shift = (_controller.value * 2 - 1) * widget.width;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) =>
                  LinearGradient(
                    colors: [base, highlight, base],
                    stops: const [0.15, 0.5, 0.85],
                  ).createShader(
                    Rect.fromLTWH(
                      bounds.left + shift,
                      bounds.top,
                      bounds.width,
                      bounds.height,
                    ),
                  ),
              child: const ColoredBox(color: Color(0xFFFFFFFF)),
            );
          },
        ),
      ),
    );
  }
}

class _MigrationProgressSummary extends StatelessWidget {
  const _MigrationProgressSummary({
    required this.completedParts,
    required this.state,
    this.availableAmountText,
    this.statusValueOverride,
  });

  final int completedParts;
  final _MigrationProgressState state;
  final String? availableAmountText;
  final String? statusValueOverride;

  @override
  Widget build(BuildContext context) {
    return _MigrationSummaryRows(
      first: _MigrationValueRow(
        icon: AppIcons.shieldKeyhole,
        label: 'Available in Ironwood',
        value:
            availableAmountText ?? (completedParts == 0 ? '0 ZEC' : '40 ZEC'),
        emphasized: true,
      ),
      second: _MigrationValueRow(
        icon: AppIcons.wrench,
        label: 'Status',
        value:
            statusValueOverride ??
            switch (state) {
              _MigrationProgressState.syncing => 'Syncing',
              _MigrationProgressState.broadcasting =>
                'All is well. Broadcasting notes…',
              _MigrationProgressState.confirming => 'Waiting for confirmations',
              _MigrationProgressState.needsInput =>
                'Waiting for your confirmation',
              _MigrationProgressState.readyToSubmit =>
                'Scheduled transaction ready',
              _ => 'Waiting for next migration step',
            },
      ),
    );
  }
}

class _MigrationSummaryRows extends StatelessWidget {
  const _MigrationSummaryRows({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          first,
          const SizedBox(height: AppSpacing.sm),
          second,
        ],
      ),
    );
  }
}

class _MigrationProgressStatus extends StatelessWidget {
  const _MigrationProgressStatus({required this.state, this.bodyOverride});

  final _MigrationProgressState state;
  final String? bodyOverride;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (state) {
      _MigrationProgressState.syncing => (
        AppIcons.loader,
        'Syncing migration progress',
        'Checking the latest confirmations and migration status.',
      ),
      _MigrationProgressState.waitingNotificationsOn => (
        AppIcons.notificationBell,
        '~2 hrs 15 mins',
        'Next migration step expected in this time.\n'
            'Notifications are on. You can leave Vizor and check back later.',
      ),
      _MigrationProgressState.waitingNotificationsOff => (
        AppIcons.warningCircle,
        'Waiting for next migration step',
        'Notifications are disabled. Open Vizor after block 123456 '
            '(~1 hr 30 mins) and approve the next migration batch.',
      ),
      _MigrationProgressState.readyToSubmit => (
        AppIcons.migrationTimer,
        'Ready now',
        'The scheduled transaction is ready for automatic submission. '
            'Keep Vizor open.',
      ),
      _MigrationProgressState.broadcasting => (
        AppIcons.notificationBell,
        'All is well. Broadcasting notes…',
        '~2 hrs 15 mins.\n'
            'Notifications are on. You can leave Vizor and check back later.',
      ),
      _MigrationProgressState.confirming => (
        AppIcons.migrationTimer,
        'Waiting for confirmations',
        'Confirmations are still arriving. You can leave Vizor and check '
            'again later.',
      ),
      _MigrationProgressState.needsInput => (
        AppIcons.migrationSign,
        'Waiting for your confirmation',
        'Batch #1 is ready.',
      ),
    };
    final waitingWithNotifications =
        state == _MigrationProgressState.waitingNotificationsOn;
    final notificationsOff =
        state == _MigrationProgressState.waitingNotificationsOff;
    final broadcasting = state == _MigrationProgressState.broadcasting;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 24,
            child: Center(
              child: AppIcon(
                icon,
                size: notificationsOff ? 20 : 24,
                color: context.colors.icon.success,
              ),
            ),
          ),
          SizedBox(height: broadcasting ? AppSpacing.sm : AppSpacing.md),
          if (waitingWithNotifications) ...[
            Text(
              _migrationTimingFromBody(bodyOverride) ?? title,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: context.colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ] else if (notificationsOff)
            Text(
              bodyOverride ?? body,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.accent,
              ),
            )
          else if (broadcasting)
            Text(
              'Next migration step expected in\n'
              '${_migrationTimingFromBody(bodyOverride) ?? '~2 hrs 15 mins'}.\n'
              'Notifications are on. You can leave Vizor and check back later.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: context.colors.text.accent,
              ),
            )
          else ...[
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              bodyOverride ?? body,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _migrationTimingFromBody(String? value) {
    if (value == null || value.isEmpty) return null;
    final firstLine = value.split('\n').first.trim();
    return firstLine.replaceFirst(RegExp(r'\.$'), '');
  }
}

class _MigrationNeedsInputCard extends StatelessWidget {
  const _MigrationNeedsInputCard({
    this.message,
    this.actionLabel,
    this.batchLabel,
    this.batchValue,
    this.onAction,
    this.actionRunning = false,
  });

  final String? message;
  final String? actionLabel;
  final String? batchLabel;
  final String? batchValue;
  final VoidCallback? onAction;
  final bool actionRunning;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null) ...[
          Text(
            message!,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (batchLabel != null || batchValue != null) ...[
          _MigrationPreviewCard(
            child: _MigrationValueRow(
              icon: AppIcons.checkCircle,
              label: batchLabel ?? 'Batch #1',
              value: batchValue ?? '40 ZEC (30%)',
              emphasized: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else if (actionLabel == null) ...[
          _MigrationPreviewCard(
            child: _MigrationValueRow(
              icon: AppIcons.checkCircle,
              label: 'Batch #1',
              value: '40 ZEC (30%)',
              emphasized: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppButton(
          key: const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
          expand: true,
          constrainContent: true,
          height: 50,
          onPressed: actionRunning ? null : onAction ?? () {},
          leading: actionRunning
              ? const AppIcon(
                  AppIcons.loader,
                  semanticLabel: 'Migration action in progress',
                )
              : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(actionLabel ?? 'Sign batch #1'),
          ),
        ),
      ],
    );
  }
}

class _PreparationCompleteModalBody extends StatelessWidget {
  const _PreparationCompleteModalBody({this.onDone});

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final contentHeight = (MediaQuery.sizeOf(context).height - 112).clamp(
      420.0,
      470.0,
    );
    return SizedBox(
      height: contentHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Preparation is done',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'What’s Next?',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _AnimatedMigrationWaitLoop(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            expand: true,
            height: 50,
            onPressed: onDone ?? () {},
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _AnimatedMigrationWaitLoop extends StatefulWidget {
  const _AnimatedMigrationWaitLoop();

  @override
  State<_AnimatedMigrationWaitLoop> createState() =>
      _AnimatedMigrationWaitLoopState();
}

class _AnimatedMigrationWaitLoopState extends State<_AnimatedMigrationWaitLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 298,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RotationTransition(
            key: const ValueKey('mobile_ironwood_preparation_complete_orbit'),
            turns: _controller,
            child: CustomPaint(
              painter: _MigrationWaitLoopPainter(
                lineColor: context.colors.text.accent,
                successColor: context.colors.icon.success,
                labelStyle: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Center(
            key: const ValueKey('mobile_ironwood_preparation_complete_center'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.history,
                  size: 24,
                  color: context.colors.text.secondary,
                ),
                const SizedBox(height: AppSpacing.s),
                SizedBox(
                  width: 177,
                  child: Text(
                    'Repeat several times,\n'
                    'waiting could take 2–10\n'
                    'hours',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The amount shown on a finished migration.
///
/// Single rule on purpose. The dedicated completion route and the status
/// screen's completion branch both render the same result, and the completion
/// provider publishes its own total for routing — three places that could
/// otherwise disagree about what the user migrated.
String migrationCompletedAmountText(
  rust_sync.MigrationStatus status, {
  required String fallbackAmountText,
}) {
  final total = status.parts.isNotEmpty
      ? status.parts.fold<BigInt>(
          BigInt.zero,
          (sum, part) => sum + part.valueZatoshi,
        )
      : status.targetValuesZatoshi.fold<BigInt>(
          BigInt.zero,
          (sum, value) => sum + value,
        );
  final text = total > BigInt.zero
      ? ZecAmount.fromZatoshi(total).compactBalance.amountText
      : fallbackAmountText;
  return '$text ZEC';
}

/// The finished-migration result, with the behaviour that has to accompany it.
///
/// Owns marking the completion seen so the dedicated route and the status
/// screen cannot drift apart on when a result stops being re-shown. The two
/// reach this surface under different conditions — the route because home
/// found an unseen completion, the status screen because the run it is already
/// showing finished — but once here they must behave identically.
class _MigrationCompleteSurface extends ConsumerStatefulWidget {
  const _MigrationCompleteSurface({
    required this.status,
    required this.onDone,
    required this.fallbackAmountText,
  });

  final rust_sync.MigrationStatus status;
  final VoidCallback onDone;
  final String fallbackAmountText;

  @override
  ConsumerState<_MigrationCompleteSurface> createState() =>
      _MigrationCompleteSurfaceState();
}

class _MigrationCompleteSurfaceState
    extends ConsumerState<_MigrationCompleteSurface> {
  bool _seenRecorded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_markCompletionSeen());
    });
  }

  Future<void> _markCompletionSeen() async {
    if (_seenRecorded || !mounted) return;
    _seenRecorded = true;
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    // Prefer the identity the completion provider itself published. Recomputing
    // it from this status can disagree with the status the provider read, and a
    // key that never matches leaves the run forever unseen, so home would route
    // back to the result on every return. Only trust it for the account on
    // screen: a reloading provider keeps serving its previous value, so right
    // after an account switch the published identity can still be the account
    // the user left.
    final publishedValue = ref.read(ironwoodMigrationCompletionProvider).value;
    final published = publishedValue?.accountUuid == accountUuid
        ? publishedValue
        : null;
    final network =
        published?.network ?? ref.read(ironwoodMigrationInputsProvider).network;
    final completionId =
        published?.completionId ?? ironwoodMigrationCompletionId(widget.status);
    try {
      await ref
          .read(ironwoodMigrationCompletionStoreProvider)
          .markSeen(
            network: network,
            accountUuid: accountUuid,
            completionId: completionId,
          );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    ref.invalidate(ironwoodMigrationCompletionProvider);
  }

  @override
  Widget build(BuildContext context) {
    return _MigrationCompletePreview(
      amountText: migrationCompletedAmountText(
        widget.status,
        fallbackAmountText: widget.fallbackAmountText,
      ),
      onDone: widget.onDone,
    );
  }
}

class _MigrationCompletePreview extends StatelessWidget {
  const _MigrationCompletePreview({required this.amountText, this.onDone});

  /// Required, and never empty. A placeholder default here would be a sample
  /// amount rendered to a real user as their migration result; an empty one
  /// leaves the headline with a blank line where the total belongs. Preview
  /// call sites pass their own sample.
  final String amountText;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return _MigrationPreviewPage(
      navTitle: 'You’re all set!',
      onBack: onDone,
      backgroundColor: const Color(0xFF007F49),
      navForegroundColor: const Color(0xFFFFFFFF),
      bottom: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDone ?? () {},
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            alignment: Alignment.center,
            child: Text(
              'Done',
              style: AppTypography.labelLarge.copyWith(
                color: const Color(0xFF1B1F1F),
              ),
            ),
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 256,
            child: Image(
              image: AssetImage(
                'assets/illustrations/ironwood_migration_done_coins.png',
              ),
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Your\n$amountText\nare on Ironwood!',
            textAlign: TextAlign.center,
            style: AppTypography.displayLarge.copyWith(
              color: const Color(0xFFFFFFFF),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Migration went successfully and you can spend your funds as '
            'usual.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationHomeAttentionPreview extends StatelessWidget {
  const _MigrationHomeAttentionPreview({this.showModal = false});

  final bool showModal;

  @override
  Widget build(BuildContext context) {
    final background = _MigrationPreviewPage(
      navTitle: 'Wallet 1',
      contentGap: AppSpacing.md,
      child: Column(
        children: [
          _MigrationPreviewCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ironwood balance',
                  style: AppTypography.labelLarge.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  r'$1,200.12',
                  style: AppTypography.displayLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                Text(
                  '40.01 ZEC',
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MobileIronwoodMigrationBanner(
            inProgress: false,
            attentionKind: MobileIronwoodMigrationAttentionKind.signature,
            actionNeededCount: 2,
            remainingText: null,
            onTap: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Recent activity',
              style: AppTypography.bodyLarge.copyWith(
                color: context.colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _MigrationValueRow(
            icon: AppIcons.history,
            label: 'Received',
            value: '+31.10 ZEC',
          ),
        ],
      ),
    );
    if (!showModal) return background;
    return _MigrationModalPreview(
      background: background,
      child: MobileIronwoodMigrationAttentionSheetBody(
        kind: MobileIronwoodMigrationAttentionKind.signature,
        count: 2,
        onOpenMigration: () {},
        onLater: () {},
      ),
    );
  }
}

class _MigrationKeystoneHelpPreview extends StatelessWidget {
  const _MigrationKeystoneHelpPreview();

  @override
  Widget build(BuildContext context) {
    final background = _MigrationPreviewPage(
      navTitle: 'Step 1/2',
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            expand: true,
            height: 50,
            onPressed: () {},
            child: const Text('Next step'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            expand: true,
            height: 50,
            variant: AppButtonVariant.ghost,
            onPressed: () {},
            child: const Text('Cancel'),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Scan with Keystone',
            style: appSerifDisplayStyle(color: context.colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.base),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: const SizedBox.square(
              dimension: 236,
              child: Center(
                child: AppIcon(
                  AppIcons.qr,
                  size: 184,
                  color: Color(0xFF000000),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Tap QR on your Keystone,\nthen scan this QR code.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.primary,
            ),
          ),
        ],
      ),
    );
    return _MigrationModalPreview(
      background: background,
      child: MobileIronwoodKeystoneScanHelpBody(onConfirm: () {}),
    );
  }
}

class _MigrationModalPreview extends StatelessWidget {
  const _MigrationModalPreview({
    required this.background,
    required this.child,
    this.animateEntry = false,
  });

  final Widget background;
  final Widget child;
  final bool animateEntry;

  @override
  Widget build(BuildContext context) {
    final modal = MobileModalScaffold(
      title: '',
      showTitle: false,
      showClose: false,
      bottomPadding: AppSpacing.base,
      onClose: _noopMigrationPreviewAction,
      child: child,
    );
    return MobileModalOverlay(
      background: background,
      child: !animateEntry || MediaQuery.disableAnimationsOf(context)
          ? modal
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, progress, child) => Transform.translate(
                offset: Offset(0, 96 * progress),
                child: child,
              ),
              child: modal,
            ),
    );
  }
}

class _MigrationPreviewCard extends StatelessWidget {
  const _MigrationPreviewCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: context.colors.border.subtle),
        boxShadow: appSurfaceShadow(context.colors),
      ),
      child: child,
    );
  }
}

class _MigrationIconTextRow extends StatelessWidget {
  const _MigrationIconTextRow({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(icon, size: 20, color: context.colors.text.accent),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _MigrationValueRow extends StatelessWidget {
  const _MigrationValueRow({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String icon;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final style =
              (emphasized
                      ? AppTypography.labelLarge
                      : AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w400,
                        ))
                  .copyWith(
                    color: emphasized
                        ? context.colors.text.accent
                        : context.colors.text.primary,
                  );
          final labelPainter = TextPainter(
            text: TextSpan(text: label, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
          )..layout();
          const fixedWidth = 20 + AppSpacing.xs;
          const minimumValueWidth = 80.0;
          final labelWidth = math.min(
            labelPainter.width,
            math.max(
              0.0,
              constraints.maxWidth - fixedWidth - minimumValueWidth,
            ),
          );
          final labelText = Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
          final valueText = Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: style,
          );
          return Row(
            children: [
              AppIcon(
                icon,
                size: 20,
                color: emphasized
                    ? context.colors.text.accent
                    : context.colors.text.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(width: labelWidth, child: labelText),
              Expanded(child: valueText),
            ],
          );
        },
      ),
    );
  }
}

class _AnimatedMigrationAttentionRing extends StatefulWidget {
  const _AnimatedMigrationAttentionRing({
    required this.dimension,
    required this.segmentWeights,
    required this.completedSegments,
    required this.awaitingSegments,
    required this.highlightedSegments,
  });

  final double dimension;
  final List<double> segmentWeights;
  final Set<int> completedSegments;
  final Set<int> awaitingSegments;
  final Set<int> highlightedSegments;

  @override
  State<_AnimatedMigrationAttentionRing> createState() =>
      _AnimatedMigrationAttentionRingState();
}

class _AnimatedMigrationAttentionRingState
    extends State<_AnimatedMigrationAttentionRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 0,
    );
    _opacity = Tween<double>(
      begin: 0.40,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedMigrationAttentionRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_reducedMotion || widget.highlightedSegments.isEmpty) {
      _controller.stop();
      _controller.value = 1;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.value = 0;
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => CustomPaint(
        key: const ValueKey('mobile_ironwood_migration_attention_ring'),
        size: Size.square(widget.dimension),
        painter: _MigrationRingPainter(
          trackColor: context.colors.border.subtle,
          activeColor: context.colors.border.utilityPositiveStrong,
          segmentWeights: widget.segmentWeights,
          completedSegments: widget.completedSegments,
          awaitingSegments: widget.awaitingSegments,
          highlightedSegments: widget.highlightedSegments,
          highlightColor: context.colors.text.accent,
          highlightOpacity: _reducedMotion ? 1 : _opacity.value,
        ),
      ),
    );
  }
}

/// Opacity the design uses for a broadcast part that is still confirming.
const double _awaitingSegmentOpacity = 0.5;

class _MigrationRingPainter extends CustomPainter {
  const _MigrationRingPainter({
    required this.trackColor,
    required this.activeColor,
    required this.segmentWeights,
    this.completedSegments = const {},
    this.awaitingSegments = const {},
    this.highlightedSegments = const {},
    this.highlightColor,
    this.highlightOpacity = 1,
  });

  final Color trackColor;
  final Color activeColor;
  final List<double> segmentWeights;
  final Set<int> completedSegments;

  /// Parts already broadcast but still waiting for their confirmations. They
  /// are past the point the user can influence, yet not final, so they read as
  /// a dimmed form of the completed colour rather than as untouched track.
  final Set<int> awaitingSegments;
  final Set<int> highlightedSegments;
  final Color? highlightColor;
  final double highlightOpacity;
  final double visibleSegmentGap = 4;

  int get segments => segmentWeights.length;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 7;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const strokeWidth = 12.0;
    final segmentPitch = math.pi * 2 / segments;
    final roundCapGap = (strokeWidth + math.max(0, visibleSegmentGap)) / radius;
    final useRoundCaps = segments == 1 || roundCapGap <= segmentPitch * 0.8;
    final gap = segments == 1
        ? 0.0
        : useRoundCaps
        ? roundCapGap
        : math.min(
            math.max(0, visibleSegmentGap) / radius,
            segmentPitch * 0.35,
          );
    final sweepBudget = math.max(0.0, math.pi * 2 - segments * gap);
    var cursor = -math.pi / 2;
    for (var index = 0; index < segments; index++) {
      final segmentSweep = segmentWeights[index] * sweepBudget;
      final start = cursor + gap / 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = useRoundCaps ? StrokeCap.round : StrokeCap.butt
        ..strokeWidth = strokeWidth;
      paint.color = completedSegments.contains(index)
          ? activeColor
          : awaitingSegments.contains(index)
          ? activeColor.withValues(alpha: _awaitingSegmentOpacity)
          : highlightedSegments.contains(index)
          ? (highlightColor ?? activeColor).withValues(alpha: highlightOpacity)
          : trackColor;
      canvas.drawArc(rect, start, segmentSweep, false, paint);
      cursor += segmentSweep + gap;
    }
  }

  @override
  bool shouldRepaint(_MigrationRingPainter oldDelegate) {
    return trackColor != oldDelegate.trackColor ||
        activeColor != oldDelegate.activeColor ||
        !_sameDoubleList(segmentWeights, oldDelegate.segmentWeights) ||
        completedSegments != oldDelegate.completedSegments ||
        awaitingSegments != oldDelegate.awaitingSegments ||
        highlightedSegments != oldDelegate.highlightedSegments ||
        highlightColor != oldDelegate.highlightColor ||
        highlightOpacity != oldDelegate.highlightOpacity ||
        visibleSegmentGap != oldDelegate.visibleSegmentGap;
  }
}

List<double> _normalizedMigrationRingWeights({
  required int segments,
  required List<BigInt>? valuesZatoshi,
}) {
  final safeSegments = math.max(1, segments);
  List<double> equalWeights() =>
      List<double>.filled(safeSegments, 1 / safeSegments);
  if (valuesZatoshi == null ||
      valuesZatoshi.length != safeSegments ||
      valuesZatoshi.any((value) => value <= BigInt.zero)) {
    return equalWeights();
  }
  final total = valuesZatoshi.fold<BigInt>(
    BigInt.zero,
    (sum, value) => sum + value,
  );
  if (total <= BigInt.zero) return equalWeights();
  final totalDouble = total.toDouble();
  if (!totalDouble.isFinite || totalDouble <= 0) return equalWeights();
  return [for (final value in valuesZatoshi) value.toDouble() / totalDouble];
}

bool _sameDoubleList(List<double> first, List<double> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

class _MigrationWaitLoopPainter extends CustomPainter {
  const _MigrationWaitLoopPainter({
    required this.lineColor,
    required this.successColor,
    required this.labelStyle,
  });

  final Color lineColor;
  final Color successColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final loopRect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: 132,
    );
    const dash = 3.5;
    const gap = 4.5;
    final cycle = dash + gap;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = lineColor;

    void drawDashedArc(double startAngle, double sweepAngle) {
      final path = Path()..addArc(loopRect, startAngle, sweepAngle);
      final metric = path.computeMetrics().first;
      var distance = 0.0;
      while (distance < metric.length) {
        final start = distance;
        final end = math.min(metric.length, distance + dash);
        canvas.drawPath(metric.extractPath(start, end), paint);
        distance += cycle;
      }
    }

    final topSegments = [
      _MigrationArcTextSegment('Wait', successColor),
      _MigrationArcTextSegment(' for the window', lineColor),
    ];
    final bottomSegments = [
      _MigrationArcTextSegment('Sign', successColor),
      _MigrationArcTextSegment(' the batch of transactions', lineColor),
    ];
    const textRadius = 131.0;
    const labelClearance = 12.0;
    final clearanceAngle = labelClearance / textRadius;
    final topHalfAngle = _measureArcTextAdvance(topSegments) / textRadius / 2;
    final bottomHalfAngle =
        _measureArcTextAdvance(bottomSegments) / textRadius / 2;
    final rightArcStart = -math.pi / 2 + topHalfAngle + clearanceAngle;
    final rightArcEnd = math.pi / 2 - bottomHalfAngle - clearanceAngle;
    final leftArcStart = math.pi / 2 + bottomHalfAngle + clearanceAngle;
    final leftArcEnd = math.pi * 3 / 2 - topHalfAngle - clearanceAngle;

    // Derive the side arcs from the rendered label widths. The lower label is
    // substantially longer, so fixed angles can let its first or last glyphs
    // collide with the dashed stroke.
    drawDashedArc(rightArcStart, rightArcEnd - rightArcStart);
    drawDashedArc(leftArcStart, leftArcEnd - leftArcStart);

    void drawArrow(double angle) {
      final center = loopRect.center;
      final point = Offset(
        center.dx + math.cos(angle) * loopRect.width / 2,
        center.dy + math.sin(angle) * loopRect.height / 2,
      );
      final tangent = Offset(-math.sin(angle), math.cos(angle));
      final normal = Offset(math.cos(angle), math.sin(angle));
      final arrowPath = Path()
        ..moveTo(point.dx, point.dy)
        ..lineTo(
          point.dx - tangent.dx * 6 + normal.dx * 6,
          point.dy - tangent.dy * 6 + normal.dy * 6,
        )
        ..moveTo(point.dx, point.dy)
        ..lineTo(
          point.dx - tangent.dx * 6 - normal.dx * 6,
          point.dy - tangent.dy * 6 - normal.dy * 6,
        );
      canvas.drawPath(arrowPath, paint);
    }

    drawArrow(rightArcEnd);
    drawArrow(leftArcEnd);

    _paintArcText(
      canvas,
      center: loopRect.center,
      radius: textRadius,
      centerAngle: -math.pi / 2,
      clockwise: true,
      segments: topSegments,
    );
    _paintArcText(
      canvas,
      center: loopRect.center,
      radius: textRadius,
      centerAngle: math.pi / 2,
      clockwise: false,
      segments: bottomSegments,
    );
  }

  double _measureArcTextAdvance(List<_MigrationArcTextSegment> segments) {
    var totalAdvance = 0.0;
    for (final segment in segments) {
      for (final rune in segment.text.runes) {
        final painter = TextPainter(
          text: TextSpan(text: String.fromCharCode(rune), style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        totalAdvance += painter.width;
      }
    }
    return totalAdvance;
  }

  void _paintArcText(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double centerAngle,
    required bool clockwise,
    required List<_MigrationArcTextSegment> segments,
  }) {
    final glyphs = <_MigrationArcGlyph>[];
    for (final segment in segments) {
      for (final rune in segment.text.runes) {
        final painter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(rune),
            style: labelStyle.copyWith(color: segment.color),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        glyphs.add(_MigrationArcGlyph(painter));
      }
    }

    final totalAdvance = glyphs.fold<double>(
      0,
      (sum, glyph) => sum + glyph.painter.width,
    );
    final direction = clockwise ? 1.0 : -1.0;
    var angle = centerAngle - direction * totalAdvance / radius / 2;
    for (final glyph in glyphs) {
      final advanceAngle = glyph.painter.width / radius;
      angle += direction * advanceAngle / 2;
      final position = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas
        ..save()
        ..translate(position.dx, position.dy)
        ..rotate(angle + direction * math.pi / 2);
      glyph.painter.paint(
        canvas,
        Offset(-glyph.painter.width / 2, -glyph.painter.height / 2),
      );
      canvas.restore();
      angle += direction * advanceAngle / 2;
    }
  }

  @override
  bool shouldRepaint(_MigrationWaitLoopPainter oldDelegate) {
    return lineColor != oldDelegate.lineColor ||
        successColor != oldDelegate.successColor ||
        labelStyle != oldDelegate.labelStyle;
  }
}

class _MigrationArcTextSegment {
  const _MigrationArcTextSegment(this.text, this.color);

  final String text;
  final Color color;
}

class _MigrationArcGlyph {
  const _MigrationArcGlyph(this.painter);

  final TextPainter painter;
}
