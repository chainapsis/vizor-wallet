part of '../ironwood_migration_flow_screen.dart';

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
  Future<void> _confirmStop() async {
    final accountUuid = widget.accountUuid;
    final runId = widget.status.activeRunId;
    if (accountUuid == null || runId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DesktopMigrationStopDialog(),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .stop(accountUuid: accountUuid, runId: runId);
      if (mounted) context.go('/home');
    } catch (e) {
      log('Migration stop failed: $e');
    }
  }

  Future<void> _confirmFinishImmediately() async {
    final accountUuid = widget.accountUuid;
    final runId = widget.status.activeRunId;
    if (accountUuid == null || runId == null) return;
    try {
      final network = ref.read(ironwoodMigrationInputsProvider).network;
      final plan = await ref
          .read(ironwoodMigrationServiceProvider)
          .immediatePlan(network: network, accountUuid: accountUuid);
      if (plan == null) {
        throw StateError(
          'No remaining Orchard balance is available to migrate.',
        );
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _DesktopMigrationFinishImmediatelyDialog(plan: plan),
      );
      if (confirmed != true || !mounted) return;
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .finishImmediately(
            accountUuid: accountUuid,
            runId: runId,
            approvedPlan: plan,
          );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ref
            .read(ironwoodMigrationCoordinatorProvider.notifier)
            .reportAccountError(accountUuid: accountUuid, error: e);
      }
      log('Immediate migration completion failed: $e');
    }
  }

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
    final accountState = ref.watch(accountProvider).value;
    final isHardware =
        accountState?.accounts
            .where((account) => account.uuid == widget.accountUuid)
            .any((account) => account.isHardware) ??
        false;
    final action = _statusAction(status, isHardware: isHardware);
    final canUseAction = widget.accountUuid != null;
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    final syncState = ref.watch(syncProvider).asData?.value;
    final isAdvancing =
        widget.accountUuid != null &&
        coordinator.advancingAccounts.contains(widget.accountUuid);
    final isStopping =
        widget.accountUuid != null &&
        coordinator.stoppingAccounts.contains(widget.accountUuid);
    final isFinishingImmediately =
        widget.accountUuid != null &&
        coordinator.finishingImmediatelyAccounts.contains(widget.accountUuid);
    final immediatePlan = !isHardware && widget.accountUuid != null
        ? ref
              .watch(
                ironwoodActiveMigrationImmediatePlanProvider(
                  ironwoodActiveMigrationImmediatePlanRequest(
                    network: ref.watch(ironwoodMigrationInputsProvider).network,
                    accountUuid: widget.accountUuid!,
                    status: status,
                    observedHeight: syncState?.scannedHeight ?? 0,
                  ),
                ),
              )
              .value
        : null;
    final canFinishImmediately =
        !isHardware &&
        (status.phase == kIronwoodMigrationImmediatePendingPhase ||
            immediatePlan != null);
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
      return _withStopAction(
        _MigrationStatusContent(
          status: status,
          currentHeight: _currentMigrationHeight(syncState),
          action: action,
          isAdvancing: isAdvancing,
          onAction: actionCallback,
        ),
        isStopping: isStopping,
        isFinishingImmediately: isFinishingImmediately,
        canFinishImmediately: canFinishImmediately,
      );
    }

    return _withStopAction(
      SizedBox(
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
                        value:
                            '${status.confirmedTxCount}/${status.totalCount}',
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
      ),
      isStopping: isStopping,
      isFinishingImmediately: isFinishingImmediately,
      canFinishImmediately: canFinishImmediately,
    );
  }

  Widget _withStopAction(
    Widget child, {
    required bool isStopping,
    required bool isFinishingImmediately,
    required bool canFinishImmediately,
  }) {
    if (widget.status.activeRunId == null ||
        (!canFinishImmediately && !widget.status.canAbandon)) {
      return child;
    }
    return Stack(
      children: [
        child,
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canFinishImmediately) ...[
                AppButton(
                  key: const ValueKey(
                    'ironwood_finish_migration_immediately_button',
                  ),
                  height: 32,
                  expand: false,
                  onPressed: isStopping || isFinishingImmediately
                      ? null
                      : () => unawaited(_confirmFinishImmediately()),
                  child: Text(
                    isFinishingImmediately
                        ? 'Finishing...'
                        : 'Finish immediately',
                  ),
                ),
                if (widget.status.canAbandon)
                  const SizedBox(width: AppSpacing.xxs),
              ],
              if (widget.status.canAbandon)
                AppButton(
                  key: const ValueKey('ironwood_stop_migration_button'),
                  height: 32,
                  expand: false,
                  variant: AppButtonVariant.ghost,
                  onPressed: isStopping || isFinishingImmediately
                      ? null
                      : () => unawaited(_confirmStop()),
                  child: Text(isStopping ? 'Stopping...' : 'Stop migration'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopMigrationFinishImmediatelyDialog extends StatelessWidget {
  const _DesktopMigrationFinishImmediatelyDialog({required this.plan});

  final rust_sync.OrchardMigrationImmediatePlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Finish migration immediately?',
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The remaining ${_formatZecAmountCompact(plan.migratedZatoshi)} '
                'ZEC will move in one transaction with an estimated fee of '
                '${_formatZecAmountCompact(plan.feeZatoshi)} ZEC. This is '
                'faster, but reveals the remaining amount and timing together.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey(
                  'ironwood_confirm_finish_migration_immediately_button',
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Finish immediately'),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                variant: AppButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep private migration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopMigrationStopDialog extends StatelessWidget {
  const _DesktopMigrationStopDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Stop migration?',
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vizor will discard work that has not been submitted. '
                'Transactions already sent to the network cannot be cancelled '
                'and will remain in your wallet history.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('ironwood_confirm_stop_migration_button'),
                variant: AppButtonVariant.destructive,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Stop migration'),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                variant: AppButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep migrating'),
              ),
            ],
          ),
        ),
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
      isHardware &&
              (status.currentSigningPartIndices == null ||
                  status.currentSigningPartIndices!.isNotEmpty)
          ? _StatusAction.needsInput
          : _StatusAction.none,
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
        body: 'This usually takes around 30 minutes per split.',
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
    kIronwoodMigrationImmediatePendingPhase => const _StatusPresentation(
      title: 'Finishing migration',
      body:
          'The Immediate migration transaction is saved and awaiting network '
          'reconciliation.',
      footer: 'Retry Finish immediately when the wallet is online.',
      buttonLabel: 'Awaiting submission',
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
      status.phase == kIronwoodMigrationPausedPhase ||
      status.phase == kIronwoodMigrationImmediatePendingPhase) {
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
