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
    required this.synchronizeOnEntry,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;
  final bool isHardware;
  final bool synchronizeOnEntry;

  @override
  ConsumerState<_MobileMigrationRedesignedStatus> createState() =>
      _MobileMigrationRedesignedStatusState();
}

class _MobileMigrationRedesignedStatusState
    extends ConsumerState<_MobileMigrationRedesignedStatus> {
  AppLifecycleListener? _lifecycleListener;
  bool _wasBackgrounded = false;
  bool _entrySyncing = false;
  bool _entrySyncStarted = false;
  Object? _entrySyncError;
  bool _notificationsAuthorized = false;
  IronwoodMigrationPreparationRuntimeState _preparationRuntimeState =
      IronwoodMigrationPreparationRuntimeState.idle;
  bool _showPreparationComplete = false;
  bool _actionRunning = false;

  @override
  void initState() {
    super.initState();
    _entrySyncing = widget.synchronizeOnEntry;
    _lifecycleListener = AppLifecycleListener(
      onHide: _markBackgrounded,
      onPause: _markBackgrounded,
      onResume: _resumeIfNeeded,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.synchronizeOnEntry) {
        unawaited(_synchronizeEntry());
      } else {
        unawaited(_initializeCurrentSessionSurface());
      }
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
    super.dispose();
  }

  void _markBackgrounded() {
    _wasBackgrounded = true;
  }

  void _resumeIfNeeded() {
    if (!_wasBackgrounded) return;
    _wasBackgrounded = false;
    unawaited(_synchronizeEntry());
  }

  Future<void> _synchronizeEntry() async {
    if (_entrySyncStarted) return;
    _entrySyncStarted = true;
    if (mounted) {
      setState(() {
        _entrySyncing = true;
        _entrySyncError = null;
      });
    }
    try {
      try {
        await ref
            .read(ironwoodMigrationCoordinatorProvider.notifier)
            .synchronizeAndReconcileAfterReentry();
      } catch (error) {
        if (mounted) setState(() => _entrySyncError = error);
        return;
      }
      try {
        await _refreshNotificationAuthorization();
      } catch (_) {
        // Permission is fail-closed and must not masquerade as a sync failure.
        if (mounted) {
          setState(() => _notificationsAuthorized = false);
        }
      }
      await _reconcilePreparationRuntimeState();
      try {
        await _showPreparationCompleteIfNeeded();
      } catch (_) {
        // The acknowledgement modal is best-effort after a successful sync.
      }
    } finally {
      _entrySyncStarted = false;
      if (mounted) setState(() => _entrySyncing = false);
    }
  }

  Future<void> _initializeCurrentSessionSurface() async {
    try {
      await _refreshNotificationAuthorization();
      await _reconcilePreparationRuntimeState();
      await _showPreparationCompleteIfNeeded();
    } catch (_) {
      // Permission state is fail-closed and the status surface remains usable.
    }
  }

  Future<void> _refreshNotificationAuthorization() async {
    final authorized =
        await ref
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
          () =>
              _preparationRuntimeState =
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
          () =>
              _preparationRuntimeState =
                  !_notificationsAuthorized
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
          () =>
              _preparationRuntimeState =
                  IronwoodMigrationPreparationRuntimeState.idle,
        );
      }
      return;
    }
    if (!mounted) return;
    final retryError =
        ref.read(ironwoodMigrationCoordinatorProvider).errors[accountUuid];
    if (retryError != null) {
      setState(
        () =>
            _preparationRuntimeState =
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
        () =>
            _preparationRuntimeState =
                IronwoodMigrationPreparationRuntimeState.idle,
      );
    }
  }

  Future<void> _showPreparationCompleteIfNeeded() async {
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
    if (mounted) setState(() => _showPreparationComplete = false);
  }

  @override
  Widget build(BuildContext context) {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    final coordinatorError =
        accountUuid == null ? null : coordinator.errors[accountUuid];
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

    if (_entrySyncing) {
      if (widget.status.phase ==
          kIronwoodMigrationWaitingDenomConfirmationsPhase) {
        return _MigrationPreparationPreview(
          state: _MigrationPreparationState.syncing,
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

    if (_entrySyncError != null) {
      return _MigrationEntrySyncError(
        onBack: () => context.go('/home'),
        onRetry: () => unawaited(_synchronizeEntry()),
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
        statusValueOverride:
            needsHardwareCredentialAttention
                ? 'Keystone account required'
                : null,
        actionMessage:
            needsHardwareCredentialAttention
                ? 'Reconnect or re-import your Keystone account to continue this '
                    'migration.'
                : null,
        actionLabel:
            needsHardwareCredentialAttention
                ? 'Back to home'
                : needsSoftwareCredentialRecovery
                ? recoveryInProgress
                    ? 'Recovering...'
                    : 'Recover'
                : _actionRunning
                ? 'Retrying...'
                : 'Retry',
        onAction:
            accountUuid == null || recoveryInProgress || _actionRunning
                ? null
                : needsHardwareCredentialAttention
                ? () => context.go('/home')
                : needsSoftwareCredentialRecovery
                ? () => unawaited(_confirmRecovery(accountUuid))
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
        state:
            needsManualResume
                ? _MigrationPreparationState.paused
                : _MigrationPreparationState.active,
        isKeystone: widget.isHardware,
        onBack: () => context.go('/home'),
        onContinue:
            !needsManualResume || accountUuid == null
                ? null
                : () => unawaited(_continuePreparation(accountUuid)),
      );
    }

    if (widget.status.phase == kIronwoodMigrationCompletePhase) {
      return _MigrationCompletePreview(
        amountText: _totalAmountText(widget.status),
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
    final hasLateScheduledBroadcast = _hasLateScheduledBroadcast(widget.status);
    final batchNumber = batchProgress.currentBatchNumber;
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
      migratedAmountText: _migratedAmountText(widget.status),
      totalAmountText: _totalAmountText(widget.status),
      availableAmountText: _availableAmountText(accountUuid),
      nextActionText: nextActionText,
      actionLabel:
          hasLateScheduledBroadcast
              ? 'Retry broadcast'
              : 'Sign batch #$batchNumber',
      actionBatchLabel: 'Batch #$batchNumber',
      actionBatchValue:
          batchProgress.currentBatchParts.isEmpty
              ? null
              : _actionBatchValueText(
                widget.status,
                batchProgress.currentBatchParts,
              ),
      onAction:
          accountUuid == null || _actionRunning
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
    if (_hasLateScheduledBroadcast(status)) return true;
    final nextHeight = status.nextActionHeight;
    if (nextHeight != null && currentHeight > 0 && nextHeight > currentHeight) {
      return false;
    }
    if (status.phase == kIronwoodMigrationReadyToMigratePhase) {
      return !hasChildProofBatchPermit;
    }
    return status.phase == kIronwoodMigrationBroadcastScheduledPhase &&
        status.signedChildPcztCount > 0 &&
        nextHeight != null &&
        currentHeight > 0 &&
        nextHeight <= currentHeight &&
        !hasChildProofBatchPermit;
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

  String _nextActionText(
    rust_sync.MigrationStatus status, {
    required _MigrationProgressState state,
  }) {
    final currentHeight = _currentHeight();
    final nextHeight = status.nextActionHeight;
    final timing =
        nextHeight != null && currentHeight > 0
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
      builder:
          (_) => AppTheme(
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
    final nextActionPartIndex = status.nextActionPartIndex;
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
    final currentBatchPartCount =
        currentBatchParts.isEmpty
            ? inferredCurrentBatchPartCount
            : currentBatchParts.length;
    final completedCurrentBatchParts =
        currentBatchParts.isEmpty
            ? (_completedParts(status) - currentBatchStart).clamp(
              0,
              currentBatchPartCount,
            )
            : currentBatchParts
                .where(
                  (part) =>
                      part.state == rust_sync.MigrationPartState.completed,
                )
                .length;

    var completedBatches = 0;
    if (ordered.isEmpty) {
      final completedParts = _completedParts(status).clamp(0, totalParts);
      completedBatches =
          completedParts >= totalParts
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
    final completed =
        status.parts.isNotEmpty
            ? status.parts
                .where(
                  (part) =>
                      part.state == rust_sync.MigrationPartState.completed,
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
    final total =
        status.parts.isNotEmpty
            ? status.parts.fold<BigInt>(
              BigInt.zero,
              (sum, part) => sum + part.valueZatoshi,
            )
            : status.targetValuesZatoshi.fold<BigInt>(
              BigInt.zero,
              (sum, value) => sum + value,
            );
    final fallback =
        total > BigInt.zero
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

class _MigrationEntrySyncError extends StatelessWidget {
  const _MigrationEntrySyncError({required this.onBack, required this.onRetry});

  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _MigrationPreviewPage(
      navTitle: 'Migration in progress…',
      onBack: onBack,
      bottom: AppButton(
        key: const ValueKey('mobile_ironwood_migration_sync_retry'),
        variant: AppButtonVariant.primary,
        expand: true,
        height: 50,
        onPressed: onRetry,
        child: const Text('Retry sync'),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.warning,
              size: 40,
              color: context.colors.icon.warning,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Couldn't update migration",
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              "Vizor couldn't sync the latest confirmations. Try again before "
              'continuing.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
