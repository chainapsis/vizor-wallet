part of '../ironwood_migration_flow_screen.dart';

class _RedirectTo extends StatefulWidget {
  const _RedirectTo(this.location);

  final String location;

  @override
  State<_RedirectTo> createState() => _RedirectToState();
}

class _RedirectToState extends State<_RedirectTo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(widget.location);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IronwoodMigrationLoadingShell extends StatelessWidget {
  const _IronwoodMigrationLoadingShell({required this.step});

  final IronwoodMigrationFlowStep step;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationFrame(
      toolbar: _toolbarFor(context, step),
      disableSidebarActions: step != IronwoodMigrationFlowStep.options,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _IronwoodMigrationShell extends StatelessWidget {
  const _IronwoodMigrationShell({
    required this.step,
    required this.data,
    this.previewPrivatePlan,
    this.previewReviewStage = IronwoodMigrationReviewPreviewStage.review,
    this.onOpenReleaseNotesOverride,
  });

  final IronwoodMigrationFlowStep step;
  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final IronwoodMigrationReviewPreviewStage previewReviewStage;
  final VoidCallback? onOpenReleaseNotesOverride;

  @override
  Widget build(BuildContext context) {
    final content = switch (step) {
      IronwoodMigrationFlowStep.prepare => const Center(
        child: CircularProgressIndicator(),
      ),
      IronwoodMigrationFlowStep.intro => _IronwoodMigrationIntroContent(
        data: data,
        onOpenReleaseNotes: () =>
            _openReleaseNotes(context, override: onOpenReleaseNotesOverride),
      ),
      IronwoodMigrationFlowStep.howItWorks =>
        _IronwoodMigrationHowItWorksContent(data: data),
      IronwoodMigrationFlowStep.options => _IronwoodMigrationOptionsContent(
        data: data,
      ),
      IronwoodMigrationFlowStep.review =>
        _IronwoodMigrationPrivateReviewContent(
          data: data,
          previewPlan:
              previewReviewStage ==
                  IronwoodMigrationReviewPreviewStage.analyzing
              ? null
              : previewPrivatePlan,
          forceAnalyzing:
              previewReviewStage ==
              IronwoodMigrationReviewPreviewStage.analyzing,
        ),
    };

    return _IronwoodMigrationFrame(
      toolbar: _toolbarFor(context, step),
      disableSidebarActions: step != IronwoodMigrationFlowStep.options,
      child: content,
    );
  }
}

Future<void> _openReleaseNotes(
  BuildContext context, {
  VoidCallback? override,
}) async {
  if (override != null) {
    override();
    return;
  }
  final uri = Uri.parse(kIronwoodMigrationReleaseNotesUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Widget _toolbarFor(BuildContext context, IronwoodMigrationFlowStep step) {
  return AppPaneToolbar(
    leading: AppBackLink(
      label: switch (step) {
        IronwoodMigrationFlowStep.prepare => 'Home',
        IronwoodMigrationFlowStep.intro => 'Home',
        IronwoodMigrationFlowStep.howItWorks => 'Ironwood Pool',
        IronwoodMigrationFlowStep.options => 'How Migration Works',
        IronwoodMigrationFlowStep.review => 'Migration Options',
      },
      onTap: () {
        switch (step) {
          case IronwoodMigrationFlowStep.prepare:
            context.go('/home');
          case IronwoodMigrationFlowStep.intro:
            context.go('/home');
          case IronwoodMigrationFlowStep.howItWorks:
            context.go('/migration/intro');
          case IronwoodMigrationFlowStep.options:
            context.go('/migration/how-it-works');
          case IronwoodMigrationFlowStep.review:
            context.go('/migration/options');
        }
      },
    ),
  );
}

Widget _privateStatusToolbar(BuildContext context) {
  return AppPaneToolbar(
    leading: AppBackLink(label: 'Home', onTap: () => context.go('/home')),
  );
}

class _IronwoodMigrationFrame extends StatelessWidget {
  const _IronwoodMigrationFrame({
    required this.toolbar,
    required this.child,
    required this.disableSidebarActions,
  });

  final Widget toolbar;
  final Widget child;
  final bool disableSidebarActions;

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: ColoredBox(color: context.colors.background.window),
      sidebar: AppMainSidebar(
        disabledRoutePaths: disableSidebarActions
            ? const {'/swap', '/voting'}
            : const {},
      ),
      pane: AppPaneScrollScaffold(
        toolbar: toolbar,
        child: Align(alignment: Alignment.topCenter, child: child),
      ),
    );
  }
}

class _IronwoodMigrationIntroContent extends StatelessWidget {
  const _IronwoodMigrationIntroContent({
    required this.data,
    required this.onOpenReleaseNotes,
  });

  final IronwoodMigrationFlowData data;
  final VoidCallback onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = data.amountText;
    final isDark = colors.background.window == AppColors.dark.background.window;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 16,
            width: 420,
            height: 200,
            child: _PoolMigrationHero(data: data),
          ),
          Positioned(
            left: 0,
            top: 250,
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _DarkBadge(label: 'Zcash Network Upgrade'),
                const SizedBox(height: 24),
                SvgPicture.asset(
                  'assets/illustrations/ironwood_wordmark.svg',
                  width: 290,
                  height: 39,
                  colorFilter: ColorFilter.mode(
                    colors.text.accent,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 352,
                  child: Text(
                    'A new shielded pool for Zcash.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 328,
                  child: Text(
                    'Your $amount ZEC is currently in Orchard.\n'
                    'To keep using these funds for shielded payments, '
                    'you will need to move them to Ironwood. You will '
                    'review the migration plan before any funds move.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark ? colors.text.muted : colors.text.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 540,
            width: 230,
            child: _FlowButtons(
              primaryKey: const ValueKey(
                'ironwood_migration_intro_continue_button',
              ),
              primaryLabel: 'Next',
              onPrimary: () => context.go('/migration/how-it-works'),
              secondaryLabel: 'Official Announcement',
              onSecondary: onOpenReleaseNotes,
              secondaryLeading: const AppIcon(AppIcons.link, size: 16),
              secondaryFirst: true,
              spacing: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationHowItWorksContent extends StatelessWidget {
  const _IronwoodMigrationHowItWorksContent({required this.data});

  final IronwoodMigrationFlowData data;

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
            top: 24,
            width: 396,
            child: Text(
              'How Migration Works',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 81.5,
            width: 396,
            child: const Column(
              children: [
                _ProcessCard(
                  steps: [
                    _ProcessStepData(
                      number: 1,
                      title: 'Choose how you migrate',
                      body:
                          'Compare a privacy-optimized schedule with a faster '
                          'migration.',
                    ),
                    _ProcessStepData(
                      number: 2,
                      title: 'Prepare your balance',
                      body:
                          'Vizor reorganizes your balance into common-sized '
                          'parts before migration begins.',
                    ),
                    _ProcessStepData(
                      number: 3,
                      title: 'Move to Ironwood',
                      body:
                          'Privacy-optimized migrations send parts at staggered '
                          'times to reduce linkability.',
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _SpendAsFundsArriveCard(),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 540,
            width: 230,
            child: AppButton(
              key: const ValueKey(
                'ironwood_migration_how_it_works_continue_button',
              ),
              onPressed: () => context.go('/migration/options'),
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              child: const Text(
                'Continue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationOptionsContent extends StatefulWidget {
  const _IronwoodMigrationOptionsContent({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  State<_IronwoodMigrationOptionsContent> createState() =>
      _IronwoodMigrationOptionsContentState();
}

class _IronwoodMigrationOptionsContentState
    extends State<_IronwoodMigrationOptionsContent> {
  var _selected = _MigrationMode.private;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 49,
            top: 68,
            width: 322,
            child: Column(
              children: [
                Text(
                  'Choose How to Migrate',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 322,
                  child: Text(
                    'Choose between more privacy over time or a faster '
                    'migration. You can review the details before anything '
                    'moves.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 193,
            width: 396,
            child: Column(
              children: [
                _MigrationOptionCard(
                  key: const ValueKey('ironwood_migration_private_option'),
                  mode: _MigrationMode.private,
                  selected: _selected == _MigrationMode.private,
                  title: 'Privacy optimized',
                  badge: 'Recommended',
                  body: 'Sends independent parts over different time windows.',
                  onTap: () =>
                      setState(() => _selected = _MigrationMode.private),
                ),
                const SizedBox(height: 12),
                _MigrationOptionCard(
                  key: const ValueKey('ironwood_migration_fast_option'),
                  mode: _MigrationMode.fast,
                  selected: _selected == _MigrationMode.fast,
                  title: 'Faster but less private',
                  body: 'Coming soon. Moves funds sooner with less separation.',
                  onTap: () => setState(() => _selected = _MigrationMode.fast),
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              key: const ValueKey('ironwood_migration_select_review_button'),
              onPressed: _selected == _MigrationMode.private
                  ? () => context.go('/migration/private/review')
                  : null,
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: const Text('Select & Review'),
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationPrivateStatusContent extends ConsumerStatefulWidget {
  const _IronwoodMigrationPrivateStatusContent({
    required this.status,
    this.accountUuid,
  });

  final rust_sync.MigrationStatus status;
  final String? accountUuid;

  @override
  ConsumerState<_IronwoodMigrationPrivateStatusContent> createState() =>
      _IronwoodMigrationPrivateStatusContentState();
}

class _IronwoodMigrationPrivateStatusContentState
    extends ConsumerState<_IronwoodMigrationPrivateStatusContent> {
  Future<void> _handleAction(_StatusAction action) async {
    final accountUuid = widget.accountUuid;
    if (accountUuid == null) return;
    if (action == _StatusAction.needsInput) {
      context.go('/migration/private/keystone/batch/sign');
      return;
    }
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retry(accountUuid);
    } catch (e) {
      log('Migration continuation failed: $e');
    }
    _invalidateIronwoodMigrationStatusState(
      ref,
      statusRequest: IronwoodMigrationStatusRequest(
        network: ref.read(ironwoodMigrationInputsProvider).network,
        accountUuid: accountUuid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = widget.status;
    final presentation = _statusPresentation(status);
    final progress = _statusProgress(status);
    final syncState = ref.watch(syncProvider).asData?.value;
    final currentHeight = _currentMigrationHeight(syncState);
    final accountState = ref.watch(accountProvider).value;
    final isHardware =
        accountState?.accounts
            .where((account) => account.uuid == widget.accountUuid)
            .any((account) => account.isHardware) ??
        false;
    final action = _statusAction(status, isHardware: isHardware);
    final canUseAction = widget.accountUuid != null;
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    final isAdvancing =
        widget.accountUuid != null &&
        coordinator.advancingAccounts.contains(widget.accountUuid);
    final actionLabel = isAdvancing
        ? action.busyLabel
        : switch (action) {
            _StatusAction.needsInput || _StatusAction.retry => action.label,
            _StatusAction.backHome ||
            _StatusAction.none => presentation.buttonLabel,
          };
    final coordinatorError = widget.accountUuid == null
        ? null
        : coordinator.errors[widget.accountUuid!];
    final footerText = coordinatorError == null
        ? presentation.footer
        : _privateMigrationContinueErrorMessage(coordinatorError);
    final actionCallback = switch (action) {
      _StatusAction.needsInput || _StatusAction.retry =>
        canUseAction ? () => unawaited(_handleAction(action)) : null,
      _StatusAction.backHome => () => context.go('/home'),
      _StatusAction.none => null,
    };

    if ((status.activeRunId != null ||
            status.phase == kIronwoodMigrationCompletePhase) &&
        {
          kIronwoodMigrationWaitingDenomConfirmationsPhase,
          kIronwoodMigrationReadyToMigratePhase,
          kIronwoodMigrationBroadcastScheduledPhase,
          kIronwoodMigrationBroadcastingPhase,
          kIronwoodMigrationWaitingConfirmationsPhase,
          kIronwoodMigrationCompletePhase,
        }.contains(status.phase)) {
      return _MigrationStatusContent(
        status: status,
        action: action,
        isAdvancing: isAdvancing,
        currentHeight: currentHeight,
        onAction: actionCallback,
      );
    }

    return SizedBox(
      key: ValueKey('ironwood_migration_status_${status.phase}'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 29,
            top: 48,
            width: 362,
            child: Column(
              children: [
                Text(
                  presentation.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 318,
                  child: Text(
                    presentation.body,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 210,
            width: 396,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                child: Column(
                  children: [
                    if (progress != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: colors.background.raised,
                          color: GreenPrimitives.p500Light,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _ReviewMetricRow(
                      icon: AppIcons.swapArrows,
                      label: 'Split progress',
                      value:
                          '${status.denominationSplitCompletedCount}/'
                          '${status.denominationSplitTotalCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.time,
                      label: 'Pending broadcasts',
                      value: '${status.pendingTxCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.plane,
                      label: 'Broadcasted',
                      value: '${status.broadcastedTxCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.checkCircle,
                      label: 'Confirmed',
                      value: '${status.confirmedTxCount}/${status.totalCount}',
                    ),
                    if (status.message != null) ...[
                      const SizedBox(height: 18),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.border.subtle,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        status.message!,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 51,
            top: 515,
            width: 318,
            child: Text(
              footerText,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              key: const ValueKey('ironwood_migration_status_action_button'),
              onPressed: isAdvancing ? null : actionCallback,
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: Text(
                actionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationPrivateStatusErrorContent extends StatelessWidget {
  const _IronwoodMigrationPrivateStatusErrorContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 29,
            top: 74,
            width: 362,
            child: Column(
              children: [
                Text(
                  'Migration status unavailable',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 318,
                  child: Text(
                    "Vizor couldn't verify the current Ironwood migration "
                    'state. No new migration will start until the status can '
                    'be checked.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 262,
            width: 396,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                child: Text(
                  'Return home and try again after sync refreshes. If a '
                  'migration is already in progress, Vizor will continue from '
                  'the saved state after it can be read.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              onPressed: () => context.go('/home'),
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: const Text(
                'Back home',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.title,
    required this.body,
    required this.footer,
    required this.buttonLabel,
  });

  final String title;
  final String body;
  final String footer;
  final String buttonLabel;
}

enum _StatusAction { none, needsInput, retry, backHome }

extension _StatusActionLabels on _StatusAction {
  String get label => switch (this) {
    _StatusAction.needsInput => 'Sign with Keystone',
    _StatusAction.retry => 'Retry migration',
    _StatusAction.backHome => 'Back home',
    _StatusAction.none => '',
  };

  String get busyLabel => switch (this) {
    _StatusAction.retry => 'Retrying...',
    _ => 'Continuing...',
  };
}

_StatusAction _statusAction(
  rust_sync.MigrationStatus status, {
  required bool isHardware,
}) {
  return switch (status.phase) {
    kIronwoodMigrationWaitingDenomConfirmationsPhase => _StatusAction.none,
    kIronwoodMigrationReadyToMigratePhase =>
      isHardware ? _StatusAction.needsInput : _StatusAction.none,
    kIronwoodMigrationFailedRecoverablePhase => _StatusAction.retry,
    kIronwoodMigrationCompletePhase => _StatusAction.backHome,
    _ => _StatusAction.none,
  };
}

_StatusPresentation _statusPresentation(rust_sync.MigrationStatus status) {
  return switch (status.phase) {
    kIronwoodMigrationWaitingDenomConfirmationsPhase =>
      const _StatusPresentation(
        title: 'Preparing...',
        body: 'This will take around 10-20m',
        footer: 'You can leave this screen.\nBut keep Vizor open & running.',
        buttonLabel: '',
      ),
    kIronwoodMigrationReadyToMigratePhase => const _StatusPresentation(
      title: 'Ready to Migrate',
      body:
          'The private split is ready. The next step will prepare the '
          'Ironwood migration batch.',
      footer:
          'Continue migration to prepare and broadcast the Ironwood '
          'transaction when it is due.',
      buttonLabel: 'Continue migration',
    ),
    kIronwoodMigrationBroadcastScheduledPhase => const _StatusPresentation(
      title: 'Broadcast Scheduled',
      body:
          'Your migration transaction is prepared and waiting for its '
          'scheduled broadcast window.',
      footer:
          'When Vizor is open, scheduled broadcasts will be advanced by the '
          'migration worker.',
      buttonLabel: 'Continue migration',
    ),
    kIronwoodMigrationBroadcastingPhase => const _StatusPresentation(
      title: 'Migrating...',
      body:
          'Vizor is broadcasting the prepared Ironwood migration transaction.',
      footer: 'You can leave this screen.\nBut keep Vizor open & running.',
      buttonLabel: 'Broadcasting',
    ),
    kIronwoodMigrationWaitingConfirmationsPhase => const _StatusPresentation(
      title: 'Migrating...',
      body:
          'The migration transaction was broadcast. Vizor is waiting for '
          'network confirmations.',
      footer: 'You can leave this screen.\nBut keep Vizor open & running.',
      buttonLabel: 'Waiting for confirmations',
    ),
    kIronwoodMigrationCompletePhase => const _StatusPresentation(
      title: 'Migration Complete',
      body: 'Your funds have moved into the Ironwood pool.',
      footer: 'You can return home and continue using Vizor.',
      buttonLabel: 'Back home',
    ),
    kIronwoodMigrationPausedPhase => const _StatusPresentation(
      title: 'Migration Paused',
      body: 'The private migration is paused before the next action.',
      footer:
          'No new transaction will be prepared until migration execution is '
          'resumed.',
      buttonLabel: 'Paused',
    ),
    kIronwoodMigrationFailedRecoverablePhase => const _StatusPresentation(
      title: 'Migration Needs Attention',
      body:
          'Vizor hit a recoverable migration error before completing the '
          'Ironwood transition.',
      footer:
          'No funds are lost. Retry migration after checking that Vizor is '
          'synced and online.',
      buttonLabel: 'Retry migration',
    ),
    _ => const _StatusPresentation(
      title: 'Migration Status',
      body: 'Vizor is tracking the current Ironwood migration state.',
      footer:
          'This state is visible for diagnostics while the migration flow is '
          'being connected.',
      buttonLabel: 'Migration in progress',
    ),
  };
}

double? _statusProgress(rust_sync.MigrationStatus status) {
  if (status.phase == kIronwoodMigrationFailedRecoverablePhase ||
      status.phase == kIronwoodMigrationPausedPhase) {
    return null;
  }
  if (status.phase == kIronwoodMigrationCompletePhase) return 1;

  if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
    final target = status.denominationConfirmationTarget;
    if (target > 0) {
      return (status.denominationConfirmationCount / target).clamp(0, 1);
    }
    final total = status.denominationSplitTotalCount;
    if (total > 0) {
      return (status.denominationSplitCompletedCount / total).clamp(0, 1);
    }
    return 0.25;
  }

  final partProgress = _migrationPartProgress(status);
  if (partProgress != null) return partProgress;

  final total = status.totalCount;
  if (total > 0) {
    return (status.confirmedTxCount / total).clamp(0, 1);
  }

  return switch (status.phase) {
    kIronwoodMigrationReadyToMigratePhase => 0.45,
    kIronwoodMigrationBroadcastScheduledPhase => 0.65,
    kIronwoodMigrationBroadcastingPhase => 0.75,
    kIronwoodMigrationWaitingConfirmationsPhase => 0.85,
    _ => 0.1,
  };
}
