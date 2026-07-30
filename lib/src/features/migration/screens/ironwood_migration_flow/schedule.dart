part of '../ironwood_migration_flow_screen.dart';

enum IronwoodMigrationSchedulePreviewOverlay {
  manage,
  immediateConfirmation,
  stopConfirmation,
}

class IronwoodMigrationPreparationScheduleScreen extends StatelessWidget {
  const IronwoodMigrationPreparationScheduleScreen({
    this.previewStatus,
    this.previewOverlay,
    this.previewImmediatePlan,
    this.previewCanStop = false,
    super.key,
  });

  final rust_sync.MigrationStatus? previewStatus;
  final IronwoodMigrationSchedulePreviewOverlay? previewOverlay;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final bool previewCanStop;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationScheduleRoute(
      preparation: true,
      previewStatus: previewStatus,
      previewOverlay: previewOverlay,
      previewImmediatePlan: previewImmediatePlan,
      previewCanStop: previewCanStop,
    );
  }
}

class IronwoodMigrationScheduleScreen extends StatelessWidget {
  const IronwoodMigrationScheduleScreen({
    this.previewStatus,
    this.previewOverlay,
    this.previewImmediatePlan,
    this.previewCanStop = false,
    super.key,
  });

  final rust_sync.MigrationStatus? previewStatus;
  final IronwoodMigrationSchedulePreviewOverlay? previewOverlay;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final bool previewCanStop;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationScheduleRoute(
      preparation: false,
      previewStatus: previewStatus,
      previewOverlay: previewOverlay,
      previewImmediatePlan: previewImmediatePlan,
      previewCanStop: previewCanStop,
    );
  }
}

enum _MigrationManageStage { closed, choose, confirmImmediate, confirmStop }

enum _MigrationManageChoice { immediate, stop }

class _IronwoodMigrationScheduleRoute extends ConsumerStatefulWidget {
  const _IronwoodMigrationScheduleRoute({
    required this.preparation,
    this.previewStatus,
    this.previewOverlay,
    this.previewImmediatePlan,
    this.previewCanStop = false,
  });

  final bool preparation;
  final rust_sync.MigrationStatus? previewStatus;
  final IronwoodMigrationSchedulePreviewOverlay? previewOverlay;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final bool previewCanStop;

  @override
  ConsumerState<_IronwoodMigrationScheduleRoute> createState() =>
      _IronwoodMigrationScheduleRouteState();
}

