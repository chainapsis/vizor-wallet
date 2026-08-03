part of '../ironwood_migration_flow_screen.dart';

// Keystone reliably scans the denser 300-byte migration frames at 5 fps.
const _keystoneMigrationQrMaxFragmentLen = 300;
const _keystoneMigrationQrFrameInterval = Duration(milliseconds: 200);

class IronwoodMigrationKeystoneCombinedSignScreen extends StatelessWidget {
  const IronwoodMigrationKeystoneCombinedSignScreen({
    required this.approvedSchedule,
    this.previewRequest,
    this.previewUrParts = const [],
    this.previewStartScanning = false,
    super.key,
  });

  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;
  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;
  final bool previewStartScanning;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.combined,
      approvedSchedule: approvedSchedule,
      previewRequest: previewRequest,
      previewUrParts: previewUrParts,
      previewStartScanning: previewStartScanning,
    );
  }
}

class IronwoodMigrationKeystoneImmediateSignScreen extends StatelessWidget {
  const IronwoodMigrationKeystoneImmediateSignScreen({
    required this.approvedPlan,
    this.previewRequest,
    this.previewUrParts = const [],
    this.previewStartScanning = false,
    super.key,
  });

  final rust_sync.OrchardMigrationImmediatePlan approvedPlan;
  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;
  final bool previewStartScanning;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.immediate,
      approvedSchedule: const [],
      approvedImmediatePlan: approvedPlan,
      previewRequest: previewRequest,
      previewUrParts: previewUrParts,
      previewStartScanning: previewStartScanning,
    );
  }
}

class MobileIronwoodMigrationKeystoneImmediateSignScreen
    extends StatelessWidget {
  const MobileIronwoodMigrationKeystoneImmediateSignScreen({
    required this.approvedPlan,
    this.previewRequest,
    this.previewUrParts = const [],
    this.previewStartScanning = false,
    super.key,
  });

  final rust_sync.OrchardMigrationImmediatePlan approvedPlan;
  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;
  final bool previewStartScanning;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.immediate,
      approvedSchedule: const [],
      approvedImmediatePlan: approvedPlan,
      mobileLayout: true,
      previewRequest: previewRequest,
      previewUrParts: previewUrParts,
      previewStartScanning: previewStartScanning,
    );
  }
}

class MobileIronwoodMigrationKeystoneCombinedSignScreen
    extends StatelessWidget {
  const MobileIronwoodMigrationKeystoneCombinedSignScreen({
    required this.approvedSchedule,
    this.initialRequest,
    this.initialAccountUuid,
    this.previewRequest,
    this.previewUrParts = const [],
    this.previewStartScanning = false,
    super.key,
  });

  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;
  final rust_sync.KeystoneMigrationSigningRequest? initialRequest;
  final String? initialAccountUuid;
  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;
  final bool previewStartScanning;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.combined,
      approvedSchedule: approvedSchedule,
      mobileLayout: true,
      initialRequest: initialRequest,
      initialAccountUuid: initialAccountUuid,
      previewRequest: previewRequest,
      previewUrParts: previewUrParts,
      previewStartScanning: previewStartScanning,
    );
  }
}

class MobileIronwoodMigrationKeystoneCombinedSignEntry {
  const MobileIronwoodMigrationKeystoneCombinedSignEntry({
    required this.approvedSchedule,
    required this.request,
    required this.accountUuid,
  });

  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;
  final rust_sync.KeystoneMigrationSigningRequest request;
  final String accountUuid;
}

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
    this.initialRequest,
    this.initialAccountUuid,
    this.previewRequest,
    this.previewUrParts = const [],
    super.key,
  });

  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;
  final rust_sync.KeystoneMigrationSigningRequest? initialRequest;
  final String? initialAccountUuid;
  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.denominations,
      approvedSchedule: approvedSchedule,
      mobileLayout: true,
      initialRequest: initialRequest,
      initialAccountUuid: initialAccountUuid,
      previewRequest: previewRequest,
      previewUrParts: previewUrParts,
    );
  }
}

class MobileIronwoodMigrationKeystoneDenominationSignEntry {
  const MobileIronwoodMigrationKeystoneDenominationSignEntry({
    required this.approvedSchedule,
    required this.request,
    required this.accountUuid,
  });

  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;
  final rust_sync.KeystoneMigrationSigningRequest request;
  final String accountUuid;
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
    this.approvedImmediatePlan,
    this.mobileLayout = false,
    this.initialRequest,
    this.initialAccountUuid,
    this.previewRequest,
    this.previewUrParts = const [],
    this.previewStartScanning = false,
  });

  final _KeystonePrivateSignStep step;
  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;
  final rust_sync.OrchardMigrationImmediatePlan? approvedImmediatePlan;
  final bool mobileLayout;
  final rust_sync.KeystoneMigrationSigningRequest? initialRequest;
  final String? initialAccountUuid;
  final rust_sync.KeystoneMigrationSigningRequest? previewRequest;
  final List<String> previewUrParts;
  final bool previewStartScanning;

  @override
  ConsumerState<_IronwoodMigrationKeystonePrivateSignScreen> createState() =>
      _IronwoodMigrationKeystonePrivateSignScreenState();
}

