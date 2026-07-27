part of 'mobile_ironwood_migration_flow_screen.dart';

bool _keystoneTwoRoundPlanSupported(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  return plan.signingBatchLimit > 0;
}

String _mobilePrivateMigrationStartErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('mnemonic')) {
    return "Secret Passphrase isn't available for this account.";
  }
  if (message.contains('secret storage') ||
      message.contains('unlocked session')) {
    return 'Unlock Vizor before starting migration.';
  }
  if (message.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (message.contains('broadcast') || message.contains('sendtransaction')) {
    return "Couldn't broadcast the migration transaction. Try again.";
  }
  return "Couldn't start migration. Try again.";
}

String _mobileImmediateMigrationStartErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('plan changed')) {
    return 'The amount or fee changed. Review the updated details.';
  }
  return _mobilePrivateMigrationStartErrorMessage(error);
}

class _MobileMigrationFastReview extends ConsumerStatefulWidget {
  const _MobileMigrationFastReview({
    required this.data,
    required this.previewPlan,
    required this.privateMigrationEnabled,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationImmediatePlan? previewPlan;
  final bool privateMigrationEnabled;

  @override
  ConsumerState<_MobileMigrationFastReview> createState() =>
      _MobileMigrationFastReviewState();
}

class _MobileMigrationFastReviewState
    extends ConsumerState<_MobileMigrationFastReview> {
  bool _isBroadcasting = false;
  String? _broadcastError;

  Future<void> _startImmediateMigration(
    rust_sync.OrchardMigrationImmediatePlan plan,
  ) async {
    if (_isBroadcasting) return;
    setState(() {
      _isBroadcasting = true;
      _broadcastError = null;
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
        // The broadcast is already durable. Home will continue normal sync
        // even when this best-effort immediate refresh cannot complete.
      }
      if (!mounted) return;
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      if (error.toString().toLowerCase().contains('plan changed')) {
        ref.invalidate(ironwoodMigrationImmediatePlanProvider);
      }
      setState(() {
        _broadcastError = _mobileImmediateMigrationStartErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBroadcasting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final planAsync = widget.previewPlan != null
        ? AsyncValue<rust_sync.OrchardMigrationImmediatePlan?>.data(
            widget.previewPlan,
          )
        : ref.watch(ironwoodMigrationImmediatePlanProvider);
    final plan = planAsync.asData?.value;
    final planUnavailable = planAsync.asData != null && plan == null;
    final canBroadcast = plan != null && !_isBroadcasting;
    final migratedText = plan == null
        ? (planUnavailable ? 'Unavailable' : 'Calculating…')
        : '${ZecAmount.fromZatoshi(plan.migratedZatoshi).pretty(minFractionDigits: 2, maxFractionDigits: 2).amountText} ZEC';
    return _MobileMigrationReviewScaffold(
      onBack: () => context.go(
        widget.privateMigrationEnabled
            ? '/migration/options'
            : '/migration/how-it-works',
      ),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.privateMigrationEnabled) ...[
            AppButton(
              variant: AppButtonVariant.secondary,
              expand: true,
              height: 50,
              onPressed: _isBroadcasting
                  ? null
                  : () => context.go('/migration/options'),
              leading: const AppIcon(AppIcons.chevronBackward, size: 20),
              child: const Text('Consider another option'),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          if (_broadcastError != null) ...[
            Text(
              _broadcastError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          AppButton(
            key: const ValueKey('mobile_ironwood_immediate_broadcast_button'),
            variant: AppButtonVariant.destructive,
            expand: true,
            height: 50,
            onPressed: canBroadcast
                ? () => _startImmediateMigration(plan)
                : null,
            leading: _isBroadcasting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const AppIcon(AppIcons.warning, size: 20),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: _MobileReviewCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  _ReviewRow(label: 'Amount', value: migratedText, height: 32),
                  const SizedBox(height: AppSpacing.xs),
                  _ReviewRow(
                    label: 'Migration complete in',
                    value: _mobileImmediateMigrationCompletionEstimate,
                    height: 32,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            key: const ValueKey('mobile_ironwood_fast_privacy_card'),
            height: 189,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.homeCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colors.border.inverseOpacity,
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.base,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(
                      AppIcons.transparentBalance,
                      key: const ValueKey('mobile_ironwood_fast_privacy_icon'),
                      size: 20,
                      color: colors.text.homeCard,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Privacy trade-off',
                            style: AppTypography.bodySmall.copyWith(
                              color: colors.text.homeCard,
                              fontWeight: FontWeight.w600,
                              height: 16 / 14,
                              letterSpacing: -0.06,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text.rich(
                            TextSpan(
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.homeCard,
                                fontSize: 15.5,
                                height: 21 / 14,
                                letterSpacing: -0.21,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      'Crosses in one visible step — your '
                                      '${widget.data.amountText} ZEC and '
                                      'timing are ',
                                ),
                                const TextSpan(
                                  text: 'easier to associate with your wallet',
                                  style: TextStyle(color: Color(0xFFC06ECE)),
                                ),
                                const TextSpan(text: '. '),
                                const TextSpan(
                                  text:
                                      'Consider choosing a Private Migration '
                                      'option.',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (planAsync.hasError) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              "Couldn't calculate the Immediate migration fee. Sync and try again.",
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ] else if (planUnavailable) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              'No spendable Orchard balance is available for Immediate migration.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const _mobileImmediateEstimatedSecondsPerBlock = 75;
const _mobileImmediateConfirmationBlocks = 3;

String get _mobileImmediateMigrationCompletionEstimate {
  final estimatedMinutes =
      (_mobileImmediateEstimatedSecondsPerBlock *
      _mobileImmediateConfirmationBlocks /
      Duration.secondsPerMinute);
  final roundedFiveMinuteUnits = (estimatedMinutes / 5).ceil();
  return '~${roundedFiveMinuteUnits * 5} mins';
}