class _IronwoodMigrationScheduleRouteState
    extends ConsumerState<_IronwoodMigrationScheduleRoute> {
  _MigrationManageStage _manageStage = _MigrationManageStage.closed;
  _MigrationManageChoice _manageChoice = _MigrationManageChoice.immediate;
  String? _managedRunId;
  String? _manageError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final overlay = widget.previewOverlay;
    final runId = widget.previewStatus?.activeRunId;
    if (overlay == null || runId == null) return;
    _managedRunId = runId;
    switch (overlay) {
      case IronwoodMigrationSchedulePreviewOverlay.manage:
        _manageStage = _MigrationManageStage.choose;
      case IronwoodMigrationSchedulePreviewOverlay.immediateConfirmation:
        _manageStage = _MigrationManageStage.confirmImmediate;
      case IronwoodMigrationSchedulePreviewOverlay.stopConfirmation:
        _manageStage = _MigrationManageStage.confirmStop;
        _manageChoice = _MigrationManageChoice.stop;
    }
  }

  void _openManage({
    required rust_sync.MigrationStatus status,
    required bool canFinishImmediately,
  }) {
    final runId = status.activeRunId;
    if (runId == null) return;
    setState(() {
      _manageStage = _MigrationManageStage.choose;
      _manageChoice = canFinishImmediately
          ? _MigrationManageChoice.immediate
          : _MigrationManageChoice.stop;
      _managedRunId = runId;
      _manageError = null;
    });
  }

  void _dismissManage() {
    if (_submitting) return;
    setState(() {
      _manageStage = _MigrationManageStage.closed;
      _managedRunId = null;
      _manageError = null;
    });
  }

  Future<void> _continueManage({
    required rust_sync.MigrationStatus status,
  }) async {
    if (_managedRunId == null ||
        status.activeRunId != _managedRunId ||
        _submitting) {
      return;
    }
    if (!status.canAbandon && !widget.previewCanStop) {
      setState(() {
        _manageError = 'This migration can no longer be cancelled.';
      });
      return;
    }
    setState(() {
      _manageStage = _manageChoice == _MigrationManageChoice.stop
          ? _MigrationManageStage.confirmStop
          : _MigrationManageStage.confirmImmediate;
      _manageError = null;
    });
  }

  Future<void> _confirmManage({
    required rust_sync.MigrationStatus status,
    required IronwoodMigrationStatusRequest request,
  }) async {
    final runId = _managedRunId;
    if (runId == null || status.activeRunId != runId || _submitting) return;

    if (!status.canAbandon && !widget.previewCanStop) {
      setState(() {
        _manageError = 'This migration can no longer be cancelled.';
      });
      return;
    }

    final finishImmediately =
        _manageStage == _MigrationManageStage.confirmImmediate;
    setState(() {
      _submitting = true;
      _manageError = null;
    });
    try {
      final coordinator = ref.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );
      await coordinator.stop(accountUuid: request.accountUuid, runId: runId);
      if (!mounted) return;
      if (finishImmediately) {
        ref.invalidate(ironwoodMigrationImmediatePlanProvider);
        context.go('/migration/immediate/review');
        return;
      }
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _manageError = _migrationManageErrorMessage(error);
        _submitting = false;
      });
      log('Migration schedule management failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.previewStatus;
    final syncState = ref.watch(syncProvider).asData?.value;
    final request = ref.watch(ironwoodMigrationInputsProvider).statusRequest;
    if (preview != null) {
      return _frame(context, preview, syncState, request: request);
    }
    if (request == null) {
      return _frame(context, null, syncState, statusUnavailable: true);
    }
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    return ref
        .watch(ironwoodMigrationStatusProvider(request))
        .when(
          skipLoadingOnReload: true,
          loading: () => _frame(context, null, syncState, request: request),
          error: (_, _) {
            final cachedStatus = coordinator.statuses[request.accountUuid];
            return cachedStatus == null
                ? _frame(
                    context,
                    null,
                    syncState,
                    request: request,
                    statusUnavailable: true,
                    onRetry: () => ref.invalidate(
                      ironwoodMigrationStatusProvider(request),
                    ),
                  )
                : _frame(context, cachedStatus, syncState, request: request);
          },
          data: (status) =>
              _frame(context, status, syncState, request: request),
        );
  }

  Widget _frame(
    BuildContext context,
    rust_sync.MigrationStatus? status,
    SyncState? syncState, {
    IronwoodMigrationStatusRequest? request,
    bool statusUnavailable = false,
    VoidCallback? onRetry,
  }) {
    final canStop =
        request != null &&
        (status?.canAbandon == true ||
            (widget.previewStatus != null && widget.previewCanStop));
    final canFinishImmediately = canStop;
    final canManage =
        status != null &&
        status.activeRunId != null &&
        (canFinishImmediately || canStop);
    final managedRunIsCurrent =
        status != null &&
        _managedRunId != null &&
        status.activeRunId == _managedRunId;
    // A durable stop clears activeRunId before the coordinator finishes its
    // balance and status refreshes. Keep the blocking modal mounted through
    // that gap so the user cannot leave before _confirmManage routes home.
    final showOverlay =
        request != null &&
        status != null &&
        (_submitting ? _managedRunId != null : managedRunIsCurrent) &&
        _manageStage != _MigrationManageStage.closed;

    return _IronwoodMigrationFrame(
      toolbar: AppPaneToolbar(
        leading: AppBackLink(
          key: ValueKey(
            widget.preparation
                ? 'ironwood_migration_preparation_schedule_back_button'
                : 'ironwood_migration_schedule_back_button',
          ),
          label: 'Ironwood Migration',
          onTap: () => context.go('/migration/private/status'),
        ),
      ),
      disableSidebarActions: true,
      overlay: showOverlay
          ? AppPaneModalOverlay(
              onDismiss: _dismissManage,
              child: _MigrationManageModal(
                stage: _manageStage,
                choice: _manageChoice,
                canFinishImmediately: canFinishImmediately,
                canStop: canStop,
                submitting: _submitting,
                error: _manageError,
                onChoiceChanged: (choice) {
                  setState(() {
                    _manageChoice = choice;
                    _manageError = null;
                  });
                },
                onCancel: _dismissManage,
                onContinue: () => unawaited(_continueManage(status: status)),
                onConfirm: () =>
                    unawaited(_confirmManage(status: status, request: request)),
              ),
            )
          : null,
      child: statusUnavailable
          ? _MigrationScheduleErrorContent(onRetry: onRetry)
          : status == null
          ? const Center(child: CircularProgressIndicator())
          : widget.preparation
          ? _MigrationPreparationScheduleContent(
              status: status,
              currentHeight: _currentMigrationHeight(syncState),
              onManage: canManage
                  ? () => _openManage(
                      status: status,
                      canFinishImmediately: canFinishImmediately,
                    )
                  : null,
            )
          : _MigrationScheduleContent(
              status: status,
              currentHeight: _currentMigrationHeight(syncState),
              onManage: canManage
                  ? () => _openManage(
                      status: status,
                      canFinishImmediately: canFinishImmediately,
                    )
                  : null,
            ),
    );
  }
}

