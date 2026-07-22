part of 'mobile_ironwood_migration_flow_screen.dart';

const _mobileMigrationStartVerificationTimeout = Duration(seconds: 2);

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
  bool _isRefreshingPlan = false;
  bool _planRefreshFailed = false;
  String? _startError;
  String? _planRefreshMessage;
  rust_sync.OrchardMigrationPrivatePlan? _displayedPlan;
  String? _displayedPlanFingerprint;
  ProviderSubscription<({bool isWaiting, bool hasSyncFailure})>?
  _syncReadinessSubscription;
  ProviderSubscription<AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>>?
  _planSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.previewPlan != null) return;
    _syncReadinessSubscription = ref.listenManual(
      ironwoodMigrationInputsProvider.select(
        (inputs) => (
          isWaiting:
              inputs.isSyncing ||
              inputs.isBackgroundMode ||
              !inputs.isSyncComplete ||
              inputs.hasSyncFailure,
          hasSyncFailure: inputs.hasSyncFailure,
        ),
      ),
      (previous, next) {
        if (next.hasSyncFailure) {
          if (_analysisComplete) {
            setState(() {
              _isRefreshingPlan = false;
              _planRefreshFailed = true;
              _planRefreshMessage =
                  "Sync didn't finish. Try again before starting migration.";
            });
          }
          return;
        }
        if (next.isWaiting) {
          if (_analysisComplete) _markPlanRefreshing();
          return;
        }
        if (previous?.isWaiting ?? true) {
          if (_analysisComplete) _markPlanRefreshing();
          ref.invalidate(ironwoodMigrationPrivatePlanProvider);
        }
      },
    );
    _planSubscription = ref.listenManual(
      ironwoodMigrationPrivatePlanProvider,
      _handlePlanStateChanged,
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _syncReadinessSubscription?.close();
    _planSubscription?.close();
    super.dispose();
  }

  void _resetAnalysis({bool invalidatePlan = false}) {
    if (!mounted) return;
    setState(() {
      _analysisComplete = false;
      _analysisEpoch++;
      _isRefreshingPlan = false;
      _planRefreshFailed = false;
      _planRefreshMessage = null;
      _displayedPlan = null;
      _displayedPlanFingerprint = null;
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

  void _markPlanRefreshing() {
    if (!mounted) return;
    setState(() {
      _isRefreshingPlan = true;
      _planRefreshFailed = false;
      _planRefreshMessage = null;
    });
  }

  void _handlePlanStateChanged(
    AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>? previous,
    AsyncValue<rust_sync.OrchardMigrationPrivatePlan?> next,
  ) {
    if (!mounted) return;
    if (next is AsyncData<rust_sync.OrchardMigrationPrivatePlan?>) {
      final refreshedPlan = next.value;
      if (refreshedPlan == null) {
        if (_analysisComplete && _isRefreshingPlan) {
          setState(() {
            _isRefreshingPlan = false;
            _planRefreshFailed = true;
            _planRefreshMessage =
                'The migration plan is no longer available after sync.';
          });
        }
        return;
      }

      final refreshedFingerprint = _mobilePrivatePlanFingerprint(refreshedPlan);
      final planChanged =
          _analysisComplete &&
          _displayedPlanFingerprint != null &&
          _displayedPlanFingerprint != refreshedFingerprint;
      setState(() {
        if (_displayedPlan == null || planChanged) {
          _displayedPlan = refreshedPlan;
          _displayedPlanFingerprint = refreshedFingerprint;
        }
        _isRefreshingPlan = false;
        _planRefreshFailed = false;
        _planRefreshMessage = planChanged
            ? 'Migration plan updated after sync. Review the changes.'
            : null;
      });
      return;
    }

    if (next is AsyncError<rust_sync.OrchardMigrationPrivatePlan?> &&
        _analysisComplete &&
        _isRefreshingPlan) {
      setState(() {
        _isRefreshingPlan = false;
        _planRefreshFailed = true;
        _planRefreshMessage =
            "Couldn't update the migration plan after sync. Try again.";
      });
    }
  }

  void _handleAnalysisCompleted() {
    if (_analysisComplete || !mounted) return;
    final plan = ref.read(ironwoodMigrationPrivatePlanProvider).asData?.value;
    setState(() {
      _analysisComplete = true;
      if (plan != null) {
        _displayedPlan = plan;
        _displayedPlanFingerprint = _mobilePrivatePlanFingerprint(plan);
      }
    });
  }

  Future<void> _startMigration(
    rust_sync.OrchardMigrationPrivatePlan plan,
  ) async {
    if (_isStarting) return;
    IronwoodMigrationStatusRequest? statusRequest;
    String? softwareAccountUuid;
    var softwareStartAttempted = false;
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
      statusRequest = IronwoodMigrationStatusRequest(
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

      softwareAccountUuid = accountUuid;
      softwareStartAttempted = true;
      await ref
          .read(ironwoodMigrationServiceProvider)
          .startSoftwarePrivateMigration(
            accountUuid: accountUuid,
            approvedSchedule: plan.scheduledTransfers,
          );
      if (!mounted) return;
      if (!await _migrationMayHaveStarted(statusRequest)) {
        throw StateError('Migration did not create an active run.');
      }
      if (!mounted) return;
      _openMigrationStatus(plan);
    } catch (error) {
      if (!mounted) return;
      final request = statusRequest;
      if (softwareStartAttempted &&
          softwareAccountUuid != null &&
          request != null &&
          await _migrationMayHaveStarted(request)) {
        unawaited(_recoverBackgroundTrackingBestEffort(softwareAccountUuid));
        if (!mounted) return;
        _openMigrationStatus(plan);
        return;
      }
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

  Future<bool> _migrationMayHaveStarted(
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

  Future<void> _recoverBackgroundTrackingBestEffort(String accountUuid) async {
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

  void _openMigrationStatus(rust_sync.OrchardMigrationPrivatePlan plan) {
    ref.invalidate(ironwoodMigrationRouteCtaProvider);
    ref.invalidate(ironwoodHomeMigrationCtaProvider);
    ref.invalidate(ironwoodMigrationFlowDataProvider);
    ref.invalidate(ironwoodMigrationPrivatePlanProvider);
    context.go('/migration/private/status', extra: plan);
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
    final currentPlan = planAsync.asData?.value;
    final plan = preview ?? _displayedPlan ?? currentPlan;
    final awaitingInitialPlan = planAsync.isLoading && plan == null;
    final waitingForSync =
        preview == null &&
        (migrationInputs!.isSyncing || migrationInputs.isBackgroundMode);
    final waitingForPlan = awaitingInitialPlan || waitingForSync;
    final showAnalyzing =
        staticAnalysisPreview ||
        (animatedAnalysisPreview && !_analysisComplete) ||
        (preview == null && !_analysisComplete);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final Widget child;
    if (showAnalyzing) {
      child = KeyedSubtree(
        key: ValueKey('mobile_ironwood_analysis_epoch_$_analysisEpoch'),
        child: _MobileMigrationAnalyzing(
          key: const ValueKey('mobile_ironwood_migration_analysis_stage'),
          preview: staticAnalysisPreview,
          ready: !waitingForPlan,
          completionSucceeded: syncReadyForPlan && plan != null,
          onCompleted: staticAnalysisPreview ? null : _handleAnalysisCompleted,
        ),
      );
    } else {
      final keystonePlanSupported =
          !widget.isHardware ||
          plan == null ||
          _keystoneTwoRoundPlanSupported(plan);
      final canStart = plan != null && !_isStarting && keystonePlanSupported;
      final displayedError = _startError ?? _planRefreshMessage;
      final displayedMessageIsError = _startError != null || _planRefreshFailed;
      final canStartCurrentPlan =
          canStart &&
          syncReadyForPlan &&
          !_isRefreshingPlan &&
          !_planRefreshFailed;

      child = KeyedSubtree(
        key: const ValueKey('mobile_ironwood_migration_review_stage'),
        child: _MobilePrivateReviewScaffold(
          onBack: () => context.go('/migration/options'),
          bottom: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (displayedError != null) ...[
                Text(
                  displayedError,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: displayedMessageIsError
                        ? context.colors.text.destructive
                        : context.colors.text.warning,
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
                    : _planRefreshFailed
                    ? 'Try again'
                    : !syncReadyForPlan
                    ? 'Syncing...'
                    : _isRefreshingPlan
                    ? 'Updating plan...'
                    : widget.isHardware
                    ? 'Continue with Keystone'
                    : 'Start migration',
                onPressed: _planRefreshFailed
                    ? _retryAnalysis
                    : canStartCurrentPlan
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

String _mobilePrivatePlanFingerprint(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final transferValues =
      plan.scheduledTransfers.map((transfer) => transfer.valueZatoshi).toList()
        ..sort();
  final targetValues = plan.targetValuesZatoshi.toList()..sort();
  return [
    plan.totalInputZatoshi,
    plan.totalMigratableZatoshi,
    plan.orchardChangeZatoshi,
    plan.denominationSplitFeeZatoshi,
    plan.migrationFeeZatoshi,
    plan.estimatedTotalFeeZatoshi,
    plan.plannedBatchCount,
    plan.denominationSplitStageCount,
    plan.signingBatchLimit,
    plan.maxPreparedNotesPerRun,
    targetValues.join(','),
    transferValues.join(','),
  ].join('|');
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

class _MobileMigrationFastReview extends StatelessWidget {
  const _MobileMigrationFastReview({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _MobileMigrationReviewScaffold(
      onBack: () => context.go('/migration/options'),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            variant: AppButtonVariant.secondary,
            expand: true,
            height: 50,
            onPressed: () => context.go('/migration/options'),
            leading: const AppIcon(AppIcons.chevronBackward, size: 20),
            child: const Text('Consider another option'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            variant: AppButtonVariant.destructive,
            expand: true,
            height: 50,
            // The Immediate migration backend is not available yet. Keep the
            // reviewed CTA interactive for the approved flow and visual state,
            // but intentionally make it a no-op until execution is wired.
            onPressed: () {},
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
                    value: '${data.amountText} ZEC',
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
                                      '${data.amountText} ZEC and '
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
        ],
      ),
    );
  }
}
