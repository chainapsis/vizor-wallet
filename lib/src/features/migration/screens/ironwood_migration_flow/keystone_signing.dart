part of '../ironwood_migration_flow_screen.dart';

class IronwoodMigrationKeystoneDenominationSignScreen extends StatelessWidget {
  const IronwoodMigrationKeystoneDenominationSignScreen({
    this.approvedSchedule = const [],
    super.key,
  });

  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.denominations,
      approvedSchedule: approvedSchedule,
    );
  }
}

class IronwoodMigrationKeystoneBatchSignScreen extends StatelessWidget {
  const IronwoodMigrationKeystoneBatchSignScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.batch,
      approvedSchedule: [],
    );
  }
}

class MobileIronwoodMigrationKeystoneDenominationSignScreen
    extends StatelessWidget {
  const MobileIronwoodMigrationKeystoneDenominationSignScreen({
    this.approvedSchedule = const [],
    this.previewRequest,
    this.previewUrParts = const [],
    super.key,
  });

  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;
  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.denominations,
      approvedSchedule: approvedSchedule,
      mobileLayout: true,
      previewRequest: previewRequest,
      previewUrParts: previewUrParts,
    );
  }
}

class MobileIronwoodMigrationKeystoneBatchSignScreen extends StatelessWidget {
  const MobileIronwoodMigrationKeystoneBatchSignScreen({
    this.previewRequest,
    this.previewUrParts = const [],
    super.key,
  });

  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.batch,
      approvedSchedule: const [],
      mobileLayout: true,
      previewRequest: previewRequest,
      previewUrParts: previewUrParts,
    );
  }
}

class _IronwoodMigrationKeystonePrivateSignScreen
    extends ConsumerStatefulWidget {
  const _IronwoodMigrationKeystonePrivateSignScreen({
    required this.step,
    required this.approvedSchedule,
    this.mobileLayout = false,
    this.previewRequest,
    this.previewUrParts = const [],
  });

  final _KeystonePrivateSignStep step;
  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;
  final bool mobileLayout;
  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;

  @override
  ConsumerState<_IronwoodMigrationKeystonePrivateSignScreen> createState() =>
      _IronwoodMigrationKeystonePrivateSignScreenState();
}

enum _KeystonePrivateSignStep { denominations, batch }

class MobileIronwoodKeystoneScanHelpBody extends StatelessWidget {
  const MobileIronwoodKeystoneScanHelpBody({
    required this.onConfirm,
    super.key,
  });

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: Image.asset(
            'assets/illustrations/keystone_qr_scan_error.png',
            width: 48,
            height: 48,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 255),
            child: Text(
              'Having issues with scanning the QR code?',
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'There may be a newer version of Keystone Cypherpunk firmware '
          'available. Check if you have the latest version.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        AppButton(
          expand: true,
          height: 50,
          onPressed: onConfirm,
          child: const Text('Ok, I will check'),
        ),
      ],
    );
  }
}

extension _KeystonePrivateSignStepCopy on _KeystonePrivateSignStep {
  String get logName => switch (this) {
    _KeystonePrivateSignStep.denominations => 'denominations',
    _KeystonePrivateSignStep.batch => 'batch',
  };

  String get toolbarLabel => switch (this) {
    _KeystonePrivateSignStep.denominations => 'Review migration',
    _KeystonePrivateSignStep.batch => 'Migration status',
  };

  String get previousRoute => switch (this) {
    _KeystonePrivateSignStep.denominations => '/migration/private/review',
    _KeystonePrivateSignStep.batch => '/migration/private/status',
  };

  String get previousButtonLabel => switch (this) {
    _KeystonePrivateSignStep.denominations => 'Back to review',
    _KeystonePrivateSignStep.batch => 'Back to status',
  };

  String get qrTitle => switch (this) {
    _KeystonePrivateSignStep.denominations => 'Sign private split',
    _KeystonePrivateSignStep.batch => 'Sign Ironwood batch',
  };

  String get qrBody => switch (this) {
    _KeystonePrivateSignStep.denominations =>
      'Scan this QR code with Keystone to sign the private split transactions.',
    _KeystonePrivateSignStep.batch =>
      'Scan this QR code with Keystone to sign the Ironwood migration batch.',
  };

