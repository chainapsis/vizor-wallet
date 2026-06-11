import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/keystone.dart' as rust_keystone_wallet;
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../migration_copy.dart';
import '../models/migration_step_state.dart';
import '../models/migration_view_state.dart';
import '../providers/migration_expected_transfer_count_provider.dart';
import '../providers/migration_run_controller.dart';
import '../providers/orchard_migration_status_provider.dart';
import '../widgets/migration_step_card.dart';

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  static const _keystoneMigrationBatchMaxFragmentLen = 140;

  Timer? _progressRefreshTimer;
  Timer? _submissionProgressTimer;
  Timer? _keystoneProofTimer;
  KeystoneSigningModalPhase? _keystonePhase;
  String? _keystoneError;
  List<String> _keystoneUrParts = const [];
  List<List<String>> _keystoneChunkUrParts = const [];
  _KeystoneMigrationSession? _keystoneSession;
  rust_sync.KeystoneMigrationSigningRequest? _keystoneRequest;
  List<rust_sync.KeystoneSignedMigrationMessage> _keystoneSignedMessages =
      const [];
  int _keystoneChunkIndex = 0;
  int _keystoneChunkTotal = 0;
  bool _keystoneProofReady = false;
  String? _keystoneProofProgress;
  bool _keystoneCompleting = false;
  int _keystoneSessionCounter = 0;

  @override
  void dispose() {
    _progressRefreshTimer?.cancel();
    _submissionProgressTimer?.cancel();
    _keystoneProofTimer?.cancel();
    final requestId = _keystoneRequestId;
    if (requestId != null && !_keystoneCompleting) {
      _discardKeystoneRequest(requestId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountProvider).value;
    final account = accountState?.activeAccount;
    final accountUuid = accountState?.activeAccountUuid;
    final endpoint = ref.watch(rpcEndpointProvider);
    final isHardware = account?.isHardware ?? false;
    final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    final migrationTransactions = _migrationTransactions(
      sync.recentTransactions,
    );
    final expectedTransferCount = ref.watch(
      migrationExpectedTransferCountProvider,
    );
    final scopedExpectedTransferCount = accountUuid == null
        ? null
        : expectedTransferCount[accountUuid];
    final now = DateTime.now();
    final hasUnconfirmedMigration = migrationTransactions.any(
      _isPendingMigration,
    );
    final expectedTransferCountIsFresh =
        scopedExpectedTransferCount != null &&
        (!scopedExpectedTransferCount.isExpired(now) ||
            hasUnconfirmedMigration);
    final freshExpectedTransferCount = expectedTransferCountIsFresh
        ? scopedExpectedTransferCount
        : null;
    final scopedExpectedCount = freshExpectedTransferCount?.count;
    final currentRunMigrationTransactions = _currentRunMigrationTransactions(
      migrationTransactions,
      freshExpectedTransferCount,
    );
    final currentRunCompletedCount = currentRunMigrationTransactions
        .where(_isCompletedMigration)
        .length;
    final expectedMigrationInProgress =
        scopedExpectedCount != null &&
        currentRunCompletedCount < scopedExpectedCount;
    final hasPendingMigration =
        hasUnconfirmedMigration || expectedMigrationInProgress;
    final hasCompletedMigration = migrationTransactions.any(
      _isCompletedMigration,
    );
    final migrationStatusAsync = ref.watch(
      activeOrchardMigrationStatusProvider,
    );
    final migrationStatus = migrationStatusAsync.value;
    final runState = ref.watch(migrationRunControllerProvider);
    final statusIsLoading =
        accountUuid != null &&
        migrationStatus == null &&
        migrationStatusAsync.isLoading;
    final statusError = migrationStatusAsync.error;

    late final Widget body;
    MigrationViewState? viewState;
    if (statusIsLoading) {
      body = const _StatusNote(
        title: MigrationCopy.checkingTitle,
        body: MigrationCopy.checkingBody,
      );
    } else if (accountUuid != null &&
        statusError != null &&
        migrationStatus == null) {
      body = _StatusNote(
        title: MigrationCopy.failedRecoverableTitle,
        body: MigrationCopy.failedRecoverableBody,
        details: statusError.toString(),
        onRetry: () => ref.invalidate(activeOrchardMigrationStatusProvider),
      );
      viewState = MigrationViewState.failedRecoverable;
    } else {
      viewState = migrationViewState(
        rustPhase: migrationStatus?.phase,
        hasPendingMigration: hasPendingMigration,
        hasCompletedMigration: hasCompletedMigration,
        orchardBalance: sync.orchardBalance,
        ironwoodBalance: sync.ironwoodBalance,
      );

      final steps = migrationStepsModel(
        viewState: viewState,
        status: migrationStatus,
        runInFlight: runState.inFlight,
        intent: runState.intent,
      );
      final effectiveExpectedCount =
          migrationStatus != null && migrationStatus.totalCount > 0
          ? migrationStatus.totalCount
          : scopedExpectedCount;

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            MigrationCopy.idleTitle,
            style: AppTypography.displaySmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            MigrationCopy.idleBody,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _stepOneCard(
            steps,
            viewState,
            migrationStatus,
            runState,
            sync,
            isHardware,
          ),
          const SizedBox(height: AppSpacing.s),
          _stepTwoCard(
            steps,
            viewState,
            migrationStatus,
            runState,
            sync,
            currentRunMigrationTransactions,
            effectiveExpectedCount,
            isHardware,
          ),
        ],
      );
    }

    _syncMigrationProgressPolling(
      hasPendingMigration || (viewState?.shouldPollProgress ?? false),
    );
    _syncSubmissionProgressTicker(
      _shouldTickSubmissionProgress(migrationStatus),
    );
    _clearExpiredExpectedTransferCount(
      accountUuid: accountUuid,
      expectedTransferCount: scopedExpectedTransferCount,
      hasPendingMigration:
          hasUnconfirmedMigration || (viewState?.hasActiveRun ?? false),
    );
    _syncKeystoneSessionContext(
      accountUuid: accountUuid,
      networkName: endpoint.walletNetworkName,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: body,
            ),
            if (_keystonePhase != null)
              AppPaneModalOverlay(
                onDismiss: _keystoneCanDismiss
                    ? _cancelKeystoneMigration
                    : () {},
                child: KeystoneSigningModal(
                  phase: _keystonePhase!,
                  urParts: _keystoneUrParts,
                  error: _keystoneError,
                  title: _keystoneModalTitle,
                  subtitle: _keystoneModalSubtitle,
                  instruction: _keystonePhase == KeystoneSigningModalPhase.ready
                      ? _keystoneModalInstruction
                      : null,
                  primaryLabel:
                      _keystonePhase == KeystoneSigningModalPhase.ready
                      ? _keystonePrimaryLabel
                      : null,
                  onPrimary:
                      _keystonePhase == KeystoneSigningModalPhase.ready &&
                          _keystoneProofReady &&
                          !_keystoneCompleting
                      ? () => unawaited(_getKeystoneMigrationSignature())
                      : null,
                  secondaryLabel:
                      _keystonePhase == KeystoneSigningModalPhase.preparing ||
                          _keystoneCompleting
                      ? null
                      : 'Reject',
                  onSecondary: _cancelKeystoneMigration,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String get _keystoneModalTitle {
    final chunkLabel = _keystoneChunkLabel;
    return switch (_keystoneIntent) {
      MigrationRunIntent.preparing => 'Sign migration on your Keystone',
      MigrationRunIntent.migrating when chunkLabel != null =>
        'Sign migration $chunkLabel',
      MigrationRunIntent.migrating => 'Sign migration on your Keystone',
      _ => 'Sign on your Keystone',
    };
  }

  String get _keystoneModalSubtitle {
    final chunkLabel = _keystoneChunkLabel;
    if (_keystoneIntent == MigrationRunIntent.migrating && chunkLabel != null) {
      return 'Keystone QR $chunkLabel';
    }
    return 'Scan the QR code to sign';
  }

  String get _keystoneModalInstruction {
    if (!_keystoneProofReady) {
      final progress = _keystoneProofProgress;
      return progress == null
          ? 'Scan now. Signature import unlocks after proofs are ready.'
          : 'Scan now. Signature import unlocks after proofs are ready. $progress';
    }
    final chunkLabel = _keystoneChunkLabel;
    if (_keystoneIntent == MigrationRunIntent.migrating && chunkLabel != null) {
      return 'After this signature is ready, scan it back into Vizor.';
    }
    return 'After you scanned, click Get signature.';
  }

  String get _keystonePrimaryLabel {
    if (!_keystoneProofReady) return 'Preparing';
    final chunkLabel = _keystoneChunkLabel;
    if (_keystoneIntent == MigrationRunIntent.migrating && chunkLabel != null) {
      return 'Get signature $chunkLabel';
    }
    return 'Get signature';
  }

  bool get _keystoneCanDismiss => !_keystoneCompleting;

  String? get _keystoneRequestId => _keystoneSession?.requestId;

  MigrationRunIntent? get _keystoneIntent => _keystoneSession?.intent;

  String? get _keystoneChunkLabel {
    if (_keystoneChunkTotal <= 1) return null;
    return '${_keystoneChunkIndex + 1} of $_keystoneChunkTotal';
  }

  void _syncKeystoneSessionContext({
    required String? accountUuid,
    required String networkName,
    required String lightwalletdUrl,
  }) {
    if (_keystonePhase == null || _keystoneCompleting) return;
    final session = _keystoneSession;
    if (session == null || !session.hasContext) return;
    if (session.matchesContext(
      accountUuid: accountUuid,
      networkName: networkName,
      lightwalletdUrl: lightwalletdUrl,
    )) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _keystonePhase == null || _keystoneCompleting) return;
      if (_keystoneSession?.generation == session.generation) {
        _clearKeystoneMigration(discardRequest: true);
      }
    });
  }

  bool _keystoneSessionIdentityIsCurrent(_KeystoneMigrationSession expected) {
    final session = _keystoneSession;
    if (!mounted ||
        _keystonePhase == null ||
        session == null ||
        !session.sameRun(expected)) {
      return false;
    }
    if (!expected.hasContext) return true;
    final currentAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    final currentEndpoint = ref.read(rpcEndpointProvider);
    return expected.matchesContext(
      accountUuid: currentAccountUuid,
      networkName: currentEndpoint.walletNetworkName,
      lightwalletdUrl: currentEndpoint.normalizedLightwalletdUrl,
    );
  }

  bool _keystoneSessionIsCurrent(_KeystoneMigrationSession expected) {
    final session = _keystoneSession;
    return expected.hasRequestContext &&
        session != null &&
        session.sameRequest(expected) &&
        _keystoneSessionIdentityIsCurrent(expected);
  }

  void _discardKeystoneRequest(String requestId) {
    unawaited(rust_sync.discardKeystoneMigrationRequest(requestId: requestId));
  }

  Future<void> _advanceMigration(
    MigrationRunIntent intent,
    bool isHardware,
  ) async {
    if (!isHardware) {
      await ref.read(migrationRunControllerProvider.notifier).advance(intent);
      return;
    }

    _showKeystoneMigration(intent);
  }

  void _showKeystoneMigration(MigrationRunIntent intent) {
    if (_keystonePhase != null) return;
    final session = _KeystoneMigrationSession(
      generation: ++_keystoneSessionCounter,
      intent: intent,
    );
    setState(() {
      _keystonePhase = KeystoneSigningModalPhase.preparing;
      _keystoneError = null;
      _keystoneUrParts = const [];
      _keystoneChunkUrParts = const [];
      _keystoneSession = session;
      _keystoneRequest = null;
      _keystoneSignedMessages = const [];
      _keystoneChunkIndex = 0;
      _keystoneChunkTotal = 0;
      _keystoneProofReady = false;
      _keystoneProofProgress = null;
      _keystoneCompleting = false;
    });
    unawaited(_prepareKeystoneMigration(session));
  }

  Future<void> _prepareKeystoneMigration(
    _KeystoneMigrationSession session,
  ) async {
    final intent = session.intent;
    var activeSession = session;
    String? preparedRequestId;
    try {
      final accountState = ref.read(accountProvider).value;
      final account = accountState?.activeAccount;
      final accountUuid = accountState?.activeAccountUuid;
      if (account == null || accountUuid == null) {
        throw const _KeystoneMigrationError('No active account.');
      }
      if (!account.isHardware) {
        throw const _KeystoneMigrationError(
          'Keystone migration requires a hardware account.',
        );
      }

      final endpoint = ref.read(rpcEndpointProvider);
      if (endpoint.network != ZcashNetwork.testnet) {
        throw const _KeystoneMigrationError(
          'Select a testnet endpoint before migrating.',
        );
      }
      final networkName = endpoint.walletNetworkName;
      final lightwalletdUrl = endpoint.normalizedLightwalletdUrl;
      if (!_keystoneSessionIdentityIsCurrent(session)) {
        return;
      }
      activeSession = session.withContext(
        accountUuid: accountUuid,
        networkName: networkName,
        lightwalletdUrl: lightwalletdUrl,
      );
      setState(() {
        _keystoneSession = activeSession;
      });

      final dbPath = await getWalletDbPath();
      final syncNotifier = ref.read(syncProvider.notifier);
      final syncPause = await syncNotifier.pauseForWalletMutation(
        onStoppingSync: () {
          log('MigrationScreen: pausing sync before Keystone migration prep');
        },
      );

      late final rust_sync.KeystoneMigrationSigningRequest request;
      try {
        request = switch (intent) {
          MigrationRunIntent.preparing =>
            await rust_sync.prepareOrchardMigrationSingleQrPczt(
              dbPath: dbPath,
              network: networkName,
              accountUuid: accountUuid,
            ),
          MigrationRunIntent.migrating =>
            await rust_sync.prepareOrchardMigrationBatchPczt(
              dbPath: dbPath,
              network: networkName,
              accountUuid: accountUuid,
            ),
          _ => throw const _KeystoneMigrationError(
            'Unsupported Keystone migration step.',
          ),
        };
      } finally {
        syncNotifier.resumeAfterWalletMutation(syncPause);
      }
      preparedRequestId = request.requestId;
      final preparedSession = activeSession.withRequestId(request.requestId);
      if (!_keystoneSessionIdentityIsCurrent(activeSession)) {
        _discardKeystoneRequest(request.requestId);
        return;
      }
      setState(() {
        _keystoneSession = preparedSession;
        _keystoneRequest = request;
      });

      final chunkTotal = _keystoneChunkCount(request);
      if (chunkTotal == 0) {
        throw const _KeystoneMigrationError(
          'Keystone migration request has no messages.',
        );
      }
      final chunkUrParts = await _encodeKeystoneMigrationChunks(request);
      final urParts = chunkUrParts.first;
      log(
        'MigrationScreen: encoded Keystone migration batch '
        '1/$chunkTotal with ${_keystoneChunkMessages(request, 0).length} '
        'of ${request.messages.length} messages into ${urParts.length} UR parts',
      );

      if (!_keystoneSessionIsCurrent(preparedSession)) {
        _discardKeystoneRequest(request.requestId);
        return;
      }
      setState(() {
        _keystonePhase = KeystoneSigningModalPhase.ready;
        _keystoneSignedMessages = const [];
        _keystoneChunkIndex = 0;
        _keystoneChunkTotal = chunkTotal;
        _keystoneUrParts = urParts;
        _keystoneChunkUrParts = chunkUrParts;
        _keystoneProofReady = false;
        _keystoneProofProgress = null;
      });
      _startKeystoneProofPolling(preparedSession);
    } catch (e, st) {
      log('MigrationScreen._prepareKeystoneMigration: ERROR: $e\n$st');
      if (preparedRequestId != null && !_keystoneCompleting) {
        _discardKeystoneRequest(preparedRequestId);
      }
      if (!_keystoneSessionIdentityIsCurrent(activeSession)) {
        return;
      }
      setState(() {
        _keystonePhase = KeystoneSigningModalPhase.failed;
        _keystoneCompleting = false;
        _keystoneSession = activeSession.withoutRequestId();
        _keystoneRequest = null;
        _keystoneError = _friendlyKeystoneError(e);
      });
    }
  }

  void _startKeystoneProofPolling(_KeystoneMigrationSession session) {
    _keystoneProofTimer?.cancel();
    final requestId = session.requestId;
    if (requestId == null) return;

    Future<void> poll() async {
      try {
        final status = await rust_sync.keystoneMigrationProofStatus(
          requestId: requestId,
        );
        if (!_keystoneSessionIsCurrent(session)) {
          return;
        }

        if (status.isFailed) {
          _keystoneProofTimer?.cancel();
          setState(() {
            _keystonePhase = KeystoneSigningModalPhase.failed;
            _keystoneProofReady = false;
            _keystoneProofProgress = null;
            _keystoneError =
                status.message ??
                'Vizor proof generation failed. Reject and prepare a new request.';
          });
          return;
        }

        if (status.isReady) {
          _keystoneProofTimer?.cancel();
          setState(() {
            _keystoneProofReady = true;
            _keystoneProofProgress = null;
          });
          return;
        }

        setState(() {
          _keystoneProofProgress =
              'Proofs ${status.readyCount} of ${status.totalCount}.';
        });
      } catch (e, st) {
        log('MigrationScreen._startKeystoneProofPolling: ERROR: $e\n$st');
        if (!_keystoneSessionIsCurrent(session)) {
          return;
        }
        _keystoneProofTimer?.cancel();
        setState(() {
          _keystonePhase = KeystoneSigningModalPhase.failed;
          _keystoneProofReady = false;
          _keystoneProofProgress = null;
          _keystoneError = _friendlyKeystoneError(e);
        });
      }
    }

    unawaited(poll());
    _keystoneProofTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(poll()),
    );
  }

  Future<void> _getKeystoneMigrationSignature() async {
    final request = _keystoneRequest;
    final session = _keystoneSession;
    if (_keystonePhase != KeystoneSigningModalPhase.ready ||
        request == null ||
        session == null ||
        !session.hasRequestContext ||
        !_keystoneProofReady ||
        _keystoneCompleting) {
      return;
    }

    final chunkIndex = _keystoneChunkIndex;
    final cbor = await context.push<Uint8List>('/migration/scan');
    if (cbor == null || !_keystoneSessionIsCurrent(session)) {
      return;
    }

    setState(() {
      _keystonePhase = KeystoneSigningModalPhase.preparing;
      _keystoneError = null;
    });

    try {
      final result = await rust_keystone.decodeZcashSignResultCbor(cbor: cbor);
      if (!_keystoneSessionIsCurrent(session)) {
        return;
      }
      if (result.requestId != request.requestId) {
        throw _KeystoneMigrationError(
          'Signed result is for ${result.requestId}, expected ${request.requestId}.',
        );
      }
      final signedMessages = result.results
          .map(
            (message) => rust_sync.KeystoneSignedMigrationMessage(
              id: message.id,
              signedPczt: message.signedPcztBytes,
            ),
          )
          .toList(growable: false);

      final signedForChunk = _validateKeystoneSignedChunk(
        request: request,
        chunkIndex: chunkIndex,
        signedMessages: signedMessages,
      );
      final allSignedMessages = [..._keystoneSignedMessages, ...signedForChunk];
      final nextChunkIndex = chunkIndex + 1;
      if (nextChunkIndex < _keystoneChunkTotal) {
        final nextUrParts = _keystoneChunkUrParts[nextChunkIndex];
        if (!_keystoneSessionIsCurrent(session)) {
          return;
        }
        setState(() {
          _keystonePhase = KeystoneSigningModalPhase.preparing;
          _keystoneError = null;
          _keystoneUrParts = const [];
          _keystoneSignedMessages = allSignedMessages;
          _keystoneChunkIndex = nextChunkIndex;
        });

        log(
          'MigrationScreen: encoded Keystone migration batch '
          '${nextChunkIndex + 1}/$_keystoneChunkTotal with '
          '${_keystoneChunkMessages(request, nextChunkIndex).length} '
          'of ${request.messages.length} messages into '
          '${nextUrParts.length} UR parts',
        );
        if (!_keystoneSessionIsCurrent(session)) {
          return;
        }
        setState(() {
          _keystonePhase = KeystoneSigningModalPhase.ready;
          _keystoneUrParts = nextUrParts;
        });
        return;
      }

      await _completeKeystoneMigration(
        session: session,
        signedMessages: allSignedMessages,
      );
    } catch (e, st) {
      log('MigrationScreen._getKeystoneMigrationSignature: ERROR: $e\n$st');
      if (!_keystoneSessionIsCurrent(session)) {
        if (mounted &&
            _keystoneCompleting &&
            _keystoneSession?.sameRequest(session) == true) {
          _clearKeystoneMigration(
            discardRequest: true,
            discardCompletingRequest: true,
          );
        }
        return;
      }
      setState(() {
        _keystonePhase = KeystoneSigningModalPhase.failed;
        _keystoneCompleting = false;
        _keystoneError = _friendlyKeystoneError(e);
      });
    }
  }

  Future<void> _completeKeystoneMigration({
    required _KeystoneMigrationSession session,
    required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  }) async {
    final requestId = session.requestId;
    final accountUuid = session.accountUuid;
    final networkName = session.networkName;
    final lightwalletdUrl = session.lightwalletdUrl;
    if (requestId == null ||
        accountUuid == null ||
        networkName == null ||
        lightwalletdUrl == null) {
      return;
    }

    final dbPath = await getWalletDbPath();
    if (!_keystoneSessionIsCurrent(session)) {
      if (mounted && _keystoneSession?.sameRequest(session) == true) {
        _clearKeystoneMigration(discardRequest: true);
      }
      return;
    }
    final syncNotifier = ref.read(syncProvider.notifier);
    final syncPause = await syncNotifier.pauseForWalletMutation(
      onStoppingSync: () {
        log('MigrationScreen: pausing sync before Keystone migration commit');
      },
    );
    if (!_keystoneSessionIsCurrent(session)) {
      syncNotifier.resumeAfterWalletMutation(syncPause);
      if (mounted && _keystoneSession?.sameRequest(session) == true) {
        _clearKeystoneMigration(discardRequest: true);
      }
      return;
    }

    late final rust_sync.IronwoodMigrationResult result;
    setState(() {
      _keystoneCompleting = true;
      _keystonePhase = KeystoneSigningModalPhase.preparing;
      _keystoneError = null;
    });
    try {
      result = switch (session.intent) {
        MigrationRunIntent.preparing => await () async {
          final security = ref.read(appSecurityProvider.notifier);
          final password = security.requireSessionPasswordForNativeSecretUse();
          final saltBase64 = await security
              .requireSecretPayloadSaltForNativeSecretUse();
          return rust_sync.completeOrchardMigrationSingleQrPczt(
            dbPath: dbPath,
            lightwalletdUrl: lightwalletdUrl,
            network: networkName,
            accountUuid: accountUuid,
            requestId: requestId,
            signedMessages: signedMessages,
            password: password,
            saltBase64: saltBase64,
          );
        }(),
        MigrationRunIntent.migrating => await () async {
          final security = ref.read(appSecurityProvider.notifier);
          final password = security.requireSessionPasswordForNativeSecretUse();
          final saltBase64 = await security
              .requireSecretPayloadSaltForNativeSecretUse();
          return rust_sync.completeOrchardMigrationBatchPczt(
            dbPath: dbPath,
            network: networkName,
            accountUuid: accountUuid,
            requestId: requestId,
            signedMessages: signedMessages,
            password: password,
            saltBase64: saltBase64,
          );
        }(),
        _ => throw const _KeystoneMigrationError(
          'Unsupported Keystone migration step.',
        ),
      };
    } finally {
      syncNotifier.resumeAfterWalletMutation(syncPause);
    }
    if (!_keystoneSessionIsCurrent(session)) {
      if (mounted && _keystoneSession?.sameRequest(session) == true) {
        _clearKeystoneMigration(discardRequest: false);
      }
      return;
    }

    log(
      'MigrationScreen: Keystone intent=${session.intent.name} '
      'txids=${result.txids} status=${result.status} '
      'broadcasted=${result.broadcastedCount}/${result.totalCount} '
      'fee=${result.feeZatoshi} migrated=${result.migratedZatoshi}',
    );

    final firstTxid = _firstTxid(result.txids);
    if (result.totalCount > 0 && firstTxid != null) {
      ref
          .read(migrationExpectedTransferCountProvider.notifier)
          .setCount(accountUuid, result.totalCount, firstTxid: firstTxid);
    }

    if (!migrationRunAdvanced(result)) {
      throw _KeystoneMigrationError(
        result.message ?? MigrationCopy.partialBroadcastError,
      );
    }

    await ref
        .read(syncProvider.notifier)
        .refreshAfterSend(
          transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
        );
    ref.invalidate(activeOrchardMigrationStatusProvider);

    if (!mounted) return;
    _clearKeystoneMigration(discardRequest: false);
  }

  void _cancelKeystoneMigration() {
    if (!mounted) return;
    _clearKeystoneMigration(discardRequest: true);
  }

  void _clearKeystoneMigration({
    required bool discardRequest,
    bool discardCompletingRequest = false,
  }) {
    final requestId = _keystoneRequestId;
    _keystoneProofTimer?.cancel();
    _keystoneProofTimer = null;
    _keystoneSessionCounter++;
    if (discardRequest &&
        requestId != null &&
        (!_keystoneCompleting || discardCompletingRequest)) {
      _discardKeystoneRequest(requestId);
    }
    setState(() {
      _keystonePhase = null;
      _keystoneError = null;
      _keystoneUrParts = const [];
      _keystoneChunkUrParts = const [];
      _keystoneSession = null;
      _keystoneRequest = null;
      _keystoneSignedMessages = const [];
      _keystoneChunkIndex = 0;
      _keystoneChunkTotal = 0;
      _keystoneProofReady = false;
      _keystoneProofProgress = null;
      _keystoneCompleting = false;
    });
  }

  int _keystoneBatchLimit(rust_sync.KeystoneMigrationSigningRequest request) {
    final limit = request.signingBatchLimit;
    if (limit <= 0) {
      throw const _KeystoneMigrationError(
        'Keystone migration request has an invalid signing batch limit.',
      );
    }
    return limit;
  }

  int _keystoneChunkCount(rust_sync.KeystoneMigrationSigningRequest request) {
    if (request.messages.isEmpty) return 0;
    final limit = _keystoneBatchLimit(request);
    return ((request.messages.length - 1) ~/ limit) + 1;
  }

  List<rust_sync.KeystoneMigrationMessage> _keystoneChunkMessages(
    rust_sync.KeystoneMigrationSigningRequest request,
    int chunkIndex,
  ) {
    final limit = _keystoneBatchLimit(request);
    final start = chunkIndex * limit;
    if (start < 0 || start >= request.messages.length) {
      throw _KeystoneMigrationError(
        'Keystone migration batch ${chunkIndex + 1} is out of range.',
      );
    }
    final uncappedEnd = start + limit;
    final end = uncappedEnd > request.messages.length
        ? request.messages.length
        : uncappedEnd;
    return request.messages.sublist(start, end);
  }

  Future<List<List<String>>> _encodeKeystoneMigrationChunks(
    rust_sync.KeystoneMigrationSigningRequest request,
  ) async {
    final chunkTotal = _keystoneChunkCount(request);
    final chunks = <List<String>>[];
    for (var chunkIndex = 0; chunkIndex < chunkTotal; chunkIndex++) {
      chunks.add(await _encodeKeystoneMigrationChunk(request, chunkIndex));
    }
    return chunks;
  }

  Future<List<String>> _encodeKeystoneMigrationChunk(
    rust_sync.KeystoneMigrationSigningRequest request,
    int chunkIndex,
  ) {
    final messages = _keystoneChunkMessages(request, chunkIndex);
    return rust_keystone.encodeZcashSignBatchUrParts(
      requestId: request.requestId,
      messages: messages
          .map(
            (message) => rust_keystone_wallet.ZcashBatchMessageInput(
              id: message.id,
              pcztBytes: message.redactedPczt,
            ),
          )
          .toList(growable: false),
      maxFragmentLen: BigInt.from(_keystoneMigrationBatchMaxFragmentLen),
    );
  }

  List<rust_sync.KeystoneSignedMigrationMessage> _validateKeystoneSignedChunk({
    required rust_sync.KeystoneMigrationSigningRequest request,
    required int chunkIndex,
    required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  }) {
    final expectedIds = _keystoneChunkMessages(
      request,
      chunkIndex,
    ).map((message) => message.id).toSet();
    if (signedMessages.length != expectedIds.length) {
      throw _KeystoneMigrationError(
        'Keystone returned ${signedMessages.length} signed messages for '
        '${expectedIds.length} requested messages.',
      );
    }

    final seenIds = <String>{};
    for (final message in signedMessages) {
      if (!expectedIds.contains(message.id)) {
        throw _KeystoneMigrationError(
          'Keystone returned an unexpected signed migration message.',
        );
      }
      if (!seenIds.add(message.id)) {
        throw _KeystoneMigrationError(
          'Keystone returned duplicate signed migration message ${message.id}.',
        );
      }
    }
    return signedMessages;
  }

  String? _firstTxid(String txids) {
    for (final txid in txids.split(',')) {
      final trimmed = txid.trim();
      if (trimmed.isNotEmpty) return trimmed.toLowerCase();
    }
    return null;
  }

  String _friendlyKeystoneError(Object error) {
    if (error is _KeystoneMigrationError) return error.message;
    final lower = error.toString().toLowerCase();
    if (lower.contains('insufficient') || lower.contains('spendable')) {
      return 'Receive enough Orchard funds, let Vizor sync, then try again.';
    }
    if (lower.contains('sync') || lower.contains('scan required')) {
      return 'Sync the wallet before migrating.';
    }
    if (lower.contains('unexpected ur type')) {
      return 'Open the signed migration QR on Keystone, then scan again.';
    }
    return '${error.runtimeType}: $error';
  }

  Widget _stepOneCard(
    MigrationStepsModel steps,
    MigrationViewState viewState,
    rust_sync.MigrationStatus? status,
    MigrationRunState runState,
    SyncState sync,
    bool isHardware,
  ) {
    final errorBanner = runState.errorIntent == MigrationRunIntent.preparing
        ? runState.error
        : null;

    return switch (steps.stepOne) {
      MigrationStepOneState.blocked => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        isDimmed: true,
        statusLine: viewState == MigrationViewState.noOrchardFunds
            ? MigrationCopy.stepOneNoFunds
            : MigrationCopy.stepOneUnspendable,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.stepOneCta,
        onCta: null,
      ),
      MigrationStepOneState.active => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        statusLine: MigrationCopy.stepOneBody,
        errorBanner: errorBanner,
        body: [_readyAmount(sync)],
        ctaLabel: MigrationCopy.stepOneCta,
        onCta: () => unawaited(
          _advanceMigration(MigrationRunIntent.preparing, isHardware),
        ),
      ),
      MigrationStepOneState.running => const MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        showSpinner: true,
        statusLine: MigrationCopy.stepOneRunning,
      ),
      MigrationStepOneState.waiting => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        showSpinner: true,
        statusLine: MigrationCopy.stepOneWaitingConfirmations(
          _boundedConfirmationCount(status),
          _denominationConfirmationTarget(status),
        ),
        errorBanner: errorBanner,
        body: [
          if (status != null && status.totalCount > 0)
            Text(
              MigrationCopy.stepOnePreparedCounts(
                status.preparedNoteCount,
                status.totalCount,
              ),
              style: AppTypography.bodyExtraSmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
        ],
      ),
      MigrationStepOneState.done => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        isDone: true,
        statusLine: status != null && status.totalCount > 0
            ? MigrationCopy.stepOneDone(status.totalCount)
            : MigrationCopy.stepOneDoneGeneric,
      ),
      MigrationStepOneState.error => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        statusLine: status?.message ?? MigrationCopy.failedRecoverableBody,
        statusIsError: true,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.retryCta,
        onCta: () => unawaited(
          _advanceMigration(MigrationRunIntent.preparing, isHardware),
        ),
      ),
    };
  }

  int _denominationConfirmationTarget(rust_sync.MigrationStatus? status) {
    final target = status?.denominationConfirmationTarget ?? 3;
    return target <= 0 ? 3 : target;
  }

  int _boundedConfirmationCount(rust_sync.MigrationStatus? status) {
    final target = _denominationConfirmationTarget(status);
    final count = status?.denominationConfirmationCount ?? 0;
    return count.clamp(0, target).toInt();
  }

  Widget _stepTwoCard(
    MigrationStepsModel steps,
    MigrationViewState viewState,
    rust_sync.MigrationStatus? status,
    MigrationRunState runState,
    SyncState sync,
    List<rust_sync.TransactionInfo> currentRunMigrationTransactions,
    int? effectiveExpectedCount,
    bool isHardware,
  ) {
    final errorBanner = runState.errorIntent == MigrationRunIntent.migrating
        ? runState.error
        : null;
    final total = status?.totalCount ?? 0;
    final submissionProgress = _scheduleSubmissionProgress(status);
    void startMigration() =>
        unawaited(_advanceMigration(MigrationRunIntent.migrating, isHardware));

    return switch (steps.stepTwo) {
      MigrationStepTwoState.locked => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        isDimmed: true,
        statusLine: MigrationCopy.stepTwoLocked,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.stepTwoCta,
        onCta: null,
      ),
      MigrationStepTwoState.ready => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: MigrationCopy.stepTwoReady(
          total,
          MigrationCopy.migrationWindowText(
            (status?.broadcastWindowSeconds ?? BigInt.from(60)).toInt(),
          ),
        ),
        errorBanner: errorBanner,
        body: [
          if (viewState == MigrationViewState.paused)
            Text(
              MigrationCopy.stepTwoPausedNote,
              style: AppTypography.bodyExtraSmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
        ],
        ctaLabel: MigrationCopy.stepTwoCta,
        onCta: startMigration,
      ),
      MigrationStepTwoState.running => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        showSpinner: _stepTwoShowsSpinner(status, runState),
        statusLine: _stepTwoRunningLine(status),
        progress: submissionProgress,
        body: [
          if (status != null && status.scheduledBroadcasts.isNotEmpty)
            _ScheduledBroadcastsList(broadcasts: status.scheduledBroadcasts),
        ],
      ),
      MigrationStepTwoState.confirming => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: MigrationCopy.inProgressBody,
        progress: submissionProgress ?? 1,
        body: [
          _MigrationTransfersList(
            migrationTransactions: currentRunMigrationTransactions,
            expectedTransferCount: effectiveExpectedCount,
            amountZatoshi: _migrationDisplayAmount(
              sync,
              currentRunMigrationTransactions,
            ),
          ),
        ],
      ),
      MigrationStepTwoState.done => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        isDone: true,
        statusLine: MigrationCopy.doneBody,
      ),
      MigrationStepTwoState.error => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: switch (viewState) {
          MigrationViewState.failedTerminal =>
            status?.message ?? MigrationCopy.failedTerminalBody,
          MigrationViewState.abandoned => MigrationCopy.abandonedBody,
          _ => status?.message ?? MigrationCopy.failedRecoverableBody,
        },
        statusIsError: true,
        errorBanner: errorBanner,
        ctaLabel: viewState == MigrationViewState.failedRecoverable
            ? MigrationCopy.retryCta
            : null,
        onCta: viewState == MigrationViewState.failedRecoverable
            ? startMigration
            : null,
      ),
    };
  }

  String _stepTwoRunningLine(rust_sync.MigrationStatus? status) {
    final total = status?.totalCount ?? 0;
    if (status?.phase == 'broadcast_scheduled') {
      final nextScheduled = _nextScheduledBroadcast(status);
      if (nextScheduled == null) return MigrationCopy.stepTwoScheduledWaiting;
      final scheduledAt = DateTime.fromMillisecondsSinceEpoch(
        nextScheduled.scheduledAtMs.toInt(),
      );
      return MigrationCopy.stepTwoScheduled(
        _remainingSubmissionText(scheduledAt),
      );
    }
    if (status?.phase == 'broadcasting' && total > 0) {
      final next = ((status?.broadcastedTxCount ?? 0) + 1).clamp(1, total);
      return MigrationCopy.stepTwoSubmitting(next, total);
    }
    return MigrationCopy.stepTwoSigning;
  }

  bool _stepTwoShowsSpinner(
    rust_sync.MigrationStatus? status,
    MigrationRunState runState,
  ) {
    if (runState.inFlight) return true;
    if (status?.phase == 'ready_to_migrate' &&
        migrationHasSignedChildPczts(status)) {
      return true;
    }
    return status?.phase == 'building_signing_batch' ||
        status?.phase == 'signing_batch' ||
        status?.phase == 'broadcasting';
  }

  rust_sync.MigrationScheduledBroadcast? _nextScheduledBroadcast(
    rust_sync.MigrationStatus? status,
  ) {
    final scheduled = status?.scheduledBroadcasts.where(
      (broadcast) => broadcast.status == 'scheduled',
    );
    if (scheduled == null || scheduled.isEmpty) return null;
    return scheduled.first;
  }

  String _remainingSubmissionText(DateTime scheduledAt) {
    final remaining = scheduledAt.difference(DateTime.now());
    if (remaining.inSeconds <= 0) return 'now';
    return 'in ${migrationCountdownLabel(remaining)}';
  }

  double? _scheduleSubmissionProgress(rust_sync.MigrationStatus? status) {
    final broadcasts = status?.scheduledBroadcasts;
    if (broadcasts == null || broadcasts.isEmpty) return null;
    final scheduledTimes = broadcasts
        .map(
          (broadcast) => DateTime.fromMillisecondsSinceEpoch(
            broadcast.scheduledAtMs.toInt(),
          ),
        )
        .toList(growable: false);
    final firstScheduledAt = scheduledTimes.reduce(
      (a, b) => a.isBefore(b) ? a : b,
    );
    final lastScheduledAt = scheduledTimes.reduce(
      (a, b) => a.isAfter(b) ? a : b,
    );
    final total = lastScheduledAt.difference(firstScheduledAt).inMilliseconds;
    if (total <= 0) return 1;
    final elapsed = DateTime.now().difference(firstScheduledAt).inMilliseconds;
    return (elapsed / total).clamp(0, 1).toDouble();
  }

  Widget _readyAmount(SyncState sync) {
    final amount = ZecAmount.fromZatoshi(
      sync.orchardBalance,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.readyToMigrateLabel,
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          amount,
          key: const ValueKey('migration_ready_amount'),
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          MigrationCopy.poolFlow,
          style: AppTypography.bodyExtraSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }

  void _syncMigrationProgressPolling(bool enabled) {
    if (enabled && _progressRefreshTimer == null) {
      _progressRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_refreshMigrationProgress());
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_refreshMigrationProgress());
      });
      return;
    }

    if (!enabled && _progressRefreshTimer != null) {
      _progressRefreshTimer?.cancel();
      _progressRefreshTimer = null;
    }
  }

  void _syncSubmissionProgressTicker(bool enabled) {
    if (enabled && _submissionProgressTimer == null) {
      _submissionProgressTimer = Timer.periodic(const Duration(seconds: 1), (
        _,
      ) {
        if (!mounted) return;
        setState(() {});
      });
      return;
    }

    if (!enabled && _submissionProgressTimer != null) {
      _submissionProgressTimer?.cancel();
      _submissionProgressTimer = null;
    }
  }

  bool _shouldTickSubmissionProgress(rust_sync.MigrationStatus? status) {
    final progress = _scheduleSubmissionProgress(status);
    return progress != null && progress < 1;
  }

  Future<void> _refreshMigrationProgress() async {
    try {
      await ref
          .read(syncProvider.notifier)
          .refreshAfterSend(
            transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
          );
    } catch (e) {
      log('MigrationScreen: migration progress refresh failed: $e');
    }
  }

  void _clearExpiredExpectedTransferCount({
    required String? accountUuid,
    required MigrationExpectedTransferCount? expectedTransferCount,
    required bool hasPendingMigration,
  }) {
    if (accountUuid == null ||
        expectedTransferCount == null ||
        hasPendingMigration ||
        !expectedTransferCount.isExpired(DateTime.now())) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(migrationExpectedTransferCountProvider.notifier)
          .clearCount(accountUuid);
    });
  }
}

