part of 'mobile_ironwood_migration_flow_screen.dart';

enum _MobileMigrationStartPhase { loading, keystoneReady, error }

enum _PrivateMigrationContinuationDestination {
  status,
  keystoneCombinedSigning,
  keystoneDenominationSigning,
}

bool _privatePlanUsesCombinedKeystoneSigning(
  rust_sync.OrchardMigrationPrivatePlan plan,
) => plan.denominationSplitStageCount > 0;

Future<void> _refreshPrivateMigrationDraftPresentation(WidgetRef ref) async {
  ref.invalidate(ironwoodMigrationRouteCtaProvider);
  ref.invalidate(ironwoodHomeMigrationCtaProvider);
  ref.invalidate(ironwoodPostMigrationStateProvider);
  try {
    await ref.read(ironwoodHomeMigrationCtaProvider.future);
  } catch (error) {
    // The durable draft is already saved. Let the destination screen reconcile
    // it rather than trapping the user on the option picker for a stale read.
    debugPrint('Failed to refresh private migration presentation: $error');
  }
}

Future<bool> _hasDurablePrivateMigrationRun(WidgetRef ref) async {
  ref.invalidate(ironwoodMigrationRouteCtaProvider);
  try {
    final cta = await ref.read(ironwoodMigrationRouteCtaProvider.future);
    return cta.status?.activeRunId != null;
  } catch (_) {
    return false;
  }
}

void _openPrivateMigrationDestination(
  BuildContext context,
  ({
    _PrivateMigrationContinuationDestination destination,
    MobileIronwoodMigrationKeystoneCombinedSignEntry? combinedEntry,
    MobileIronwoodMigrationKeystoneDenominationSignEntry? denominationEntry,
  })
  continuation,
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  switch (continuation.destination) {
    case _PrivateMigrationContinuationDestination.status:
      context.go(
        '/migration/private/status',
        extra: MobileIronwoodMigrationStatusEntry(approvedPlan: plan),
      );
      return;
    case _PrivateMigrationContinuationDestination.keystoneCombinedSigning:
      final entry = continuation.combinedEntry;
      if (entry == null) {
        throw StateError('Keystone signing request is unavailable.');
      }
      context.go('/migration/private/keystone/sign', extra: entry);
      return;
    case _PrivateMigrationContinuationDestination.keystoneDenominationSigning:
      final entry = continuation.denominationEntry;
      if (entry == null) {
        throw StateError(
          'Keystone preparation signing request is unavailable.',
        );
      }
      context.go(
        '/migration/private/keystone/denominations/sign',
        extra: entry,
      );
      return;
  }
}

Future<
  ({
    _PrivateMigrationContinuationDestination destination,
    MobileIronwoodMigrationKeystoneCombinedSignEntry? combinedEntry,
    MobileIronwoodMigrationKeystoneDenominationSignEntry? denominationEntry,
  })
>
_continuePrivateMigrationAfterNotificationGate(
  WidgetRef ref,
  rust_sync.OrchardMigrationPrivatePlan plan,
) async {
  final accountState = await ref.read(accountProvider.future);
  final accountUuid = accountState.activeAccountUuid;
  if (accountUuid == null) {
    throw StateError('No active account is selected.');
  }

  if (accountState.activeAccount?.isHardware ?? false) {
    final service = ref.read(ironwoodMigrationServiceProvider);
    if (!_privatePlanUsesCombinedKeystoneSigning(plan)) {
      final request = await service.prepareKeystoneDenominationPrivateMigration(
        accountUuid: accountUuid,
      );
      if (request.messages.isEmpty) {
        await service.completeKeystoneDenominationPrivateMigration(
          accountUuid: accountUuid,
          requestId: request.requestId,
          signedMessages: const [],
          approvedSchedule: plan.scheduledTransfers,
        );
        _invalidateStartedPrivateMigration(ref);
        return (
          destination: _PrivateMigrationContinuationDestination.status,
          combinedEntry: null,
          denominationEntry: null,
        );
      }
      return (
        destination: _PrivateMigrationContinuationDestination
            .keystoneDenominationSigning,
        combinedEntry: null,
        denominationEntry: MobileIronwoodMigrationKeystoneDenominationSignEntry(
          approvedSchedule: plan.scheduledTransfers,
          request: request,
          accountUuid: accountUuid,
        ),
      );
    }
    if (await _hasDurablePrivateMigrationRun(ref)) {
      return (
        destination: _PrivateMigrationContinuationDestination.status,
        combinedEntry: null,
        denominationEntry: null,
      );
    }
    final request = await service.prepareKeystoneSingleQrPrivateMigration(
      accountUuid: accountUuid,
      approvedSchedule: plan.scheduledTransfers,
    );
    return (
      destination:
          _PrivateMigrationContinuationDestination.keystoneCombinedSigning,
      combinedEntry: MobileIronwoodMigrationKeystoneCombinedSignEntry(
        approvedSchedule: plan.scheduledTransfers,
        request: request,
        accountUuid: accountUuid,
      ),
      denominationEntry: null,
    );
  }

  await ref
      .read(ironwoodMigrationCoordinatorProvider.notifier)
      .startSoftwareMigration(
        accountUuid: accountUuid,
        approvedSchedule: plan.scheduledTransfers,
      );

  _invalidateStartedPrivateMigration(ref);
  return (
    destination: _PrivateMigrationContinuationDestination.status,
    combinedEntry: null,
    denominationEntry: null,
  );
}

