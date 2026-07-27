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

  void _retryPlan() {
    setState(() => _error = null);
    ref.invalidate(ironwoodMigrationImmediatePlanProvider);
  }

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
        if (!mounted) return;
        context.go('/migration/immediate/keystone/sign', extra: plan);
        return;
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
    final planFailed = planAsync.hasError;
    final planUnavailable = planAsync.asData != null && plan == null;
    final planLoading = planAsync.isLoading;
    final colors = context.colors;
    final amount = plan != null
        ? '${_formatZecAmountCompact(plan.migratedZatoshi)} ZEC'
        : planLoading
        ? 'Calculating…'
        : 'Unavailable';
    final fee = plan != null
        ? '~${_formatZecAmountCompact(plan.feeZatoshi)} ZEC'
        : planLoading
        ? 'Calculating…'
        : 'Unavailable';
    final planMessage = planFailed
        ? "Couldn't calculate the Immediate migration plan. Sync and try again."
        : planUnavailable
        ? 'No spendable Orchard balance is available for Immediate migration.'
        : null;
    final displayedError = _error ?? planMessage;

    return SizedBox(
      key: const ValueKey('ironwood_migration_immediate_review_screen'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 96,
            width: 396,
            child: Column(
              children: [
                Text(
                  'Review Migration Plan',
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
                          label: 'Migration complete in',
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
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppIcon(
                          AppIcons.transparentBalance,
                          size: 20,
                          color: colors.icon.accent,
                        ),
                        const SizedBox(width: 8),
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
                              Text.rich(
                                TextSpan(
                                  text:
                                      'Crosses in one visible step — your '
                                      '$amount and timing are ',
                                  children: const [
                                    TextSpan(
                                      text:
                                          'easier to associate with your '
                                          'wallet.',
                                      style: TextStyle(
                                        color: Color(0xFFCA4ADC),
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          '\nConsider choosing a Private '
                                          'Migration option.',
                                    ),
                                  ],
                                ),
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
                if (displayedError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    displayedError,
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
                  variant: AppButtonVariant.ghost,
                  height: 44,
                  minWidth: 230,
                  expand: true,
                  leading: const AppIcon(AppIcons.chevronBackward, size: 18),
                  child: const Text('Consider another option'),
                ),
                const SizedBox(height: 12),
                AppButton(
                  key: const ValueKey(
                    'ironwood_migration_immediate_broadcast_button',
                  ),
                  onPressed: _isBroadcasting
                      ? null
                      : planFailed
                      ? _retryPlan
                      : plan == null
                      ? null
                      : () => unawaited(_start(plan)),
                  variant: planFailed
                      ? AppButtonVariant.primary
                      : AppButtonVariant.destructive,
                  height: 44,
                  minWidth: 230,
                  expand: true,
                  leading: _isBroadcasting
                      ? const AppIcon(
                          AppIcons.loader,
                          size: 18,
                          semanticLabel: 'Authorising migration',
                        )
                      : const AppIcon(AppIcons.warning, size: 18),
                  child: Text(
                    _isBroadcasting
                        ? 'Authorising…'
                        : planFailed
                        ? 'Retry calculation'
                        : planLoading
                        ? 'Calculating…'
                        : planUnavailable
                        ? 'Unavailable'
                        : 'Authorise anyway',
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
  if (message.contains('keystone')) return "Couldn't prepare Keystone signing.";
  if (message.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  return "Couldn't start migration. Try again.";
}
