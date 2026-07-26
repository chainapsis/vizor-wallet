part of '../ironwood_migration_flow_screen.dart';

class _IronwoodMigrationImmediateReviewContent extends ConsumerStatefulWidget {
  const _IronwoodMigrationImmediateReviewContent({
    required this.data,
    this.previewPlan,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationImmediatePlan? previewPlan;

  @override
  ConsumerState<_IronwoodMigrationImmediateReviewContent> createState() =>
      _IronwoodMigrationImmediateReviewContentState();
}

class _IronwoodMigrationImmediateReviewContentState
    extends ConsumerState<_IronwoodMigrationImmediateReviewContent> {
  bool _isBroadcasting = false;
  String? _error;

  Future<void> _start(rust_sync.OrchardMigrationImmediatePlan plan) async {
    if (_isBroadcasting) return;
    setState(() {
      _isBroadcasting = true;
      _error = null;
    });
    try {
      final accountState = await ref.read(accountProvider.future);
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      if (accountState.activeAccount?.isHardware ?? false) {
        throw UnsupportedError(
          'Immediate migration is not available with Keystone.',
        );
      }
      await ref
          .read(ironwoodMigrationServiceProvider)
          .startSoftwareImmediateMigration(
            accountUuid: accountUuid,
            approvedPlan: plan,
          );
      if (!mounted) return;
      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (_) {
        // Broadcast already succeeded; the regular sync loop will reconcile it.
      }
      if (mounted) context.go('/home');
    } catch (error) {
      if (!mounted) return;
      if (error.toString().toLowerCase().contains('plan changed')) {
        ref.invalidate(ironwoodMigrationImmediatePlanProvider);
      }
      setState(() {
        _error = _immediateMigrationStartErrorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _isBroadcasting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = widget.previewPlan == null
        ? ref.watch(ironwoodMigrationImmediatePlanProvider)
        : AsyncValue<rust_sync.OrchardMigrationImmediatePlan?>.data(
            widget.previewPlan,
          );
    final plan = planAsync.asData?.value;
    final colors = context.colors;
    final amount = plan == null
        ? 'Calculating…'
        : '${_formatZecAmountCompact(plan.migratedZatoshi)} ZEC';
    final fee = plan == null
        ? 'Shown before send'
        : '~${_formatZecAmountCompact(plan.feeZatoshi)} ZEC';

    return SizedBox(
      key: const ValueKey('ironwood_migration_immediate_review_screen'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 36,
            width: 396,
            child: Column(
              children: [
                Text(
                  'Review immediate migration',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 24),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background.ground,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    child: Column(
                      children: [
                        _ImmediateReviewRow(label: 'Amount', value: amount),
                        const SizedBox(height: 8),
                        _ImmediateReviewRow(
                          label: 'Fees (estimate)',
                          value: fee,
                        ),
                        const SizedBox(height: 8),
                        const _ImmediateReviewRow(
                          label: 'Est. completion',
                          value: '~5 mins',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background.ground,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.border.subtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppIcon(
                          AppIcons.transparentBalance,
                          size: 20,
                          color: colors.icon.accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Privacy trade-off',
                                style: AppTypography.bodyMediumStrong.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Immediate migration crosses in one visible '
                                'step. Your balance and timing are easier to '
                                'associate with your wallet. Consider choosing '
                                'Private instead.',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 540,
            width: 230,
            child: Column(
              children: [
                AppButton(
                  onPressed: _isBroadcasting
                      ? null
                      : () => context.go('/migration/options'),
                  variant: AppButtonVariant.secondary,
                  height: 44,
                  minWidth: 230,
                  expand: true,
                  child: const Text('Consider another option'),
                ),
                const SizedBox(height: 12),
                AppButton(
                  key: const ValueKey(
                    'ironwood_migration_immediate_broadcast_button',
                  ),
                  onPressed: plan == null || _isBroadcasting
                      ? null
                      : () => unawaited(_start(plan)),
                  variant: AppButtonVariant.destructive,
                  height: 44,
                  minWidth: 230,
                  expand: true,
                  leading: _isBroadcasting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const AppIcon(AppIcons.warning, size: 18),
                  child: Text(
                    _isBroadcasting ? 'Authorising…' : 'Authorise anyway',
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

class _ImmediateReviewRow extends StatelessWidget {
  const _ImmediateReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.labelLarge.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          Text(
            value,
            style: AppTypography.labelLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ],
      ),
    );
  }
}

String _immediateMigrationStartErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('plan changed')) {
    return 'The amount or fee changed. Review the updated details.';
  }
  if (message.contains('mnemonic')) {
    return "Secret Passphrase isn't available for this account.";
  }
  if (message.contains('keystone')) {
    return 'Immediate migration is not available with Keystone.';
  }
  if (message.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  return "Couldn't start migration. Try again.";
}