List<rust_sync.TransactionInfo> _migrationTransactions(
  Iterable<rust_sync.TransactionInfo> transactions,
) {
  return transactions
      .where((tx) => tx.txKind == 'migration')
      .toList(growable: false);
}

List<rust_sync.TransactionInfo> _currentRunMigrationTransactions(
  List<rust_sync.TransactionInfo> migrationTransactions,
  MigrationExpectedTransferCount? expectedTransferCount,
) {
  final firstTxid = expectedTransferCount?.firstTxid.toLowerCase();
  if (firstTxid == null) return migrationTransactions;

  final firstTxIndex = migrationFirstTransactionIndex(
    transactionTxids: migrationTransactions.map((tx) => tx.txidHex),
    firstTxid: firstTxid,
  );
  if (firstTxIndex < 0) return const [];

  return migrationTransactions.take(firstTxIndex + 1).toList(growable: false);
}

bool _isPendingMigration(rust_sync.TransactionInfo tx) =>
    tx.minedHeight == BigInt.zero && !tx.expiredUnmined;

bool _isCompletedMigration(rust_sync.TransactionInfo tx) =>
    tx.minedHeight != BigInt.zero && !tx.expiredUnmined;

BigInt _migrationDisplayAmount(
  SyncState sync,
  List<rust_sync.TransactionInfo> migrationTransactions,
) {
  final txAmount = migrationTransactions.fold<BigInt>(
    BigInt.zero,
    (sum, tx) => sum + tx.displayAmount,
  );
  if (txAmount > BigInt.zero) return txAmount;
  return sync.orchardBalance;
}

