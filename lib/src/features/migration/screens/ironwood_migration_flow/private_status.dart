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
    final presentation = _statusPresentation(context.l10n, status);
    final progress = _statusProgress(status);
    final accountState = ref.watch(accountProvider).value;
    AccountInfo? account;
    for (final candidate in accountState?.accounts ?? const <AccountInfo>[]) {
      if (candidate.uuid == widget.accountUuid) {
        account = candidate;
        break;
      }
    }
    final action = _statusAction(
      status,
      isKeystone: account?.isKeystone ?? false,
    );
    final canUseAction = widget.accountUuid != null;
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    final syncState = ref.watch(syncProvider).asData?.value;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final isAdvancing =
        widget.accountUuid != null &&
        coordinator.advancingAccounts.contains(widget.accountUuid);
    final actionLabel = isAdvancing
        ? action.busyLabel(context.l10n)
        : switch (action) {
            _StatusAction.needsInput ||
            _StatusAction.retry => action.label(context.l10n),
            _StatusAction.backHome ||
            _StatusAction.none => presentation.buttonLabel,
          };
    final coordinatorError = widget.accountUuid == null
        ? null
        : coordinator.errors[widget.accountUuid!];
    final ledgerSigningUnsupported =
        (account?.isLedger ?? false) &&
        migrationRequiresKeystoneSignature(status);
    final footerText = coordinatorError == null
        ? ledgerSigningUnsupported
              ? context.l10n.migrationStatusLedgerUnsupported
              : presentation.footer
        : _privateMigrationContinueErrorMessage(context.l10n, coordinatorError);
    final actionCallback = switch (action) {
      _StatusAction.needsInput || _StatusAction.retry =>
        canUseAction ? () => unawaited(_handleAction(action)) : null,
      _StatusAction.backHome => () => context.go('/home'),
      _StatusAction.none => null,
    };

    if (status.phase == kIronwoodMigrationStoppedByUpgradePhase) {
      return _MigrationUpgradeStoppedStatusContent(
        status: status,
        privacyModeEnabled: privacyModeEnabled,
        orchardBalanceZatoshi: ref
            .watch(ironwoodMigrationFlowDataProvider)
            ?.amountZatoshi,
        onMoveRemaining: () => context.go('/migration/options'),
      );
    }

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
        privacyModeEnabled: privacyModeEnabled,
        currentHeight: _currentMigrationHeight(syncState),
        action: action,
        isAdvancing: isAdvancing,
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
                      label: context.l10n.migrationStatusSplitProgress,
                      value:
                          '${status.denominationSplitCompletedCount}/' // l10n-ignore: count format
                          '${status.denominationSplitTotalCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.time,
                      label: context.l10n.migrationStatusPendingBroadcasts,
                      value: '${status.pendingTxCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.plane,
                      label: context.l10n.migrationStatusBroadcasted,
                      value: '${status.broadcastedTxCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.checkCircle,
                      label: context.l10n.migrationBroadcastConfirmed,
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
                        context.l10n.commonDetails(status.message!),
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
                  context.l10n.migrationStatusUnavailableTitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 318,
                  child: Text(
                    context.l10n.migrationStatusUnavailableBody,
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
                  context.l10n.migrationStatusUnavailableHint,
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
              child: Text(
                context.l10n.migrationBackHome,
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
  String label(AppLocalizations l10n) => switch (this) {
    _StatusAction.needsInput => l10n.migrationSignWithKeystone,
    _StatusAction.retry => l10n.migrationRetryMigration,
    _StatusAction.backHome => l10n.migrationBackHome,
    _StatusAction.none => '',
  };

  String busyLabel(AppLocalizations l10n) => switch (this) {
    _StatusAction.retry => l10n.migrationRetrying,
    _ => l10n.migrationContinuing,
  };
}

_StatusAction _statusAction(
  rust_sync.MigrationStatus status, {
  required bool isKeystone,
}) {
  return switch (status.phase) {
    kIronwoodMigrationWaitingDenomConfirmationsPhase => _StatusAction.none,
    kIronwoodMigrationReadyToMigratePhase =>
      isKeystone && migrationRequiresKeystoneSignature(status)
          ? _StatusAction.needsInput
          : _StatusAction.none,
    kIronwoodMigrationFailedRecoverablePhase => _StatusAction.retry,
    kIronwoodMigrationCompletePhase => _StatusAction.backHome,
    _ => _StatusAction.none,
  };
}

_StatusPresentation _statusPresentation(
  AppLocalizations l10n,
  rust_sync.MigrationStatus status,
) {
  return switch (status.phase) {
    kIronwoodMigrationWaitingDenomConfirmationsPhase => _StatusPresentation(
      title: l10n.commonPreparingDots,
      body: l10n.migrationStatusPreparingBody,
      footer: l10n.migrationStatusLeaveFooter,
      buttonLabel: '',
    ),
    kIronwoodMigrationReadyToMigratePhase => _StatusPresentation(
      title: l10n.migrationStatusReadyTitle,
      body: l10n.migrationStatusReadyBody,
      footer: l10n.migrationStatusReadyFooter,
      buttonLabel: l10n.migrationContinueMigration,
    ),
    kIronwoodMigrationBroadcastScheduledPhase => _StatusPresentation(
      title: l10n.migrationStatusScheduledTitle,
      body: l10n.migrationStatusScheduledBody,
      footer: l10n.migrationStatusScheduledFooter,
      buttonLabel: l10n.migrationContinueMigration,
    ),
    kIronwoodMigrationBroadcastingPhase => _StatusPresentation(
      title: l10n.commonMigrating,
      body: l10n.migrationStatusBroadcastingBody,
      footer: l10n.migrationStatusLeaveFooter,
      buttonLabel: l10n.migrationScheduleBroadcasting,
    ),
    kIronwoodMigrationWaitingConfirmationsPhase => _StatusPresentation(
      title: l10n.commonMigrating,
      body: l10n.migrationStatusConfirmingBody,
      footer: l10n.migrationStatusLeaveFooter,
      buttonLabel: l10n.migrationNextActionDetailWaitingForConfirmations,
    ),
    kIronwoodMigrationCompletePhase => _StatusPresentation(
      title: l10n.migrationStatusCompleteTitle,
      body: l10n.migrationStatusCompleteBody,
      footer: l10n.migrationStatusCompleteFooter,
      buttonLabel: l10n.migrationBackHome,
    ),
    kIronwoodMigrationPausedPhase => _StatusPresentation(
      title: l10n.migrationStatusPausedTitle,
      body: l10n.migrationStatusPausedBody,
      footer: l10n.migrationStatusPausedFooter,
      buttonLabel: l10n.migrationStatusPausedButton,
    ),
    kIronwoodMigrationFailedRecoverablePhase => _StatusPresentation(
      title: l10n.migrationStatusAttentionTitle,
      body: l10n.migrationStatusAttentionBody,
      footer: l10n.migrationStatusAttentionFooter,
      buttonLabel: l10n.migrationRetryMigration,
    ),
    _ => _StatusPresentation(
      title: l10n.migrationStatusDefaultTitle,
      body: l10n.migrationStatusDefaultBody,
      footer: l10n.migrationStatusDefaultFooter,
      buttonLabel: l10n.migrationStatusDefaultButton,
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
