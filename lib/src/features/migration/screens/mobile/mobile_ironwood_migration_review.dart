part of 'mobile_ironwood_migration_flow_screen.dart';

const _mobileMigrationStartVerificationTimeout = Duration(seconds: 2);

class _MobileMigrationPrivateStart extends ConsumerStatefulWidget {
  const _MobileMigrationPrivateStart({this.privatePlan});

  final rust_sync.OrchardMigrationPrivatePlan? privatePlan;

  @override
  ConsumerState<_MobileMigrationPrivateStart> createState() =>
      _MobileMigrationPrivateStartState();
}

class _MobileMigrationPrivateStartState
    extends ConsumerState<_MobileMigrationPrivateStart> {
  bool _starting = false;
  bool _isKeystone = false;
  String? _error;
  rust_sync.OrchardMigrationPrivatePlan? _keystonePlan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });

    IronwoodMigrationStatusRequest? statusRequest;
    rust_sync.OrchardMigrationPrivatePlan? activePlan;
    String? softwareAccountUuid;
    var softwareStartAttempted = false;
    try {
      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }

      activePlan =
          widget.privatePlan ??
          await ref.read(ironwoodMigrationPrivatePlanProvider.future);
      if (!mounted) return;
      if (activePlan == null) {
        throw StateError('Migration plan is unavailable.');
      }

      final isHardware = accountState.activeAccount?.isHardware ?? false;
      setState(() {
        _isKeystone = isHardware;
      });
      if (isHardware && !_keystoneTwoRoundPlanSupported(activePlan)) {
        setState(() {
          _error =
              'This migration needs more transactions than one Keystone '
              'signing request supports.';
        });
        return;
      }

      statusRequest = IronwoodMigrationStatusRequest(
        network: ref.read(ironwoodMigrationInputsProvider).network,
        accountUuid: accountUuid,
      );
      if (isHardware) {
        setState(() {
          _keystonePlan = activePlan;
        });
        return;
      }

      softwareAccountUuid = accountUuid;
      softwareStartAttempted = true;
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .startSoftwareMigration(
            accountUuid: accountUuid,
            approvedSchedule: activePlan.scheduledTransfers,
          );
      if (!mounted) return;
      if (!await _mobilePrivateMigrationMayHaveStarted(ref, statusRequest)) {
        throw StateError('Migration did not create an active run.');
      }
      if (!mounted) return;
      _openMigrationStatus(activePlan);
    } catch (error) {
      if (!mounted) return;
      final request = statusRequest;
      final plan = activePlan;
      if (softwareStartAttempted &&
          softwareAccountUuid != null &&
          request != null &&
          plan != null &&
          await _mobilePrivateMigrationMayHaveStarted(ref, request)) {
        unawaited(
          _recoverMobileBackgroundTrackingBestEffort(ref, softwareAccountUuid),
        );
        if (!mounted) return;
        _openMigrationStatus(plan);
        return;
      }
      setState(() {
        _error = _mobilePrivateMigrationStartErrorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _openMigrationStatus(rust_sync.OrchardMigrationPrivatePlan plan) {
    ref.invalidate(ironwoodMigrationRouteCtaProvider);
    ref.invalidate(ironwoodHomeMigrationCtaProvider);
    ref.invalidate(ironwoodMigrationFlowDataProvider);
    ref.invalidate(ironwoodMigrationPrivatePlanProvider);
    context.go(
      '/migration/private/status',
      extra: MobileIronwoodMigrationStatusEntry(approvedPlan: plan),
    );
  }

  void _openKeystoneDenominationSigning(
    rust_sync.OrchardMigrationPrivatePlan plan,
  ) {
    context.go(
      '/migration/private/keystone/denominations/sign',
      extra: plan.scheduledTransfers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keystonePlan = _keystonePlan;
    final paused = _error != null || keystonePlan != null;
    return _MigrationPreparationPreview(
      state: paused
          ? _MigrationPreparationState.paused
          : _MigrationPreparationState.active,
      progress: 0,
      isKeystone: _isKeystone,
      pausedMessage: _error ??
          (keystonePlan == null ? null : _keystonePreparationSignatureMessage),
      onBack: () => context.go('/home'),
      onContinue: _starting
          ? null
          : keystonePlan == null
          ? () => unawaited(_start())
          : () => _openKeystoneDenominationSigning(keystonePlan),
    );
  }
}

Future<bool> _mobilePrivateMigrationMayHaveStarted(
  WidgetRef ref,
  IronwoodMigrationStatusRequest request,
) async {
  ref.invalidate(ironwoodMigrationStatusProvider(request));
  try {
    final status = await ref
        .read(ironwoodMigrationStatusProvider(request).future)
        .timeout(_mobileMigrationStartVerificationTimeout);
    return status.activeRunId != null;
  } catch (_) {
    // A status read failure after submission is not proof that no durable
    // migration run exists. The status route can safely reconcile it.
    return true;
  }
}

Future<void> _recoverMobileBackgroundTrackingBestEffort(
  WidgetRef ref,
  String accountUuid,
) async {
  try {
    await ref
        .read(ironwoodMigrationServiceProvider)
        .continueSoftwarePrivateMigration(accountUuid: accountUuid);
  } catch (error) {
    debugPrint(
      'Failed to recover Ironwood background migration tracking: $error',
    );
  }
}

bool _keystoneTwoRoundPlanSupported(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final limit = plan.signingBatchLimit;
  if (limit <= 0) return false;
  return plan.denominationSplitStageCount <= limit &&
      plan.plannedBatchCount <= limit;
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
    required this.isHardware,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationImmediatePlan? previewPlan;
  final bool isHardware;

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
    final canBroadcast = !widget.isHardware && plan != null && !_isBroadcasting;
    final migratedText = plan == null
        ? (planUnavailable ? 'Unavailable' : 'Calculating…')
        : '${ZecAmount.fromZatoshi(plan.migratedZatoshi).pretty(minFractionDigits: 2, maxFractionDigits: 2).amountText} ZEC';
    return _MobileMigrationReviewScaffold(
      onBack: () => context.go('/migration/options'),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