String _migrationManageErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('No remaining Orchard balance')) {
    return 'There is no remaining Orchard balance to migrate.';
  }
  return 'The migration could not be updated. Please try again.';
}

class _MigrationManageButton extends StatelessWidget {
  const _MigrationManageButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppButton(
        key: const ValueKey('ironwood_migration_schedule_manage_button'),
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.mediumLarge,
        height: 36,
        expand: false,
        leading: const AppIcon(AppIcons.wrench, size: 16),
        onPressed: onPressed,
        child: const Text('Manage'),
      ),
    );
  }
}

class _MigrationManageModal extends StatelessWidget {
  const _MigrationManageModal({
    required this.stage,
    required this.choice,
    required this.canFinishImmediately,
    required this.canStop,
    required this.submitting,
    required this.error,
    required this.onChoiceChanged,
    required this.onCancel,
    required this.onContinue,
    required this.onConfirm,
  });

  final _MigrationManageStage stage;
  final _MigrationManageChoice choice;
  final bool canFinishImmediately;
  final bool canStop;
  final bool submitting;
  final String? error;
  final ValueChanged<_MigrationManageChoice> onChoiceChanged;
  final VoidCallback onCancel;
  final VoidCallback onContinue;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return AppModalCard(
      key: const ValueKey('ironwood_migration_manage_modal'),
      child: switch (stage) {
        _MigrationManageStage.choose => _buildChoice(context),
        _MigrationManageStage.confirmImmediate => _buildImmediate(context),
        _MigrationManageStage.confirmStop => _buildStop(context),
        _MigrationManageStage.closed => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildChoice(BuildContext context) {
    final colors = context.colors;
    final choiceIsAvailable = switch (choice) {
      _MigrationManageChoice.immediate => canFinishImmediately,
      _MigrationManageChoice.stop => canStop,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Manage Migration',
          style: AppTypography.bodyLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _MigrationManageChoiceRow(
          key: const ValueKey('ironwood_migration_manage_immediate_option'),
          label: 'Switch to Immediate',
          selected: choice == _MigrationManageChoice.immediate,
          enabled: canFinishImmediately,
          onTap: () => onChoiceChanged(_MigrationManageChoice.immediate),
        ),
        const SizedBox(height: AppSpacing.xs),
        _MigrationManageChoiceRow(
          key: const ValueKey('ironwood_migration_manage_stop_option'),
          label: 'Stop Migration',
          selected: choice == _MigrationManageChoice.stop,
          enabled: canStop,
          onTap: () => onChoiceChanged(_MigrationManageChoice.stop),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _MigrationManageError(message: error!),
        ],
        const SizedBox(height: AppSpacing.md),
        AppModalActions(
          onCancel: submitting ? null : onCancel,
          actionLabel: submitting ? 'Loading...' : 'Continue',
          onAction: submitting || !choiceIsAvailable ? null : onContinue,
          actionLeading: submitting
              ? const AppIcon(AppIcons.loader, size: 16)
              : null,
          cancelKey: const ValueKey('ironwood_migration_manage_cancel_button'),
          actionKey: const ValueKey(
            'ironwood_migration_manage_continue_button',
          ),
        ),
      ],
    );
  }

  Widget _buildImmediate(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Switch to Immediate',
          style: AppTypography.bodyLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Process the remaining migration immediately.',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _MigrationManageBullet(
          text:
              'Remaining split notes will be processed as an immediate '
              'migration, slightly increasing traceability',
        ),
        const SizedBox(height: AppSpacing.xs),
        const _MigrationManageBullet(
          text: 'Transactions already broadcast will not be reverted',
        ),
        const SizedBox(height: AppSpacing.xs),
        const _MigrationManageBullet(
          text: 'There’s no way to revert an immediate migration',
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _MigrationManageError(message: error!),
        ],
        const SizedBox(height: AppSpacing.md),
        AppModalActions(
          onCancel: submitting ? null : onCancel,
          actionLabel: submitting ? 'Stopping...' : 'Confirm',
          onAction: submitting || !canFinishImmediately ? null : onConfirm,
          actionLeading: AppIcon(
            submitting ? AppIcons.loader : AppIcons.migrationFast,
            size: 16,
          ),
          cancelKey: const ValueKey(
            'ironwood_migration_immediate_confirm_cancel_button',
          ),
          actionKey: const ValueKey(
            'ironwood_confirm_finish_migration_immediately_button',
          ),
        ),
      ],
    );
  }

  Widget _buildStop(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Are you sure you want to stop?',
          style: AppTypography.bodyLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This cancels the remaining scheduled migration transactions. '
          'You can re-start the migration from the home page.',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _MigrationManageError(message: error!),
        ],
        const SizedBox(height: AppSpacing.md),
        AppModalActions(
          onCancel: submitting ? null : onCancel,
          actionLabel: submitting ? 'Cancelling...' : 'Confirm',
          onAction: submitting || !canStop ? null : onConfirm,
          actionVariant: AppButtonVariant.destructive,
          actionLeading: submitting
              ? const AppIcon(AppIcons.loader, size: 16)
              : null,
          cancelKey: const ValueKey(
            'ironwood_migration_stop_confirm_cancel_button',
          ),
          actionKey: const ValueKey('ironwood_confirm_stop_migration_button'),
        ),
      ],
    );
  }
}