void _invalidateStartedPrivateMigration(WidgetRef ref) {
  ref.invalidate(ironwoodMigrationRouteCtaProvider);
  ref.invalidate(ironwoodHomeMigrationCtaProvider);
  ref.invalidate(ironwoodMigrationFlowDataProvider);
  ref.invalidate(ironwoodMigrationPrivatePlanProvider);
}

class MobileIronwoodMigrationStartScreen extends ConsumerStatefulWidget {
  const MobileIronwoodMigrationStartScreen({this.approvedPlan, super.key});

  final rust_sync.OrchardMigrationPrivatePlan? approvedPlan;

  @override
  ConsumerState<MobileIronwoodMigrationStartScreen> createState() =>
      _MobileIronwoodMigrationStartScreenState();
}

class _MobileIronwoodMigrationStartScreenState
    extends ConsumerState<MobileIronwoodMigrationStartScreen> {
  static const _messages = [
    'Preparing your migration...',
    'Organizing migration batches...',
    'Preparing your migration plan...',
  ];
  static const _messagePeriod = Duration(milliseconds: 1400);

  Timer? _messageTimer;
  _MobileMigrationStartPhase _phase = _MobileMigrationStartPhase.loading;
  _PrivateMigrationContinuationDestination? _destination;
  MobileIronwoodMigrationKeystoneCombinedSignEntry? _keystoneCombinedEntry;
  rust_sync.OrchardMigrationPrivatePlan? _resolvedPlan;
  String? _error;
  var _messageIndex = 0;
  var _isPreparing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepare());
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  void _startMessageRotation() {
    _messageTimer?.cancel();
    _messageTimer = Timer.periodic(_messagePeriod, (_) {
      if (!mounted || _phase != _MobileMigrationStartPhase.loading) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _messages.length;
      });
    });
  }

  Future<void> _prepare() async {
    if (_isPreparing) return;
    _isPreparing = true;
    final minimumDelay = Future<void>.delayed(
      ref.read(mobileIronwoodMigrationStartMinimumDurationProvider),
    );
    var draftSaved = false;
    if (mounted) {
      setState(() {
        _phase = _MobileMigrationStartPhase.loading;
        _destination = null;
        _keystoneCombinedEntry = null;
        _error = null;
        _messageIndex = 0;
      });
    }
    _startMessageRotation();

    try {
      final plan =
          widget.approvedPlan ??
          await ref.read(ironwoodMigrationPrivatePlanProvider.future);
      if (plan == null) {
        throw StateError('Migration plan is unavailable.');
      }
      _resolvedPlan = plan;

      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      final isHardware = accountState.activeAccount?.isHardware ?? false;
      if (isHardware && !_keystoneTwoRoundPlanSupported(plan)) {
        throw StateError(
          'This migration needs more transactions than one Keystone '
          'signing request supports.',
        );
      }

      if (!isHardware || !_privatePlanUsesCombinedKeystoneSigning(plan)) {
        await ref
            .read(ironwoodMigrationServiceProvider)
            .savePrivateMigrationDraft(
              accountUuid: accountUuid,
              approvedSchedule: plan.scheduledTransfers,
            );
        draftSaved = true;
        if (!mounted) return;
        await _refreshPrivateMigrationDraftPresentation(ref);
        if (!mounted) return;
      }

      final continuation = await _continuePrivateMigrationAfterNotificationGate(
        ref,
        plan,
      );
      await minimumDelay;
      if (!mounted) return;

      if (continuation.destination ==
          _PrivateMigrationContinuationDestination.keystoneCombinedSigning) {
        _messageTimer?.cancel();
        _isPreparing = false;
        setState(() {
          _phase = _MobileMigrationStartPhase.keystoneReady;
          _destination = continuation.destination;
          _keystoneCombinedEntry = continuation.combinedEntry;
        });
        return;
      }
      _isPreparing = false;
      _openPrivateMigrationDestination(context, continuation, plan);
    } catch (error) {
      await minimumDelay;
      if (!mounted) return;
      if (draftSaved || await _hasDurablePrivateMigrationRun(ref)) {
        if (!mounted) return;
        _isPreparing = false;
        context.go(
          '/migration/private/status',
          extra: MobileIronwoodMigrationStatusEntry(
            approvedPlan: _resolvedPlan,
          ),
        );
        return;
      }
      _messageTimer?.cancel();
      _isPreparing = false;
      setState(() {
        _phase = _MobileMigrationStartPhase.error;
        _error = _mobilePrivateMigrationStartErrorMessage(error);
      });
    } finally {
      _isPreparing = false;
    }
  }

  void _continueWithKeystone() {
    final plan = _resolvedPlan;
    final entry = _keystoneCombinedEntry;
    if (plan == null ||
        entry == null ||
        _destination !=
            _PrivateMigrationContinuationDestination.keystoneCombinedSigning) {
      return;
    }
    _openPrivateMigrationDestination(context, (
      destination:
          _PrivateMigrationContinuationDestination.keystoneCombinedSigning,
      combinedEntry: entry,
      denominationEntry: null,
    ), plan);
  }

  @override
  Widget build(BuildContext context) {
    final loading = _phase == _MobileMigrationStartPhase.loading;
    final ready = _phase == _MobileMigrationStartPhase.keystoneReady;
    return PopScope(
      canPop: _phase == _MobileMigrationStartPhase.error,
      child: _MigrationPreviewPage(
        navTitle: 'Preparing your migration',
        showBackButton: _phase == _MobileMigrationStartPhase.error,
        onBack: _phase == _MobileMigrationStartPhase.error
            ? () => context.go('/migration/options')
            : null,
        bottom: ready
            ? SizedBox(
                width: double.infinity,
                child: AppButton(
                  key: const ValueKey(
                    'mobile_ironwood_migration_start_continue_button',
                  ),
                  expand: true,
                  constrainContent: true,
                  height: 50,
                  onPressed: _continueWithKeystone,
                  leading: const AppIcon(AppIcons.qr, size: 20),
                  child: const Text('Continue'),
                ),
              )
            : _phase == _MobileMigrationStartPhase.error
            ? SizedBox(
                width: double.infinity,
                child: AppButton(
                  key: const ValueKey(
                    'mobile_ironwood_migration_start_retry_button',
                  ),
                  expand: true,
                  constrainContent: true,
                  height: 50,
                  onPressed: _isPreparing ? null : () => unawaited(_prepare()),
                  child: const Text('Retry'),
                ),
              )
            : null,
        child: Center(
          child: SizedBox(
            key: loading
                ? const ValueKey('mobile_ironwood_migration_start_loading')
                : null,
            width: 320,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: ready
                  ? _MobileMigrationStartReadyContent(
                      key: const ValueKey(
                        'mobile_ironwood_migration_start_keystone_ready',
                      ),
                    )
                  : _phase == _MobileMigrationStartPhase.error
                  ? _MobileMigrationStartErrorContent(error: _error)
                  : _MobileMigrationStartLoadingContent(
                      message: _messages[_messageIndex],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileMigrationStartPreview extends StatelessWidget {
  const _MobileMigrationStartPreview({this.ready = false});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    return _MigrationPreviewPage(
      navTitle: 'Preparing your migration',
      showBackButton: false,
      bottom: ready
          ? SizedBox(
              width: double.infinity,
              child: AppButton(
                expand: true,
                constrainContent: true,
                height: 50,
                onPressed: _noopMigrationPreviewAction,
                leading: const AppIcon(AppIcons.qr, size: 20),
                child: const Text('Continue'),
              ),
            )
          : null,
      child: Center(
        child: SizedBox(
          width: 320,
          child: ready
              ? const _MobileMigrationStartReadyContent()
              : const _MobileMigrationStartLoadingContent(
                  message: 'Preparing your migration...',
                ),
        ),
      ),
    );
  }
}

class _MobileMigrationStartLoadingContent extends StatelessWidget {
  const _MobileMigrationStartLoadingContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const IronwoodMigrationAnalyzingProgressBar(
          key: ValueKey('mobile_ironwood_migration_start_loading_indicator'),
        ),
        const SizedBox(height: AppSpacing.xl),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: IronwoodMigrationShimmerText(
            key: ValueKey(message),
            text: message,
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall,
            baseColor: context.colors.text.muted,
            highlightColor: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 286,
          child: Text(
            'Vizor is preparing your migration. This may take a moment.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileMigrationStartReadyContent extends StatelessWidget {
  const _MobileMigrationStartReadyContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          AppIcons.migrationSign,
          size: 40,
          color: context.colors.icon.success,
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'Ready to sign',
          textAlign: TextAlign.center,
          style: AppTypography.headlineSmall.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 286,
          child: Text(
            'Continue to sign the preparation transactions and migration '
            'batches together with Keystone.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileMigrationStartErrorContent extends StatelessWidget {
  const _MobileMigrationStartErrorContent({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          AppIcons.warningCircle,
          size: 40,
          color: context.colors.icon.destructive,
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          "Couldn't prepare your migration",
          textAlign: TextAlign.center,
          style: AppTypography.headlineSmall.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          error ?? 'Try again when you are ready.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.primary,
          ),
        ),
      ],
    );
  }
}