enum _KeystonePrivateSignStep { immediate, combined, denominations, batch }

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
    _KeystonePrivateSignStep.immediate => 'immediate',
    _KeystonePrivateSignStep.combined => 'combined',
    _KeystonePrivateSignStep.denominations => 'denominations',
    _KeystonePrivateSignStep.batch => 'batch',
  };

  String get toolbarLabel => switch (this) {
    _KeystonePrivateSignStep.immediate => 'Migration Options',
    _KeystonePrivateSignStep.combined => 'Review migration',
    _KeystonePrivateSignStep.denominations => 'Review migration',
    _KeystonePrivateSignStep.batch => 'Migration status',
  };

  String get previousRoute => switch (this) {
    _KeystonePrivateSignStep.immediate => '/migration/immediate/review',
    _KeystonePrivateSignStep.combined => '/migration/private/review',
    _KeystonePrivateSignStep.denominations => '/migration/private/review',
    _KeystonePrivateSignStep.batch => '/migration/private/status',
  };

  String get previousButtonLabel => switch (this) {
    _KeystonePrivateSignStep.immediate => 'Back to review',
    _KeystonePrivateSignStep.combined => 'Back to review',
    _KeystonePrivateSignStep.denominations => 'Back to review',
    _KeystonePrivateSignStep.batch => 'Back to status',
  };

  String get qrTitle => switch (this) {
    _KeystonePrivateSignStep.immediate => 'Confirm Migration with Keystone',
    _KeystonePrivateSignStep.combined => 'Sign migration',
    _KeystonePrivateSignStep.denominations => 'Sign private split',
    _KeystonePrivateSignStep.batch => 'Sign Ironwood batch',
  };

  String get qrBody => switch (this) {
    _KeystonePrivateSignStep.immediate =>
      'Scan the QR code with your Keystone wallet to confirm migration.',
    _KeystonePrivateSignStep.combined =>
      'Scan this request with Keystone to sign the preparation transactions '
          'and migration batches together.',
    _KeystonePrivateSignStep.denominations =>
      'Scan this request QR with Keystone. Keystone will show a new signed QR when it finishes.',
    _KeystonePrivateSignStep.batch =>
      'Scan this request QR with Keystone. Keystone will show a new signed QR when it finishes.',
  };

  String get messageUnit => switch (this) {
    _KeystonePrivateSignStep.immediate => 'migration transaction',
    _KeystonePrivateSignStep.combined => 'transaction',
    _KeystonePrivateSignStep.denominations => 'split transaction',
    _KeystonePrivateSignStep.batch => 'migration transaction',
  };

  Future<rust_sync.KeystoneMigrationSigningRequest> prepare(
    IronwoodMigrationService service, {
    required String accountUuid,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
    rust_sync.OrchardMigrationImmediatePlan? approvedImmediatePlan,
  }) {
    return switch (this) {
      _KeystonePrivateSignStep.immediate =>
        service.prepareKeystoneImmediateMigrationRequest(
          accountUuid: accountUuid,
          approvedPlan:
              approvedImmediatePlan ??
              (throw StateError('Immediate migration plan is missing.')),
        ),
      _KeystonePrivateSignStep.combined =>
        service.prepareKeystoneSingleQrPrivateMigration(
          accountUuid: accountUuid,
          approvedSchedule: approvedSchedule,
        ),
      _KeystonePrivateSignStep.denominations =>
        service.prepareKeystoneDenominationPrivateMigration(
          accountUuid: accountUuid,
          approvedSchedule: approvedSchedule,
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
      _KeystonePrivateSignStep.immediate =>
        service.completeKeystoneImmediateMigrationRequest(
          accountUuid: accountUuid,
          requestId: requestId,
          signedMessages: signedMessages,
        ),
      _KeystonePrivateSignStep.combined =>
        service.completeKeystoneSingleQrPrivateMigration(
          accountUuid: accountUuid,
          requestId: requestId,
          signedMessages: signedMessages,
        ),
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
  List<List<rust_sync.KeystoneMigrationMessage>> _signingRounds = const [];
  List<List<String>> _signingRoundUrParts = const [];
  List<rust_sync.KeystoneSignedMigrationMessage> _signedPriorRounds = const [];
  int _signingRoundIndex = 0;
  String? _error;
  Timer? _proofPollTimer;
  rust_sync.KeystoneMigrationProofStatus? _proofStatus;
  List<rust_sync.KeystoneSignedMigrationMessage>? _pendingSignedMessages;
  KeystoneQrScannerControls? _scannerControls;
  bool _decoding = false;
  // Multi-part UR scan progress (0-100) for the mobile scanner chrome. The
  // scanner card reports it; the mobile view renders it under the viewfinder.
  int _scanProgress = 0;
  bool _requestCompleted = false;
  Future<void>? _completionOperation;
  IronwoodMigrationPrivacyLockSuppressionNotifier?
  _privacyLockSuppressionNotifier;
  IronwoodMigrationPrivacyLockSuppression? _privacyLockSuppression;

  @override
  void initState() {
    super.initState();
    _migrationService = ref.read(ironwoodMigrationServiceProvider);
    if (!widget.mobileLayout) {
      _privacyLockSuppressionNotifier = ref.read(
        ironwoodMigrationPrivacyLockSuppressionProvider.notifier,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _privacyLockSuppression != null) return;
        _privacyLockSuppression = _privacyLockSuppressionNotifier?.acquire();
      });
    }
    final previewRequest = widget.previewRequest;
    if (previewRequest != null) {
      _request = previewRequest;
      _accountUuid = 'preview-account';
      _signingRounds = _keystoneSigningRounds(
        previewRequest.messages,
        previewRequest.signingBatchLimit,
      );
      _signingRoundUrParts = [
        for (var index = 0; index < _signingRounds.length; index++)
          index == 0 ? widget.previewUrParts : const <String>[],
      ];
      _urParts = widget.previewUrParts;
      _stage = widget.previewStartScanning
          ? _KeystoneDenominationSignStage.scanning
          : _KeystoneDenominationSignStage.showQr;
      _requestCompleted = true;
      return;
    }
    unawaited(
      _prepareRequest(
        preparedRequest: widget.initialRequest,
        preparedAccountUuid: widget.initialAccountUuid,
      ),
    );
  }

  @override
  void dispose() {
    _stopProofPolling();
    final privacyLockSuppression = _privacyLockSuppression;
    final privacyLockSuppressionNotifier = _privacyLockSuppressionNotifier;
    if (privacyLockSuppression != null &&
        privacyLockSuppressionNotifier != null) {
      // Riverpod disallows provider mutations while Flutter is finalizing this
      // route. Release immediately after the current widget lifecycle pass.
      scheduleMicrotask(() {
        privacyLockSuppressionNotifier.release(privacyLockSuppression);
      });
    }
    _privacyLockSuppression = null;
    _privacyLockSuppressionNotifier = null;
    if (!_requestCompleted) {
      final requestId = _request?.requestId;
      final accountUuid = _accountUuid;
      if (requestId != null && accountUuid != null) {
        unawaited(_discardRequest(accountUuid, requestId));
      }
    }
    super.dispose();
  }

  Future<void> _prepareRequest({
    rust_sync.KeystoneMigrationSigningRequest? preparedRequest,
    String? preparedAccountUuid,
  }) async {
    _stopProofPolling();
    setState(() {
      _stage = _KeystoneDenominationSignStage.preparing;
      _request = null;
      _accountUuid = null;
      _urParts = const [];
      _signingRounds = const [];
      _signingRoundUrParts = const [];
      _signedPriorRounds = const [];
      _signingRoundIndex = 0;
      _error = null;
      _proofStatus = null;
      _pendingSignedMessages = null;
      _scannerControls = null;
      _decoding = false;
      _scanProgress = 0;
    });

    String? requestIdToDiscard = preparedRequest?.requestId;
    String? requestAccountUuid = preparedAccountUuid;
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
      if (preparedRequest != null && preparedAccountUuid != accountUuid) {
        throw StateError(
          'Prepared Keystone request does not match the active account.',
        );
      }
      requestAccountUuid = accountUuid;
      final request =
          preparedRequest ??
          await widget.step.prepare(
            _migrationService,
            accountUuid: accountUuid,
            approvedSchedule: widget.approvedSchedule,
            approvedImmediatePlan: widget.approvedImmediatePlan,
          );
      requestIdToDiscard = request.requestId;
      if (!mounted) {
        await _discardRequest(accountUuid, request.requestId);
        return;
      }
      _request = request;
      _accountUuid = accountUuid;
      final signingRounds = _keystoneSigningRounds(
        request.messages,
        request.signingBatchLimit,
      );
      _signingRounds = signingRounds;
      if (request.messages.isEmpty) {
        if (widget.step != _KeystonePrivateSignStep.denominations) {
          throw StateError('Keystone migration request has no messages.');
        }
        await _completeSignedMessages(const []);
        return;
      }
      _startProofPolling(request.requestId);

      final signingRoundUrParts = <List<String>>[];
      for (var index = 0; index < signingRounds.length; index++) {
        signingRoundUrParts.add(
          await rust_keystone.encodeZcashSignBatchUrParts(
            requestId: _keystoneSigningRoundRequestId(
              request.requestId,
              index,
              signingRounds.length,
            ),
            messages: signingRounds[index]
                .map(
                  (message) => rust_keystone_wallet.ZcashBatchMessageInput(
                    id: message.id,
                    pcztBytes: message.redactedPczt,
                  ),
                )
                .toList(),
            maxFragmentLen: BigInt.from(_keystoneMigrationQrMaxFragmentLen),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _stage = _KeystoneDenominationSignStage.showQr;
        _signingRoundUrParts = signingRoundUrParts;
        _urParts = signingRoundUrParts.first;
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
      _signingRounds = const [];
      _signingRoundUrParts = const [];
      _signedPriorRounds = const [];
      _signingRoundIndex = 0;
      if (requestId != null && requestAccountUuid != null) {
        unawaited(_discardRequest(requestAccountUuid, requestId));
      }
      if (!mounted) return;
      setState(() {
        _stage = _KeystoneDenominationSignStage.failed;
        _error = ironwoodMigrationKeystoneSigningErrorMessage(e);
      });
    }
  }

  List<rust_sync.KeystoneMigrationMessage>? get _currentSigningRound {
    if (_signingRoundIndex < 0 || _signingRoundIndex >= _signingRounds.length) {
      return null;
    }
    return _signingRounds[_signingRoundIndex];
  }

  String? get _signingRoundLabel => _signingRounds.length <= 1
      ? null
      : 'Round ${_signingRoundIndex + 1} of ${_signingRounds.length}';

  /// How many transactions the QR currently on screen signs.
  ///
  /// `_signingRounds` is the exact partition of `request.messages` that the
  /// QR encoder consumes (`_keystoneSigningRounds`, capped by
  /// `signingBatchLimit` and the Keystone byte budget), so the current round's
  /// length is the real message count for this QR and the flattened total is
  /// the request's message count.
  String? get _signingMessageCountLabel {
    final round = _currentSigningRound;
    if (round == null || round.isEmpty) return null;
    final total = _request?.messages.length ?? round.length;
    if (round.length >= total) {
      return 'Signs ${_transactionCountText(total)}';
    }
    return 'Signs ${round.length} of ${_transactionCountText(total)}';
  }

  String _transactionCountText(int count) =>
      count == 1 ? '1 transaction' : '$count transactions';

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding ||
        _stage != _KeystoneDenominationSignStage.scanning ||
        _pendingSignedMessages != null) {
      return;
    }
    final request = _request;
    final accountUuid = _accountUuid;
    final signingRound = _currentSigningRound;
    if (request == null || accountUuid == null || signingRound == null) return;
    final signingRoundIndex = _signingRoundIndex;

    setState(() {
      _decoding = true;
      _stage = _KeystoneDenominationSignStage.completing;
      _error = null;
    });

    try {
      final decoded = await rust_keystone.decodeZcashBatchSignResponse(
        cbor: result.data,
        expectedRequestId: _keystoneSigningRoundRequestId(
          request.requestId,
          signingRoundIndex,
          _signingRounds.length,
        ),
        messageIds: signingRound.map((message) => message.id).toList(),
      );
      final signedMessages = [
        ..._signedPriorRounds,
        ..._signedMigrationMessagesFor(signingRound, decoded),
      ];
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
      if (signingRoundIndex + 1 < _signingRounds.length) {
        setState(() {
          _signedPriorRounds = signedMessages;
          _signingRoundIndex = signingRoundIndex + 1;
          _urParts = _signingRoundUrParts[_signingRoundIndex];
          _stage = _KeystoneDenominationSignStage.showQr;
          _scannerControls = null;
          _decoding = false;
          _error = null;
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
        _error = ironwoodMigrationKeystoneSigningErrorMessage(e);
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
            _stage = (_request?.messages.isEmpty ?? true)
                ? _KeystoneDenominationSignStage.failed
                : _KeystoneDenominationSignStage.scanning;
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
        _error = ironwoodMigrationKeystoneSigningErrorMessage(e);
      });
    }
  }

  Future<void> _completeSignedMessages(
    List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  ) {
    final existing = _completionOperation;
    if (existing != null) return existing;

    late final Future<void> tracked;
    tracked = _runCompleteSignedMessages(signedMessages).whenComplete(() {
      if (identical(_completionOperation, tracked)) {
        _completionOperation = null;
      }
    });
    _completionOperation = tracked;
    return tracked;
  }

  Future<void> _runCompleteSignedMessages(
    List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  ) async {
    final request = _request;
    final accountUuid = _accountUuid;
    if (request == null || accountUuid == null || _requestCompleted) return;

    _stopProofPolling();
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
      await _finishCommittedRequest(accountUuid);
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'complete error: $e\n$st',
      );
      if (!mounted) return;
      if (await _reconcileCommittedRequest(accountUuid, originalError: e)) {
        return;
      }
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
      if (widget.step == _KeystonePrivateSignStep.immediate &&
          await _immediateRequestWasConsumed(request.requestId)) {
        if (!mounted) return;
        setState(() {
          _stage = _KeystoneDenominationSignStage.failed;
          _request = null;
          _pendingSignedMessages = null;
          _decoding = false;
          _error =
              'This Keystone signing request can no longer be used. Prepare it again.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _stage = request.messages.isEmpty
            ? _KeystoneDenominationSignStage.failed
            : _KeystoneDenominationSignStage.scanning;
        _pendingSignedMessages = null;
        _decoding = false;
        _error = ironwoodMigrationKeystoneSigningErrorMessage(e);
      });
    }
  }

  Future<bool> _immediateRequestWasConsumed(String requestId) async {
    try {
      await _migrationService.keystoneProofStatus(requestId: requestId);
      return false;
    } catch (e, st) {
      if (_keystoneMigrationRequestMissingError(e)) return true;
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'failed to determine whether completion consumed the request: $e\n$st',
      );
      return false;
    }
  }

  Future<bool> _reconcileCommittedRequest(
    String accountUuid, {
    required Object originalError,
  }) async {
    try {
      final network = ref.read(ironwoodMigrationInputsProvider).network;
      final status = await _migrationService.readOnlyStatus(
        network: network,
        accountUuid: accountUuid,
      );
      if (!mounted || !_isKeystoneRequestCommitted(status)) return false;
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'completion returned an error after the durable migration state '
        'advanced; treating the request as committed: $originalError',
      );
      await _finishCommittedRequest(accountUuid);
      return true;
    } catch (statusError, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'failed to reconcile completion error against migration status: '
        '$statusError\n$st',
      );
      return false;
    }
  }

  bool _isKeystoneRequestCommitted(rust_sync.MigrationStatus status) {
    return switch (widget.step) {
      _KeystonePrivateSignStep.immediate => false,
      _KeystonePrivateSignStep.combined => status.activeRunId != null,
      _KeystonePrivateSignStep.denominations => status.activeRunId != null,
      _KeystonePrivateSignStep.batch =>
        !status.parts.any(
              (part) => part.state == rust_sync.MigrationPartState.needsInput,
            ) &&
            (status.phase != kIronwoodMigrationReadyToMigratePhase ||
                status.signedChildPcztCount > 0),
    };
  }

  Future<void> _finishCommittedRequest(String accountUuid) async {
    if (widget.step == _KeystonePrivateSignStep.immediate) {
      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (_) {
        // The normal sync loop will reconcile an accepted transaction.
      }
      if (!mounted) return;
      _stopProofPolling();
      _requestCompleted = true;
      _pendingSignedMessages = null;
      if (widget.mobileLayout) {
        // Mobile lands on home, which reads the migration CTA and the
        // post-migration state directly.
        _invalidateIronwoodMigrationStatusState(ref);
      }
      context.go('/home');
      return;
    }
    final coordinator = ref.read(ironwoodMigrationCoordinatorProvider.notifier);
    coordinator.clearChildProofBatchPermit(accountUuid);
    if (widget.step == _KeystonePrivateSignStep.combined ||
        widget.step == _KeystonePrivateSignStep.denominations) {
      coordinator.grantForegroundProgressPermit(accountUuid);
    }
    await coordinator.refreshNow();
    if (!mounted) return;
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
      extra: const MobileIronwoodMigrationStatusEntry(),
    );
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

  Future<void> _retryRequest() async {
    final requestId = _request?.requestId;
    final accountUuid = _accountUuid;
    setState(() {
      _stage = _KeystoneDenominationSignStage.preparing;
      _error = null;
      _proofStatus = null;
      _pendingSignedMessages = null;
    });
    if (requestId != null && accountUuid != null) {
      await _discardRequest(accountUuid, requestId);
    }
    if (!mounted) return;
    await _prepareRequest();
  }

  Future<void> _returnToReview() async {
    if (_stage == _KeystoneDenominationSignStage.completing) return;
    final requestId = _request?.requestId;
    final accountUuid = _accountUuid;
    _stopProofPolling();
    _request = null;
    if (!_requestCompleted && requestId != null && accountUuid != null) {
      await _discardRequest(accountUuid, requestId);
    }
    if (!mounted) return;
    final previousRoute = switch ((widget.mobileLayout, widget.step)) {
      (true, _KeystonePrivateSignStep.immediate) => '/migration/fast/review',
      // Combined signing creates the durable run only at completion, so a
      // cancelled mobile session has no draft for the status screen to show.
      (true, _KeystonePrivateSignStep.combined) => '/migration/options',
      (true, _KeystonePrivateSignStep.denominations) =>
        '/migration/private/status',
      _ => widget.step.previousRoute,
    };
    context.go(previousRoute);
  }

  void _handleBack() {
    if (_stage == _KeystoneDenominationSignStage.scanning) {
      _showRequestQrAgain();
      return;
    }
    unawaited(_returnToReview());
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
    if (status.isReady) return null;
    if (status.totalCount > 0) {
      return 'Preparing local proofs ${status.readyCount}/${status.totalCount}';
    }
    return 'Preparing local proofs';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobileLayout) return _buildMobileScreen(context);
    if (widget.step == _KeystonePrivateSignStep.immediate) {
      return _buildImmediateDesktopScreen(context);
    }

    return _IronwoodMigrationFrame(
      toolbar: _keystoneDenominationToolbar(
        label: _stage == _KeystoneDenominationSignStage.scanning
            ? 'Request QR'
            : widget.step.toolbarLabel,
        onBack: _handleBack,
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

  Widget _buildImmediateDesktopScreen(BuildContext context) {
    final showingScanner =
        _stage == _KeystoneDenominationSignStage.scanning ||
        _stage == _KeystoneDenominationSignStage.waitingForProofs ||
        _stage == _KeystoneDenominationSignStage.completing;
    final proofFailed = ironwoodMigrationKeystoneProofFailed(_proofStatus);
    final modalPhase = switch (_stage) {
      _KeystoneDenominationSignStage.preparing =>
        KeystoneSigningModalPhase.preparing,
      _KeystoneDenominationSignStage.showQr when proofFailed =>
        KeystoneSigningModalPhase.failed,
      _KeystoneDenominationSignStage.showQr => KeystoneSigningModalPhase.ready,
      _KeystoneDenominationSignStage.failed => KeystoneSigningModalPhase.failed,
      _ => null,
    };
    final ready =
        _stage == _KeystoneDenominationSignStage.showQr && !proofFailed;
    final failed =
        _stage == _KeystoneDenominationSignStage.failed || proofFailed;

    return _IronwoodMigrationFrame(
      toolbar: _keystoneDenominationToolbar(
        label: 'Ironwood Migration',
        onBack: () => unawaited(_returnToReview()),
      ),
      disableSidebarActions: true,
      overlay: modalPhase == null
          ? null
          : AppPaneModalOverlay(
              onDismiss: () => unawaited(_returnToReview()),
              child: KeystoneSigningModal(
                key: const ValueKey(
                  'ironwood_immediate_keystone_signing_modal',
                ),
                phase: modalPhase,
                urParts: _urParts,
                error: _error,
                title: 'Confirm Migration with Keystone',
                subtitle: 'Scan with your Keystone',
                instruction: failed
                    ? null
                    : 'After you scanned, click Get signature.',
                primaryLabel: failed
                    ? 'Try again'
                    : ready
                    ? 'Get signature'
                    : 'Preparing',
                onPrimary: failed
                    ? () => unawaited(_retryRequest())
                    : ready && _urParts.isNotEmpty
                    ? () {
                        setState(() {
                          _stage = _KeystoneDenominationSignStage.scanning;
                          _error = null;
                          _decoding = false;
                        });
                      }
                    : null,
                secondaryLabel: 'Cancel',
                onSecondary: () => unawaited(_returnToReview()),
                qrSize: 200,
              ),
            ),
      child: showingScanner
          ? SizedBox(width: 520, child: _buildScannerContent(context))
          : IgnorePointer(
              child: _IronwoodMigrationImmediateReviewContent(
                data: _fallbackMigrationFlowData(),
                previewPlan: widget.approvedImmediatePlan,
              ),
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
        if (!didPop && !completing) _handleBack();
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
      signingRoundLabel: _signingRoundLabel,
      signingMessageCountLabel: _signingMessageCountLabel,
      qrCode: KeystonePcztQrStage(
        key: const ValueKey('mobile_ironwood_keystone_qr'),
        phase: KeystonePcztQrStagePhase.ready,
        urParts: _urParts,
        error: _error,
        size: 305,
        scanOptimized: true,
        frameInterval: _keystoneMigrationQrFrameInterval,
      ),
      onNext: _urParts.isEmpty || proofFailed
          ? null
          : () {
              setState(() {
                _stage = _KeystoneDenominationSignStage.scanning;
                _error = null;
                _decoding = false;
                _scanProgress = 0;
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
          onProgress: (progress) {
            if (_pendingSignedMessages != null || !mounted) return;
            if (_error == null && _scanProgress == progress) return;
            setState(() {
              _error = null;
              _scanProgress = progress;
            });
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
          // The mobile view renders a viewfinder-width progress bar with a
          // percentage instead of the card's small bottom bar.
          showScanProgress: false,
          onControlsReady: _handleScannerControlsReady,
        ),
      ),
      scannerMessage:
          _error ??
          (completing
              ? 'Applying the Keystone signature.'
              : waitingForProofs
              ? 'Signature captured. Waiting for local proofs.'
              : 'Scan the new signed QR shown on Keystone.'),
      signingRoundLabel: _signingRoundLabel,
      scanProgress: completing || waitingForProofs || _scanProgress <= 0
          ? null
          : _scanProgress / 100,
      scannerMessageIsError: _error != null,
      onToggleFlashlight:
          completing || waitingForProofs || scannerControls == null
          ? null
          : () => unawaited(scannerControls.toggleTorch()),
      onShowRequestQr: completing || waitingForProofs
          ? null
          : _showRequestQrAgain,
      onCancel: completing ? null : _showRequestQrAgain,
    );
  }

  void _handleScannerControlsReady(KeystoneQrScannerControls controls) {
    if (!mounted || identical(_scannerControls, controls)) return;
    setState(() => _scannerControls = controls);
  }

  void _showRequestQrAgain() {
    if (!mounted) return;
    setState(() {
      _stage = _KeystoneDenominationSignStage.showQr;
      _error = null;
      _decoding = false;
      _scannerControls = null;
      _scanProgress = 0;
    });
  }

  Future<void> _showEnlargedRequestQr() async {
    final urParts = List<String>.of(_urParts);
    if (urParts.isEmpty) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        final availableSize = math.min(
          viewport.width - AppSpacing.xl * 2,
          viewport.height - AppSpacing.xl * 2,
        );
        final qrSize = math
            .min(520.0, availableSize)
            .clamp(264.0, 520.0)
            .toDouble();
        return Dialog(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Semantics(
            label: 'Enlarged Keystone request QR',
            child: KeystonePcztQrStage(
              key: const ValueKey('keystone_migration_enlarged_qr'),
              phase: KeystonePcztQrStagePhase.ready,
              urParts: urParts,
              error: null,
              size: qrSize,
              frameInterval: _keystoneMigrationQrFrameInterval,
            ),
          ),
        );
      },
    );
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
    final signingRound = _currentSigningRound;
    final signingRoundLabel = _signingRoundLabel;
    final proofStatusText = _proofStatusText;
    final proofFailed = ironwoodMigrationKeystoneProofFailed(_proofStatus);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (signingRoundLabel != null) ...[
            Text(
              signingRoundLabel,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          Text(
            widget.step == _KeystonePrivateSignStep.immediate
                ? widget.step.qrTitle
                : 'Scan request with Keystone',
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
          Semantics(
            label: 'Enlarge Keystone request QR',
            button: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey('keystone_migration_enlarge_qr'),
                onTap: () => unawaited(_showEnlargedRequestQr()),
                behavior: HitTestBehavior.opaque,
                child: KeystoneScanHelpOverlay(
                  visible: _urParts.isNotEmpty && !proofFailed,
                  child: KeystonePcztQrStage(
                    phase: KeystonePcztQrStagePhase.ready,
                    urParts: _urParts,
                    error: _error,
                    size: 264,
                    frameInterval: _keystoneMigrationQrFrameInterval,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            request == null || signingRound == null
                ? 'Preparing migration request'
                : '${signingRound.length} ${widget.step.messageUnit}'
                      '${signingRound.length == 1 ? '' : 's'} to sign'
                      ' · click QR to enlarge',
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
            child: const Text('Scan Keystone signature'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: () => unawaited(_returnToReview()),
            variant: AppButtonVariant.ghost,
            height: 44,
            minWidth: 230,
            child: Text(widget.step.previousButtonLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerContent(BuildContext context) {
    final colors = context.colors;
    final signingRoundLabel = _signingRoundLabel;
    final completing = _stage == _KeystoneDenominationSignStage.completing;
    final waitingForProofs =
        _stage == _KeystoneDenominationSignStage.waitingForProofs;
    return Padding(
      padding: EdgeInsets.only(
        top: widget.step == _KeystonePrivateSignStep.immediate
            ? 80
            : AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (signingRoundLabel != null) ...[
            Text(
              signingRoundLabel,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          Text(
            widget.step == _KeystonePrivateSignStep.immediate
                ? 'Scan QR Code'
                : 'Scan Keystone signature',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: 360,
            child: Text(
              widget.step == _KeystonePrivateSignStep.immediate &&
                      !completing &&
                      !waitingForProofs
                  ? 'Prepare your Keystone wallet'
                  : completing
                  ? 'Applying the Keystone signature to your migration plan.'
                  : waitingForProofs
                  ? 'Signature captured. Vizor will continue when local proofs are ready.'
                  : 'Scan the new signed QR shown on Keystone.',
              textAlign: TextAlign.center,
              style:
                  (widget.step == _KeystonePrivateSignStep.immediate
                          ? AppTypography.bodyMedium
                          : AppTypography.bodyMediumStrong)
                      .copyWith(color: colors.text.accent),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          if (widget.previewRequest != null)
            const _ImmediateKeystoneScannerPreviewCard()
          else
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

class _ImmediateKeystoneScannerPreviewCard extends StatelessWidget {
  const _ImmediateKeystoneScannerPreviewCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 396,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 396,
            height: 310,
            decoration: BoxDecoration(
              color: const Color(0xFF171918),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFFFFFFF), width: 4),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Center(
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: const Color(0xFF343737),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            children: [
              AppIcon(AppIcons.camera, size: 18, color: colors.icon.regular),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Camera',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const Spacer(),
              Text(
                'Face Time HD Camera (Default)',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                AppIcons.doubleArrowVertical,
                size: 14,
                color: colors.icon.regular,
              ),
            ],
          ),
        ],
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
  List<rust_sync.KeystoneMigrationMessage> messages,
  rust_keystone.KeystoneSigResult decoded,
) {
  final signedById = <String, List<rust_keystone.KeystoneActionSig>>{};
  for (final result in decoded.results) {
    signedById[utf8.decode(result.messageId)] = result.sigs;
  }

  return [
    for (final message in messages)
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

// The Keystone firmware enforces two independent caps on one signing round:
// the message count (`signingBatchLimit`) and a 512 KiB ceiling that covers
// both the canonical PCZT byte total and the request-id + Postcard envelope
// (`ZCASH_SIGN_BATCH_MAX_TOTAL_BYTES` in rust/src/wallet/keystone.rs). Rounds
// must stay under both, or QR encoding rejects the round after the user has
// already approved the migration.
const _keystoneSigningRoundMaxTotalBytes = 512 * 1024;
// Headroom for the request id and per-message Postcard framing, which the
// firmware counts against the same ceiling as the raw PCZT payloads.
const _keystoneSigningRoundByteBudget =
    _keystoneSigningRoundMaxTotalBytes - 16 * 1024;

@visibleForTesting
List<List<rust_sync.KeystoneMigrationMessage>> keystoneSigningRoundsForTest(
  List<rust_sync.KeystoneMigrationMessage> messages,
  int limit,
) => _keystoneSigningRounds(messages, limit);

List<List<rust_sync.KeystoneMigrationMessage>> _keystoneSigningRounds(
  List<rust_sync.KeystoneMigrationMessage> messages,
  int limit,
) {
  if (messages.isEmpty) return const [];
  if (limit <= 0) {
    throw StateError('Keystone signing batch limit must be positive.');
  }
  final rounds = <List<rust_sync.KeystoneMigrationMessage>>[];
  var round = <rust_sync.KeystoneMigrationMessage>[];
  var roundBytes = 0;
  for (final message in messages) {
    final messageBytes = message.redactedPczt.length + message.id.length;
    // A round cannot be split below one message, so a transaction that alone
    // exceeds the budget can never be encoded. Fail here rather than let the
    // firmware limit reject the request after the user approves the migration.
    if (messageBytes > _keystoneSigningRoundByteBudget) {
      throw StateError(
        'A migration transaction is too large for one Keystone signing '
        'request.',
      );
    }
    final overflowsByteBudget =
        round.isNotEmpty &&
        roundBytes + messageBytes > _keystoneSigningRoundByteBudget;
    if (round.length >= limit || overflowsByteBudget) {
      rounds.add(round);
      round = <rust_sync.KeystoneMigrationMessage>[];
      roundBytes = 0;
    }
    round.add(message);
    roundBytes += messageBytes;
  }
  if (round.isNotEmpty) rounds.add(round);
  return rounds;
}

String _keystoneSigningRoundRequestId(
  String requestId,
  int roundIndex,
  int roundCount,
) {
  if (roundCount <= 1) return requestId;
  return '$requestId-round-${roundIndex + 1}-of-$roundCount';
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

bool _keystoneMigrationRequestMissingError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('request') &&
      (lower.contains('not found') || lower.contains('already used'));
}

@visibleForTesting
String ironwoodMigrationKeystoneSigningErrorMessage(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('batch result request id') &&
      lower.contains('does not match')) {
    return 'This signed QR is from another round. Go back, scan the current '
        'request with Keystone, then scan its new signed QR.';
  }
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
