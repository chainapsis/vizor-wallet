part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationBatchProgress {
  const _MobileMigrationBatchProgress({
    required this.completedBatches,
    required this.totalBatches,
    required this.currentBatchNumber,
    required this.currentBatchStartIndex,
    required this.currentBatchPartCount,
    required this.currentBatchParts,
  });

  final int completedBatches;
  final int totalBatches;
  final int currentBatchNumber;
  final int currentBatchStartIndex;
  final int currentBatchPartCount;
  final List<rust_sync.MigrationPartStatus> currentBatchParts;
}

class _MobileMigrationRedesignedStatus extends ConsumerStatefulWidget {
  const _MobileMigrationRedesignedStatus({
    required this.data,
    required this.status,
    required this.isHardware,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;
  final bool isHardware;

  @override
  ConsumerState<_MobileMigrationRedesignedStatus> createState() =>
      _MobileMigrationRedesignedStatusState();
}

class _MobileMigrationRedesignedStatusState
    extends ConsumerState<_MobileMigrationRedesignedStatus> {
  static const _syncSurfaceRevealDelay = Duration(milliseconds: 800);
  static const _syncSurfaceMinimumDuration = Duration(milliseconds: 500);
  static const _advancingLabelRevealDelay = Duration(milliseconds: 800);
  static const _advancingLabelMinimumDuration = Duration(seconds: 2);

  AppLifecycleListener? _lifecycleListener;
  Timer? _syncSurfaceRevealTimer;
  Timer? _syncSurfaceMinimumTimer;
  Timer? _advancingLabelRevealTimer;
  Timer? _advancingLabelMinimumTimer;
  bool _syncSurfaceMinimumElapsed = false;
  bool _wasBackgrounded = false;
  bool _surfaceRefreshInProgress = false;
  bool _surfaceRefreshRequested = false;
  bool _showSyncSurface = false;
  bool _walletSyncActive = false;

  // A sync transition invalidates the status shown by this surface. Only a
  // coordinator refresh and route-status reload from the same epoch can make
  // it current again.
  bool _hasCompletedSurfaceRefresh = false;
  int _surfaceRefreshFailures = 0;
  Timer? _surfaceRefreshRetryTimer;
  int _statusFreshnessEpoch = 0;
  int _refreshedStatusEpoch = -1;
  // Null until the first authorization lookup resolves, so copy can stay quiet
  // about notifications instead of claiming they are off.
  bool? _notificationsAuthorized;
  // Null until the first capability lookup resolves. Only an explicit `false`
  // may claim this device cannot track preparation in the background; unknown
  // keeps the existing copy instead of guessing during the first frames.
  bool? _supportsBackgroundPreparationTracking;
  IronwoodMigrationPreparationRuntimeState _preparationRuntimeState =
      IronwoodMigrationPreparationRuntimeState.idle;
  bool _showPreparationComplete = false;
  bool _actionRunning = false;
  // Raw coordinator advance signal and its debounced, display-only shadow. Only
  // the preparation dial copy reads the debounced one; everything that must
  // react immediately (back gating, button labels) keeps reading the raw
  // membership.
  bool _coordinatorAdvancing = false;
  bool _showAdvancingLabel = false;
  int _advancingLabelEpoch = 0;
  bool _advancingLabelMinimumElapsed = false;
  bool _softwarePreparationResumeAttempted = false;
  String? _softwarePreparationResumeError;
  String? _recordedAttentionFingerprint;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onHide: _markBackgrounded,
      onPause: _markBackgrounded,
      onResume: _resumeIfNeeded,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleSyncActivity(ref.read(syncProvider).value?.isSyncing ?? false);
      _handleCoordinatorAdvancing(
        _isCoordinatorAdvancing(
          ref.read(ironwoodMigrationCoordinatorProvider),
          ref.read(accountProvider).value?.activeAccountUuid,
        ),
      );
      unawaited(_initializeCurrentSession());
    });
  }

  Future<void> _initializeCurrentSession() async {
    if (_shouldResumeSoftwarePreparation) {
      await _resumeSoftwarePreparation();
    }
    if (mounted) await _initializeCurrentSessionSurface();
  }

  @override
  void didUpdateWidget(covariant _MobileMigrationRedesignedStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final enteredAwaitingPreparation =
        oldWidget.status.phase != kIronwoodMigrationAwaitingPreparationPhase &&
        widget.status.phase == kIronwoodMigrationAwaitingPreparationPhase;
    if (oldWidget.status.activeRunId != widget.status.activeRunId ||
        enteredAwaitingPreparation) {
      _softwarePreparationResumeAttempted = false;
      _softwarePreparationResumeError = null;
    }
    final completedPreparation =
        oldWidget.status.phase ==
            kIronwoodMigrationWaitingDenomConfirmationsPhase &&
        widget.status.phase != kIronwoodMigrationWaitingDenomConfirmationsPhase;
    if (completedPreparation) {
      unawaited(_showPreparationCompleteIfNeeded());
    }
    if (enteredAwaitingPreparation && !widget.isHardware) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resumeSoftwarePreparation());
      });
    }
  }

  bool get _shouldResumeSoftwarePreparation =>
      !widget.isHardware &&
      widget.status.activeRunId != null &&
      widget.status.phase == kIronwoodMigrationAwaitingPreparationPhase &&
      !_softwarePreparationResumeAttempted;

  Future<void> _resumeSoftwarePreparation() async {
    if (!_shouldResumeSoftwarePreparation || _actionRunning) return;
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    _softwarePreparationResumeAttempted = true;
    setState(() {
      _actionRunning = true;
      _softwarePreparationResumeError = null;
    });
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .resumeSoftwarePreparation(
            accountUuid: accountUuid,
            status: widget.status,
          );
    } catch (error) {
      if (mounted) {
        setState(() {
          _softwarePreparationResumeError =
              _mobilePrivateMigrationStartErrorMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _syncSurfaceRevealTimer?.cancel();
    _syncSurfaceMinimumTimer?.cancel();
    _advancingLabelRevealTimer?.cancel();
    _advancingLabelMinimumTimer?.cancel();
    _surfaceRefreshRetryTimer?.cancel();
    super.dispose();
  }

  void _markBackgrounded() {
    _wasBackgrounded = true;
  }

  void _resumeIfNeeded() {
    if (!_wasBackgrounded) return;
    _wasBackgrounded = false;
    unawaited(_initializeCurrentSessionSurface());
  }

  Future<void> _initializeCurrentSessionSurface() async {
    if (_surfaceRefreshInProgress) {
      _surfaceRefreshRequested = true;
      return;
    }
    _surfaceRefreshInProgress = true;
    _surfaceRefreshRequested = false;
    try {
      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      final refreshEpoch = _statusFreshnessEpoch;
      final accountUuid = accountState.activeAccountUuid;
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();
      if (!mounted) return;
      final refreshedCta = await ref.read(
        ironwoodMigrationRouteCtaProvider.future,
      );
      if (!mounted) return;
      try {
        await _refreshNotificationAuthorization();
      } catch (_) {
        if (mounted) {
          setState(() => _notificationsAuthorized = false);
        }
      }
      try {
        await _refreshBackgroundPreparationSupport();
      } catch (_) {
        // A failed capability probe must never promise a background lane.
        if (mounted) {
          setState(() => _supportsBackgroundPreparationTracking = false);
        }
      }
      await _reconcilePreparationRuntimeState();
      if (!mounted) return;
      if (!_walletSyncActive &&
          refreshEpoch == _statusFreshnessEpoch &&
          accountUuid != null &&
          ref.read(accountProvider).value?.activeAccountUuid == accountUuid &&
          refreshedCta.accountUuid == accountUuid) {
        setState(() {
          _hasCompletedSurfaceRefresh = true;
          _refreshedStatusEpoch = refreshEpoch;
        });
      }
      if (!(ref.read(syncProvider).value?.isSyncing ?? false)) {
        await _showPreparationCompleteIfNeeded();
      }
      if (accountUuid != null &&
          _shouldAutomaticallyResumePreparation(accountUuid)) {
        await _continuePreparation(accountUuid);
      }
      _surfaceRefreshFailures = 0;
    } catch (error) {
      // One transient failure must not park this screen on the sync skeleton —
      // that would hide the required-action card the user was called in for.
      debugPrint('[zcash] migration surface refresh failed: $error');
      _surfaceRefreshFailures += 1;
      if (mounted && _surfaceRefreshFailures == 1) {
        _surfaceRefreshRetryTimer?.cancel();
        _surfaceRefreshRetryTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) unawaited(_initializeCurrentSessionSurface());
        });
      } else if (mounted && !_hasCompletedSurfaceRefresh) {
        // Repeated failures degrade to the last known status; the five-second
        // coordinator poll keeps trying to freshen it.
        setState(() => _hasCompletedSurfaceRefresh = true);
      }
    } finally {
      _surfaceRefreshInProgress = false;
      if (_surfaceRefreshRequested && mounted) {
        unawaited(_initializeCurrentSessionSurface());
      }
    }
  }

  /// Whether this reentry should restart the software preparation advance on
  /// its own. Backgrounding drops the foreground permit, and iOS before 26
  /// reports no runtime state at all, so without this every return to the app
  /// blames the user for leaving and waits for a manual continue.
  bool _shouldAutomaticallyResumePreparation(String accountUuid) {
    if (widget.isHardware || _actionRunning) return false;
    if (widget.status.phase !=
        kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return false;
    }
    // `widget.isHardware` is false while the account list is still loading, so
    // the account record decides. A Keystone run needs the device, never this.
    final accountState = ref.read(accountProvider).value;
    final account = accountState?.activeAccountUuid == accountUuid
        ? accountState?.activeAccount
        : null;
    if (account == null || account.isHardware) return false;
    // Work the native task or an in-flight advance already owns must never be
    // restarted from here.
    if (_preparationRuntimeState !=
            IronwoodMigrationPreparationRuntimeState.idle &&
        _preparationRuntimeState !=
            IronwoodMigrationPreparationRuntimeState.disabled) {
      return false;
    }
    final coordinator = ref.read(ironwoodMigrationCoordinatorProvider);
    return coordinator.errors[accountUuid] == null &&
        !coordinator.foregroundProgressPermits.contains(accountUuid) &&
        !coordinator.advancingAccounts.contains(accountUuid);
  }

  void _handleSyncActivity(bool isSyncing) {
    if (_walletSyncActive != isSyncing) {
      setState(() {
        _walletSyncActive = isSyncing;
        _statusFreshnessEpoch++;
      });
    }
    if (!isSyncing) {
      _syncSurfaceRevealTimer?.cancel();
      _syncSurfaceRevealTimer = null;
      if (!_showSyncSurface || !mounted) return;
      if (_syncSurfaceMinimumElapsed) {
        _hideSyncSurface();
      }
      return;
    }
    if (_showSyncSurface || _syncSurfaceRevealTimer != null) return;
    _syncSurfaceRevealTimer = Timer(_syncSurfaceRevealDelay, () {
      _syncSurfaceRevealTimer = null;
      if (!mounted ||
          !(ref.read(syncProvider).value?.isSyncing ?? false) ||
          _showPreparationComplete) {
        return;
      }
      setState(() {
        _showSyncSurface = true;
        _syncSurfaceMinimumElapsed = false;
      });
      _syncSurfaceMinimumTimer?.cancel();
      _syncSurfaceMinimumTimer = Timer(_syncSurfaceMinimumDuration, () {
        _syncSurfaceMinimumTimer = null;
        _syncSurfaceMinimumElapsed = true;
        if (!mounted || (ref.read(syncProvider).value?.isSyncing ?? false)) {
          return;
        }
        _hideSyncSurface();
      });
    });
  }

  void _hideSyncSurface() {
    if (!mounted || !_showSyncSurface) return;
    setState(() {
      _showSyncSurface = false;
      _syncSurfaceMinimumElapsed = false;
    });
  }

  bool _isCoordinatorAdvancing(
    IronwoodMigrationCoordinatorState coordinator,
    String? accountUuid,
  ) =>
      accountUuid != null &&
      coordinator.advancingAccounts.contains(accountUuid);

  /// Debounces the coordinator's advance signal for the preparation dial copy.
  ///
  /// While confirmations are pending the coordinator probes for an advance every
  /// few seconds, and each no-op probe still enters and leaves
  /// `advancingAccounts`. Bound directly to the dial, those sub-second flashes
  /// swap "Keep Vizor open." in and out on every poll. The label therefore only
  /// follows a signal that stays on long enough to be worth reading, and only
  /// lets go once it has been on screen long enough not to flicker at the end.
  ///
  /// This is display-only: back gating, button labels, and the sync-surface
  /// condition keep reading the raw membership so they stay immediate.
  void _handleCoordinatorAdvancing(bool advancing) {
    if (_coordinatorAdvancing == advancing) return;
    _coordinatorAdvancing = advancing;
    if (!advancing) {
      _advancingLabelRevealTimer?.cancel();
      _advancingLabelRevealTimer = null;
      if (!_showAdvancingLabel || !mounted) return;
      if (_advancingLabelMinimumElapsed) _hideAdvancingLabel();
      return;
    }
    // A signal that returns while the label is still up keeps the minimum timer
    // it was revealed with; cancelling it here would leave the label with no
    // path back once the signal drops again.
    if (_showAdvancingLabel || _advancingLabelRevealTimer != null) return;
    final epoch = ++_advancingLabelEpoch;
    _advancingLabelRevealTimer = Timer(_advancingLabelRevealDelay, () {
      _advancingLabelRevealTimer = null;
      if (!mounted || epoch != _advancingLabelEpoch || !_coordinatorAdvancing) {
        return;
      }
      setState(() {
        _showAdvancingLabel = true;
        _advancingLabelMinimumElapsed = false;
      });
      _advancingLabelMinimumTimer?.cancel();
      _advancingLabelMinimumTimer = Timer(_advancingLabelMinimumDuration, () {
        _advancingLabelMinimumTimer = null;
        _advancingLabelMinimumElapsed = true;
        if (!mounted || _coordinatorAdvancing) return;
        _hideAdvancingLabel();
      });
    });
  }

  void _hideAdvancingLabel() {
    if (!mounted || !_showAdvancingLabel) return;
    _advancingLabelEpoch++;
    setState(() {
      _showAdvancingLabel = false;
      _advancingLabelMinimumElapsed = false;
    });
  }

  bool get _awaitingFreshMigrationStatus =>
      !_hasCompletedSurfaceRefresh ||
      _refreshedStatusEpoch != _statusFreshnessEpoch;

  bool get _shouldShowSyncSurface =>
      _showSyncSurface ||
      (!_walletSyncActive && _awaitingFreshMigrationStatus) ||
      !_hasCompletedSurfaceRefresh;

  Future<void> _refreshNotificationAuthorization() async {
    final authorized = await ref
        .read(ironwoodMigrationServiceProvider)
        .notificationAuthorizationStatus();
    if (!mounted) return;
    setState(
      () => _notificationsAuthorized = authorized.allowsBackgroundMigration,
    );
  }

  Future<void> _refreshBackgroundPreparationSupport() async {
    final supported = await ref
        .read(ironwoodMigrationServiceProvider)
        .backgroundPreparationTrackingSupported();
    if (!mounted) return;
    setState(() => _supportsBackgroundPreparationTracking = supported);
  }

  Future<void> _reconcilePreparationRuntimeState() async {
    if (widget.status.phase !=
        kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      if (mounted) {
        setState(
          () => _preparationRuntimeState =
              IronwoodMigrationPreparationRuntimeState.idle,
        );
      }
      return;
    }

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final runId = widget.status.activeRunId;
    if (accountUuid == null ||
        runId == null ||
        _notificationsAuthorized != true) {
      if (mounted) {
        setState(
          () => _preparationRuntimeState = _notificationsAuthorized != true
              ? IronwoodMigrationPreparationRuntimeState.disabled
              : IronwoodMigrationPreparationRuntimeState.idle,
        );
      }
      return;
    }

    final service = ref.read(ironwoodMigrationServiceProvider);
    IronwoodMigrationPreparationRuntimeState runtimeState;
    try {
      runtimeState = await service.preparationRuntimeState(
        accountUuid: accountUuid,
        runId: runId,
      );
    } catch (_) {
      runtimeState = IronwoodMigrationPreparationRuntimeState.idle;
    }
    if (!mounted) return;
    setState(() => _preparationRuntimeState = runtimeState);
    if (runtimeState !=
        IronwoodMigrationPreparationRuntimeState
            .foregroundContinuationPending) {
      return;
    }

    // Claim the foreground handoff before advancing. The advance path re-arms
    // background confirmation tracking after it updates the durable run. If
    // this token remains until after the advance, native startPreparation()
    // sees no trackable scope and reports success without submitting a task.
    try {
      await service.acknowledgePreparationContinuation(
        accountUuid: accountUuid,
        runId: runId,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _preparationRuntimeState =
              IronwoodMigrationPreparationRuntimeState.idle,
        );
      }
      return;
    }

    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retry(accountUuid);
    } catch (_) {
      if (mounted) {
        setState(
          () => _preparationRuntimeState =
              IronwoodMigrationPreparationRuntimeState.idle,
        );
      }
      return;
    }
    if (mounted) {
      setState(
        () => _preparationRuntimeState =
            IronwoodMigrationPreparationRuntimeState.idle,
      );
    }
  }

  /// Phases whose surface actually hosts the modal. Setting the flag anywhere
  /// else only suppresses the sync surface while nothing replaces it.
  static const _preparationCompletePhases = {
    kIronwoodMigrationReadyToMigratePhase,
    kIronwoodMigrationBroadcastScheduledPhase,
    kIronwoodMigrationBroadcastingPhase,
    kIronwoodMigrationWaitingConfirmationsPhase,
  };

  Future<void> _showPreparationCompleteIfNeeded() async {
    if (ref.read(syncProvider).value?.isSyncing ?? false) return;
    final status = widget.status;
    final runId = status.activeRunId;
    if (runId == null || !_preparationCompletePhases.contains(status.phase)) {
      return;
    }
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid != null &&
        ref.read(ironwoodMigrationCoordinatorProvider).errors[accountUuid] !=
            null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = 'zcash_ironwood_migration_preparation_complete_seen_$runId';
    if (prefs.getBool(key) ?? false) return;
    if (!mounted) return;
    setState(() => _showPreparationComplete = true);
    // Recorded as the modal becomes visible, not on Done: a system back that
    // pops this route would otherwise bring the modal back on every reentry.
    await prefs.setBool(key, true);
  }

  Future<void> _dismissPreparationComplete() async {
    final runId = widget.status.activeRunId;
    if (runId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'zcash_ironwood_migration_preparation_complete_seen_$runId',
        true,
      );
    }
    if (!mounted) return;
    setState(() => _showPreparationComplete = false);
    _handleSyncActivity(ref.read(syncProvider).value?.isSyncing ?? false);
  }

  @override
  Widget build(BuildContext context) {
    // This screen returns from a dozen different branches, so the back
    // handling is wrapped once out here instead of at every return.
    return _MobileIronwoodMigrationBackScope(
      // Leaving is always allowed, including mid-action: the coordinator owns
      // the work and keeps running it off-screen, so there is no reason to
      // hold the user on this surface.
      onFallback: () => context.go('/home'),
      child: _buildStatusSurface(context),
    );
  }

  Widget _buildStatusSurface(BuildContext context) {
    ref.listen(syncProvider, (previous, next) {
      final wasSyncing = previous?.value?.isSyncing ?? false;
      final isSyncing = next.value?.isSyncing ?? false;
      _handleSyncActivity(isSyncing);
      if (wasSyncing && !isSyncing) {
        unawaited(_initializeCurrentSessionSurface());
      }
    });
    ref.listen(ironwoodMigrationCoordinatorProvider, (previous, next) {
      _handleCoordinatorAdvancing(
        _isCoordinatorAdvancing(
          next,
          ref.read(accountProvider).value?.activeAccountUuid,
        ),
      );
    });
    // The debounced signal is account-scoped, so a switch has to re-evaluate it
    // too; otherwise the previous account's advance copy outlives its run.
    ref.listen(accountProvider, (previous, next) {
      _handleCoordinatorAdvancing(
        _isCoordinatorAdvancing(
          ref.read(ironwoodMigrationCoordinatorProvider),
          next.value?.activeAccountUuid,
        ),
      );
    });
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    final coordinatorError = accountUuid == null
        ? null
        : coordinator.errors[accountUuid];
    final needsCredentialRecovery =
        accountUuid != null &&
        ironwoodMigrationNeedsCredentialRecovery(coordinatorError);
    final needsHardwareCredentialAttention =
        needsCredentialRecovery && widget.isHardware;
    final needsSoftwareCredentialRecovery =
        needsCredentialRecovery && !widget.isHardware;
    final recoveryInProgress =
        accountUuid != null &&
        coordinator.advancingAccounts.contains(accountUuid);
    final hasForegroundPermit =
        accountUuid != null &&
        coordinator.foregroundProgressPermits.contains(accountUuid);
    final hasChildProofBatchPermit =
        accountUuid != null &&
        coordinator.childProofBatchPermits.contains(accountUuid);
    final actionInProgress =
        _actionRunning ||
        (accountUuid != null &&
            coordinator.advancingAccounts.contains(accountUuid));
    void viewMigrationSchedule() {
      context.push('/migration/private/schedule');
    }

    void viewPreparationSchedule() {
      context.push('/migration/private/preparation-schedule');
    }

    final leftToMigrateText = _leftToMigrateText(widget.status);
    final completionEstimateText = _completionEstimateText(widget.status);
    _recordVisibleAttention(accountUuid);

    if (widget.status.phase == kIronwoodMigrationAwaitingPreparationPhase ||
        widget.status.phase ==
            kIronwoodMigrationAwaitingDenominationSignaturePhase) {
      // Rust never writes `awaiting_denomination_signature`, so a hardware
      // draft that still needs a split signature is durably stored as
      // `awaiting_preparation`. Both phases mean the same thing for a Keystone
      // account: only the device can move preparation forward.
      final awaitingKeystoneSignature =
          widget.isHardware &&
          (widget.status.phase ==
                  kIronwoodMigrationAwaitingDenominationSignaturePhase ||
              widget.status.phase ==
                  kIronwoodMigrationAwaitingPreparationPhase);
      final softwareResumeFailed =
          !widget.isHardware && _softwarePreparationResumeError != null;
      return _MigrationPreparationPreview(
        state: awaitingKeystoneSignature || softwareResumeFailed
            ? _MigrationPreparationState.paused
            : _MigrationPreparationState.active,
        isKeystone: awaitingKeystoneSignature,
        pausedMessage: awaitingKeystoneSignature
            ? _keystonePreparationSignatureMessage
            : _softwarePreparationResumeError,
        onBack: () => context.go('/home'),
        onViewSchedule: viewPreparationSchedule,
        onContinue: accountUuid == null
            ? null
            : awaitingKeystoneSignature
            ? () =>
                  context.push('/migration/private/keystone/denominations/sign')
            : softwareResumeFailed
            ? () {
                _softwarePreparationResumeAttempted = false;
                unawaited(_resumeSoftwarePreparation());
              }
            : null,
      );
    }

    if (_shouldShowSyncSurface &&
        !_showPreparationComplete &&
        !actionInProgress) {
      if (widget.status.phase ==
          kIronwoodMigrationWaitingDenomConfirmationsPhase) {
        return _MigrationPreparationPreview(
          state: _MigrationPreparationState.syncing,
          onBack: () => context.go('/home'),
          onViewSchedule: viewPreparationSchedule,
        );
      }
      return _MigrationProgressPreview(
        state: _MigrationProgressState.syncing,
        onBack: () => context.go('/home'),
        onViewSchedule: viewMigrationSchedule,
        completedParts: _completedParts(widget.status),
        totalParts: _totalParts(widget.status),
        segmentValuesZatoshi: _migrationRingSegmentValues(widget.status),
        migratedAmountText: _migratedAmountText(widget.status),
        totalAmountText: _totalAmountText(widget.status),
        availableAmountText: _availableAmountText(accountUuid),
        leftToMigrateText: leftToMigrateText,
        completionEstimateText: completionEstimateText,
      );
    }

    if (coordinatorError != null &&
        widget.status.phase ==
            kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return _MigrationPreparationPreview(
        state: _MigrationPreparationState.paused,
        // A recorded failure, not backgrounding, is why this run stopped.
        pausedMessage: _mobilePrivateMigrationStartErrorMessage(
          coordinatorError,
        ),
        onBack: () => context.go('/home'),
        onViewSchedule: viewPreparationSchedule,
        onContinue: accountUuid == null || _actionRunning
            ? null
            : () => unawaited(_continuePreparation(accountUuid)),
      );
    }

    if (coordinatorError != null) {
      final batchProgress = _batchProgress(widget.status);
      // An expired schedule surfaces here as a recovery error, but the only
      // way forward for a Keystone run is another signature — retrying the
      // outbox can never produce one.
      final needsKeystoneResign =
          !needsHardwareCredentialAttention &&
          widget.isHardware &&
          _requiresKeystoneSignature(widget.status);
      final keystoneResignLabel =
          widget.status.parts.any(
            (part) => part.state == rust_sync.MigrationPartState.needsInput,
          )
          ? 'Re-sign migration transactions'
          : 'Sign migration transactions';
      return _MigrationProgressPreview(
        state: _MigrationProgressState.needsInput,
        onBack: () => context.go('/home'),
        onViewSchedule: viewMigrationSchedule,
        completedParts: _completedParts(widget.status),
        totalParts: _totalParts(widget.status),
        segmentValuesZatoshi: _migrationRingSegmentValues(widget.status),
        completedBatches: batchProgress.completedBatches,
        totalBatches: batchProgress.totalBatches,
        completedRingSegments: _completedRingSegments(widget.status),
        awaitingRingSegments: _awaitingRingSegments(widget.status),
        migratedAmountText: _migratedAmountText(widget.status),
        totalAmountText: _totalAmountText(widget.status),
        availableAmountText: _availableAmountText(accountUuid),
        leftToMigrateText: leftToMigrateText,
        completionEstimateText: completionEstimateText,
        nextActionPresentation: _nextMigrationPresentation(
          widget.status,
          requiresInput: true,
        ),
        statusValueOverride: needsHardwareCredentialAttention
            ? 'Keystone account required'
            : null,
        actionMessage: needsHardwareCredentialAttention
            ? 'Reconnect or re-import your Keystone account to continue this '
                  'migration.'
            : needsKeystoneResign
            ? 'Sign the rebuilt migration transactions with Keystone to '
                  'continue.'
            : needsSoftwareCredentialRecovery
            ? 'Your migration credentials need to be restored before '
                  'continuing.'
            : "Couldn't continue this migration. Try again.",
        actionLabel: needsHardwareCredentialAttention
            ? 'Back to home'
            : needsKeystoneResign
            ? keystoneResignLabel
            : needsSoftwareCredentialRecovery
            ? recoveryInProgress
                  ? 'Recovering...'
                  : 'Recover'
            : _actionRunning
            ? 'Retrying...'
            : 'Retry',
        onAction: accountUuid == null || recoveryInProgress || _actionRunning
            ? null
            : needsHardwareCredentialAttention
            ? () => context.go('/home')
            : needsKeystoneResign
            ? () => unawaited(_performRequiredAction(accountUuid))
            : needsSoftwareCredentialRecovery
            ? () => unawaited(_confirmRecovery(accountUuid))
            : () => unawaited(_retryAfterError(accountUuid)),
      );
    }

    final durableActionPhase =
        widget.status.phase == kIronwoodMigrationPausedPhase ||
        widget.status.phase == kIronwoodMigrationFailedRecoverablePhase;
    if (durableActionPhase) {
      final batchProgress = _batchProgress(widget.status);
      final paused = widget.status.phase == kIronwoodMigrationPausedPhase;
      return _MigrationProgressPreview(
        state: _MigrationProgressState.needsInput,
        onBack: () => context.go('/home'),
        onViewSchedule: viewMigrationSchedule,
        completedParts: _completedParts(widget.status),
        totalParts: _totalParts(widget.status),
        segmentValuesZatoshi: _migrationRingSegmentValues(widget.status),
        completedBatches: batchProgress.completedBatches,
        totalBatches: batchProgress.totalBatches,
        completedRingSegments: _completedRingSegments(widget.status),
        awaitingRingSegments: _awaitingRingSegments(widget.status),
        migratedAmountText: _migratedAmountText(widget.status),
        totalAmountText: _totalAmountText(widget.status),
        availableAmountText: _availableAmountText(accountUuid),
        leftToMigrateText: leftToMigrateText,
        completionEstimateText: completionEstimateText,
        nextActionPresentation: _nextMigrationPresentation(
          widget.status,
          requiresInput: true,
        ),
        actionMessage: widget.status.message,
        actionLabel: _actionRunning
            ? paused
                  ? 'Resuming...'
                  : 'Retrying...'
            : paused
            ? 'Resume'
            : 'Retry',
        onAction: accountUuid == null || _actionRunning
            ? null
            : () => unawaited(_retryAfterError(accountUuid)),
      );
    }

    if (widget.status.phase ==
        kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      final needsManualResume =
          !hasForegroundPermit &&
          !_preparationRuntimeState.hasAutomaticBackgroundWork &&
          _preparationRuntimeState !=
              IronwoodMigrationPreparationRuntimeState
                  .foregroundContinuationPending;
      // This device has no background preparation lane at all, so neither the
      // notification prompt nor the "you left" copy names the real cause.
      final backgroundTrackingUnsupported =
          _supportsBackgroundPreparationTracking == false;
      // Whether leaving now stalls the run. An advance holds the foreground
      // permit, so backgrounding drops it and nothing moves until the next
      // reentry. An armed background task keeps observing without the app.
      // Requiring the capability here is a structural guard, not the live
      // signal: iOS before 26 can never report scheduled/running because it has
      // no continued-processing task, so the "you can close Vizor" promise
      // becomes unreachable on a device that cannot keep it.
      final backgroundTrackingArmed =
          !backgroundTrackingUnsupported &&
          (_preparationRuntimeState ==
                  IronwoodMigrationPreparationRuntimeState.scheduled ||
              _preparationRuntimeState ==
                  IronwoodMigrationPreparationRuntimeState.running);
      // Notifications are only the blocker where the lane exists. Without one,
      // asking the user to allow notifications promises something granting them
      // cannot deliver.
      final notificationsDisabled =
          !backgroundTrackingUnsupported &&
          _preparationRuntimeState ==
              IronwoodMigrationPreparationRuntimeState.disabled;
      // Display-only debounce: a user-triggered action shows its progress at
      // once, while the coordinator's own advance probes have to persist before
      // they may relabel the dial. Reading `actionInProgress` here instead would
      // thrash this copy on every confirmation poll.
      final showsAdvancingCopy = _actionRunning || _showAdvancingLabel;
      final preparationState = showsAdvancingCopy
          ? _MigrationPreparationState.advancing
          : backgroundTrackingArmed
          ? _MigrationPreparationState.backgroundTracking
          : needsManualResume
          ? _MigrationPreparationState.paused
          : _MigrationPreparationState.active;
      return _MigrationPreparationPreview(
        state: preparationState,
        // Without notifications the task cannot be armed at all, so the
        // generic "you left" pause copy would misname the cause.
        pausedMessage:
            notificationsDisabled &&
                preparationState == _MigrationPreparationState.paused
            ? _migrationPreparationNotificationsDisabledMessage
            : null,
        deviceLimitMessage: backgroundTrackingUnsupported
            ? _migrationPreparationBackgroundUnsupportedMessage
            : null,
        onBack: () => context.go('/home'),
        onViewSchedule: viewPreparationSchedule,
        onContinue: !needsManualResume || accountUuid == null
            ? null
            : () => unawaited(_continuePreparation(accountUuid)),
      );
    }

    if (widget.status.phase == kIronwoodMigrationCompletePhase) {
      return _MigrationCompleteSurface(
        status: widget.status,
        fallbackAmountText: widget.data.amountText,
        onDone: () => context.go('/home'),
      );
    }

    final state = _progressState(
      widget.status,
      hasChildProofBatchPermit: hasChildProofBatchPermit,
    );
    final nextActionText = _nextActionText(widget.status, state: state);
    final actionPart = _actionPart(widget.status);
    final batchProgress = _batchProgress(widget.status, actionPart: actionPart);
    final hasDueProofBatch = _hasDueProofBatch(widget.status);
    final hasLateScheduledBroadcast =
        !hasDueProofBatch && _hasLateScheduledBroadcast(widget.status);
    final batchNumber = batchProgress.currentBatchNumber;
    final signingAllKeystoneTransactions =
        widget.isHardware && _isInitialKeystoneSigning(widget.status);
    final resigningKeystoneTransactions =
        widget.isHardware &&
        widget.status.parts.any(
          (part) => part.state == rust_sync.MigrationPartState.needsInput,
        );
    return _MigrationProgressPreview(
      state: state,
      showPreparationCompleteModal: _showPreparationComplete,
      onPreparationCompleteDone: () => unawaited(_dismissPreparationComplete()),
      onBack: () => context.go('/home'),
      onViewSchedule: viewMigrationSchedule,
      completedParts: _completedParts(widget.status),
      totalParts: _totalParts(widget.status),
      segmentValuesZatoshi: _migrationRingSegmentValues(widget.status),
      completedBatches: batchProgress.completedBatches,
      totalBatches: batchProgress.totalBatches,
      completedRingSegments: _completedRingSegments(widget.status),
      awaitingRingSegments: _awaitingRingSegments(widget.status),
      currentSigningPartIndices: _currentSigningRingSegments(widget.status),
      migratedAmountText: _migratedAmountText(widget.status),
      totalAmountText: _totalAmountText(widget.status),
      availableAmountText: _availableAmountText(accountUuid),
      leftToMigrateText: leftToMigrateText,
      completionEstimateText: completionEstimateText,
      nextActionPresentation: _nextMigrationPresentation(
        widget.status,
        requiresInput: state == _MigrationProgressState.needsInput,
      ),
      nextActionText: nextActionText,
      actionLabel: _requiredActionLabel(
        widget.status,
        batchNumber: batchNumber,
        hasLateScheduledBroadcast: hasLateScheduledBroadcast,
        actionInProgress: actionInProgress,
      ),
      actionBatchLabel: signingAllKeystoneTransactions
          ? 'All transactions'
          : resigningKeystoneTransactions
          ? 'Transactions needing signature'
          : 'Batch #$batchNumber',
      actionBatchValue: signingAllKeystoneTransactions
          ? _allMigrationActionValueText(widget.status)
          : resigningKeystoneTransactions
          ? _needsInputActionValueText(widget.status)
          : batchProgress.currentBatchParts.isEmpty
          ? null
          : _actionBatchValueText(
              widget.status,
              batchProgress.currentBatchParts,
            ),
      actionRunning: _actionRunning,
      onAction: accountUuid == null || _actionRunning
          ? null
          : () => unawaited(_performRequiredAction(accountUuid)),
    );
  }

  _MigrationProgressState _progressState(
    rust_sync.MigrationStatus status, {
    required bool hasChildProofBatchPermit,
  }) {
    if (_requiresUserAction(
      status,
      hasChildProofBatchPermit: hasChildProofBatchPermit,
    )) {
      return _MigrationProgressState.needsInput;
    }
    final confirming =
        status.phase == kIronwoodMigrationWaitingConfirmationsPhase ||
        status.broadcastedTxCount > 0;
    if (confirming) return _MigrationProgressState.confirming;
    final broadcasting = status.phase == kIronwoodMigrationBroadcastingPhase;
    if (broadcasting) return _MigrationProgressState.broadcasting;
    if (migrationHasDueScheduledBroadcast(
      status,
      currentHeight: _currentHeight(),
    )) {
      return _MigrationProgressState.readyToSubmit;
    }
    return _notificationsAuthorized == true
        ? _MigrationProgressState.waitingNotificationsOn
        : _MigrationProgressState.waitingNotificationsOff;
  }

  bool _requiresUserAction(
    rust_sync.MigrationStatus status, {
    required bool hasChildProofBatchPermit,
  }) {
    if (status.parts.any(
      (part) => part.state == rust_sync.MigrationPartState.needsInput,
    )) {
      return true;
    }
    if (widget.isHardware &&
        status.phase == kIronwoodMigrationReadyToMigratePhase &&
        status.signedChildPcztCount <= 0) {
      return true;
    }
    if (_hasDueProofBatch(status)) return !hasChildProofBatchPermit;
    if (_hasLateScheduledBroadcast(status)) return true;
    if (_hasDueReadyToMigrateProofAction(status)) {
      return !hasChildProofBatchPermit;
    }
    return false;
  }

  /// The `ready_to_migrate` due branch of [_requiresUserAction]: proofs are
  /// already built and the scheduled block has passed, so only the one-shot
  /// child-proof permit stands between the run and its next batch.
  bool _hasDueReadyToMigrateProofAction(rust_sync.MigrationStatus status) {
    if (status.phase != kIronwoodMigrationReadyToMigratePhase) return false;
    final nextHeight = status.nextActionHeight;
    final currentHeight = _currentHeight();
    return status.proofReady == true &&
        nextHeight != null &&
        currentHeight > 0 &&
        nextHeight <= currentHeight;
  }

  bool _hasLateScheduledBroadcast(rust_sync.MigrationStatus status) =>
      _earliestLateScheduledBroadcastHeight(status) != null;

  /// The lowest scheduled block whose broadcast is past its late grace window,
  /// or null when none is late.
  int? _earliestLateScheduledBroadcastHeight(rust_sync.MigrationStatus status) {
    final currentHeight = _currentBroadcastHeight();
    if (currentHeight <= 0) return null;
    int? earliest;
    for (final broadcast in status.scheduledBroadcasts) {
      if (broadcast.status.toLowerCase() != 'scheduled' ||
          broadcast.scheduledHeight <= 0 ||
          currentHeight <
              broadcast.scheduledHeight + kIronwoodMigrationLateGraceBlocks) {
        continue;
      }
      if (earliest == null || broadcast.scheduledHeight < earliest) {
        earliest = broadcast.scheduledHeight;
      }
    }
    return earliest;
  }

  bool _hasDueProofBatch(rust_sync.MigrationStatus status) {
    return migrationHasDueProofBatch(status, currentHeight: _currentHeight());
  }

  String _nextActionText(
    rust_sync.MigrationStatus status, {
    required _MigrationProgressState state,
  }) {
    final currentHeight = _currentHeight();
    final nextHeight = status.nextActionHeight;
    final timing = nextHeight != null && currentHeight > 0
        ? migrationHeightRemainingDurationLabel(
            nextHeight,
            currentHeight: currentHeight,
          ).replaceFirst('~in ', '~')
        : 'Timing is updating';
    if (state == _MigrationProgressState.waitingNotificationsOff) {
      if (nextHeight != null) {
        return 'Notifications are disabled. Open Vizor after block '
            '$nextHeight ($timing) and approve the next migration batch.';
      }
      return 'Notifications are disabled. Open Vizor again when the timing '
          'is available and approve the next migration batch.';
    }
    if (state == _MigrationProgressState.broadcasting) {
      // The broadcasting status view renders this verbatim, so the timing and
      // notification lines are composed once, here.
      final expectation =
          timing == 'Timing is updating' || timing == 'ready now'
          ? 'Next migration step is on the way.'
          : 'Next migration step expected in\n$timing.';
      return switch (_notificationsAuthorized) {
        true =>
          '$expectation\nNotifications are on. You can leave Vizor and check '
              'back later.',
        false =>
          '$expectation\nNotifications are disabled. Open Vizor again to '
              'continue.',
        null => expectation,
      };
    }
    if (state == _MigrationProgressState.readyToSubmit) {
      return 'The scheduled transaction is ready for automatic submission. '
          'Keep Vizor open.';
    }
    if (state == _MigrationProgressState.confirming) {
      return 'Confirmations are still arriving. You can leave Vizor and '
          'check again later.';
    }
    if (timing == 'ready now') {
      return 'The next migration step is ready. Keep Vizor open to continue.';
    }
    return '$timing until the next migration step.\n'
        'Notifications are on; you can leave Vizor and check back later.';
  }

  Future<void> _continuePreparation(String accountUuid) async {
    if (_actionRunning) return;
    setState(() => _actionRunning = true);
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retry(accountUuid);
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Future<void> _retryAfterError(String accountUuid) async {
    if (_actionRunning) return;
    setState(() => _actionRunning = true);
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retry(accountUuid);
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Future<void> _confirmRecovery(String accountUuid) async {
    final appTheme = AppTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppTheme(
        data: appTheme,
        child: const _MobileMigrationRecoveryDialog(),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actionRunning = true);
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .recover(accountUuid);
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  /// Runs the required action for [accountUuid]. Only a tap reaches here.
  Future<void> _performRequiredAction(String accountUuid) async {
    if (_actionRunning) return;
    if (widget.isHardware && _requiresKeystoneSignature(widget.status)) {
      context.push('/migration/private/keystone/batch/sign');
      return;
    }
    setState(() {
      _actionRunning = true;
    });
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retry(accountUuid, status: widget.status);
      if (!mounted) return;
      await ref.read(ironwoodMigrationRouteCtaProvider.future);
    } catch (_) {
      // The coordinator records the error for this screen to render. Avoid an
      // unawaited tap future escaping after the action button returns idle.
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  bool _requiresKeystoneSignature(rust_sync.MigrationStatus status) {
    if (status.parts.any(
      (part) => part.state == rust_sync.MigrationPartState.needsInput,
    )) {
      return true;
    }
    return status.phase == kIronwoodMigrationReadyToMigratePhase &&
        status.signedChildPcztCount <= 0;
  }

  String _requiredActionLabel(
    rust_sync.MigrationStatus status, {
    required int batchNumber,
    required bool hasLateScheduledBroadcast,
    required bool actionInProgress,
  }) {
    if (actionInProgress) {
      return hasLateScheduledBroadcast
          ? 'Submitting scheduled transaction...'
          : 'Preparing batch #$batchNumber...';
    }
    if (hasLateScheduledBroadcast) return 'Submit scheduled transaction';
    if (!widget.isHardware) return 'Prepare batch #$batchNumber';
    if (_requiresKeystoneSignature(status)) {
      final isResigning = status.parts.any(
        (part) => part.state == rust_sync.MigrationPartState.needsInput,
      );
      return isResigning
          ? 'Re-sign migration transactions'
          : 'Sign migration transactions';
    }
    return 'Prepare batch #$batchNumber';
  }

  bool _isInitialKeystoneSigning(rust_sync.MigrationStatus status) {
    return status.phase == kIronwoodMigrationReadyToMigratePhase &&
        status.signedChildPcztCount <= 0 &&
        !status.parts.any(
          (part) => part.state == rust_sync.MigrationPartState.needsInput,
        );
  }

  int _currentHeight() {
    final sync = ref.read(syncProvider).value;
    if (sync == null) return 0;
    return mobileIronwoodSafelyObservedHeight(
      scannedHeight: sync.scannedHeight,
      chainTipHeight: sync.chainTipHeight,
    );
  }

  MigrationNextActionPresentation _nextMigrationPresentation(
    rust_sync.MigrationStatus status, {
    required bool requiresInput,
  }) {
    return migrationNextActionPresentation(
      status: status,
      currentHeight: _currentHeight(),
      requiresInput: requiresInput,
      waitingForAnchor:
          status.phase == kIronwoodMigrationReadyToMigratePhase &&
          status.proofReady == false,
    );
  }

  String _leftToMigrateText(rust_sync.MigrationStatus status) {
    final total = migrationTargetTotal(status);
    final completed = migrationCompletedValue(status);
    final remaining = total > completed ? total - completed : BigInt.zero;
    return '${_compactZec(remaining)} ZEC';
  }

  String _completionEstimateText(rust_sync.MigrationStatus status) {
    return migrationApproximateCompletionTimingLabel(
      status,
      currentHeight: _currentHeight(),
    );
  }

  /// Records that this completed run has been presented, so home stops routing
  /// back here. Deliberately keyed to the screen actually rendering rather than
  /// to the navigation that brought the user here: a launch that dies before
  /// the frame is drawn should still owe the user its result.
  void _recordVisibleAttention(String? accountUuid) {
    final runId = widget.status.activeRunId;
    if (accountUuid == null || runId == null) return;
    final attention = mobileIronwoodMigrationAttention(
      widget.status,
      currentHeight: _currentHeight(),
      broadcastHeight: _currentBroadcastHeight(),
      isHardware: widget.isHardware,
    );
    if (attention == null) return;
    final fingerprint = mobileIronwoodMigrationAttentionFingerprint(
      accountUuid: accountUuid,
      runId: runId,
      status: widget.status,
      attention: attention,
    );
    if (_recordedAttentionFingerprint == fingerprint) return;
    _recordedAttentionFingerprint = fingerprint;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(mobileIronwoodMigrationAttentionSessionProvider.notifier)
          .markSeen(fingerprint);
    });
  }

  int _completedParts(rust_sync.MigrationStatus status) {
    if (status.phase == kIronwoodMigrationReadyToMigratePhase &&
        !migrationHasTransferProgress(status)) {
      return 0;
    }
    if (status.parts.isNotEmpty) {
      return status.parts
          .where((part) => part.state == rust_sync.MigrationPartState.completed)
          .length;
    }
    return status.confirmedTxCount;
  }

  /// Ring segments for parts that are on the network but not yet confirmed.
  ///
  /// Without this they render as untouched track, so a user who just watched
  /// every transfer go out sees an empty ring under a "waiting for
  /// confirmations" line and cannot tell the two states apart.
  Set<int> _awaitingRingSegments(rust_sync.MigrationStatus status) {
    if (status.parts.isEmpty) {
      final confirmed = status.confirmedTxCount.clamp(0, _totalParts(status));
      final broadcast = status.broadcastedTxCount.clamp(0, _totalParts(status));
      return {for (var index = confirmed; index < broadcast; index++) index};
    }
    final stateByPartIndex = {
      for (final part in status.parts) part.partIndex: part.state,
    };
    final partOrder = _migrationRingPartOrder(status);
    return {
      for (
        var displayIndex = 0;
        displayIndex < partOrder.length;
        displayIndex++
      )
        if (_awaitsConfirmation(stateByPartIndex[partOrder[displayIndex]]))
          displayIndex,
    };
  }

  /// Whether a part is on the network but not final yet. Rust reports a
  /// broadcast part as `migrating` until it is mined and `confirming` until it
  /// reaches its confirmation target; both are past the point the user can act
  /// on, so both read the same way on the ring.
  static bool _awaitsConfirmation(rust_sync.MigrationPartState? state) {
    return state == rust_sync.MigrationPartState.migrating ||
        state == rust_sync.MigrationPartState.confirming;
  }

  Set<int> _completedRingSegments(rust_sync.MigrationStatus status) {
    if (status.phase == kIronwoodMigrationReadyToMigratePhase &&
        !migrationHasTransferProgress(status)) {
      return const {};
    }
    if (status.parts.isEmpty) {
      return {
        for (
          var index = 0;
          index < status.confirmedTxCount.clamp(0, _totalParts(status));
          index++
        )
          index,
      };
    }
    final stateByPartIndex = {
      for (final part in status.parts) part.partIndex: part.state,
    };
    final partOrder = _migrationRingPartOrder(status);
    return {
      for (
        var displayIndex = 0;
        displayIndex < partOrder.length;
        displayIndex++
      )
        if (stateByPartIndex[partOrder[displayIndex]] ==
            rust_sync.MigrationPartState.completed)
          displayIndex,
    };
  }

  rust_sync.MigrationPartStatus? _actionPart(rust_sync.MigrationStatus status) {
    final ordered = [...status.parts]
      ..sort((left, right) => left.partIndex.compareTo(right.partIndex));
    for (final part in ordered) {
      if (part.state == rust_sync.MigrationPartState.needsInput) return part;
    }
    final nextActionPartIndex = status.nextActionPartIndex;
    if (_hasDueProofBatch(status) && nextActionPartIndex != null) {
      for (final part in ordered) {
        if (part.partIndex == nextActionPartIndex) return part;
      }
    }
    final currentHeight = _currentHeight();
    if (currentHeight > 0) {
      for (final broadcast in status.scheduledBroadcasts) {
        if (broadcast.status.toLowerCase() != 'scheduled' ||
            broadcast.scheduledHeight <= 0 ||
            currentHeight <
                broadcast.scheduledHeight + kIronwoodMigrationLateGraceBlocks) {
          continue;
        }
        for (final part in ordered) {
          if (part.txidHex?.toLowerCase() == broadcast.txidHex.toLowerCase()) {
            return part;
          }
        }
      }
    }
    if (nextActionPartIndex != null) {
      for (final part in ordered) {
        if (part.partIndex == nextActionPartIndex) return part;
      }
    }
    for (final part in ordered) {
      if (part.state != rust_sync.MigrationPartState.completed) return part;
    }
    return null;
  }

  _MobileMigrationBatchProgress _batchProgress(
    rust_sync.MigrationStatus status, {
    rust_sync.MigrationPartStatus? actionPart,
  }) {
    final totalParts = _totalParts(status);
    final totalBatches = math.max(
      1,
      (totalParts + _migrationPartsPerBatch - 1) ~/ _migrationPartsPerBatch,
    );
    final ordered = [...status.parts]
      ..sort((left, right) => left.partIndex.compareTo(right.partIndex));
    var currentBatchIndex = 0;
    if (actionPart != null) {
      final actionIndex = ordered.indexWhere(
        (part) => part.partIndex == actionPart.partIndex,
      );
      if (actionIndex >= 0) {
        currentBatchIndex = actionIndex ~/ _migrationPartsPerBatch;
      }
    } else {
      final firstIncompleteIndex = ordered.indexWhere(
        (part) => part.state != rust_sync.MigrationPartState.completed,
      );
      if (firstIncompleteIndex >= 0) {
        currentBatchIndex = firstIncompleteIndex ~/ _migrationPartsPerBatch;
      } else if (ordered.isNotEmpty) {
        currentBatchIndex = totalBatches - 1;
      } else {
        currentBatchIndex = (_completedParts(status) ~/ _migrationPartsPerBatch)
            .clamp(0, totalBatches - 1);
      }
    }
    currentBatchIndex = currentBatchIndex.clamp(0, totalBatches - 1);
    final currentBatchStart = currentBatchIndex * _migrationPartsPerBatch;
    final currentBatchParts = ordered
        .skip(currentBatchStart)
        .take(_migrationPartsPerBatch)
        .toList(growable: false);
    final inferredCurrentBatchPartCount = math.min(
      _migrationPartsPerBatch,
      math.max(0, totalParts - currentBatchStart),
    );
    final currentBatchPartCount = currentBatchParts.isEmpty
        ? inferredCurrentBatchPartCount
        : currentBatchParts.length;
    var completedBatches = 0;
    if (ordered.isEmpty) {
      final completedParts = _completedParts(status).clamp(0, totalParts);
      completedBatches = completedParts >= totalParts
          ? totalBatches
          : completedParts ~/ _migrationPartsPerBatch;
    } else {
      for (
        var start = 0;
        start < ordered.length;
        start += _migrationPartsPerBatch
      ) {
        final parts = ordered
            .skip(start)
            .take(_migrationPartsPerBatch)
            .toList(growable: false);
        final expectedCount = math.min(
          _migrationPartsPerBatch,
          totalParts - start,
        );
        if (parts.length == expectedCount &&
            parts.every(
              (part) => part.state == rust_sync.MigrationPartState.completed,
            )) {
          completedBatches++;
        }
      }
    }

    return _MobileMigrationBatchProgress(
      completedBatches: completedBatches.clamp(0, totalBatches),
      totalBatches: totalBatches,
      currentBatchNumber: currentBatchIndex + 1,
      currentBatchStartIndex: currentBatchStart,
      currentBatchPartCount: currentBatchPartCount,
      currentBatchParts: currentBatchParts,
    );
  }

  int _currentBroadcastHeight() {
    final sync = ref.read(syncProvider).value;
    if (sync == null) return 0;
    return mobileIronwoodObservedBroadcastHeight(
      scannedHeight: sync.scannedHeight,
      chainTipHeight: sync.chainTipHeight,
    );
  }

  String _actionBatchValueText(
    rust_sync.MigrationStatus status,
    List<rust_sync.MigrationPartStatus> parts,
  ) {
    final batchValue = parts.fold<BigInt>(
      BigInt.zero,
      (sum, part) => sum + part.valueZatoshi,
    );
    final amount = ZecAmount.fromZatoshi(batchValue).compactBalance.amountText;
    final total = status.parts.fold<BigInt>(
      BigInt.zero,
      (sum, item) => sum + item.valueZatoshi,
    );
    if (total <= BigInt.zero) return '$amount ZEC';
    final percentage =
        ((batchValue * BigInt.from(100)) + (total ~/ BigInt.two)) ~/ total;
    return '$amount ZEC ($percentage%)';
  }

  String _allMigrationActionValueText(rust_sync.MigrationStatus status) {
    final total = status.parts.isNotEmpty
        ? status.parts.fold<BigInt>(
            BigInt.zero,
            (sum, part) => sum + part.valueZatoshi,
          )
        : status.targetValuesZatoshi.fold<BigInt>(
            BigInt.zero,
            (sum, value) => sum + value,
          );
    final amount = ZecAmount.fromZatoshi(total).compactBalance.amountText;
    return '$amount ZEC (100%)';
  }

  String _needsInputActionValueText(rust_sync.MigrationStatus status) {
    final total = status.parts.fold<BigInt>(
      BigInt.zero,
      (sum, part) => sum + part.valueZatoshi,
    );
    final needsInput = status.parts
        .where((part) => part.state == rust_sync.MigrationPartState.needsInput)
        .fold<BigInt>(BigInt.zero, (sum, part) => sum + part.valueZatoshi);
    final amount = ZecAmount.fromZatoshi(needsInput).compactBalance.amountText;
    final percentage = total <= BigInt.zero
        ? 0
        : ((needsInput * BigInt.from(100)) ~/ total).toInt();
    return '$amount ZEC ($percentage%)';
  }

  int _totalParts(rust_sync.MigrationStatus status) {
    return math.max(
      1,
      math.max(
        status.totalCount,
        math.max(status.parts.length, status.targetValuesZatoshi.length),
      ),
    );
  }

  List<int> _migrationRingPartOrder(rust_sync.MigrationStatus status) {
    final totalParts = _totalParts(status);
    final orderedParts = _orderedMobileMigrationParts(status.parts);
    final partIndices = orderedParts.map((part) => part.partIndex).toSet();
    final hasCompletePartOrder =
        orderedParts.length == totalParts &&
        partIndices.length == totalParts &&
        partIndices.every((partIndex) => partIndex < totalParts);
    return hasCompletePartOrder
        ? [for (final part in orderedParts) part.partIndex]
        : List<int>.generate(totalParts, (index) => index);
  }

  Set<int> _currentSigningRingSegments(rust_sync.MigrationStatus status) {
    final signingPartIndices =
        status.currentSigningPartIndices?.toSet() ?? const <int>{};
    final partOrder = _migrationRingPartOrder(status);
    return {
      for (
        var displayIndex = 0;
        displayIndex < partOrder.length;
        displayIndex++
      )
        if (signingPartIndices.contains(partOrder[displayIndex])) displayIndex,
    };
  }

  List<BigInt>? _migrationRingSegmentValues(rust_sync.MigrationStatus status) {
    final totalParts = _totalParts(status);
    final targetValues = status.targetValuesZatoshi;
    final valueByPartIndex = {
      for (final part in status.parts) part.partIndex: part.valueZatoshi,
    };
    final values = <BigInt>[];
    for (final partIndex in _migrationRingPartOrder(status)) {
      final partValue = valueByPartIndex[partIndex];
      if (partValue != null) {
        values.add(partValue);
      } else if (partIndex < targetValues.length) {
        values.add(targetValues[partIndex]);
      } else {
        return null;
      }
    }
    return values.length == totalParts ? values : null;
  }

  String _migratedAmountText(rust_sync.MigrationStatus status) {
    final completed = migrationCompletedValue(status);
    return '${ZecAmount.fromZatoshi(completed).compactBalance.amountText} ZEC';
  }

  String _totalAmountText(rust_sync.MigrationStatus status) {
    return migrationCompletedAmountText(
      status,
      fallbackAmountText: widget.data.amountText,
    );
  }

  String _availableAmountText(String? accountUuid) {
    final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    final amount = sync.hasBalanceData ? sync.ironwoodBalance : BigInt.zero;
    return '${ZecAmount.fromZatoshi(amount).compactBalance.amountText} ZEC';
  }
}