class _ScheduledBroadcastsList extends StatelessWidget {
  const _ScheduledBroadcastsList({required this.broadcasts});

  final List<rust_sync.MigrationScheduledBroadcast> broadcasts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final total = broadcasts.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0)
            Divider(height: AppSpacing.md, color: colors.border.subtle),
          _ScheduledBroadcastRow(
            index: i,
            total: total,
            broadcast: broadcasts[i],
            now: now,
          ),
        ],
      ],
    );
  }
}

class _ScheduledBroadcastRow extends StatelessWidget {
  const _ScheduledBroadcastRow({
    required this.index,
    required this.total,
    required this.broadcast,
    required this.now,
  });

  final int index;
  final int total;
  final rust_sync.MigrationScheduledBroadcast broadcast;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheduledAt = DateTime.fromMillisecondsSinceEpoch(
      broadcast.scheduledAtMs.toInt(),
    );
    final status = _scheduledBroadcastStatus(broadcast.status, scheduledAt);
    final icon = switch (status.kind) {
      _ScheduledBroadcastKind.scheduled => AppIcons.time,
      _ScheduledBroadcastKind.submitted => AppIcons.checkCircle,
      _ScheduledBroadcastKind.confirmed => AppIcons.checkCircle,
      _ScheduledBroadcastKind.failed => AppIcons.warning,
    };
    final iconColor = switch (status.kind) {
      _ScheduledBroadcastKind.scheduled => colors.icon.muted,
      _ScheduledBroadcastKind.submitted => colors.icon.success,
      _ScheduledBroadcastKind.confirmed => colors.icon.success,
      _ScheduledBroadcastKind.failed => colors.icon.destructive,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(icon, size: AppIconSize.medium, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MigrationCopy.scheduledSubmissionLabel(index + 1, total),
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Scheduled for ${_clockTime(scheduledAt)}',
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Text(
          status.label,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }

  _ScheduledBroadcastStatus _scheduledBroadcastStatus(
    String status,
    DateTime scheduledAt,
  ) {
    return switch (status) {
      'scheduled' => _ScheduledBroadcastStatus(
        scheduledAt.isAfter(now)
            ? _durationUntilLabel(scheduledAt, now)
            : 'Due now',
        _ScheduledBroadcastKind.scheduled,
      ),
      'broadcasted' => const _ScheduledBroadcastStatus(
        'Submitted',
        _ScheduledBroadcastKind.submitted,
      ),
      'confirmed' => const _ScheduledBroadcastStatus(
        'Confirmed',
        _ScheduledBroadcastKind.confirmed,
      ),
      _ => const _ScheduledBroadcastStatus(
        'Needs attention',
        _ScheduledBroadcastKind.failed,
      ),
    };
  }
}

enum _ScheduledBroadcastKind { scheduled, submitted, confirmed, failed }

class _ScheduledBroadcastStatus {
  const _ScheduledBroadcastStatus(this.label, this.kind);

  final String label;
  final _ScheduledBroadcastKind kind;
}

String _clockTime(DateTime time) {
  return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:'
      '${_twoDigits(time.second)}';
}

String _durationUntilLabel(DateTime future, DateTime now) {
  final remaining = future.difference(now);
  if (remaining.inSeconds <= 0) return 'Due now';
  return 'in ${migrationCountdownLabel(remaining)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class _KeystoneMigrationError {
  const _KeystoneMigrationError(this.message);

  final String message;

  @override
  String toString() => message;
}

class _KeystoneMigrationSession {
  const _KeystoneMigrationSession({
    required this.generation,
    required this.intent,
    this.requestId,
    this.accountUuid,
    this.networkName,
    this.lightwalletdUrl,
  });

  final int generation;
  final MigrationRunIntent intent;
  final String? requestId;
  final String? accountUuid;
  final String? networkName;
  final String? lightwalletdUrl;

  bool get hasContext =>
      accountUuid != null && networkName != null && lightwalletdUrl != null;

  bool get hasRequestContext => requestId != null && hasContext;

  _KeystoneMigrationSession withContext({
    required String accountUuid,
    required String networkName,
    required String lightwalletdUrl,
  }) {
    return _KeystoneMigrationSession(
      generation: generation,
      intent: intent,
      requestId: requestId,
      accountUuid: accountUuid,
      networkName: networkName,
      lightwalletdUrl: lightwalletdUrl,
    );
  }

  _KeystoneMigrationSession withRequestId(String requestId) {
    return _KeystoneMigrationSession(
      generation: generation,
      intent: intent,
      requestId: requestId,
      accountUuid: accountUuid,
      networkName: networkName,
      lightwalletdUrl: lightwalletdUrl,
    );
  }

  _KeystoneMigrationSession withoutRequestId() {
    return _KeystoneMigrationSession(
      generation: generation,
      intent: intent,
      accountUuid: accountUuid,
      networkName: networkName,
      lightwalletdUrl: lightwalletdUrl,
    );
  }

  bool sameRun(_KeystoneMigrationSession other) {
    return generation == other.generation && intent == other.intent;
  }

  bool sameRequest(_KeystoneMigrationSession other) {
    return sameRun(other) &&
        requestId == other.requestId &&
        accountUuid == other.accountUuid &&
        networkName == other.networkName &&
        lightwalletdUrl == other.lightwalletdUrl;
  }

  bool matchesContext({
    required String? accountUuid,
    required String networkName,
    required String lightwalletdUrl,
  }) {
    return this.accountUuid == accountUuid &&
        this.networkName == networkName &&
        this.lightwalletdUrl == lightwalletdUrl;
  }
}

/// Compact title/body note used for the pre-card loading and status-error
/// branches.
class _StatusNote extends StatelessWidget {
  const _StatusNote({
    required this.title,
    required this.body,
    this.details,
    this.onRetry,
  });

  final String title;
  final String body;
  final String? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        if (details != null && details!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            details!,
            style: AppTypography.bodyExtraSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: onRetry,
            child: const Text(MigrationCopy.retryCta),
          ),
        ],
      ],
    );
  }
}