  String get messageUnit => switch (this) {
    _KeystonePrivateSignStep.denominations => 'split transaction',
    _KeystonePrivateSignStep.batch => 'migration transaction',
  };

  Future<rust_sync.KeystoneMigrationSigningRequest> prepare(
    IronwoodMigrationService service, {
    required String accountUuid,
  }) {
    return switch (this) {
      _KeystonePrivateSignStep.denominations =>
        service.prepareKeystoneDenominationPrivateMigration(
          accountUuid: accountUuid,
        ),
      _KeystonePrivateSignStep.batch =>
        service.prepareKeystoneBatchPrivateMigration(accountUuid: accountUuid),
    };
  }

  Future<rust_sync.IronwoodMigrationResult> complete(
    IronwoodMigrationService service, {
    required String accountUuid,
    required String requestId,
    required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) {
    return switch (this) {
      _KeystonePrivateSignStep.denominations =>
        service.completeKeystoneDenominationPrivateMigration(
          accountUuid: accountUuid,
          requestId: requestId,
          signedMessages: signedMessages,
          approvedSchedule: approvedSchedule,
        ),
      _KeystonePrivateSignStep.batch =>
        service.completeKeystoneBatchPrivateMigration(
          accountUuid: accountUuid,
          requestId: requestId,
          signedMessages: signedMessages,
        ),
    };
  }
}

enum _KeystoneDenominationSignStage {
  preparing,
  showQr,
  scanning,
  waitingForProofs,
  completing,
  failed,
}

class _IronwoodMigrationKeystonePrivateSignScreenState
    extends ConsumerState<_IronwoodMigrationKeystonePrivateSignScreen> {
  _KeystoneDenominationSignStage _stage =
      _KeystoneDenominationSignStage.preparing;
  late final IronwoodMigrationService _migrationService;
  rust_sync.KeystoneMigrationSigningRequest? _request;
  String? _accountUuid;
  List<String> _urParts = const [];
  String? _error;
  Timer? _proofPollTimer;
  rust_sync.KeystoneMigrationProofStatus? _proofStatus;
  List<rust_sync.KeystoneSignedMigrationMessage>? _pendingSignedMessages;
  KeystoneQrScannerControls? _scannerControls;
  bool _decoding = false;
  bool _requestCompleted = false;

  @override
  void initState() {
    super.initState();
    _migrationService = ref.read(ironwoodMigrationServiceProvider);
    final previewRequest = widget.previewRequest;
    if (previewRequest != null) {
      _request = previewRequest;
      _accountUuid = 'preview-account';
      _urParts = widget.previewUrParts;
      _stage = _KeystoneDenominationSignStage.showQr;
      _requestCompleted = true;
      return;
    }
    unawaited(_prepareRequest());
  }

  @override
  void dispose() {
    _stopProofPolling();
    if (!_requestCompleted) {
      final requestId = _request?.requestId;
      final accountUuid = _accountUuid;
      if (requestId != null && accountUuid != null) {
        unawaited(_discardRequest(accountUuid, requestId));
      }
    }
    super.dispose();
  }

  Future<void> _prepareRequest() async {
    _stopProofPolling();
    setState(() {
      _stage = _KeystoneDenominationSignStage.preparing;
      _request = null;
      _accountUuid = null;
      _urParts = const [];
      _error = null;
      _proofStatus = null;
      _pendingSignedMessages = null;
      _scannerControls = null;
      _decoding = false;
    });

    String? requestIdToDiscard;
    String? requestAccountUuid;
    try {
      final accountState = await ref.read(accountProvider.future);
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      final activeAccount = accountState.activeAccount;
      if (activeAccount == null || !activeAccount.isHardware) {
        throw StateError('Active account is not a Keystone account.');
      }
      requestAccountUuid = accountUuid;

      final request = await widget.step.prepare(
        _migrationService,
        accountUuid: accountUuid,
      );
      requestIdToDiscard = request.requestId;
      if (!mounted) {
        await _discardRequest(accountUuid, request.requestId);
        return;
      }
      if (request.messages.isEmpty) {
        throw StateError('Keystone migration request has no messages.');
      }
      _request = request;
      _accountUuid = accountUuid;
      _startProofPolling(request.requestId);

      final urParts = await rust_keystone.encodeZcashSignBatchUrParts(
        requestId: request.requestId,
        messages: request.messages
            .map(
              (message) => rust_keystone_wallet.ZcashBatchMessageInput(
                id: message.id,
                pcztBytes: message.redactedPczt,
              ),
            )
            .toList(),
        maxFragmentLen: BigInt.from(140),
      );
      if (!mounted) return;
      setState(() {
        _stage = _KeystoneDenominationSignStage.showQr;
        _urParts = urParts;
      });
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'prepare error: $e\n$st',
      );
      _stopProofPolling();
      final requestId = _request?.requestId ?? requestIdToDiscard;
      _request = null;
      _accountUuid = null;
      _proofStatus = null;
      _pendingSignedMessages = null;
      if (requestId != null && requestAccountUuid != null) {
        unawaited(_discardRequest(requestAccountUuid, requestId));
      }
      if (!mounted) return;
      setState(() {
        _stage = _KeystoneDenominationSignStage.failed;
        _error = _keystoneMigrationSigningErrorMessage(e);
      });
    }
  }

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding ||
        _stage != _KeystoneDenominationSignStage.scanning ||
        _pendingSignedMessages != null) {
      return;
    }
    final request = _request;
    final accountUuid = _accountUuid;
    if (request == null || accountUuid == null) return;

    setState(() {
      _decoding = true;
      _stage = _KeystoneDenominationSignStage.completing;
      _error = null;
    });

    try {
      final decoded = await rust_keystone.decodeZcashBatchSignResponse(
        cbor: result.data,
        expectedRequestId: request.requestId,
        messageIds: request.messages.map((message) => message.id).toList(),
      );
      final signedMessages = _signedMigrationMessagesFor(request, decoded);
      final proofStatus = _proofStatus;
      if (ironwoodMigrationKeystoneProofFailed(proofStatus)) {
        if (!mounted) return;
        setState(() {
          _stage = _KeystoneDenominationSignStage.scanning;
          _decoding = false;
          _error = ironwoodMigrationKeystoneProofFailureMessage(proofStatus);
        });
        return;
      }
      if (ironwoodMigrationKeystoneProofShouldWait(proofStatus)) {
        if (!mounted) return;
        setState(() {
          _stage = _KeystoneDenominationSignStage.waitingForProofs;
          _pendingSignedMessages = signedMessages;
          _decoding = false;
          _error = ironwoodMigrationKeystoneProofWaitingMessage(proofStatus);
        });
        return;
      }

      await _completeSignedMessages(signedMessages);
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'complete error: $e\n$st',
      );
      if (!mounted) return;
      setState(() {
        _stage = _KeystoneDenominationSignStage.scanning;
        _decoding = false;
        _error = _keystoneMigrationSigningErrorMessage(e);
      });
    }
  }

  void _startProofPolling(String requestId) {
    _stopProofPolling();
    _proofPollTimer = Timer.periodic(
      _keystoneMigrationProofPollInterval,
      (_) => unawaited(_refreshProofStatus(requestId)),
    );
    unawaited(_refreshProofStatus(requestId));
  }

  Future<void> _refreshProofStatus(String requestId) async {
    try {
      final status = await _migrationService.keystoneProofStatus(
        requestId: requestId,
      );
      if (!mounted || _requestCompleted || _request?.requestId != requestId) {
        return;
      }

      final pendingSignedMessages = _pendingSignedMessages;
      if (status.isReady || status.isFailed) {
        _stopProofPolling();
      }

      setState(() {
        _proofStatus = status;
        if (status.isFailed) {
          _pendingSignedMessages = null;
          _error = ironwoodMigrationKeystoneProofFailureMessage(status);
          if (_stage == _KeystoneDenominationSignStage.waitingForProofs) {
            _stage = _KeystoneDenominationSignStage.scanning;
          }
        } else if (_stage == _KeystoneDenominationSignStage.waitingForProofs) {
          _error = status.isReady
              ? null
              : ironwoodMigrationKeystoneProofWaitingMessage(status);
        }
      });

      if (status.isReady &&
          pendingSignedMessages != null &&
          !_decoding &&
          !_requestCompleted) {
        unawaited(_completeSignedMessages(pendingSignedMessages));
      }
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'proof status error: $e\n$st',
      );
      if (!mounted || _requestCompleted || _request?.requestId != requestId) {
        return;
      }
      setState(() {
        _error = _keystoneMigrationSigningErrorMessage(e);
      });
    }
  }

  Future<void> _completeSignedMessages(
    List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  ) async {
    final request = _request;
    final accountUuid = _accountUuid;
    if (request == null || accountUuid == null || _requestCompleted) return;

    setState(() {
      _stage = _KeystoneDenominationSignStage.completing;
      _decoding = true;
      _error = null;
    });

    try {
      await widget.step.complete(
        _migrationService,
        accountUuid: accountUuid,
        requestId: request.requestId,
        signedMessages: signedMessages,
        approvedSchedule: widget.approvedSchedule,
      );
      if (!mounted) return;
      ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .grantChildProofBatchPermit(accountUuid);
      _stopProofPolling();
      _requestCompleted = true;
      _pendingSignedMessages = null;
      _invalidateIronwoodMigrationStatusState(
        ref,
        statusRequest: IronwoodMigrationStatusRequest(
          network: ref.read(ironwoodMigrationInputsProvider).network,
          accountUuid: accountUuid,
        ),
      );
      context.go(
        '/migration/private/status',
        extra: const MobileIronwoodMigrationStatusEntry(
          synchronizeOnEntry: false,
        ),
      );
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'complete error: $e\n$st',
      );
      if (!mounted) return;
      if (_keystoneMigrationProofStillPendingError(e)) {
        _pendingSignedMessages = signedMessages;
        _startProofPolling(request.requestId);
        setState(() {
          _stage = _KeystoneDenominationSignStage.waitingForProofs;
          _decoding = false;
          _error = ironwoodMigrationKeystoneProofWaitingMessage(_proofStatus);
        });
        return;
      }
      setState(() {
        _stage = _KeystoneDenominationSignStage.scanning;
        _pendingSignedMessages = null;
        _decoding = false;
        _error = _keystoneMigrationSigningErrorMessage(e);
      });
    }
  }

  Future<void> _discardRequest(String accountUuid, String requestId) async {
    try {
      await _migrationService.discardKeystonePrivateMigrationRequest(
        accountUuid: accountUuid,
        requestId: requestId,
      );
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'discard error: $e\n$st',
      );
    }
  }

  Future<void> _returnToReview() async {
    if (_stage == _KeystoneDenominationSignStage.completing) return;
    final requestId = _request?.requestId;
    final accountUuid = _accountUuid;
    _stopProofPolling();
    _request = null;
    if (requestId != null && accountUuid != null) {
      await _discardRequest(accountUuid, requestId);
    }
    if (!mounted) return;
    context.go(widget.step.previousRoute);
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = ironwoodMigrationKeystoneScanErrorMessage(error);
    if (_error == message) return;
    setState(() {
      _error = message;
    });
  }

  void _stopProofPolling() {
    _proofPollTimer?.cancel();
    _proofPollTimer = null;
  }

  String? get _proofStatusText {
    final status = _proofStatus;
    if (status == null) return null;
    if (status.isFailed) {
      return ironwoodMigrationKeystoneProofFailureMessage(status);
    }
    if (status.isReady) return 'Local proofs ready';
    if (status.totalCount > 0) {
      return 'Preparing local proofs ${status.readyCount}/${status.totalCount}';
    }
    return 'Preparing local proofs';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobileLayout) return _buildMobileScreen(context);

    return _IronwoodMigrationFrame(
      toolbar: _keystoneDenominationToolbar(
        label: widget.step.toolbarLabel,
        onBack: () => unawaited(_returnToReview()),
      ),
      disableSidebarActions: true,
      child: SizedBox(
        width: 520,
        child: switch (_stage) {
          _KeystoneDenominationSignStage.preparing => const SizedBox(
            height: 560,
            child: Center(child: CircularProgressIndicator()),
          ),
          _KeystoneDenominationSignStage.showQr => _buildQrContent(context),
          _KeystoneDenominationSignStage.scanning ||
          _KeystoneDenominationSignStage.waitingForProofs ||
          _KeystoneDenominationSignStage.completing => _buildScannerContent(
            context,
          ),
          _KeystoneDenominationSignStage.failed => _buildFailureContent(
            context,
          ),
        },
      ),
    );
  }

  Widget _buildMobileScreen(BuildContext context) {
    final completing = _stage == _KeystoneDenominationSignStage.completing;
    final round = widget.step == _KeystonePrivateSignStep.denominations
        ? MobileIronwoodKeystoneSigningRound.denominationSplit
        : MobileIronwoodKeystoneSigningRound.migrationBatch;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !completing) unawaited(_returnToReview());
      },
      child: KeyedSubtree(
        key: const ValueKey('mobile_ironwood_keystone_sign_screen'),
        child: switch (_stage) {
          _KeystoneDenominationSignStage.preparing =>
            MobileIronwoodKeystoneSigningView(
              state: MobileIronwoodKeystoneSigningViewState.loading,
              round: round,
              onCancel: () => unawaited(_returnToReview()),
            ),
          _KeystoneDenominationSignStage.showQr => _buildMobileQrContent(
            context,
            round: round,
          ),
          _KeystoneDenominationSignStage.scanning ||
          _KeystoneDenominationSignStage.waitingForProofs ||
          _KeystoneDenominationSignStage.completing =>
            _buildMobileScannerContent(context, round: round),
          _KeystoneDenominationSignStage.failed => Scaffold(
            backgroundColor: context.colors.background.window,
            body: SafeArea(
              child: Column(
                children: [
                  MobileTopNav.back(
                    title: 'Keystone migration',
                    onBack: () => unawaited(_returnToReview()),
                  ),
                  Expanded(child: _buildMobileFailureContent(context)),
                ],
              ),
            ),
          ),
        },
      ),
    );
  }

  Widget _buildMobileQrContent(
    BuildContext context, {
    required MobileIronwoodKeystoneSigningRound round,
  }) {
    final proofFailed = ironwoodMigrationKeystoneProofFailed(_proofStatus);
    return MobileIronwoodKeystoneSigningView(
      state: MobileIronwoodKeystoneSigningViewState.ready,
      round: round,
      qrCode: KeystonePcztQrStage(
        key: const ValueKey('mobile_ironwood_keystone_qr'),
        phase: KeystonePcztQrStagePhase.ready,
        urParts: _urParts,
        error: _error,
        size: 305,
        scanOptimized: true,
      ),
      onNext: _urParts.isEmpty || proofFailed
          ? null
          : () {
              setState(() {
                _stage = _KeystoneDenominationSignStage.scanning;
                _error = null;
                _decoding = false;
              });
            },
      onCancel: () => unawaited(_returnToReview()),
      onShowScanHelp: () => unawaited(_showKeystoneScanHelp()),
    );
  }

  Future<void> _showKeystoneScanHelp() {
    return showAppMobileSheet<void>(
      context: context,
      builder: (sheetContext) => MobileModalScaffold(
        title: '',
        showTitle: false,
        showClose: false,
        bottomPadding: AppSpacing.base,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: MobileIronwoodKeystoneScanHelpBody(
          onConfirm: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }

  Widget _buildMobileScannerContent(
    BuildContext context, {
    required MobileIronwoodKeystoneSigningRound round,
  }) {
    final completing = _stage == _KeystoneDenominationSignStage.completing;
    final waitingForProofs =
        _stage == _KeystoneDenominationSignStage.waitingForProofs;
    final scannerControls = _scannerControls;
    return MobileIronwoodKeystoneSigningView(
      state: MobileIronwoodKeystoneSigningViewState.scanner,
      round: round,
      camera: LayoutBuilder(
        builder: (context, constraints) => KeystoneQrScannerCard(
          expectedUrType: _keystoneMigrationSignBatchResultUrType,
          decoding: _decoding || waitingForProofs,
          error: null,
          onProgress: (_) {
            if (_pendingSignedMessages != null) return;
            if (_error == null || !mounted) return;
            setState(() => _error = null);
          },
          onDecodeError: _handleDecodeError,
          onComplete: (result) => unawaited(_handleScanComplete(result)),
          decodingLabel: waitingForProofs
              ? 'Preparing local proofs...'
              : 'Reading signature...',
          unavailableMessage:
              'Allow camera access to scan the signed Keystone QR.',
          cardWidth: constraints.maxWidth,
          cameraHeight: constraints.maxHeight,
          fullBleedMobile: true,
          showScanOverlay: false,
          onControlsReady: _handleScannerControlsReady,
        ),
      ),
      scannerMessage:
          _error ??
          (completing
              ? 'Applying the Keystone signature.'
              : waitingForProofs
              ? 'Signature captured. Waiting for local proofs.'
              : null),
      onToggleFlashlight:
          completing || waitingForProofs || scannerControls == null
          ? null
          : () => unawaited(scannerControls.toggleTorch()),
      onShowRequestQr: completing || waitingForProofs
          ? null
          : _showMobileRequestQrAgain,
      onCancel: completing ? null : _showMobileRequestQrAgain,
    );
  }

  void _handleScannerControlsReady(KeystoneQrScannerControls controls) {
    if (!mounted || identical(_scannerControls, controls)) return;
    setState(() => _scannerControls = controls);
  }

  void _showMobileRequestQrAgain() {
    if (!mounted) return;
    setState(() {
      _stage = _KeystoneDenominationSignStage.showQr;
      _error = null;
      _decoding = false;
      _scannerControls = null;
    });
  }

  Widget _buildMobileFailureContent(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppIcon(AppIcons.warning, size: 32),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Keystone signing unavailable',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            _error ?? 'Try again after sync finishes.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            expand: true,
            onPressed: () => unawaited(_prepareRequest()),
            leading: const AppIcon(AppIcons.renew, size: 20),
            child: const Text('Try again'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            expand: true,
            variant: AppButtonVariant.ghost,
            onPressed: () => unawaited(_returnToReview()),
            child: Text(widget.step.previousButtonLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildQrContent(BuildContext context) {
    final colors = context.colors;
    final request = _request;
    final proofStatusText = _proofStatusText;
    final proofFailed = ironwoodMigrationKeystoneProofFailed(_proofStatus);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.step.qrTitle,
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: 360,
            child: Text(
              widget.step.qrBody,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          KeystonePcztQrStage(
            phase: KeystonePcztQrStagePhase.ready,
            urParts: _urParts,
            error: _error,
            size: 264,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            request == null
                ? 'Preparing migration request'
                : '${request.messages.length} ${widget.step.messageUnit}'
                      '${request.messages.length == 1 ? '' : 's'} to sign',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (proofStatusText != null) ...[
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: 360,
              child: Text(
                proofStatusText,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: proofFailed
                      ? colors.text.destructive
                      : colors.text.secondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            onPressed: _urParts.isEmpty || proofFailed
                ? null
                : () {
                    setState(() {
                      _stage = _KeystoneDenominationSignStage.scanning;
                      _error = null;
                      _decoding = false;
                    });
                  },
            height: 44,
            minWidth: 230,
            trailing: const AppIcon(AppIcons.chevronForward, size: 20),
            child: const Text('Scan signature'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: () => unawaited(_returnToReview()),
            variant: AppButtonVariant.ghost,
            height: 36,
            minWidth: 230,
            child: Text(widget.step.previousButtonLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerContent(BuildContext context) {
    final colors = context.colors;
    final completing = _stage == _KeystoneDenominationSignStage.completing;
    final waitingForProofs =
        _stage == _KeystoneDenominationSignStage.waitingForProofs;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Scan Keystone signature',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: 360,
            child: Text(
              completing
                  ? 'Applying the Keystone signature to your migration plan.'
                  : waitingForProofs
                  ? 'Signature captured. Vizor will continue when local proofs are ready.'
                  : 'Show the signed migration QR on Keystone and scan it here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          KeystoneQrScannerCard(
            expectedUrType: _keystoneMigrationSignBatchResultUrType,
            decoding: _decoding,
            error: _error,
            onProgress: (_) {
              if (_pendingSignedMessages != null) return;
              if (_error == null || !mounted) return;
              setState(() {
                _error = null;
              });
            },
            onDecodeError: _handleDecodeError,
            onComplete: (result) => unawaited(_handleScanComplete(result)),
            decodingLabel: 'Reading signature...',
            unavailableMessage:
                'Keystone migration signing uses camera QR scanning only. '
                'Connect a camera and try again.',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: completing || waitingForProofs
                ? null
                : () {
                    setState(() {
                      _stage = _KeystoneDenominationSignStage.showQr;
                      _error = null;
                      _decoding = false;
                    });
                  },
            variant: AppButtonVariant.ghost,
            height: 36,
            minWidth: 230,
            child: const Text('Back to QR'),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureContent(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 560,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Keystone signing unavailable',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: 360,
              child: Text(
                _error ?? 'Try again after sync finishes.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              onPressed: () => unawaited(_prepareRequest()),
              minWidth: 230,
              leading: const AppIcon(AppIcons.renew, size: 20),
              child: const Text('Try again'),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              onPressed: () => unawaited(_returnToReview()),
              variant: AppButtonVariant.ghost,
              minWidth: 230,
              child: Text(widget.step.previousButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _keystoneDenominationToolbar({
  required String label,
  required VoidCallback onBack,
}) {
  return AppPaneToolbar(
    leading: AppBackLink(label: label, onTap: onBack),
  );
}

List<rust_sync.KeystoneSignedMigrationMessage> _signedMigrationMessagesFor(
  rust_sync.KeystoneMigrationSigningRequest request,
  rust_keystone.KeystoneSigResult decoded,
) {
  final signedById = <String, List<rust_keystone.KeystoneActionSig>>{};
  for (final result in decoded.results) {
    signedById[utf8.decode(result.messageId)] = result.sigs;
  }

  return [
    for (final message in request.messages)
      rust_sync.KeystoneSignedMigrationMessage(
        id: message.id,
        sigs:
            signedById[message.id] ??
            (throw StateError(
              'Keystone signature for ${message.id} is missing.',
            )),
      ),
  ];
}

@visibleForTesting
bool ironwoodMigrationKeystoneProofReady(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  return status?.isReady == true;
}

@visibleForTesting
bool ironwoodMigrationKeystoneProofFailed(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  return status?.isFailed == true;
}

@visibleForTesting
bool ironwoodMigrationKeystoneProofShouldWait(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  return status == null || (!status.isReady && !status.isFailed);
}

@visibleForTesting
String ironwoodMigrationKeystoneProofWaitingMessage(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  if (status != null && status.totalCount > 0) {
    return 'Signature captured. Vizor is still preparing local proofs '
        '(${status.readyCount}/${status.totalCount}). Keep this screen open.';
  }
  return 'Signature captured. Vizor is still preparing local proofs. '
      'Keep this screen open.';
}

@visibleForTesting
String ironwoodMigrationKeystoneProofFailureMessage(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  final message = status?.message?.trim();
  if (message != null && message.isNotEmpty) return message;
  return 'Vizor could not prepare local proofs. Go back and prepare this request again.';
}

@visibleForTesting
String ironwoodMigrationKeystoneScanErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('Unexpected UR type') &&
      message.contains(_keystoneMigrationLegacySignResultUrType)) {
    return _keystoneMigrationFirmwareUpdateError;
  }
  if (message.contains('Unexpected UR type')) {
    return 'Open the signed migration QR on Keystone, then scan again.';
  }
  return 'Keep the QR code steady and fully visible.';
}

bool _keystoneMigrationProofStillPendingError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('proof') &&
      (lower.contains('pending') ||
          lower.contains('not ready') ||
          lower.contains('still'));
}

String _keystoneMigrationSigningErrorMessage(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('not a keystone')) {
    return 'Use a Keystone account to sign this migration.';
  }
  if (lower.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (lower.contains('password') ||
      lower.contains('secret storage') ||
      lower.contains('unlocked session')) {
    return 'Unlock Vizor before signing migration.';
  }
  if (lower.contains('request') && lower.contains('not found')) {
    return 'This Keystone signing request expired. Prepare it again.';
  }
  if (lower.contains('signature') || lower.contains('qr')) {
    return 'Keystone signature could not be applied.';
  }
  return 'Keystone signing could not be prepared. Try again.';
}
