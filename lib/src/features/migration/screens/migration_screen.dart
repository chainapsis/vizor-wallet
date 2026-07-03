import 'dart:async';
import 'dart:convert';

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
import '../models/migration_timeline_model.dart';
import '../models/migration_view_state.dart';
import '../providers/migration_expected_transfer_count_provider.dart';
import '../providers/migration_run_controller.dart';
import '../providers/orchard_migration_status_provider.dart';
import 'migration_scan_screen.dart' show MigrationSignedQrResult;
import '../widgets/migration_timeline.dart';
import '../widgets/migration_warning_dialog.dart';

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  static const _keystoneMigrationBatchMaxFragmentLen = 200;
  static const _keystoneBatchSigResultUrType = 'zcash-batch-sig-result';
  static const _keystoneSignResultUrType = 'zcash-sign-result';

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
  bool _keystoneStagedFallback = false;

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
        migrationStatusAsync.isLoading &&
        !runState.keepsProgressVisible;
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
        orchardBalance: sync.orchardBalance + sync.orchardPendingBalance,
        ironwoodBalance: sync.ironwoodBalance,
        preparingInFlight:
            runState.keepsProgressVisible &&
            runState.intent == MigrationRunIntent.preparing,
        migratingInFlight:
            runState.keepsProgressVisible &&
            runState.intent == MigrationRunIntent.migrating,
      );

      final timeline = migrationTimelineModel(
        viewState: viewState,
        status: migrationStatus,
        runInFlight: runState.keepsProgressVisible,
        intent: runState.intent,
        sendNeedsScan:
            isHardware &&
            timelineSendIsAwaitingScan(viewState, migrationStatus),
      );
      final effectiveExpectedCount =
          migrationStatus != null && migrationStatus.totalCount > 0
          ? migrationStatus.totalCount
          : (scopedExpectedCount ?? 0);
      // A recoverable failure before any send is a split failure → retry stage 1;
      // a failure after sends started → retry stage 2.
      final retryIntent = timeline.split == MigrationNodeStatus.error
          ? MigrationRunIntent.preparing
          : MigrationRunIntent.migrating;

      body = _MigrationBody(
        viewState: viewState,
        timeline: timeline,
        status: migrationStatus,
        runState: runState,
        sync: sync,
        isHardware: isHardware,
        shares: currentRunMigrationTransactions,
        totalShares: effectiveExpectedCount,
        amountZatoshi: _migrationDisplayAmount(
          sync,
          currentRunMigrationTransactions,
        ),
        onMigrate: () =>
            unawaited(_startMigration(isHardware, migrationStatus)),
        onRetry: () => unawaited(_advanceMigration(retryIntent, isHardware)),
        onScanSends: () => _showKeystoneMigration(MigrationRunIntent.migrating),
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

  Future<void> _startMigration(
    bool isHardware,
    rust_sync.MigrationStatus? status,
  ) async {
    final windowSeconds = _migrationBroadcastWindowSeconds(status);
    if (windowSeconds == null) return;
    final confirmed = await MigrationWarningDialog.show(
      context,
      windowSeconds: windowSeconds,
    );
    if (!mounted || !confirmed) return;
    await _advanceMigration(MigrationRunIntent.preparing, isHardware);
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
      // Allow the Ironwood mainnet-masquerade endpoint too (networkName=main but a private
      // Ironwood test chain; isLocalIronwoodTestnetEndpoint is true under kZcashIronwoodMasquerade).
      if (endpoint.network != ZcashNetwork.testnet &&
          !isLocalIronwoodTestnetEndpoint(endpoint)) {
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
          MigrationRunIntent.preparing => await () async {
            try {
              final single = await rust_sync
                  .prepareOrchardMigrationSingleQrPczt(
                    dbPath: dbPath,
                    network: networkName,
                    accountUuid: accountUuid,
                  );
              if (mounted) setState(() => _keystoneStagedFallback = false);
              return single;
            } catch (e) {
              if (!migrationIsSingleQrTooLargeError(e)) rethrow;
              log(
                'MigrationScreen: migration too large for one QR; '
                'falling back to staged denominations-only signing',
              );
              if (mounted) setState(() => _keystoneStagedFallback = true);
              return rust_sync.prepareOrchardMigrationDenominationsPczt(
                dbPath: dbPath,
                network: networkName,
                accountUuid: accountUuid,
              );
            }
          }(),
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
    final signedQr = await context.push<MigrationSignedQrResult>(
      '/migration/scan',
    );
    if (signedQr == null || !_keystoneSessionIsCurrent(session)) {
      return;
    }

    setState(() {
      _keystonePhase = KeystoneSigningModalPhase.preparing;
      _keystoneError = null;
    });

    try {
      final result = await _decodeKeystoneSignedMigrationQr(signedQr);
      if (!_keystoneSessionIsCurrent(session)) {
        return;
      }
      final resultRequestId = _decodeKeystoneId(result.requestId);
      if (resultRequestId != request.requestId) {
        throw _KeystoneMigrationError(
          'Signed result is for $resultRequestId, expected ${request.requestId}.',
        );
      }
      final signedMessages = result.results
          .map(
            (message) => rust_sync.KeystoneSignedMigrationMessage(
              id: _decodeKeystoneId(message.messageId),
              sigs: message.sigs,
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
          // Denominations-only completion stores the signed split as a retryable
          // prep transaction before broadcasting it.
          if (_keystoneStagedFallback) {
            return rust_sync.completeOrchardMigrationDenominationsPczt(
              dbPath: dbPath,
              lightwalletdUrl: lightwalletdUrl,
              network: networkName,
              accountUuid: accountUuid,
              requestId: requestId,
              signedMessages: signedMessages,
              password: password,
              saltBase64: saltBase64,
            );
          }
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
    final broadcastWindowSeconds = _migrationBroadcastWindowSeconds(
      ref.read(activeOrchardMigrationStatusProvider).value,
    );
    if (result.totalCount > 0 &&
        firstTxid != null &&
        broadcastWindowSeconds != null) {
      ref
          .read(migrationExpectedTransferCountProvider.notifier)
          .setCount(
            accountUuid,
            result.totalCount,
            firstTxid: firstTxid,
            broadcastWindowSeconds: broadcastWindowSeconds,
          );
    }

    final advanced = migrationRunAdvanced(result);
    // Keystone completion reaches this point only after Rust has staged the run.
    // A pending broadcast result should leave the modal and let the retry tick continue.
    final retryingFromStoredRun = result.status == 'pending_broadcast';
    if (!advanced && !retryingFromStoredRun) {
      await _refreshAfterKeystoneMigrationResult(accountUuid);
      throw _KeystoneMigrationError(
        result.message ?? MigrationCopy.partialBroadcastError,
      );
    }
    ref
        .read(migrationRunControllerProvider.notifier)
        .settleAfterExternalAdvance(session.intent);

    await _refreshAfterKeystoneMigrationResult(accountUuid);

    if (!mounted) return;
    _clearKeystoneMigration(discardRequest: false);
  }

  Future<void> _refreshAfterKeystoneMigrationResult(String accountUuid) async {
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    if (activeAccountUuid == accountUuid) {
      try {
        await ref
            .read(syncProvider.notifier)
            .refreshAfterSend(
              transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
            );
      } catch (e, st) {
        log(
          'MigrationScreen: refresh after Keystone migration failed: $e\n$st',
        );
      }
    }
    ref.invalidate(activeOrchardMigrationStatusProvider);
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

  /// Decode a scanned Keystone migration signing response into the compact
  /// signature shape, routing on the scanned UR type: the new
  /// `zcash-batch-sig-result` decodes directly, while the legacy `zcash-sign-result`
  /// (current ForgeBox firmware) is normalized by extracting the
  /// spend-authorization signatures from its signed PCZTs.
  Future<rust_keystone.KeystoneSigResult> _decodeKeystoneSignedMigrationQr(
    MigrationSignedQrResult signedQr,
  ) {
    switch (signedQr.urType) {
      case _keystoneBatchSigResultUrType:
        return rust_keystone.decodeZcashSigResultCbor(cbor: signedQr.cbor);
      case _keystoneSignResultUrType:
        return rust_keystone.decodeZcashSignResultCborAsSigResult(
          cbor: signedQr.cbor,
        );
      default:
        throw _KeystoneMigrationError(
          'Unexpected Keystone migration QR type ${signedQr.urType}.',
        );
    }
  }

  /// Decode a Keystone id (request id or message id) from the raw bytes the
  /// compact `zcash-batch-sig-result` carries back. The wallet sends these ids as
  /// UTF-8 strings; if a device ever returns non-UTF-8 bytes, fall back to hex
  /// so the value is still comparable rather than throwing on decode.
  String _decodeKeystoneId(List<int> idBytes) {
    try {
      return utf8.decode(idBytes);
    } on FormatException {
      return idBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
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

  int? _migrationBroadcastWindowSeconds(rust_sync.MigrationStatus? status) {
    return status?.broadcastWindowSeconds.toInt();
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

class _MigrationBody extends StatelessWidget {
  const _MigrationBody({
    required this.viewState,
    required this.timeline,
    required this.status,
    required this.runState,
    required this.sync,
    required this.isHardware,
    required this.shares,
    required this.totalShares,
    required this.amountZatoshi,
    required this.onMigrate,
    required this.onRetry,
    required this.onScanSends,
  });

  final MigrationViewState viewState;
  final MigrationTimelineModel timeline;
  final rust_sync.MigrationStatus? status;
  final MigrationRunState runState;
  final SyncState sync;
  final bool isHardware;
  final List<rust_sync.TransactionInfo> shares;
  final int totalShares;
  final BigInt amountZatoshi;
  final VoidCallback onMigrate;
  final VoidCallback onRetry;
  final VoidCallback onScanSends;

  bool get _isIdle => migrationShouldShowEntry(
    viewState: viewState,
    keepsProgressVisible: runState.keepsProgressVisible,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.idleTitle,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.idleBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (viewState == MigrationViewState.complete)
          _done(context)
        else if (_isIdle)
          _entry(context)
        else
          MigrationTimeline(
            model: timeline,
            status: status,
            shares: shares,
            amountZatoshi: amountZatoshi,
            totalShares: totalShares,
            now: DateTime.now(),
            onScanSends: onScanSends,
            confirming:
                viewState == MigrationViewState.waitingMigrationConfirmations,
            onRetry:
                viewState == MigrationViewState.failedRecoverable ||
                    viewState == MigrationViewState.paused
                ? onRetry
                : null,
          ),
        if (runState.error != null) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            runState.error!,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ],
      ],
    );
  }

  Widget _entry(BuildContext context) {
    final colors = context.colors;
    final canStart = migrationCanStartFromEntry(viewState);
    final amount = ZecAmount.fromZatoshi(
      amountZatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final note = viewState == MigrationViewState.noOrchardFunds
        ? MigrationCopy.noFundsNote
        : viewState == MigrationViewState.waitingForSpendableOrchard
        ? MigrationCopy.unspendableNote
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Column(
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
                style: AppTypography.displaySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                MigrationCopy.poolFlow,
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            note,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(
          onPressed: canStart ? onMigrate : null,
          child: const Text(MigrationCopy.migrateCta),
        ),
      ],
    );
  }

  Widget _done(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      amountZatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            AppIcons.checkCircle,
            size: AppIconSize.large,
            color: colors.icon.success,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            MigrationCopy.doneTitle,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            status != null && status!.totalCount > 0
                ? MigrationCopy.doneBody(amount, status!.totalCount)
                : MigrationCopy.doneBodyGeneric,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
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
  return sync.orchardBalance + sync.orchardPendingBalance;
}

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
