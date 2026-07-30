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

String _mobileImmediateMigratedAmountText(
  rust_sync.OrchardMigrationImmediatePlan plan,
) {
  final amount = ZecAmount.fromZatoshi(
    plan.migratedZatoshi,
  ).pretty(minFractionDigits: 2, maxFractionDigits: 2).amountText;
  return '$amount ZEC';
}

String _mobileImmediateFeeText(rust_sync.OrchardMigrationImmediatePlan plan) {
  return '${ZecAmount.fromZatoshi(plan.feeZatoshi).balance.amountText} ZEC';
}

class _MobileMigrationFastReview extends ConsumerStatefulWidget {
  const _MobileMigrationFastReview({
    required this.data,
    required this.previewPlan,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationImmediatePlan? previewPlan;

  @override
  ConsumerState<_MobileMigrationFastReview> createState() =>
      _MobileMigrationFastReviewState();
}

class _MobileMigrationFastReviewState
    extends ConsumerState<_MobileMigrationFastReview> {
  bool _isBroadcasting = false;
  String? _broadcastError;
  rust_sync.OrchardMigrationImmediatePlan? _submittedPlan;
  String? _submittedMessage;

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

      final result = await ref
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

      // Home reads the migration CTA and the post-migration state, so both
      // have to be reconciled before this flow hands the user back to it.
      await _refreshPrivateMigrationDraftPresentation(ref);
      if (!mounted) return;

      final message = result.message?.trim();
      setState(() {
        _submittedPlan = plan;
        _submittedMessage = message == null || message.isEmpty ? null : message;
      });
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

  void _retryPlanCalculation() {
    setState(() {
      _broadcastError = null;
    });
    ref.invalidate(ironwoodMigrationImmediatePlanProvider);
  }

  void _openHome() => context.go('/home');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final submittedPlan = _submittedPlan;
    if (submittedPlan != null) {
      return _MobileIronwoodMigrationBackScope(
        onFallback: _openHome,
        child: _MigrationPreviewPage(
          navTitle: 'Fast Migration',
          showBackButton: false,
          bottom: AppButton(
            key: const ValueKey('mobile_ironwood_immediate_done_button'),
            expand: true,
            constrainContent: true,
            height: 50,
            onPressed: _openHome,
            child: const Text('Done'),
          ),
          child: Center(
            child: SizedBox(
              key: const ValueKey('mobile_ironwood_immediate_submitted'),
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.checkCircle,
                    size: 40,
                    color: colors.icon.success,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    'Migration submitted',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${_mobileImmediateMigratedAmountText(submittedPlan)} is '
                    'on its way to Ironwood.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                  if (_submittedMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _submittedMessage!,
                      key: const ValueKey(
                        'mobile_ironwood_immediate_submitted_notice',
                      ),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    final planAsync = widget.previewPlan != null
        ? AsyncValue<rust_sync.OrchardMigrationImmediatePlan?>.data(
            widget.previewPlan,
          )
        : ref.watch(ironwoodMigrationImmediatePlanProvider);
    final plan = planAsync.asData?.value;
    final planUnavailable = planAsync.asData != null && plan == null;
    final canBroadcast = plan != null && !_isBroadcasting;
    final placeholderText = planUnavailable ? 'Unavailable' : 'Calculating…';
    final migratedText = plan == null
        ? placeholderText
        : _mobileImmediateMigratedAmountText(plan);
    final feeText = plan == null
        ? placeholderText
        : _mobileImmediateFeeText(plan);
    final privacyAmountText = plan == null
        ? '${widget.data.amountText} ZEC'
        : _mobileImmediateMigratedAmountText(plan);
    final leaveReview = _isBroadcasting
        ? null
        : () => context.go('/migration/options');
    return _MobileIronwoodMigrationBackScope(
      onFallback: leaveReview,
      child: _MobileMigrationReviewScaffold(
        onBack: leaveReview,
        bottom: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              expand: true,
              height: 50,
              onPressed: leaveReview,
              leading: const AppIcon(AppIcons.chevronBackward, size: 20),
              child: const Text('Consider another option'),
            ),
            const SizedBox(height: AppSpacing.s),
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
            if (planAsync.hasError) ...[
              AppButton(
                key: const ValueKey(
                  'mobile_ironwood_immediate_retry_plan_button',
                ),
                variant: AppButtonVariant.ghost,
                expand: true,
                height: 50,
                onPressed: _isBroadcasting ? null : _retryPlanCalculation,
                child: const Text('Retry calculation'),
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
              child: Text(_isBroadcasting ? 'Sending...' : 'Continue anyway'),
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(
              height: 160,
              child: _MobileReviewCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  children: [
                    _ReviewRow(
                      label: 'Amount',
                      value: migratedText,
                      height: 32,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _ReviewRow(
                      label: 'Fees (estimate)',
                      value: feeText,
                      height: 32,
                    ),
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
                        key: const ValueKey(
                          'mobile_ironwood_fast_privacy_icon',
                        ),
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
                                        '$privacyAmountText and '
                                        'timing are ',
                                  ),
                                  const TextSpan(
                                    text:
                                        'easier to associate with your wallet',
                                    style: TextStyle(color: Color(0xFFC06ECE)),
                                  ),
                                  const TextSpan(text: '. '),
                                  const TextSpan(
                                    text:
                                        'Consider choosing a Private Migration '
                                        'option.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
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