class _MigrationManageChoiceRow extends StatefulWidget {
  const _MigrationManageChoiceRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_MigrationManageChoiceRow> createState() =>
      _MigrationManageChoiceRowState();
}

class _MigrationManageChoiceRowState extends State<_MigrationManageChoiceRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.label,
      child: Focus(
        canRequestFocus: widget.enabled,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        onKeyEvent: (_, event) {
          if (!widget.enabled || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: widget.selected || _focused
                  ? Border.all(color: colors.border.strong, width: 2)
                  : null,
            ),
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        style: AppTypography.labelLarge.copyWith(
                          color: widget.enabled
                              ? colors.text.accent
                              : colors.text.disabled,
                        ),
                      ),
                    ),
                    _MigrationManageRadio(
                      selected: widget.selected,
                      enabled: widget.enabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MigrationManageRadio extends StatelessWidget {
  const _MigrationManageRadio({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected && enabled
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: selected && enabled
          ? AppIcon(AppIcons.check, size: 12, color: colors.icon.inverse)
          : null,
    );
  }
}

class _MigrationManageBullet extends StatelessWidget {
  const _MigrationManageBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '•',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _MigrationManageError extends StatelessWidget {
  const _MigrationManageError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      key: const ValueKey('ironwood_migration_manage_error'),
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.destructive,
      ),
    );
  }
}

class _MigrationPreparationScheduleContent extends StatelessWidget {
  const _MigrationPreparationScheduleContent({
    required this.status,
    required this.currentHeight,
    this.onManage,
  });

  final rust_sync.MigrationStatus status;
  final int currentHeight;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final transactions = orderedMigrationPreparationTransactions(status);
    final rounds = _preparationRounds(transactions);
    final currentRound = _currentPreparationRound(rounds);
    final projectionIsRecalculating = transactions.any(
      (transaction) =>
          transaction.state ==
              rust_sync.MigrationPreparationTransactionState.awaitingInputs &&
          transaction.projectedHeight <= currentHeight,
    );
    final hasCompletionProjection =
        transactions.isNotEmpty && !projectionIsRecalculating;
    final finalProjectedHeight = transactions.fold<int>(
      currentHeight,
      (height, transaction) =>
          math.max(height, transaction.projectedCompletionHeight),
    );
    final remainingBlocks = math.max(0, finalProjectedHeight - currentHeight);

