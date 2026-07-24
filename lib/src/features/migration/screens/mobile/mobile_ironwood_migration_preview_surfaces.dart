part of 'mobile_ironwood_migration_flow_screen.dart';

void _noopMigrationPreviewAction() {}

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
          progress: 5 / 9,
        ),
      MobileIronwoodMigrationPreviewSurface.preparationPaused =>
        _MigrationPreparationPreview(
          state: _MigrationPreparationState.paused,
          progress: 5 / 9,
          onContinue: _noopMigrationPreviewAction,
        ),
      MobileIronwoodMigrationPreviewSurface.preparationPausedKeystone =>
        _MigrationPreparationPreview(
          state: _MigrationPreparationState.paused,
          progress: 5 / 9,
          isKeystone: true,
          onContinue: _noopMigrationPreviewAction,
        ),
      MobileIronwoodMigrationPreviewSurface.preparationSyncing =>
        const _MigrationPreparationPreview(
          state: _MigrationPreparationState.syncing,
          progress: 5 / 9,
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
        const _MigrationProgressPreview(
          state: _MigrationProgressState.needsInput,
          currentBatchPartCount: _migrationPartsPerBatch,
          migratedAmountText: '777.888 ZEC',
          totalAmountText: '999.999 ZEC',
        ),
      MobileIronwoodMigrationPreviewSurface.migrationKeystoneSignAll =>
        const _MigrationProgressPreview(
          state: _MigrationProgressState.needsInput,
          totalParts: 50,
          currentBatchPartCount: 8,
          highlightCurrentBatch: false,
          migratedAmountText: '0 ZEC',
          totalAmountText: '50 ZEC',
          actionLabel: 'Sign migration transactions',
          actionBatchLabel: 'All transactions',
          actionBatchValue: '50 ZEC (100%)',
        ),
      MobileIronwoodMigrationPreviewSurface.migrationBroadcasting =>
        const _MigrationProgressPreview(
          state: _MigrationProgressState.broadcasting,
        ),
      MobileIronwoodMigrationPreviewSurface.migrationComplete =>
        const _MigrationCompletePreview(),
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
  const _MobileMigrationNotificationPermissionScreen();

  @override
  ConsumerState<_MobileMigrationNotificationPermissionScreen> createState() =>
      _MobileMigrationNotificationPermissionScreenState();
}

