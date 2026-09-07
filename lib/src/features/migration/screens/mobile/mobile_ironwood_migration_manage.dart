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
  String? _error;

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
      _error = null;
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
        _error = 'The migration could not be updated. Please try again.';
      });
      ref.invalidate(ironwoodMigrationStatusProvider(widget.request));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ironwoodMigrationInputsProvider);
    final status = ref.watch(ironwoodMigrationStatusProvider(widget.request));
    final canStop = _canStop(status.asData?.value);
    final statusMessage = status.isLoading
        ? 'Checking migration status...'
        : status.hasError
        ? "Couldn't check the migration status. Please try again."
        : 'This migration is no longer available to manage.';
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
                        ? 'Manage migration'
                        : fast
                        ? 'Switch to Fast?'
                        : 'Stop migration?',
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
                      child: const Text('Switch to Fast'),
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
                      child: const Text('Stop migration'),
                    ),
                  ] else ...[
                    Text(
                      fast
                          ? 'Stop the private schedule and review a Fast '
                                'migration for your remaining balance. Fast '
                                'migration increases traceability and cannot '
                                'be reversed once submitted.'
                          : 'Stop the remaining migration. Funds already '
                                'migrated will stay in Ironwood.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Transactions already broadcast will not be reverted.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      key: const ValueKey('mobile_ironwood_manage_confirm'),
                      expand: true,
                      onPressed: !_submitting && canStop ? _confirm : null,
                      child: Text(_submitting ? 'Stopping...' : 'Confirm'),
                    ),
                  ],
                  if (_submitting) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Waiting for any active broadcast to finish before '
                      'stopping the remaining migration.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                  if (_error != null || (!canStop && !_submitting)) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error ?? statusMessage,
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
                      child: const Text('Retry status check'),
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
                    child: const Text('Cancel'),
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