/// Transfer list shown inside step 2 while migration transactions confirm.
class _MigrationTransfersList extends StatelessWidget {
  const _MigrationTransfersList({
    required this.migrationTransactions,
    required this.expectedTransferCount,
    required this.amountZatoshi,
  });

  final List<rust_sync.TransactionInfo> migrationTransactions;
  final int? expectedTransferCount;
  final BigInt amountZatoshi;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      amountZatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final total = [
      migrationTransactions.length,
      expectedTransferCount ?? 0,
      1,
    ].reduce((a, b) => a > b ? a : b);
    final transferTransactions = migrationTransactions.reversed.toList(
      growable: false,
    );
    final completed = transferTransactions.where(_isCompletedMigration).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.migratingAmount(amount),
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$completed of $total confirmed',
          style: AppTypography.bodyExtraSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        for (var i = 0; i < total; i++) ...[
          if (i > 0)
            Divider(height: AppSpacing.md, color: colors.border.subtle),
          _MigrationTransferRow(
            index: i,
            total: total,
            transaction: i < transferTransactions.length
                ? transferTransactions[i]
                : null,
          ),
        ],
      ],
    );
  }
}

class _MigrationTransferRow extends StatelessWidget {
  const _MigrationTransferRow({
    required this.index,
    required this.total,
    required this.transaction,
  });

  final int index;
  final int total;
  final rust_sync.TransactionInfo? transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tx = transaction;
    final isComplete = tx != null && _isCompletedMigration(tx);
    final isFailed = tx?.expiredUnmined ?? false;
    final statusText = isFailed
        ? 'Failed'
        : isComplete
        ? 'Completed'
        : 'In progress';
    final icon = isFailed
        ? AppIcons.warning
        : isComplete
        ? AppIcons.checkCircle
        : AppIcons.time;
    final iconColor = isFailed
        ? colors.icon.destructive
        : isComplete
        ? colors.icon.success
        : colors.icon.muted;

    return Row(
      children: [
        AppIcon(icon, size: AppIconSize.medium, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            MigrationCopy.transferLabel(index + 1, total),
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ),
        Text(
          statusText,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}