class _MobileMigrationNotificationPermissionScreenState
    extends ConsumerState<_MobileMigrationNotificationPermissionScreen> {
  AppLifecycleListener? _lifecycleListener;
  var _busy = false;

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
        context.go('/migration/private/review');
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
        context.go('/migration/private/review');
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
        if (mounted) context.go('/migration/private/review');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _MigrationNotificationPromptPreview(
      busy: _busy,
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
  });

  final bool showConfirmation;
  final VoidCallback? onBack;
  final VoidCallback? onAllow;
  final VoidCallback? onNotNow;
  final bool busy;

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
    this.progress = 0,
    this.isKeystone = false,
    this.onBack,
    this.onContinue,
  });

  final _MigrationPreparationState state;
  final double progress;
  final bool isKeystone;
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
          _MigrationPreparationDial(state: state, progress: progress),
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
  const _MigrationPreparationDial({
    required this.state,
    required this.progress,
  });

  final _MigrationPreparationState state;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final paused = state == _MigrationPreparationState.paused;
    final syncing = state == _MigrationPreparationState.syncing;
    return SizedBox.square(
      dimension: 256,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            key: const ValueKey('mobile_ironwood_preparation_progress_ring'),
            size: const Size.square(256),
            painter: _MigrationRingPainter(
              trackColor: context.colors.border.subtle,
              activeColor: const Color(0xFF00A460),
              segments: 8,
              progress: progress,
              segmentGap: 0.15,
            ),
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
                      ? 'Preparation was paused because you left.'
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
    this.currentBatchPartCount,
    this.completedCurrentBatchParts,
    this.highlightCurrentBatch = true,
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
    this.onBack,
    this.onPreparationCompleteDone,
  });

  final _MigrationProgressState state;
  final bool showPreparationCompleteModal;
  final int? completedParts;
  final int totalParts;
  final int? completedBatches;
  final int? totalBatches;
  final int? currentBatchPartCount;
  final int? completedCurrentBatchParts;
  final bool highlightCurrentBatch;
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
    final resolvedBatchPartCount =
        currentBatchPartCount ??
        (state == _MigrationProgressState.needsInput
            ? math.min(3, totalParts)
            : math.min(_migrationPartsPerBatch, totalParts));
    final resolvedCompletedCurrentBatchParts =
        completedCurrentBatchParts ??
        (resolvedCompletedParts % _migrationPartsPerBatch).clamp(
          0,
          resolvedBatchPartCount,
        );
    final body = _MigrationPreviewPage(
      navTitle: 'Migration in progress…',
      onBack: onBack,
      contentGap: AppSpacing.md,
      scrollableContent: state != _MigrationProgressState.syncing,
      backgroundDecoration: switch (state) {
        _MigrationProgressState.waitingNotificationsOn ||
        _MigrationProgressState.waitingNotificationsOff ||
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
          ? _MigrationSyncingContent(compact: compact)
          : Column(
              children: [
                _MigrationBatchDial(
                  state: state,
                  completedBatches: resolvedCompletedBatches,
                  totalBatches: resolvedTotalBatches,
                  currentBatchPartCount: resolvedBatchPartCount,
                  completedCurrentBatchParts:
                      resolvedCompletedCurrentBatchParts,
                  highlightCurrentBatch: highlightCurrentBatch,
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
      child: _PreparationCompleteModalBody(onDone: onPreparationCompleteDone),
    );
  }
}

class _MigrationBatchDial extends StatelessWidget {
  const _MigrationBatchDial({
    required this.state,
    required this.completedBatches,
    required this.totalBatches,
    required this.currentBatchPartCount,
    required this.completedCurrentBatchParts,
    this.highlightCurrentBatch = true,
    this.dimension = 256,
    this.migratedAmountText,
    this.totalAmountText,
  });

  final _MigrationProgressState state;
  final int completedBatches;
  final int totalBatches;
  final int currentBatchPartCount;
  final int completedCurrentBatchParts;
  final bool highlightCurrentBatch;
  final double dimension;
  final String? migratedAmountText;
  final String? totalAmountText;

  @override
  Widget build(BuildContext context) {
    final needsInput = state == _MigrationProgressState.needsInput;
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
    final completedSegments = {
      for (
        var index = 0;
        index < completedCurrentBatchParts.clamp(0, _migrationPartsPerBatch);
        index++
      )
        index,
    };
    final highlightedSegments = needsInput && highlightCurrentBatch
        ? {
            for (
              var index = 0;
              index < currentBatchPartCount.clamp(0, _migrationPartsPerBatch);
              index++
            )
              index,
          }
        : const <int>{};
    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _AnimatedMigrationAttentionRing(
            dimension: dimension,
            segments: currentBatchPartCount.clamp(1, _migrationPartsPerBatch),
            completedSegments: completedSegments,
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
  const _MigrationSyncingContent({required this.compact});

  final bool compact;

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
                size: Size.square(dialDimension),
                painter: _MigrationRingPainter(
                  trackColor: context.colors.border.subtle,
                  activeColor: context.colors.border.subtle,
                  segments: 8,
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
              _ => 'Waiting for signing window',
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
        'Signing window expected in this time.\n'
            'We will notify you when it’s ready.',
      ),
      _MigrationProgressState.waitingNotificationsOff => (
        AppIcons.warningCircle,
        'Waiting for signing window',
        'Notifications are disabled. Open Vizor after block 123456 '
            '(~1 hr 30 mins) and approve the next migration batch.',
      ),
      _MigrationProgressState.broadcasting => (
        AppIcons.notificationBell,
        'All is well. Broadcasting notes…',
        '~2 hrs 15 mins.\nWe will notify you when it’s ready.',
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
              'Signing window expected in\n'
              '${_migrationTimingFromBody(bodyOverride) ?? '~2 hrs 15 mins'}.\n'
              'We will notify you when it’s ready.',
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
  });

  final String? message;
  final String? actionLabel;
  final String? batchLabel;
  final String? batchValue;
  final VoidCallback? onAction;

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
          onPressed: onAction ?? () {},
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

class _MigrationCompletePreview extends StatelessWidget {
  const _MigrationCompletePreview({this.amountText, this.onDone});

  final String? amountText;
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
            'Your\n${amountText ?? '142.992 ZEC'}\nare on Ironwood!',
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
  const _MigrationModalPreview({required this.background, required this.child});

  final Widget background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MobileModalOverlay(
      background: background,
      child: MobileModalScaffold(
        title: '',
        showTitle: false,
        showClose: false,
        bottomPadding: AppSpacing.base,
        onClose: _noopMigrationPreviewAction,
        child: child,
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
    required this.segments,
    required this.completedSegments,
    required this.highlightedSegments,
  });

  final double dimension;
  final int segments;
  final Set<int> completedSegments;
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
      duration: const Duration(milliseconds: 1400),
      value: 1,
    );
    _opacity = Tween<double>(
      begin: 0.32,
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
        size: Size.square(widget.dimension),
        painter: _MigrationRingPainter(
          trackColor: context.colors.border.subtle,
          activeColor: const Color(0xFF00A460),
          segments: widget.segments,
          completedSegments: widget.completedSegments,
          highlightedSegments: widget.highlightedSegments,
          highlightColor: context.colors.text.accent,
          highlightOpacity: _reducedMotion ? 1 : _opacity.value,
        ),
      ),
    );
  }
}

class _MigrationRingPainter extends CustomPainter {
  const _MigrationRingPainter({
    required this.trackColor,
    required this.activeColor,
    required this.segments,
    this.completedSegments = const {},
    this.highlightedSegments = const {},
    this.highlightColor,
    this.highlightOpacity = 1,
    this.progress,
    this.segmentGap,
  });

  final Color trackColor;
  final Color activeColor;
  final int segments;
  final Set<int> completedSegments;
  final Set<int> highlightedSegments;
  final Color? highlightColor;
  final double highlightOpacity;
  final double? progress;
  final double? segmentGap;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 7;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gap = segmentGap ?? (segments == 1 ? 0.08 : 0.10);
    final segmentSweep = (math.pi * 2 / segments) - gap;
    final clampedProgress = progress?.clamp(0.0, 1.0).toDouble();
    for (var index = 0; index < segments; index++) {
      final start = -math.pi / 2 + index * (math.pi * 2 / segments) + gap / 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 12;
      if (clampedProgress != null) {
        paint.color = trackColor;
        canvas.drawArc(rect, start, segmentSweep, false, paint);
        final segmentProgress = (clampedProgress * segments - index)
            .clamp(0.0, 1.0)
            .toDouble();
        if (segmentProgress > 0) {
          paint.color = activeColor;
          canvas.drawArc(
            rect,
            start,
            segmentSweep * segmentProgress,
            false,
            paint,
          );
        }
        continue;
      }
      paint.color = completedSegments.contains(index)
          ? activeColor
          : highlightedSegments.contains(index)
          ? (highlightColor ?? activeColor).withValues(alpha: highlightOpacity)
          : trackColor;
      canvas.drawArc(rect, start, segmentSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_MigrationRingPainter oldDelegate) {
    return trackColor != oldDelegate.trackColor ||
        activeColor != oldDelegate.activeColor ||
        segments != oldDelegate.segments ||
        completedSegments != oldDelegate.completedSegments ||
        highlightedSegments != oldDelegate.highlightedSegments ||
        highlightColor != oldDelegate.highlightColor ||
        highlightOpacity != oldDelegate.highlightOpacity ||
        progress != oldDelegate.progress ||
        segmentGap != oldDelegate.segmentGap;
  }
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
