part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationPrivateReview extends ConsumerStatefulWidget {
  const _MobileMigrationPrivateReview({
    required this.data,
    required this.previewPlan,
    required this.isHardware,
    required this.previewStage,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final bool isHardware;
  final MobileIronwoodMigrationReviewPreviewStage previewStage;

  @override
  ConsumerState<_MobileMigrationPrivateReview> createState() =>
      _MobileMigrationPrivateReviewState();
}

class _MobileMigrationPrivateReviewState
    extends ConsumerState<_MobileMigrationPrivateReview> {
  bool _analysisComplete = false;
  int _analysisEpoch = 0;
  bool _isStarting = false;
  String? _startError;
  ProviderSubscription<bool>? _syncReadinessSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.previewPlan != null) return;
    _syncReadinessSubscription = ref.listenManual(
      ironwoodMigrationInputsProvider.select(
        (inputs) =>
            inputs.isSyncing ||
            inputs.isBackgroundMode ||
            !inputs.isSyncComplete ||
            inputs.hasSyncFailure,
      ),
      (wasWaiting, isWaiting) {
        if (wasWaiting == isWaiting) return;
        if (isWaiting) {
          _resetAnalysis();
        } else {
          _retryAnalysis();
        }
      },
    );
  }

  @override
  void dispose() {
    _syncReadinessSubscription?.close();
    super.dispose();
  }

  void _resetAnalysis({bool invalidatePlan = false}) {
    if (!mounted) return;
    setState(() {
      _analysisComplete = false;
      _analysisEpoch++;
    });
    if (invalidatePlan) {
      ref.invalidate(ironwoodMigrationPrivatePlanProvider);
    }
  }

  void _retryAnalysis() {
    if (!mounted) return;
    _resetAnalysis(invalidatePlan: true);

    final inputs = ref.read(ironwoodMigrationInputsProvider);
    if ((!inputs.isSyncComplete || inputs.hasSyncFailure) &&
        !inputs.isSyncing &&
        !inputs.isBackgroundMode) {
      unawaited(ref.read(syncProvider.notifier).startSyncAnyway());
    }
  }

  void _handleAnalysisCompleted() {
    if (_analysisComplete || !mounted) return;
    setState(() => _analysisComplete = true);
  }

  Future<void> _startMigration(
    rust_sync.OrchardMigrationPrivatePlan plan,
  ) async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
      _startError = null;
    });

    try {
      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      final statusRequest = IronwoodMigrationStatusRequest(
        network: ref.read(ironwoodMigrationInputsProvider).network,
        accountUuid: accountUuid,
      );
      if (accountState.activeAccount?.isHardware ?? false) {
        context.go(
          '/migration/private/keystone/denominations/sign',
          extra: plan.scheduledTransfers,
        );
        return;
      }

      await ref
          .read(ironwoodMigrationServiceProvider)
          .startSoftwarePrivateMigration(
            accountUuid: accountUuid,
            approvedSchedule: plan.scheduledTransfers,
          );
      if (!mounted) return;
      ref.invalidate(ironwoodMigrationStatusProvider(statusRequest));
      final startedStatus = await ref.read(
        ironwoodMigrationStatusProvider(statusRequest).future,
      );
      if (!mounted) return;
      if (startedStatus.activeRunId == null) {
        throw StateError('Migration did not create an active run.');
      }
      ref.invalidate(ironwoodMigrationRouteCtaProvider);
      ref.invalidate(ironwoodHomeMigrationCtaProvider);
      ref.invalidate(ironwoodMigrationFlowDataProvider);
      ref.invalidate(ironwoodMigrationPrivatePlanProvider);
      context.go('/migration/private/status');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startError = _mobilePrivateMigrationStartErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.previewPlan;
    final migrationInputs = preview == null
        ? ref.watch(ironwoodMigrationInputsProvider)
        : null;
    final planAsync = preview != null
        ? AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.data(preview)
        : ref.watch(ironwoodMigrationPrivatePlanProvider);
    final staticAnalysisPreview =
        widget.previewStage ==
        MobileIronwoodMigrationReviewPreviewStage.analyzing;
    final animatedAnalysisPreview =
        widget.previewStage ==
        MobileIronwoodMigrationReviewPreviewStage.animatedAnalyzing;
    final syncReadyForPlan =
        preview != null ||
        (!migrationInputs!.isSyncing &&
            !migrationInputs.isBackgroundMode &&
            migrationInputs.isSyncComplete &&
            !migrationInputs.hasSyncFailure);
    final plan =
        syncReadyForPlan &&
            planAsync is AsyncData<rust_sync.OrchardMigrationPrivatePlan?>
        ? planAsync.value
        : null;
    final awaitingInitialPlan = planAsync.isLoading && plan == null;
    final waitingForSync =
        preview == null &&
        (migrationInputs!.isSyncing || migrationInputs.isBackgroundMode);
    final waitingForPlan = awaitingInitialPlan || waitingForSync;
    final showAnalyzing =
        staticAnalysisPreview ||
        (animatedAnalysisPreview && !_analysisComplete) ||
        (preview == null && (!_analysisComplete || waitingForPlan));
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final Widget child;
    if (showAnalyzing) {
      child = KeyedSubtree(
        key: ValueKey('mobile_ironwood_analysis_epoch_$_analysisEpoch'),
        child: _MobileMigrationAnalyzing(
          key: const ValueKey('mobile_ironwood_migration_analysis_stage'),
          preview: staticAnalysisPreview,
          ready: !waitingForPlan,
          completionSucceeded: plan != null,
          onCompleted: staticAnalysisPreview ? null : _handleAnalysisCompleted,
        ),
      );
    } else {
      final keystonePlanSupported =
          !widget.isHardware ||
          plan == null ||
          _keystoneTwoRoundPlanSupported(plan);
      final canStart = plan != null && !_isStarting && keystonePlanSupported;

      child = KeyedSubtree(
        key: const ValueKey('mobile_ironwood_migration_review_stage'),
        child: _MobilePrivateReviewScaffold(
          onBack: () => context.go('/migration/options'),
          bottom: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_startError != null) ...[
                Text(
                  _startError!,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: context.colors.text.destructive,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              if (!keystonePlanSupported) ...[
                Text(
                  'This migration needs more transactions than one Keystone '
                  'signing request supports.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: context.colors.text.destructive,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              _MobileMigrationPrimaryButton(
                key: const ValueKey('mobile_ironwood_authorize_start_button'),
                label: _isStarting
                    ? 'Preparing...'
                    : widget.isHardware
                    ? 'Continue with Keystone'
                    : 'Start migration',
                onPressed: canStart
                    ? preview != null
                          ? () {}
                          : () => _startMigration(plan)
                    : null,
              ),
            ],
          ),
          child: plan == null
              ? _MobileMigrationUnavailable(onRetry: _retryAnalysis)
              : _MobilePrivatePlan(
                  plan: plan,
                  arrivalLabel: _migrationArrivalLabel(plan),
                ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: disableAnimations
          ? Duration.zero
          : _migrationAnalysisTransitionDuration,
      reverseDuration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 280),
      switchInCurve: _migrationAnalysisEaseOut,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: [
            for (final previousChild in previousChildren)
              IgnorePointer(child: previousChild),
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: child,
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

class _MobileMigrationFastReview extends StatefulWidget {
  const _MobileMigrationFastReview({
    required this.data,
    required this.previewMode,
  });

  final IronwoodMigrationFlowData data;
  final bool previewMode;

  @override
  State<_MobileMigrationFastReview> createState() =>
      _MobileMigrationFastReviewState();
}

class _MobileMigrationFastReviewState
    extends State<_MobileMigrationFastReview> {
  late bool _acknowledged = widget.previewMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _MobileMigrationReviewScaffold(
      onBack: () => context.go('/migration/options'),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            variant: AppButtonVariant.ghost,
            expand: true,
            height: 44,
            onPressed: () => context.go('/migration/options'),
            leading: const AppIcon(AppIcons.chevronBackward, size: 20),
            child: const Text('Consider another option'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            variant: AppButtonVariant.destructive,
            expand: true,
            height: 50,
            onPressed: _acknowledged && widget.previewMode ? () {} : null,
            leading: const AppIcon(AppIcons.warning, size: 20),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 153,
            child: _MobileReviewCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  _ReviewRow(
                    label: 'Amount',
                    value: '${widget.data.amountText} ZEC',
                    height: 32,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const _ReviewRow(
                    label: 'Fees (estimate)',
                    value: 'shown before send',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const _ReviewRow(
                    label: 'Migration complete in',
                    value: '~5 mins',
                    showInfo: true,
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
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.homeCard,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text.rich(
                            TextSpan(
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.homeCard,
                                letterSpacing: 0,
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
          const SizedBox(height: AppSpacing.md),
          Semantics(
            checked: _acknowledged,
            button: true,
            child: GestureDetector(
              key: const ValueKey('mobile_ironwood_fast_acknowledgement'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _acknowledged = !_acknowledged),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _acknowledged
                          ? colors.button.destructive.bg
                          : colors.background.ground,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _acknowledged
                            ? colors.button.destructive.bg
                            : colors.border.regular,
                      ),
                    ),
                    child: _acknowledged
                        ? AppIcon(
                            AppIcons.check,
                            size: 14,
                            color: colors.button.destructive.label,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      'I understand that this migration’s amount and timing '
                      'will be visible on the Zcash network.',
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