    return SizedBox(
      key: const ValueKey('ironwood_migration_preparation_schedule_content'),
      width: 420,
      height: 656,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: Center(
              child: Text(
                key: const ValueKey(
                  'ironwood_migration_preparation_schedule_title',
                ),
                'Preparation Schedule',
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              key: const ValueKey(
                'ironwood_migration_preparation_schedule_summary',
              ),
              height: 104,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    _MigrationSummaryMetric(
                      label: 'Current round',
                      value: rounds.isEmpty
                          ? 'Preparing'
                          : '$currentRound of ${rounds.length}',
                    ),
                    const SizedBox(height: 16),
                    _MigrationSummaryMetric(
                      label: 'Ready to migrate',
                      value: !hasCompletionProjection
                          ? 'Calculating'
                          : '#${formatGroupedInteger(finalProjectedHeight)}'
                                '${remainingBlocks > 0 ? ' · ${_formatPreparationDuration(remainingBlocks)}' : ''}',
                      valueIcon: hasCompletionProjection
                          ? AppIcons.block
                          : null,
                      secondary: true,
                    ),
                    const SizedBox(height: 16),
                    _MigrationSummaryMetric(
                      label: 'Current block',
                      value: formatGroupedInteger(currentHeight),
                      valueIcon: AppIcons.block,
                      secondary: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onManage != null) ...[
            const SizedBox(height: 8),
            _MigrationManageButton(onPressed: onManage!),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 12),
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Text(
                      'Preparing schedule',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListView.builder(
                      key: const ValueKey(
                        'ironwood_migration_preparation_schedule_list',
                      ),
                      padding: EdgeInsets.zero,
                      itemCount: rounds.length,
                      itemBuilder: (context, index) =>
                          _MigrationPreparationRoundSection(
                            round: rounds[index],
                            currentHeight: currentHeight,
                          ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

typedef _NumberedPreparationTransaction = ({
  int number,
  rust_sync.MigrationPreparationTransactionStatus transaction,
});

class _PreparationRound {
  const _PreparationRound({required this.number, required this.transactions});

  final int number;
  final List<_NumberedPreparationTransaction> transactions;
}

List<_PreparationRound> _preparationRounds(
  List<rust_sync.MigrationPreparationTransactionStatus> transactions,
) {
  final grouped = <int, List<_NumberedPreparationTransaction>>{};
  for (var index = 0; index < transactions.length; index++) {
    final transaction = transactions[index];
    grouped.putIfAbsent(transaction.round, () => []).add((
      number: index + 1,
      transaction: transaction,
    ));
  }
  final rounds = grouped.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return rounds
      .map(
        (entry) =>
            _PreparationRound(number: entry.key, transactions: entry.value),
      )
      .toList(growable: false);
}

int _currentPreparationRound(List<_PreparationRound> rounds) {
  for (final round in rounds) {
    if (round.transactions.any(
      (item) =>
          item.transaction.state !=
          rust_sync.MigrationPreparationTransactionState.completed,
    )) {
      return round.number;
    }
  }
  return rounds.isEmpty ? 0 : rounds.last.number;
}

class _MigrationPreparationRoundSection extends StatelessWidget {
  const _MigrationPreparationRoundSection({
    required this.round,
    required this.currentHeight,
  });

  final _PreparationRound round;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Split round ${round.number}',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < round.transactions.length; index++) ...[
          _MigrationPreparationStageCard(
            key: ValueKey(
              'ironwood_migration_preparation_schedule_stage_${round.transactions[index].transaction.stageIndex}',
            ),
            number: round.transactions[index].number,
            transaction: round.transactions[index].transaction,
            currentHeight: currentHeight,
          ),
          if (index != round.transactions.length - 1)
            const SizedBox(height: 20),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class _MigrationPreparationStageCard extends StatelessWidget {
  const _MigrationPreparationStageCard({
    required this.number,
    required this.transaction,
    required this.currentHeight,
    super.key,
  });

  final int number;
  final rust_sync.MigrationPreparationTransactionStatus transaction;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: _preparationScheduleRowSemantics(number, transaction),
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            key: ValueKey(
              'ironwood_migration_preparation_schedule_surface_${transaction.stageIndex}',
            ),
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$number. ${_formatZecAmountCompact(transaction.approximateValueZatoshi)} ZEC',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MigrationPreparationScheduleStatus(
                      transaction: transaction,
                      currentHeight: currentHeight,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (transaction.outputs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  for (
                    var outputIndex = 0;
                    outputIndex < transaction.outputs.length;
                    outputIndex++
                  ) ...[
                    if (outputIndex > 0) const SizedBox(height: 8),
                    _MigrationPreparationOutputRow(
                      key: ValueKey(
                        'ironwood_migration_preparation_output_${transaction.stageIndex}_$outputIndex',
                      ),
                      output: transaction.outputs[outputIndex],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MigrationPreparationOutputRow extends StatelessWidget {
  const _MigrationPreparationOutputRow({required this.output, super.key});

  final rust_sync.MigrationPreparationOutputStatus output;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayedValue = output.targetValueZatoshi ?? output.valueZatoshi;
    final destination = switch (output.kind) {
      rust_sync.MigrationPreparationOutputKind.migration => 'For migration',
      rust_sync.MigrationPreparationOutputKind.change => 'Stays in Orchard',
      rust_sync.MigrationPreparationOutputKind.continuation =>
        'Used in round ${output.nextRound ?? 1}',
    };
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Text(
            '↳',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_formatZecAmountCompact(displayedValue)} ZEC',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            destination,
            textAlign: TextAlign.right,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationPreparationScheduleStatus extends StatelessWidget {
  const _MigrationPreparationScheduleStatus({
    required this.transaction,
    required this.currentHeight,
  });

  final rust_sync.MigrationPreparationTransactionStatus transaction;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = transaction.state;
    final active =
        state == rust_sync.MigrationPreparationTransactionState.broadcasted ||
        state == rust_sync.MigrationPreparationTransactionState.confirming;
    final completed =
        state == rust_sync.MigrationPreparationTransactionState.completed;
    final awaiting =
        state == rust_sync.MigrationPreparationTransactionState.awaitingInputs;
    final overdueForecast =
        awaiting && transaction.projectedHeight <= currentHeight;
    final label = switch (state) {
      rust_sync.MigrationPreparationTransactionState.completed => 'Completed',
      rust_sync.MigrationPreparationTransactionState.confirming =>
        '${transaction.confirmationCount} of '
            '${transaction.confirmationTarget} confirmations',
      rust_sync.MigrationPreparationTransactionState.broadcasted =>
        'Broadcasting',
      rust_sync.MigrationPreparationTransactionState.scheduled =>
        '#${formatGroupedInteger(transaction.projectedHeight)}',
      rust_sync.MigrationPreparationTransactionState.awaitingInputs =>
        overdueForecast
            ? 'Recalculating'
            : 'Expected #${formatGroupedInteger(transaction.projectedHeight)}',
    };
    final style = AppTypography.labelLarge.copyWith(
      color: completed
          ? colors.text.positiveStrong
          : awaiting
          ? const Color(0xFFB83AD9)
          : colors.text.secondary,
      fontWeight: FontWeight.w400,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          completed
              ? AppIcons.checkCircle
              : active
              ? AppIcons.loader
              : awaiting
              ? AppIcons.migrationSplit
              : AppIcons.block,
          size: 16,
          color: completed
              ? colors.icon.success
              : awaiting
              ? const Color(0xFFB83AD9)
              : active
              ? colors.icon.accent
              : colors.icon.regular,
        ),
        const SizedBox(width: 4),
        if (active)
          IronwoodMigrationShimmerText(
            text: label,
            style: style,
            baseColor: colors.text.secondary,
            highlightColor: colors.text.accent,
            textAlign: TextAlign.right,
          )
        else
          Text(label, textAlign: TextAlign.right, style: style),
      ],
    );
  }
}

String _formatPreparationDuration(int blocks) {
  final minutes =
      (blocks * _migrationEstimatedSecondsPerBlock / Duration.secondsPerMinute)
          .ceil();
  if (minutes < 60) return minutes == 1 ? '~1 min' : '~$minutes mins';
  final halfHours = (minutes / 30).ceil();
  final wholeHours = halfHours ~/ 2;
  if (halfHours.isEven) {
    return wholeHours == 1 ? '~1 hr' : '~$wholeHours hrs';
  }
  return '~$wholeHours.5 hrs';
}

String _preparationScheduleRowSemantics(
  int number,
  rust_sync.MigrationPreparationTransactionStatus transaction,
) {
  final state = switch (transaction.state) {
    rust_sync.MigrationPreparationTransactionState.awaitingInputs =>
      'waiting for previous split, expected at block '
          '${transaction.projectedHeight}',
    rust_sync.MigrationPreparationTransactionState.scheduled =>
      'scheduled at block ${transaction.projectedHeight}',
    rust_sync.MigrationPreparationTransactionState.broadcasted =>
      'broadcast, waiting to be mined, projected completion at block '
          '${transaction.projectedCompletionHeight}',
    rust_sync.MigrationPreparationTransactionState.confirming =>
      'confirming, ${transaction.confirmationCount} of '
          '${transaction.confirmationTarget} confirmations, projected '
          'completion at block ${transaction.projectedCompletionHeight}',
    rust_sync.MigrationPreparationTransactionState.completed =>
      'completed${transaction.minedHeight == null ? '' : ' at block ${transaction.minedHeight}'}',
  };
  final outputs = transaction.outputs
      .map((output) {
        final displayedValue = output.targetValueZatoshi ?? output.valueZatoshi;
        final destination = switch (output.kind) {
          rust_sync.MigrationPreparationOutputKind.migration => 'for migration',
          rust_sync.MigrationPreparationOutputKind.change => 'stays in Orchard',
          rust_sync.MigrationPreparationOutputKind.continuation =>
            'used in round ${output.nextRound ?? 1}',
        };
        return '${_formatZecAmountCompact(displayedValue)} ZEC, $destination';
      })
      .join('; ');
  return [
    'Split $number, '
        '${_formatZecAmountCompact(transaction.approximateValueZatoshi)} ZEC, '
        '$state.',
    if (outputs.isNotEmpty) 'Outputs: $outputs.',
  ].join(' ');
}

class _MigrationScheduleErrorContent extends StatelessWidget {
  const _MigrationScheduleErrorContent({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('ironwood_migration_schedule_error'),
      width: 420,
      height: 656,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Migration schedule unavailable',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 318,
            child: Text(
              "Vizor couldn't load the latest migration schedule. "
              'Your saved migration state is unchanged.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            AppButton(
              key: const ValueKey('ironwood_migration_schedule_retry'),
              onPressed: onRetry,
              height: 44,
              minWidth: 160,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MigrationScheduleContent extends StatelessWidget {
  const _MigrationScheduleContent({
    required this.status,
    required this.currentHeight,
    this.onManage,
  });

  final rust_sync.MigrationStatus status;
  final int currentHeight;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parts = orderedMigrationParts(_displayMigrationParts(status));
    final total = _sumTargetValues(status);
    final completed = parts
        .where((part) => part.state == rust_sync.MigrationPartState.completed)
        .fold<BigInt>(BigInt.zero, (sum, part) => sum + part.valueZatoshi);
    final leftToMigrate = total - completed;

    return SizedBox(
      key: const ValueKey('ironwood_migration_schedule_content'),
      width: 420,
      height: 656,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(
            key: const ValueKey('ironwood_migration_schedule_title'),
            'Migration Schedule',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              key: const ValueKey('ironwood_migration_schedule_summary'),
              children: [
                _MigrationSummaryMetric(
                  label: 'Left to migrate',
                  value:
                      '${_formatZecAmountCompact(leftToMigrate > BigInt.zero ? leftToMigrate : BigInt.zero)} ZEC',
                ),
                const SizedBox(height: 16),
                _MigrationSummaryMetric(
                  label: 'Est. completion',
                  value: _migrationCompletionEstimateDisplay(
                    status,
                    currentHeight: currentHeight,
                    needsInput: false,
                    parts: parts,
                  ),
                  secondary: true,
                ),
                const SizedBox(height: 16),
                _MigrationSummaryMetric(
                  label: 'Current block',
                  value: formatGroupedInteger(currentHeight),
                  valueIcon: AppIcons.block,
                  secondary: true,
                ),
              ],
            ),
          ),
          if (onManage != null) ...[
            const SizedBox(height: 8),
            _MigrationManageButton(onPressed: onManage!),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 28),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.separated(
                key: const ValueKey('ironwood_migration_schedule_list'),
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                itemCount: parts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final part = parts[index];
                  return KeyedSubtree(
                    key: ValueKey(
                      'ironwood_migration_schedule_part_${part.partIndex}',
                    ),
                    child: _MigrationScheduleRow(
                      number: index + 1,
                      part: part,
                      total: total,
                      currentHeight: currentHeight,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationScheduleRow extends StatelessWidget {
  const _MigrationScheduleRow({
    required this.number,
    required this.part,
    required this.total,
    required this.currentHeight,
  });

  final int number;
  final rust_sync.MigrationPartStatus part;
  final BigInt total;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = part.valueZatoshi;
    return Semantics(
      label: _migrationScheduleRowSemantics(
        number,
        part,
        currentHeight: currentHeight,
      ),
      excludeSemantics: true,
      child: SizedBox(
        height: 56,
        child: DecoratedBox(
          key: ValueKey(
            'ironwood_migration_schedule_surface_${part.partIndex}',
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: '$number. ${_formatZecAmountCompact(value)} ZEC ',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: _migrationPercentage(value, total),
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                _MigrationSchedulePartStatus(
                  part: part,
                  currentHeight: currentHeight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MigrationSchedulePartStatus extends StatelessWidget {
  const _MigrationSchedulePartStatus({
    required this.part,
    required this.currentHeight,
  });

  final rust_sync.MigrationPartStatus part;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = part.state;
    final active =
        state == rust_sync.MigrationPartState.migrating ||
        state == rust_sync.MigrationPartState.confirming;
    final completed = state == rust_sync.MigrationPartState.completed;
    final needsInput = state == rust_sync.MigrationPartState.needsInput;
    final originalHeight = part.originalScheduledHeight ?? part.scheduledHeight;
    final effectiveHeight =
        part.effectiveScheduledHeight ?? part.scheduledHeight;
    final minedHeight = part.minedHeight;
    final label = switch (state) {
      rust_sync.MigrationPartState.completed =>
        minedHeight == null
            ? 'Complete'
            : 'Completed at block ${formatGroupedInteger(minedHeight)}',
      rust_sync.MigrationPartState.confirming =>
        'Confirming ${part.confirmationCount}/${part.confirmationTarget}',
      rust_sync.MigrationPartState.migrating => 'Waiting to be mined',
      rust_sync.MigrationPartState.scheduled =>
        effectiveHeight == null
            ? 'Schedule pending'
            : effectiveHeight <= currentHeight
            ? 'Due now'
            : originalHeight != null && originalHeight != effectiveHeight
            ? 'Rescheduled #${formatGroupedInteger(effectiveHeight)}'
            : 'Scheduled #${formatGroupedInteger(effectiveHeight)}',
      rust_sync.MigrationPartState.preparing => 'Preparing',
      rust_sync.MigrationPartState.needsInput => 'Ready to sign',
    };
    final textStyle = AppTypography.labelLarge.copyWith(
      color: completed
          ? colors.text.positiveStrong
          : needsInput
          ? const Color(0xFFB83AD9)
          : colors.text.secondary,
      fontWeight: FontWeight.w400,
    );
    final icon = completed
        ? AppIcons.checkCircle
        : active
        ? AppIcons.loader
        : needsInput
        ? AppIcons.migrationSign
        : AppIcons.block;
    final iconColor = completed
        ? colors.icon.success
        : needsInput
        ? const Color(0xFFB83AD9)
        : active
        ? colors.icon.accent
        : colors.icon.regular;

    return Row(
      key: ValueKey('ironwood_migration_schedule_status_${part.partIndex}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 16, color: iconColor),
        const SizedBox(width: 4),
        if (active)
          IronwoodMigrationShimmerText(
            text: label,
            style: textStyle,
            baseColor: colors.text.secondary,
            highlightColor: colors.text.accent,
            textAlign: TextAlign.right,
          )
        else
          Text(label, textAlign: TextAlign.right, style: textStyle),
      ],
    );
  }
}

String _migrationScheduleRowSemantics(
  int number,
  rust_sync.MigrationPartStatus part, {
  required int currentHeight,
}) {
  final originalHeight = part.originalScheduledHeight ?? part.scheduledHeight;
  final effectiveHeight = part.effectiveScheduledHeight ?? part.scheduledHeight;
  final minedHeight = part.minedHeight;
  final stateLabel = switch (part.state) {
    rust_sync.MigrationPartState.preparing => 'preparing',
    rust_sync.MigrationPartState.scheduled =>
      effectiveHeight == null
          ? 'schedule pending'
          : effectiveHeight <= currentHeight
          ? 'due now'
          : originalHeight != null && originalHeight != effectiveHeight
          ? 'rescheduled from block ${formatGroupedInteger(originalHeight)} '
                'to block ${formatGroupedInteger(effectiveHeight)}'
          : 'scheduled at block ${formatGroupedInteger(effectiveHeight)}',
    rust_sync.MigrationPartState.migrating => 'broadcast, waiting to be mined',
    rust_sync.MigrationPartState.confirming =>
      'confirming, ${part.confirmationCount} of '
          '${part.confirmationTarget} confirmations'
          '${minedHeight == null ? '' : ', mined at block ${formatGroupedInteger(minedHeight)}'}',
    rust_sync.MigrationPartState.completed =>
      minedHeight == null
          ? 'completed'
          : 'completed at block ${formatGroupedInteger(minedHeight)}',
    rust_sync.MigrationPartState.needsInput => 'ready to sign',
  };
  return 'Note $number, ${_formatZecAmountCompact(part.valueZatoshi)} ZEC, '
      '$stateLabel.';
}
