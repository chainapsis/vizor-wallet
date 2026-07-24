part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationBatchProgress {
  const _MobileMigrationBatchProgress({
    required this.completedBatches,
    required this.totalBatches,
    required this.currentBatchNumber,
    required this.currentBatchPartCount,
    required this.completedCurrentBatchParts,
    required this.currentBatchParts,
  });

  final int completedBatches;
  final int totalBatches;
  final int currentBatchNumber;
  final int currentBatchPartCount;
  final int completedCurrentBatchParts;
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

  AppLifecycleListener? _lifecycleListener;
  Timer? _syncSurfaceRevealTimer;
  Timer? _syncSurfaceMinimumTimer;
  bool _syncSurfaceMinimumElapsed = false;
  bool _wasBackgrounded = false;
  bool _surfaceRefreshInProgress = false;
  bool _surfaceRefreshRequested = false;
  bool _showSyncSurface = false;
  bool _notificationsAuthorized = false;
  IronwoodMigrationPreparationRuntimeState _preparationRuntimeState =
      IronwoodMigrationPreparationRuntimeState.idle;
  bool _showPreparationComplete = false;
  bool _actionRunning = false;

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
      unawaited(_initializeCurrentSessionSurface());
    });
  }

  @override
  void didUpdateWidget(covariant _MobileMigrationRedesignedStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final completedPreparation =
        oldWidget.status.phase ==
            kIronwoodMigrationWaitingDenomConfirmationsPhase &&
        widget.status.phase != kIronwoodMigrationWaitingDenomConfirmationsPhase;
    if (completedPreparation) {
      unawaited(_showPreparationCompleteIfNeeded());
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _syncSurfaceRevealTimer?.cancel();
    _syncSurfaceMinimumTimer?.cancel();
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
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();
      if (!mounted) return;
      try {
        await _refreshNotificationAuthorization();
      } catch (_) {
        if (mounted) {
          setState(() => _notificationsAuthorized = false);
        }
      }
      await _reconcilePreparationRuntimeState();
      if (!(ref.read(syncProvider).value?.isSyncing ?? false)) {
        await _showPreparationCompleteIfNeeded();
      }
    } catch (_) {
      // The status surface remains usable when runtime inspection fails.
    } finally {
      _surfaceRefreshInProgress = false;
      if (_surfaceRefreshRequested && mounted) {
        unawaited(_initializeCurrentSessionSurface());
      }
    }
  }

  void _handleSyncActivity(bool isSyncing) {
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

  Future<void> _refreshNotificationAuthorization() async {
    final authorized = await ref
        .read(ironwoodMigrationServiceProvider)
        .notificationAuthorizationStatus();
    if (!mounted) return;
    setState(
      () => _notificationsAuthorized = authorized.allowsBackgroundMigration,
    );
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
    if (accountUuid == null || runId == null || !_notificationsAuthorized) {
      if (mounted) {
        setState(
          () => _preparationRuntimeState = !_notificationsAuthorized
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
    if (!mounted) return;
    final retryError = ref
        .read(ironwoodMigrationCoordinatorProvider)
        .errors[accountUuid];
    if (retryError != null) {
      setState(
        () => _preparationRuntimeState =
            IronwoodMigrationPreparationRuntimeState.idle,
      );
      return;
    }
    try {
      await service.acknowledgePreparationContinuation(
        accountUuid: accountUuid,
        runId: runId,
      );
    } catch (_) {
      // The foreground permit already owns this session. A later entry can
      // safely retry acknowledgement if the native handoff token remains.
    }
    if (mounted) {
      setState(
        () => _preparationRuntimeState =
            IronwoodMigrationPreparationRuntimeState.idle,
      );
    }
  }

  Future<void> _showPreparationCompleteIfNeeded() async {
    if (ref.read(syncProvider).value?.isSyncing ?? false) return;
    final status = widget.status;
    final runId = status.activeRunId;
    if (runId == null ||
        status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase ||
        status.phase == kIronwoodMigrationCompletePhase) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = 'zcash_ironwood_migration_preparation_complete_seen_$runId';
    if (prefs.getBool(key) ?? false) return;
    if (!mounted) return;
    setState(() => _showPreparationComplete = true);
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
    ref.listen(syncProvider, (previous, next) {
      final wasSyncing = previous?.value?.isSyncing ?? false;
      final isSyncing = next.value?.isSyncing ?? false;
      _handleSyncActivity(isSyncing);
      if (wasSyncing && !isSyncing) {
        unawaited(_initializeCurrentSessionSurface());
      }
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

    if (_showSyncSurface && !_showPreparationComplete) {
      if (widget.status.phase ==
          kIronwoodMigrationWaitingDenomConfirmationsPhase) {
        return _MigrationPreparationPreview(
          state: _MigrationPreparationState.syncing,
          progress: _preparationProgress(widget.status),
          onBack: () => context.go('/home'),
        );
      }
      return _MigrationProgressPreview(
        state: _MigrationProgressState.syncing,
        onBack: () => context.go('/home'),
        completedParts: _completedParts(widget.status),
        totalParts: _totalParts(widget.status),
        migratedAmountText: _migratedAmountText(widget.status),
        totalAmountText: _totalAmountText(widget.status),
        availableAmountText: _availableAmountText(accountUuid),
      );
    }

    if (coordinatorError != null &&
        widget.status.phase ==
            kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return _MigrationPreparationPreview(
        state: _MigrationPreparationState.paused,
        progress: _preparationProgress(widget.status),
        isKeystone: widget.isHardware,
        onBack: () => context.go('/home'),
        onContinue: accountUuid == null || _actionRunning
            ? null
            : () => unawaited(_continuePreparation(accountUuid)),
      );
    }

    if (coordinatorError != null) {
      final batchProgress = _batchProgress(widget.status);
      return _MigrationProgressPreview(
        state: _MigrationProgressState.needsInput,
        onBack: () => context.go('/home'),
        completedParts: _completedParts(widget.status),
        totalParts: _totalParts(widget.status),
        completedBatches: batchProgress.completedBatches,
        totalBatches: batchProgress.totalBatches,
        currentBatchPartCount: batchProgress.currentBatchPartCount,
        completedCurrentBatchParts: batchProgress.completedCurrentBatchParts,
        migratedAmountText: _migratedAmountText(widget.status),
        totalAmountText: _totalAmountText(widget.status),
        availableAmountText: _availableAmountText(accountUuid),
        statusValueOverride: needsHardwareCredentialAttention
            ? 'Keystone account required'
            : null,
        actionMessage: needsHardwareCredentialAttention
            ? 'Reconnect or re-import your Keystone account to continue this '
                  'migration.'
            : null,
        actionLabel: needsHardwareCredentialAttention
            ? 'Back to home'
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
        completedParts: _completedParts(widget.status),
        totalParts: _totalParts(widget.status),
        completedBatches: batchProgress.completedBatches,
        totalBatches: batchProgress.totalBatches,
        currentBatchPartCount: batchProgress.currentBatchPartCount,
        completedCurrentBatchParts: batchProgress.completedCurrentBatchParts,
        migratedAmountText: _migratedAmountText(widget.status),
        totalAmountText: _totalAmountText(widget.status),
        availableAmountText: _availableAmountText(accountUuid),
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
      return _MigrationPreparationPreview(
        state: needsManualResume
            ? _MigrationPreparationState.paused
            : _MigrationPreparationState.active,
        progress: _preparationProgress(widget.status),
        isKeystone: widget.isHardware,
        onBack: () => context.go('/home'),
        onContinue: !needsManualResume || accountUuid == null
            ? null
            : () => unawaited(_continuePreparation(accountUuid)),
      );
    }

    if (widget.status.phase == kIronwoodMigrationCompletePhase) {
      return _MigrationCompletePreview(
        amountText: _totalAmountText(widget.status),
        onDone: accountUuid == null || _actionRunning
            ? null
            : () => unawaited(_finishCompletedMigration(accountUuid)),
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
      completedParts: _completedParts(widget.status),
      totalParts: _totalParts(widget.status),
      completedBatches: batchProgress.completedBatches,
      totalBatches: batchProgress.totalBatches,
      currentBatchPartCount: batchProgress.currentBatchPartCount,
      completedCurrentBatchParts: batchProgress.completedCurrentBatchParts,
      highlightCurrentBatch:
          !signingAllKeystoneTransactions && !resigningKeystoneTransactions,
      migratedAmountText: _migratedAmountText(widget.status),
      totalAmountText: _totalAmountText(widget.status),
      availableAmountText: _availableAmountText(accountUuid),
      nextActionText: nextActionText,
      actionLabel: _requiredActionLabel(
        widget.status,
        batchNumber: batchNumber,
        hasLateScheduledBroadcast: hasLateScheduledBroadcast,
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
        status.broadcastedTxCount > status.confirmedTxCount;
    if (confirming) return _MigrationProgressState.confirming;
    final broadcasting = status.phase == kIronwoodMigrationBroadcastingPhase;
    if (broadcasting) return _MigrationProgressState.broadcasting;
    return _notificationsAuthorized
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
    final currentHeight = _currentHeight();
    if (_hasDueProofBatch(status)) return !hasChildProofBatchPermit;
    if (_hasLateScheduledBroadcast(status)) return true;
    final nextHeight = status.nextActionHeight;
    if (nextHeight != null && currentHeight > 0 && nextHeight > currentHeight) {
      return false;
    }
    if (status.phase == kIronwoodMigrationReadyToMigratePhase) {
      return !hasChildProofBatchPermit;
    }
    return false;
  }

  bool _hasLateScheduledBroadcast(rust_sync.MigrationStatus status) {
    final currentHeight = _currentHeight();
    return currentHeight > 0 &&
        status.scheduledBroadcasts.any(
          (broadcast) =>
              broadcast.status.toLowerCase() == 'scheduled' &&
              broadcast.scheduledHeight > 0 &&
              currentHeight >=
                  broadcast.scheduledHeight + kIronwoodMigrationLateGraceBlocks,
        );
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
      if (_notificationsAuthorized) {
        return '$timing.\nWe will notify you when it’s ready.';
      }
      return '$timing until the next migration step. Open Vizor again to '
          'continue because notifications are disabled.';
    }
    if (state == _MigrationProgressState.confirming) {
      return 'Confirmations are still arriving. You can leave Vizor and '
          'check again later.';
    }
    return '$timing.\nWe will notify you when it’s ready.';
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

  Future<void> _performRequiredAction(String accountUuid) async {
    if (_actionRunning) return;
    if (widget.isHardware && _requiresKeystoneSignature(widget.status)) {
      context.push('/migration/private/keystone/batch/sign');
      return;
    }
    setState(() => _actionRunning = true);
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retry(accountUuid);
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
  }) {
    if (hasLateScheduledBroadcast) return 'Retry broadcast';
    if (!widget.isHardware) return 'Sign batch #$batchNumber';
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

  Future<void> _finishCompletedMigration(String accountUuid) async {
    if (_actionRunning) return;
    setState(() => _actionRunning = true);
    try {
      final inputs = ref.read(ironwoodMigrationInputsProvider);
      await ref
          .read(ironwoodMigrationCompletionStoreProvider)
          .markSeen(
            network: inputs.network,
            accountUuid: accountUuid,
            completionId: ironwoodMigrationCompletionId(widget.status),
          );
      ref.invalidate(ironwoodMigrationCompletionProvider);
    } catch (_) {
      // If acknowledgement persistence fails, the existing Home receipt remains
      // visible so the user does not lose the completion confirmation.
    } finally {
      if (mounted) context.go('/home');
    }
  }

  int _currentHeight() {
    final sync = ref.read(syncProvider).value;
    if (sync == null) return 0;
    if (sync.scannedHeight > 0 && sync.chainTipHeight > 0) {
      return math.min(sync.scannedHeight, sync.chainTipHeight);
    }
    return math.max(sync.scannedHeight, sync.chainTipHeight);
  }

  int _completedParts(rust_sync.MigrationStatus status) {
    if (status.parts.isNotEmpty) {
      return status.parts
          .where((part) => part.state == rust_sync.MigrationPartState.completed)
          .length;
    }
    return status.confirmedTxCount;
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
    final completedCurrentBatchParts = currentBatchParts.isEmpty
        ? (_completedParts(status) - currentBatchStart).clamp(
            0,
            currentBatchPartCount,
          )
        : currentBatchParts
              .where(
                (part) => part.state == rust_sync.MigrationPartState.completed,
              )
              .length;

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
      currentBatchPartCount: currentBatchPartCount,
      completedCurrentBatchParts: completedCurrentBatchParts,
      currentBatchParts: currentBatchParts,
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

  double _preparationProgress(rust_sync.MigrationStatus status) {
    final totalStages = status.denominationSplitTotalCount;
    if (totalStages <= 0) return 0;
    final completedStages = status.denominationSplitCompletedCount.clamp(
      0,
      totalStages,
    );
    final confirmationTarget = status.denominationConfirmationTarget;
    final currentStageProgress = confirmationTarget <= 0
        ? 0.0
        : status.denominationConfirmationCount.clamp(0, confirmationTarget) /
              confirmationTarget;
    return ((completedStages + currentStageProgress) / totalStages)
        .clamp(0.0, 1.0)
        .toDouble();
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

  String _migratedAmountText(rust_sync.MigrationStatus status) {
    final completed = status.parts.isNotEmpty
        ? status.parts
              .where(
                (part) => part.state == rust_sync.MigrationPartState.completed,
              )
              .fold<BigInt>(
                BigInt.zero,
                (total, part) => total + part.valueZatoshi,
              )
        : status.targetValuesZatoshi
              .take(status.confirmedTxCount)
              .fold<BigInt>(BigInt.zero, (total, value) => total + value);
    return '${ZecAmount.fromZatoshi(completed).compactBalance.amountText} ZEC';
  }

  String _totalAmountText(rust_sync.MigrationStatus status) {
    final total = status.parts.isNotEmpty
        ? status.parts.fold<BigInt>(
            BigInt.zero,
            (sum, part) => sum + part.valueZatoshi,
          )
        : status.targetValuesZatoshi.fold<BigInt>(
            BigInt.zero,
            (sum, value) => sum + value,
          );
    final fallback = total > BigInt.zero
        ? ZecAmount.fromZatoshi(total).compactBalance.amountText
        : widget.data.amountText;
    return '$fallback ZEC';
  }

  String _availableAmountText(String? accountUuid) {
    final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    final amount = sync.hasBalanceData ? sync.ironwoodBalance : BigInt.zero;
    return '${ZecAmount.fromZatoshi(amount).compactBalance.amountText} ZEC';
  }
}
