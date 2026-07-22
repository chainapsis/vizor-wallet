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
      context.go('/migration/private/status', extra: plan);
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

class _MobileMigrationFastReview extends ConsumerStatefulWidget {
  const _MobileMigrationFastReview({
    required this.data,
    required this.previewMode,
  });

  final IronwoodMigrationFlowData data;
  final bool previewMode;

  @override
  ConsumerState<_MobileMigrationFastReview> createState() =>
      _MobileMigrationFastReviewState();
}

class _MobileMigrationFastReviewState
    extends ConsumerState<_MobileMigrationFastReview> {
  late bool _acknowledged = widget.previewMode;
  bool _isStarting = false;
  String? _error;

  Future<void> _startImmediateMigration() async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
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
        context.go('/migration/immediate/keystone/sign');
        return;
      }
      await ref
          .read(ironwoodMigrationServiceProvider)
          .startSoftwareImmediateMigration(accountUuid: accountUuid);
      if (!mounted) return;
      final statusRequest = IronwoodMigrationStatusRequest(
        network: ref.read(ironwoodMigrationInputsProvider).network,
        accountUuid: accountUuid,
      );
      ref.invalidate(ironwoodMigrationStatusProvider(statusRequest));
      ref.invalidate(ironwoodMigrationRouteCtaProvider);
      ref.invalidate(ironwoodHomeMigrationCtaProvider);
      ref.invalidate(ironwoodMigrationFlowDataProvider);
      ref.invalidate(ironwoodMigrationImmediatePlanProvider);
      context.go('/migration/private/status');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _mobilePrivateMigrationStartErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final planAsync = widget.previewMode
        ? const AsyncValue<rust_sync.OrchardMigrationImmediatePlan?>.data(null)
        : ref.watch(ironwoodMigrationImmediatePlanProvider);
    final plan = planAsync.asData?.value;
    final amountText = plan == null
        ? widget.data.amountText
        : formatZecAmount(plan.totalMigratableZatoshi);
    final feeText = plan == null
        ? 'shown before send'
        : '${formatZecAmount(plan.estimatedTotalFeeZatoshi)} ZEC';
    final transactionCount = plan?.plannedTransactionCount ?? 1;
    return _MobileMigrationReviewScaffold(
      onBack: () => context.go('/migration/options'),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            variant: AppButtonVariant.ghost,
            expand: true,
            constrainContent: true,
            height: 44,
            onPressed: () => context.go('/migration/options'),
            leading: const AppIcon(AppIcons.chevronBackward, size: 20),
            child: const Text('Consider another option'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('mobile_ironwood_immediate_start_button'),
            variant: AppButtonVariant.destructive,
            expand: true,
            constrainContent: true,
            height: 50,
            onPressed:
                _acknowledged &&
                    !_isStarting &&
                    (widget.previewMode || plan != null)
                ? (widget.previewMode ? () {} : _startImmediateMigration)
                : null,
            leading: _isStarting
                ? AppLoadingIcon(
                    size: 20,
                    color: colors.button.destructive.label,
                  )
                : const AppIcon(AppIcons.warning, size: 20),
            child: Text(
              _isStarting ? 'Starting migration...' : 'Continue anyway',
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 153),
            child: _MobileReviewCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  _ReviewRow(
                    label: 'Amount',
                    value: '$amountText ZEC',
                    height: 32,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _ReviewRow(label: 'Fees (estimate)', value: feeText),
                  const SizedBox(height: AppSpacing.xs),
                  _ReviewRow(
                    label: 'Migration complete in',
                    value: '~5 mins',
                    showInfo: true,
                    onInfoPressed: () =>
                        _showMobileMigrationTimingSheet(context),
                    height: 32,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            key: const ValueKey('mobile_ironwood_fast_privacy_card'),
            constraints: const BoxConstraints(minHeight: 189),
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
                                      'Moves without private scheduling — your '
                                      '$amountText ZEC across '
                                      '$transactionCount visible '
                                      '${transactionCount == 1 ? 'transaction' : 'transactions'} and '
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
          if (planAsync.isLoading && !widget.previewMode) ...[
            const SizedBox(height: AppSpacing.sm),
            const AppLoadingIcon(size: 20),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
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
    );
  }
}
