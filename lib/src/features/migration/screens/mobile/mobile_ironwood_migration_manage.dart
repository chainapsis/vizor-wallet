part of 'mobile_ironwood_migration_flow_screen.dart';

enum _MobileMigrationManageChoice { fast, stop }

/// Keeps the confirmation mounted until native cleanup has finished, even when
/// the durable Rust stop clears activeRunId before the service returns.
class _MobileMigrationManageDialog extends ConsumerStatefulWidget {
  const _MobileMigrationManageDialog({
    required this.request,
    required this.runId,
  });

  final IronwoodMigrationStatusRequest request;
  final String runId;

  @override
  ConsumerState<_MobileMigrationManageDialog> createState() =>
      _MobileMigrationManageDialogState();
}

class _MobileMigrationManageDialogState
    extends ConsumerState<_MobileMigrationManageDialog> {
  _MobileMigrationManageChoice? _choice;
  bool _submitting = false;
  bool _stopAttempted = false;
  bool _updateFailed = false;

  bool _canStop(rust_sync.MigrationStatus? status) {
    if (ref.read(ironwoodMigrationInputsProvider).statusRequest !=
        widget.request) {
      return false;
    }
    if (status == null) return false;
    // A failed native cleanup can follow a committed Rust stop. Retry the same
    // run's idempotent cleanup, but never authorize stopping a newer run.
    if (_stopAttempted && status.activeRunId == null) return true;
    return status.activeRunId == widget.runId && status.canAbandon;
  }

  Future<void> _confirm() async {
    final choice = _choice;
    if (_submitting || choice == null) return;
    final status = ref
        .read(ironwoodMigrationStatusProvider(widget.request))
        .asData
        ?.value;
    if (!_canStop(status)) return;
    setState(() {
      _submitting = true;
      _stopAttempted = true;
      _updateFailed = false;
    });
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .stop(accountUuid: widget.request.accountUuid, runId: widget.runId);
      if (!mounted) return;
      Navigator.of(context).pop(choice);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _updateFailed = true;
      });
      ref.invalidate(ironwoodMigrationStatusProvider(widget.request));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ironwoodMigrationInputsProvider);
    final status = ref.watch(ironwoodMigrationStatusProvider(widget.request));
    final canStop = _canStop(status.asData?.value);
    final l10n = context.l10n;
    final statusMessage = status.isLoading
        ? l10n.migrationMobileManageChecking
        : status.hasError
        ? l10n.migrationMobileManageCheckError
        : l10n.migrationMobileManageUnavailable;
    final colors = context.colors;
    final choice = _choice;
    final fast = choice == _MobileMigrationManageChoice.fast;
    return PopScope(
      canPop: !_submitting,
      child: Dialog(
        key: const ValueKey('mobile_ironwood_manage_dialog'),
        backgroundColor: colors.background.ground,
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    choice == null
                        ? l10n.migrationMobileManageTitle
                        : fast
                        ? l10n.migrationMobileManageSwitchTitle
                        : l10n.migrationMobileManageStopTitle,
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (choice == null) ...[
                    AppButton(
                      key: const ValueKey('mobile_ironwood_manage_fast'),
                      expand: true,
                      onPressed: canStop
                          ? () => setState(() {
                              _choice = _MobileMigrationManageChoice.fast;
                            })
                          : null,
                      child: Text(l10n.migrationMobileManageSwitchAction),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppButton(
                      key: const ValueKey('mobile_ironwood_manage_stop'),
                      expand: true,
                      variant: AppButtonVariant.ghost,
                      onPressed: canStop
                          ? () => setState(() {
                              _choice = _MobileMigrationManageChoice.stop;
                            })
                          : null,
                      child: Text(l10n.migrationMobileManageStopAction),
                    ),
                  ] else ...[
                    Text(
                      fast
                          ? l10n.migrationMobileManageSwitchBody
                          : l10n.migrationMobileManageStopBody,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.migrationMobileManageNoRevert,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      key: const ValueKey('mobile_ironwood_manage_confirm'),
                      expand: true,
                      onPressed: !_submitting && canStop ? _confirm : null,
                      child: Text(
                        _submitting
                            ? l10n.migrationMobileManageStopping
                            : l10n.migrationMobileManageConfirm,
                      ),
                    ),
                  ],
                  if (_submitting) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.migrationMobileManageWaitingBroadcast,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                  if (_updateFailed || (!canStop && !_submitting)) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _updateFailed
                          ? l10n.migrationMobileManageUpdateError
                          : statusMessage,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                  if (status.hasError && !_submitting) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AppButton(
                      key: const ValueKey(
                        'mobile_ironwood_manage_retry_status',
                      ),
                      expand: true,
                      onPressed: () => ref.invalidate(
                        ironwoodMigrationStatusProvider(widget.request),
                      ),
                      child: Text(l10n.migrationMobileManageRetryStatus),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    key: const ValueKey('mobile_ironwood_manage_cancel'),
                    expand: true,
                    variant: AppButtonVariant.ghost,
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
