import 'dart:async' show Completer;
import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show MethodChannel;

import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/ironwood_migration_phases.dart';
import 'ironwood_migration_background_credential_store.dart';
import 'ironwood_migration_operation_registry.dart';

const _credentialRecoveryRequiredError =
    'Ironwood migration credential is missing for the active run.';

bool ironwoodMigrationNeedsCredentialRecovery(String? error) {
  return error?.contains(_credentialRecoveryRequiredError) ?? false;
}

typedef IronwoodMigrationStatusGetter =
    Future<rust_sync.MigrationStatus> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });

typedef IronwoodMigrationPrivatePlanGetter =
    Future<rust_sync.OrchardMigrationPrivatePlan?> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });

typedef IronwoodMigrationWalletDbPathGetter = Future<String> Function();
typedef IronwoodMigrationEndpointGetter = RpcEndpointConfig Function();
typedef IronwoodMigrationPasswordGetter = String Function();
typedef IronwoodMigrationMnemonicBytesGetter =
    Future<List<int>?> Function(String accountUuid);
typedef IronwoodMigrationPlatformCheck = bool Function();
typedef IronwoodMigrationBackgroundScheduler = Future<bool> Function();
typedef IronwoodMigrationBackgroundCanceler = Future<void> Function();
typedef IronwoodMigrationAccountRevoker =
    Future<void> Function({
      required String network,
      required String accountUuid,
    });
typedef IronwoodMigrationNotificationAuthorizationRequester =
    Future<bool> Function();
typedef IronwoodMigrationHardwareAccountCheck =
    bool Function(String accountUuid);
typedef IronwoodMigrationSoftwareStarter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required List<int> mnemonicBytes,
      required String password,
      required String saltBase64,
      required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
    });
typedef IronwoodMigrationUnbroadcastRetirer =
    Future<void> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required String expectedRunId,
    });
typedef IronwoodMigrationMacosSoftwareStarter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required String password,
      required String saltBase64,
      required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
    });
typedef IronwoodMigrationDueBroadcaster =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required String password,
      required String saltBase64,
    });
typedef IronwoodMigrationOutboxPreparer = IronwoodMigrationDueBroadcaster;
typedef IronwoodMigrationOutboxExporter =
    Future<rust_sync.MigrationOutboxBatch?> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
      required String password,
      required String saltBase64,
    });
typedef IronwoodMigrationOutboxReceiptReconciler =
    Future<void> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
      required String runId,
      required String txidHex,
      required String outcome,
      required int remoteHeight,
      String? responseMessage,
      required List<rust_sync.MigrationOutboxScheduleUpdate> scheduleUpdates,
      Uint8List? acceptedRawTransaction,
    });
typedef IronwoodMigrationOutboxBatchStager =
    Future<Map<String, String>> Function(Map<String, Object?> payload);
typedef IronwoodMigrationOutboxBatchArmer =
    Future<bool> Function({
      required String batchId,
      required Map<String, String> expectedDigests,
    });
typedef IronwoodMigrationOutboxBatchRecoverer =
    Future<bool> Function({
      required String batchId,
      required String network,
      required String accountUuid,
      required String runId,
      required String lightwalletdUrl,
      required List<String> expectedTxids,
    });
typedef IronwoodMigrationOutboxReceiptLister =
    Future<List<Map<Object?, Object?>>> Function();
typedef IronwoodMigrationOutboxReceiptAcknowledger =
    Future<void> Function(List<String> receiptIds);
typedef IronwoodMigrationOutboxForegroundRunner =
    Future<IronwoodMigrationOutboxRunResult> Function();

enum IronwoodMigrationOutboxRunOutcome {
  noWork,
  waiting,
  accepted,
  needsUserAction,
  temporarilyUnavailable,
  cancelled,
}

class IronwoodMigrationOutboxRunResult {
  const IronwoodMigrationOutboxRunResult({
    required this.outcome,
    this.nextHeight,
    this.observedHeight,
  });

  factory IronwoodMigrationOutboxRunResult.fromMap(
    Map<Object?, Object?> values,
  ) {
    final outcome = switch (values['outcome']) {
      'noWork' => IronwoodMigrationOutboxRunOutcome.noWork,
      'waiting' => IronwoodMigrationOutboxRunOutcome.waiting,
      'accepted' => IronwoodMigrationOutboxRunOutcome.accepted,
      'needsUserAction' => IronwoodMigrationOutboxRunOutcome.needsUserAction,
      'temporarilyUnavailable' =>
        IronwoodMigrationOutboxRunOutcome.temporarilyUnavailable,
      'cancelled' => IronwoodMigrationOutboxRunOutcome.cancelled,
      _ => throw const FormatException(
        'Ironwood migration outbox returned an invalid outcome.',
      ),
    };
    return IronwoodMigrationOutboxRunResult(
      outcome: outcome,
      nextHeight: (values['nextHeight'] as num?)?.toInt(),
      observedHeight: (values['observedHeight'] as num?)?.toInt(),
    );
  }

  final IronwoodMigrationOutboxRunOutcome outcome;
  final int? nextHeight;
  final int? observedHeight;
}

typedef IronwoodMigrationKeystoneDenominationPreparer =
    Future<rust_sync.KeystoneMigrationSigningRequest> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });
typedef IronwoodMigrationKeystoneDenominationCompleter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required String requestId,
      required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
      required String password,
      required String saltBase64,
      required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
    });
typedef IronwoodMigrationKeystoneBatchPreparer =
    Future<rust_sync.KeystoneMigrationSigningRequest> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });
typedef IronwoodMigrationKeystoneBatchCompleter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
      required String requestId,
      required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
      required String password,
      required String saltBase64,
    });
typedef IronwoodMigrationKeystoneProofStatusGetter =
    Future<rust_sync.KeystoneMigrationProofStatus> Function({
      required String requestId,
    });
typedef IronwoodMigrationKeystoneRequestDiscarder =
    Future<void> Function({required String requestId});

class IronwoodMigrationService {
  IronwoodMigrationService({
    required this.getWalletDbPath,
    required this.getStatus,
    required this.getPrivatePlan,
    required this.secureStore,
    IronwoodMigrationBackgroundCredentialStore? backgroundCredentialStore,
    IronwoodMigrationEndpointGetter? getEndpoint,
    IronwoodMigrationPasswordGetter? getSessionPassword,
    IronwoodMigrationMnemonicBytesGetter? getMnemonicBytesForAccount,
    IronwoodMigrationPlatformCheck? isMacOS,
    IronwoodMigrationPlatformCheck? isMobile,
    IronwoodMigrationPlatformCheck? isIOS,
    IronwoodMigrationPlatformCheck? supportsBackgroundMigration,
    IronwoodMigrationHardwareAccountCheck? isHardwareAccount,
    IronwoodMigrationBackgroundScheduler? scheduleBackgroundMigration,
    IronwoodMigrationBackgroundScheduler? startBackgroundPreparation,
    IronwoodMigrationBackgroundCanceler? cancelBackgroundMigration,
    IronwoodMigrationAccountRevoker? revokeMigrationAccount,
    IronwoodMigrationNotificationAuthorizationRequester?
    requestNotificationAuthorization,
    IronwoodMigrationSoftwareStarter? startSoftwareMigration,
    IronwoodMigrationUnbroadcastRetirer? retireUnbroadcastMigration,
    IronwoodMigrationMacosSoftwareStarter? startMacosSoftwareMigration,
    IronwoodMigrationDueBroadcaster? broadcastDueMigration,
    IronwoodMigrationOutboxPreparer? prepareMigrationOutbox,
    IronwoodMigrationOutboxExporter? exportMigrationOutbox,
    IronwoodMigrationOutboxReceiptReconciler? reconcileMigrationOutboxReceipt,
    IronwoodMigrationOutboxBatchStager? stageMigrationOutboxBatch,
    IronwoodMigrationOutboxBatchArmer? armMigrationOutboxBatch,
    IronwoodMigrationOutboxBatchRecoverer? recoverMigrationOutboxBatch,
    IronwoodMigrationOutboxReceiptLister? listMigrationOutboxReceipts,
    IronwoodMigrationOutboxReceiptAcknowledger?
    acknowledgeMigrationOutboxReceipts,
    IronwoodMigrationOutboxForegroundRunner? runMigrationOutboxOnceNow,
    IronwoodMigrationKeystoneDenominationPreparer?
    prepareKeystoneDenominationMigration,
    IronwoodMigrationKeystoneDenominationCompleter?
    completeKeystoneDenominationMigration,
    IronwoodMigrationKeystoneBatchPreparer? prepareKeystoneBatchMigration,
    IronwoodMigrationKeystoneBatchCompleter? completeKeystoneBatchMigration,
    IronwoodMigrationKeystoneProofStatusGetter? getKeystoneProofStatus,
    IronwoodMigrationKeystoneRequestDiscarder? discardKeystoneMigrationRequest,
    IronwoodMigrationOperationRegistry? operationRegistry,
  }) : backgroundCredentialStore =
           backgroundCredentialStore ??
           IronwoodMigrationBackgroundCredentialStore.instance,
       getEndpoint = getEndpoint ?? _missingEndpoint,
       getSessionPassword = getSessionPassword ?? _missingSessionPassword,
       getMnemonicBytesForAccount =
           getMnemonicBytesForAccount ?? _missingMnemonicBytesForAccount,
       isMacOS = isMacOS ?? _defaultIsMacOS,
       isMobile = isMobile ?? _defaultIsMobile,
       isIOS = isIOS ?? _defaultIsIOS,
       supportsBackgroundMigration =
           supportsBackgroundMigration ??
           (scheduleBackgroundMigration == null ? _defaultIsIOS : _alwaysTrue),
       isHardwareAccount = isHardwareAccount ?? _defaultIsHardwareAccount,
       scheduleBackgroundMigration =
           scheduleBackgroundMigration ?? _defaultScheduleBackgroundMigration,
       startBackgroundPreparation =
           startBackgroundPreparation ?? _defaultStartBackgroundPreparation,
       cancelBackgroundMigration =
           cancelBackgroundMigration ?? _defaultCancelBackgroundMigration,
       revokeMigrationAccount =
           revokeMigrationAccount ??
           IronwoodMigrationBackgroundLifecycle.instance.revokeAccount,
       requestNotificationAuthorization =
           requestNotificationAuthorization ??
           _defaultRequestNotificationAuthorization,
       startSoftwareMigration =
           startSoftwareMigration ?? rust_sync.migrateOrchardToIronwood,
       retireUnbroadcastMigration =
           retireUnbroadcastMigration ??
           rust_sync.retireUnbroadcastOrchardMigration,
       startMacosSoftwareMigration =
           startMacosSoftwareMigration ??
           rust_sync.migrateOrchardToIronwoodWithMacosStoredMnemonic,
       broadcastDueMigration =
           broadcastDueMigration ??
           rust_sync.broadcastDueOrchardMigrationTransactions,
       prepareMigrationOutbox =
           prepareMigrationOutbox ?? rust_sync.prepareOrchardMigrationOutbox,
       exportMigrationOutbox =
           exportMigrationOutbox ?? rust_sync.exportOrchardMigrationOutbox,
       reconcileMigrationOutboxReceipt =
           reconcileMigrationOutboxReceipt ??
           rust_sync.reconcileOrchardMigrationOutboxReceipt,
       stageMigrationOutboxBatch =
           stageMigrationOutboxBatch ?? _defaultStageMigrationOutboxBatch,
       armMigrationOutboxBatch =
           armMigrationOutboxBatch ?? _defaultArmMigrationOutboxBatch,
       recoverMigrationOutboxBatch =
           recoverMigrationOutboxBatch ?? _defaultRecoverMigrationOutboxBatch,
       listMigrationOutboxReceipts =
           listMigrationOutboxReceipts ?? _defaultListMigrationOutboxReceipts,
       acknowledgeMigrationOutboxReceipts =
           acknowledgeMigrationOutboxReceipts ??
           _defaultAcknowledgeMigrationOutboxReceipts,
       runMigrationOutboxOnceNow =
           runMigrationOutboxOnceNow ?? _defaultRunMigrationOutboxOnceNow,
       prepareKeystoneDenominationMigration =
           prepareKeystoneDenominationMigration ??
           rust_sync.prepareOrchardMigrationDenominationsPczt,
       completeKeystoneDenominationMigration =
           completeKeystoneDenominationMigration ??
           rust_sync.completeOrchardMigrationDenominationsPczt,
       prepareKeystoneBatchMigration =
           prepareKeystoneBatchMigration ??
           rust_sync.prepareOrchardMigrationBatchPczt,
       completeKeystoneBatchMigration =
           completeKeystoneBatchMigration ??
           rust_sync.completeOrchardMigrationBatchPczt,
       getKeystoneProofStatus =
           getKeystoneProofStatus ?? rust_sync.keystoneMigrationProofStatus,
       discardKeystoneMigrationRequest =
           discardKeystoneMigrationRequest ??
           rust_sync.discardKeystoneMigrationRequest,
       operationRegistry =
           operationRegistry ?? IronwoodMigrationOperationRegistry.instance;

  final IronwoodMigrationWalletDbPathGetter getWalletDbPath;
  final IronwoodMigrationStatusGetter getStatus;
  final IronwoodMigrationPrivatePlanGetter getPrivatePlan;
  final AppSecureStore secureStore;
  final IronwoodMigrationBackgroundCredentialStore backgroundCredentialStore;
  final IronwoodMigrationEndpointGetter getEndpoint;
  final IronwoodMigrationPasswordGetter getSessionPassword;
  final IronwoodMigrationMnemonicBytesGetter getMnemonicBytesForAccount;
  final IronwoodMigrationPlatformCheck isMacOS;
  final IronwoodMigrationPlatformCheck isMobile;
  final IronwoodMigrationPlatformCheck isIOS;
  final IronwoodMigrationPlatformCheck supportsBackgroundMigration;
  final IronwoodMigrationHardwareAccountCheck isHardwareAccount;
  final IronwoodMigrationBackgroundScheduler scheduleBackgroundMigration;
  final IronwoodMigrationBackgroundScheduler startBackgroundPreparation;
  final IronwoodMigrationBackgroundCanceler cancelBackgroundMigration;
  final IronwoodMigrationAccountRevoker revokeMigrationAccount;
  final IronwoodMigrationNotificationAuthorizationRequester
  requestNotificationAuthorization;
  final IronwoodMigrationSoftwareStarter startSoftwareMigration;
  final IronwoodMigrationUnbroadcastRetirer retireUnbroadcastMigration;
  final IronwoodMigrationMacosSoftwareStarter startMacosSoftwareMigration;
  final IronwoodMigrationDueBroadcaster broadcastDueMigration;
  final IronwoodMigrationOutboxPreparer prepareMigrationOutbox;
  final IronwoodMigrationOutboxExporter exportMigrationOutbox;
  final IronwoodMigrationOutboxReceiptReconciler
  reconcileMigrationOutboxReceipt;
  final IronwoodMigrationOutboxBatchStager stageMigrationOutboxBatch;
  final IronwoodMigrationOutboxBatchArmer armMigrationOutboxBatch;
  final IronwoodMigrationOutboxBatchRecoverer recoverMigrationOutboxBatch;
  final IronwoodMigrationOutboxReceiptLister listMigrationOutboxReceipts;
  final IronwoodMigrationOutboxReceiptAcknowledger
  acknowledgeMigrationOutboxReceipts;
  final IronwoodMigrationOutboxForegroundRunner runMigrationOutboxOnceNow;
  final IronwoodMigrationKeystoneDenominationPreparer
  prepareKeystoneDenominationMigration;
  final IronwoodMigrationKeystoneDenominationCompleter
  completeKeystoneDenominationMigration;
  final IronwoodMigrationKeystoneBatchPreparer prepareKeystoneBatchMigration;
  final IronwoodMigrationKeystoneBatchCompleter completeKeystoneBatchMigration;
  final IronwoodMigrationKeystoneProofStatusGetter getKeystoneProofStatus;
  final IronwoodMigrationKeystoneRequestDiscarder
  discardKeystoneMigrationRequest;
  final IronwoodMigrationOperationRegistry operationRegistry;
  final Set<String> _foregroundImmediateAccounts = <String>{};

  /// Whether an active migration must stay on the user-attended, foreground
  /// path. Immediate migration deliberately never uses the iOS outbox.
  bool isForegroundImmediateMigration(String accountUuid) =>
      _foregroundImmediateAccounts.contains(accountUuid);

  void clearForegroundImmediateMigration(String accountUuid) {
    _foregroundImmediateAccounts.remove(accountUuid);
  }

  final Map<String, Future<void>> _credentialOperationTails = {};
  final Set<String> _scheduledBackgroundMigrations = {};

  bool get supportsBackgroundMigrationRetry =>
      isMobile() && supportsBackgroundMigration();

  Future<rust_sync.MigrationStatus> status({
    required String network,
    required String accountUuid,
  }) async {
    return operationRegistry.run(
      network: network,
      accountUuid: accountUuid,
      operation: () async {
        final dbPath = await getWalletDbPath();
        final context = _MigrationCredentialContext(
          dbPath: dbPath,
          network: network,
          accountUuid: accountUuid,
        );
        if (!isMobile()) return _getStatusForContext(context);

        return _serializeCredentialState(context, () async {
          var status = await _getStatusForContext(context);
          if (isIOS() && status.activeRunId != null) {
            final manifest = await backgroundCredentialStore.read(
              network: context.network,
              accountUuid: context.accountUuid,
            );
            if (manifest == null &&
                await _recoverPersistedMigrationOutbox(
                  context: _contextWithCurrentEndpoint(context),
                  status: status,
                )) {
              status = await _getStatusForContext(context);
            }
          }
          await _reconcileBackgroundCredential(
            context: context,
            status: status,
          );
          return status;
        });
      },
    );
  }

  /// Restores native denomination preparation for an already-bound software
  /// migration after an explicit lifecycle recovery point.
  ///
  /// Ordinary status reads intentionally do not schedule native work. Keeping
  /// this separate prevents account-list/status refreshes from unexpectedly
  /// restarting preparation while the wallet DB is being mutated.
  Future<void> resumeBackgroundPreparationIfNeeded({
    required String network,
    required String accountUuid,
  }) async {
    if (!isIOS() || !isMobile() || isHardwareAccount(accountUuid)) return;

    final dbPath = await getWalletDbPath();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
    );
    await operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () => _serializeCredentialState(context, () async {
        final status = await _getStatusForContext(context);
        await _reconcileBackgroundCredential(context: context, status: status);
        await _resumeBoundBackgroundPreparationIfNeeded(
          context: context,
          status: status,
        );
      }),
    );
  }

  Future<rust_sync.OrchardMigrationPrivatePlan?> privatePlan({
    required String network,
    required String accountUuid,
  }) async {
    return operationRegistry.run(
      network: network,
      accountUuid: accountUuid,
      operation: () async {
        final dbPath = await getWalletDbPath();
        return getPrivatePlan(
          dbPath: dbPath,
          network: network,
          accountUuid: accountUuid,
        );
      },
    );
  }

  Future<String> pendingTxSaltBase64({
    required String network,
    required String accountUuid,
  }) {
    return secureStore.getOrCreateIronwoodMigrationPendingTxSaltBase64(
      network: network,
      accountUuid: accountUuid,
    );
  }

  Future<rust_sync.IronwoodMigrationResult> startSoftwarePrivateMigration({
    required String accountUuid,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    if (isMacOS()) {
      return _runCredentialOperation(
        context: context,
        mayCreateRun: true,
        operation: (credential) => startMacosSoftwareMigration(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
          password: credential.password,
          saltBase64: credential.saltBase64,
          approvedSchedule: approvedSchedule,
        ),
      );
    }

    final result = await _runCredentialOperation(
      context: context,
      mayCreateRun: true,
      enrollNotificationsOnActiveRun: true,
      onCurrentStatus: _reconcileBackgroundPreparationBestEffort,
      operation: (credential) async {
        final mnemonicBytes = await getMnemonicBytesForAccount(accountUuid);
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          throw Exception('Mnemonic not found for the migration account.');
        }

        late final Future<rust_sync.IronwoodMigrationResult> resultFuture;
        try {
          resultFuture = startSoftwareMigration(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            mnemonicBytes: mnemonicBytes,
            password: credential.password,
            saltBase64: credential.saltBase64,
            approvedSchedule: approvedSchedule,
          );
        } finally {
          mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
        }
        return resultFuture;
      },
    );
    return result;
  }

  /// Directly moves spendable Orchard notes to Ironwood in one foreground
  /// transaction. Immediate migration has no denomination stages, schedule,
  /// background credential, or migration outbox.
  Future<rust_sync.IronwoodMigrationResult> startSoftwareImmediateMigration({
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    try {
      return await operationRegistry.run(
        network: context.network,
        accountUuid: context.accountUuid,
        operation: () async {
          if (isMacOS()) {
            throw UnsupportedError(
              'Immediate migration is not available on macOS.',
            );
          }

          final mnemonicBytes = await getMnemonicBytesForAccount(accountUuid);
          if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
            throw Exception('Mnemonic not found for the migration account.');
          }
          try {
            return await rust_sync.migrateOrchardToIronwoodImmediately(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              accountUuid: accountUuid,
              mnemonicBytes: mnemonicBytes,
            );
          } finally {
            mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
          }
        },
      );
    } catch (_) {
      rethrow;
    }
  }

  /// Broadcasts a due Immediate migration transaction in the foreground.
  ///
  /// Unlike Private migration, this has no Swift outbox or background
  /// credential enrollment. The app coordinator invokes it while foregrounded.
  Future<rust_sync.IronwoodMigrationResult> continueSoftwareImmediateMigration({
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    return operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () async {
        final credential = await _legacyCredential(context);
        return broadcastDueMigration(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
          password: credential.password,
          saltBase64: credential.saltBase64,
        );
      },
    );
  }

  Future<rust_sync.IronwoodMigrationResult> continueSoftwarePrivateMigration({
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    final rust_sync.IronwoodMigrationResult broadcastResult;
    if (isIOS() && isMobile()) {
      broadcastResult = await _runCredentialOperation(
        context: context,
        mayCreateRun: false,
        prepareOutboxAfterOperation: false,
        onCurrentStatus: isHardwareAccount(accountUuid)
            ? null
            : _reconcileBackgroundPreparationBestEffort,
        operation: (credential) => prepareMigrationOutbox(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
          password: credential.password,
          saltBase64: credential.saltBase64,
        ),
      );
    } else {
      broadcastResult = await _runCredentialOperation(
        context: context,
        mayCreateRun: false,
        operation: (credential) => broadcastDueMigration(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
          password: credential.password,
          saltBase64: credential.saltBase64,
        ),
      );
    }
    final isHardware = isHardwareAccount(accountUuid);
    if (isHardware || broadcastResult.status != 'ready_to_migrate') {
      return broadcastResult;
    }

    if (isMacOS()) {
      return _runCredentialOperation(
        context: context,
        mayCreateRun: true,
        operation: (credential) => startMacosSoftwareMigration(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
          password: credential.password,
          saltBase64: credential.saltBase64,
          approvedSchedule: const [],
        ),
      );
    }

    return _runCredentialOperation(
      context: context,
      mayCreateRun: true,
      operation: (credential) async {
        final mnemonicBytes = await getMnemonicBytesForAccount(accountUuid);
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          throw Exception('Mnemonic not found for the migration account.');
        }
        try {
          return startSoftwareMigration(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            mnemonicBytes: mnemonicBytes,
            password: credential.password,
            saltBase64: credential.saltBase64,
            approvedSchedule: const [],
          );
        } finally {
          mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
        }
      },
    );
  }

  Future<bool> retryPrivateMigrationInBackground({
    required String accountUuid,
  }) async {
    if (!supportsBackgroundMigrationRetry) return false;

    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );
    return operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () => _serializeCredentialState(context, () async {
        final status = await _getStatusForContext(context);
        final activeRunId = status.activeRunId;
        if (activeRunId == null) return false;

        final manifest = await backgroundCredentialStore.read(
          network: context.network,
          accountUuid: context.accountUuid,
        );
        if (manifest == null) {
          return _recoverPersistedMigrationOutbox(
            context: context,
            status: status,
          );
        }
        await _resolveManifestContext(manifest, context);
        await backgroundCredentialStore.bindExpectedRunId(
          network: context.network,
          accountUuid: context.accountUuid,
          expectedRunId: activeRunId,
        );

        if (isIOS()) {
          final credential = _MigrationCredential(
            password: manifest.credentialHex,
            saltBase64: manifest.saltBase64,
          );
          await _reconcileMigrationOutboxReceipts(context: context);
          final refresh = await _refreshMigrationOutbox(
            context: context,
            credential: credential,
            prepare: true,
          );
          if (refresh.staged) {
            await _requestNotificationAuthorizationBestEffort();
          }
          return refresh.staged;
        }

        final scheduled = await scheduleBackgroundMigration();
        if (scheduled) {
          _scheduledBackgroundMigrations.add(_credentialKey(context));
          await _requestNotificationAuthorizationBestEffort();
        }
        return scheduled;
      }),
    );
  }

  Future<void> recoverSoftwarePrivateMigration({
    required String accountUuid,
  }) async {
    if (!isIOS() || !isMobile() || isHardwareAccount(accountUuid)) {
      throw StateError(
        'Ironwood migration credential recovery is only available for '
        'software accounts on iOS.',
      );
    }

    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    await operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () => _serializeCredentialState(context, () async {
        final oldStatus = await _getStatusForContext(context);
        final oldRunId = oldStatus.activeRunId;
        if (oldRunId == null) {
          throw StateError('There is no active Ironwood migration to recover.');
        }
        final existingManifest = await backgroundCredentialStore.read(
          network: context.network,
          accountUuid: context.accountUuid,
        );
        if (existingManifest != null) {
          throw StateError(
            'The active Ironwood migration still has a usable credential.',
          );
        }
        if (await _recoverPersistedMigrationOutbox(
          context: context,
          status: oldStatus,
        )) {
          return;
        }

        final mnemonicBytes = await getMnemonicBytesForAccount(accountUuid);
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          throw StateError('Mnemonic not found for the migration account.');
        }

        try {
          // Revocation stops native delivery first. Rust then checks every
          // remaining scheduled transaction against lightwalletd before it
          // unlocks the old run for a rebuild.
          await revokeMigrationAccount(
            network: context.network,
            accountUuid: context.accountUuid,
          );
          await retireUnbroadcastMigration(
            dbPath: context.dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: context.network,
            accountUuid: context.accountUuid,
            expectedRunId: oldRunId,
          );

          final manifest = await backgroundCredentialStore.prepare(
            network: context.network,
            accountUuid: context.accountUuid,
            dbPath: context.dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          );
          final credential = _MigrationCredential(
            password: manifest.credentialHex,
            saltBase64: manifest.saltBase64,
          );

          Object? startError;
          StackTrace? startStackTrace;
          try {
            await startSoftwareMigration(
              dbPath: context.dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: context.network,
              accountUuid: context.accountUuid,
              mnemonicBytes: mnemonicBytes,
              password: credential.password,
              saltBase64: credential.saltBase64,
              approvedSchedule: const [],
            );
          } catch (error, stackTrace) {
            startError = error;
            startStackTrace = stackTrace;
          }

          final currentStatus = await _getStatusForContext(context);
          await _reconcileBackgroundCredential(
            context: context,
            status: currentStatus,
          );
          await _reconcileBackgroundPreparationBestEffort(currentStatus);
          if (currentStatus.activeRunId != null &&
              currentStatus.phase !=
                  kIronwoodMigrationWaitingDenomConfirmationsPhase) {
            await _refreshMigrationOutbox(
              context: context,
              credential: credential,
              prepare: true,
            );
          }
          if (currentStatus.activeRunId != null) {
            await _requestNotificationAuthorizationBestEffort();
          }
          if (startError != null) {
            Error.throwWithStackTrace(startError, startStackTrace!);
          }
        } finally {
          mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
        }
      }),
    );
  }

  Future<rust_sync.KeystoneMigrationSigningRequest>
  prepareKeystoneDenominationPrivateMigration({
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    return operationRegistry.run(
      network: endpoint.networkName,
      accountUuid: accountUuid,
      operation: () => prepareKeystoneDenominationMigration(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
      ),
    );
  }

  Future<rust_sync.IronwoodMigrationResult>
  completeKeystoneDenominationPrivateMigration({
    required String accountUuid,
    required String requestId,
    required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    return _runCredentialOperation(
      context: context,
      mayCreateRun: true,
      enrollNotificationsOnActiveRun: true,
      operation: (credential) => completeKeystoneDenominationMigration(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        requestId: requestId,
        signedMessages: signedMessages,
        password: credential.password,
        saltBase64: credential.saltBase64,
        approvedSchedule: approvedSchedule,
      ),
    );
  }

  Future<rust_sync.KeystoneMigrationSigningRequest>
  prepareKeystoneBatchPrivateMigration({required String accountUuid}) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    return operationRegistry.run(
      network: endpoint.networkName,
      accountUuid: accountUuid,
      operation: () => prepareKeystoneBatchMigration(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
      ),
    );
  }

  Future<rust_sync.IronwoodMigrationResult>
  completeKeystoneBatchPrivateMigration({
    required String accountUuid,
    required String requestId,
    required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationCredentialContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    return _runCredentialOperation(
      context: context,
      mayCreateRun: true,
      enrollNotificationsOnActiveRun: true,
      operation: (credential) => completeKeystoneBatchMigration(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        requestId: requestId,
        signedMessages: signedMessages,
        password: credential.password,
        saltBase64: credential.saltBase64,
      ),
    );
  }

  Future<T> _runCredentialOperation<T>({
    required _MigrationCredentialContext context,
    required bool mayCreateRun,
    required Future<T> Function(_MigrationCredential credential) operation,
    bool enrollNotificationsOnActiveRun = false,
    bool prepareOutboxAfterOperation = true,
    Future<void> Function(rust_sync.MigrationStatus status)? onCurrentStatus,
  }) async {
    return operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () async {
        if (!isMobile()) {
          return operation(await _legacyCredential(context));
        }

        return _serializeCredentialState(context, () async {
          final initialStatus = await _getStatusForContext(context);
          final credential = await _selectMobileCredential(
            context: context,
            status: initialStatus,
            mayCreateRun: mayCreateRun,
          );
          if (isIOS()) {
            await _reconcileMigrationOutboxReceipts(context: context);
          }

          late T result;
          Object? operationError;
          StackTrace? operationStackTrace;
          try {
            result = await operation(credential);
          } catch (error, stackTrace) {
            operationError = error;
            operationStackTrace = stackTrace;
          }

          if (isIOS()) {
            try {
              await _reconcileMigrationOutboxReceipts(context: context);
            } catch (error, stackTrace) {
              if (operationError == null) {
                operationError = error;
                operationStackTrace = stackTrace;
              } else {
                debugPrint(
                  'Failed to reconcile Ironwood migration outbox receipts '
                  'after an operation error: $error',
                );
              }
            }
          }

          rust_sync.MigrationStatus currentStatus;
          try {
            currentStatus = await _getStatusForContext(context);
          } catch (_) {
            if (operationError != null) {
              Error.throwWithStackTrace(operationError, operationStackTrace!);
            }
            rethrow;
          }
          await _reconcileBackgroundCredential(
            context: context,
            status: currentStatus,
          );
          // Register continued preparation as soon as the durable run enters
          // its confirmation phase. Waiting until outbox refresh completes can
          // miss the last foreground execution window when the app is hidden.
          await onCurrentStatus?.call(currentStatus);
          final waitingForDenominationConfirmations =
              currentStatus.phase ==
              kIronwoodMigrationWaitingDenomConfirmationsPhase;
          if (isIOS() &&
              currentStatus.activeRunId != null &&
              !waitingForDenominationConfirmations) {
            try {
              final outboxRefresh = await _refreshMigrationOutbox(
                context: context,
                credential: credential,
                prepare: prepareOutboxAfterOperation,
              );
              if ((prepareOutboxAfterOperation && onCurrentStatus != null) ||
                  outboxRefresh.reconciledReceipt) {
                currentStatus = await _getStatusForContext(context);
                await _reconcileBackgroundCredential(
                  context: context,
                  status: currentStatus,
                );
              }
            } catch (error) {
              if (operationError == null) rethrow;
              debugPrint(
                'Failed to refresh Ironwood migration outbox after an '
                'operation error: $error',
              );
            }
          }
          if (enrollNotificationsOnActiveRun &&
              currentStatus.activeRunId != null) {
            await _requestNotificationAuthorizationBestEffort();
          }

          if (operationError != null) {
            Error.throwWithStackTrace(operationError, operationStackTrace!);
          }
          return result;
        });
      },
    );
  }

  Future<_MigrationCredential> _selectMobileCredential({
    required _MigrationCredentialContext context,
    required rust_sync.MigrationStatus status,
    required bool mayCreateRun,
  }) async {
    final activeRunId = status.activeRunId;
    if (activeRunId != null) {
      final manifest = await backgroundCredentialStore.read(
        network: context.network,
        accountUuid: context.accountUuid,
      );
      if (manifest == null) {
        if (isIOS()) {
          await _recoverPersistedMigrationOutbox(
            context: context,
            status: status,
          );
        }
        throw StateError(
          '$_credentialRecoveryRequiredError '
          'Vizor will only continue transactions preserved in the verified '
          'iOS outbox.',
        );
      }
      final resolvedManifest = await _resolveManifestContext(manifest, context);
      await backgroundCredentialStore.bindExpectedRunId(
        network: context.network,
        accountUuid: context.accountUuid,
        expectedRunId: activeRunId,
      );
      return _MigrationCredential(
        password: resolvedManifest.credentialHex,
        saltBase64: resolvedManifest.saltBase64,
      );
    }

    await _reconcileBackgroundCredential(context: context, status: status);
    if (!mayCreateRun) return _legacyCredential(context);
    final manifest = await backgroundCredentialStore.prepare(
      network: context.network,
      accountUuid: context.accountUuid,
      dbPath: context.dbPath,
      lightwalletdUrl: context.lightwalletdUrl!,
    );
    return _MigrationCredential(
      password: manifest.credentialHex,
      saltBase64: manifest.saltBase64,
    );
  }

  Future<bool> _recoverPersistedMigrationOutbox({
    required _MigrationCredentialContext context,
    required rust_sync.MigrationStatus status,
  }) async {
    final runId = status.activeRunId;
    final lightwalletdUrl = context.lightwalletdUrl;
    if (!isIOS() || runId == null || lightwalletdUrl == null) return false;

    final expectedTxids = <String>{
      for (final part in status.parts)
        if (part.txidHex case final txid? when txid.isNotEmpty)
          txid.toLowerCase(),
      for (final scheduled in status.scheduledBroadcasts)
        if (scheduled.txidHex.isNotEmpty) scheduled.txidHex.toLowerCase(),
    }.toList(growable: false);
    if (expectedTxids.isEmpty) return false;

    final recovered = await recoverMigrationOutboxBatch(
      batchId: _migrationOutboxBatchId(context, runId),
      network: context.network,
      accountUuid: context.accountUuid,
      runId: runId,
      lightwalletdUrl: lightwalletdUrl,
      expectedTxids: expectedTxids,
    );
    if (!recovered) return false;

    _scheduledBackgroundMigrations.add(_credentialKey(context));
    await runMigrationOutboxOnceNow();
    await _reconcileMigrationOutboxReceipts(context: context);
    await _requestNotificationAuthorizationBestEffort();
    return true;
  }

  _MigrationCredentialContext _contextWithCurrentEndpoint(
    _MigrationCredentialContext context,
  ) {
    if (context.lightwalletdUrl != null) return context;
    try {
      final endpoint = getEndpoint();
      if (endpoint.networkName != context.network) return context;
      return _MigrationCredentialContext(
        dbPath: context.dbPath,
        network: context.network,
        accountUuid: context.accountUuid,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      );
    } catch (_) {
      return context;
    }
  }

  Future<_MigrationCredential> _legacyCredential(
    _MigrationCredentialContext context,
  ) async {
    return _MigrationCredential(
      password: getSessionPassword(),
      saltBase64: await pendingTxSaltBase64(
        network: context.network,
        accountUuid: context.accountUuid,
      ),
    );
  }

  Future<rust_sync.MigrationStatus> _getStatusForContext(
    _MigrationCredentialContext context,
  ) {
    return getStatus(
      dbPath: context.dbPath,
      network: context.network,
      accountUuid: context.accountUuid,
    );
  }

  Future<void> _reconcileBackgroundCredential({
    required _MigrationCredentialContext context,
    required rust_sync.MigrationStatus status,
  }) async {
    final activeRunId = status.activeRunId;
    if (activeRunId != null) {
      final manifest = await backgroundCredentialStore.read(
        network: context.network,
        accountUuid: context.accountUuid,
      );
      if (manifest == null) {
        _scheduledBackgroundMigrations.remove(_credentialKey(context));
        return;
      }
      await _resolveManifestContext(manifest, context);
      await backgroundCredentialStore.bindExpectedRunId(
        network: context.network,
        accountUuid: context.accountUuid,
        expectedRunId: activeRunId,
      );
      return;
    }

    final credentialKey = _credentialKey(context);
    _scheduledBackgroundMigrations.remove(credentialKey);

    IronwoodMigrationBackgroundCredentialManifest? manifest;
    try {
      manifest = await backgroundCredentialStore.read(
        network: context.network,
        accountUuid: context.accountUuid,
      );
    } on FormatException {
      await backgroundCredentialStore.delete(
        network: context.network,
        accountUuid: context.accountUuid,
      );
      if (_isTerminalCredentialCleanupPhase(status.phase)) {
        await _cancelBackgroundMigrationBestEffort();
      }
      return;
    }
    if (manifest == null) return;

    await backgroundCredentialStore.delete(
      network: context.network,
      accountUuid: context.accountUuid,
    );
    if (manifest.expectedRunId != null ||
        _isTerminalCredentialCleanupPhase(status.phase)) {
      await _cancelBackgroundMigrationBestEffort();
    }
  }

  Future<IronwoodMigrationBackgroundCredentialManifest> _resolveManifestContext(
    IronwoodMigrationBackgroundCredentialManifest manifest,
    _MigrationCredentialContext context,
  ) async {
    if (manifest.network == context.network &&
        manifest.accountUuid == context.accountUuid) {
      if (manifest.dbPath == context.dbPath) return manifest;

      final storedDbName = _fileName(manifest.dbPath);
      final currentDbName = _fileName(context.dbPath);
      if (isIOS() && storedDbName != null && storedDbName == currentDbName) {
        return backgroundCredentialStore.replaceDbPath(
          network: context.network,
          accountUuid: context.accountUuid,
          expectedDbPath: manifest.dbPath,
          dbPath: context.dbPath,
        );
      }
    }

    throw StateError(
      'Ironwood migration credential manifest does not match the active '
      'wallet context.',
    );
  }

  Future<_MigrationOutboxRefreshResult> _refreshMigrationOutbox({
    required _MigrationCredentialContext context,
    required _MigrationCredential credential,
    required bool prepare,
  }) async {
    final lightwalletdUrl = context.lightwalletdUrl;
    if (lightwalletdUrl == null) {
      return const _MigrationOutboxRefreshResult();
    }

    if (prepare) {
      await prepareMigrationOutbox(
        dbPath: context.dbPath,
        lightwalletdUrl: lightwalletdUrl,
        network: context.network,
        accountUuid: context.accountUuid,
        password: credential.password,
        saltBase64: credential.saltBase64,
      );
    }

    final batch = await exportMigrationOutbox(
      dbPath: context.dbPath,
      network: context.network,
      accountUuid: context.accountUuid,
      password: credential.password,
      saltBase64: credential.saltBase64,
    );
    if (batch == null) return const _MigrationOutboxRefreshResult();

    final batchId = _migrationOutboxBatchId(context, batch.runId);
    final expectedDigests = await stageMigrationOutboxBatch({
      'batchId': batchId,
      'network': context.network,
      'accountUuid': context.accountUuid,
      'runId': batch.runId,
      'lightwalletdUrl': lightwalletdUrl,
      'timingMeanBlocks': batch.timingMeanBlocks,
      'timingMaxBlocks': batch.timingMaxBlocks,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      'nextProofHeight': batch.nextProofHeight,
      'items': batch.items
          .map(
            (item) => <String, Object?>{
              'itemId': item.itemId,
              'partIndex': item.partIndex,
              'txidHex': item.txidHex,
              'rawTransaction': Uint8List.fromList(item.rawTransaction),
              'anchorBoundaryHeight': item.anchorBoundaryHeight,
              'scheduledHeight': item.scheduledHeight,
              'scheduleStartHeight': item.scheduleStartHeight,
              'expiryHeight': item.expiryHeight,
            },
          )
          .toList(growable: false),
    });
    final armedAndScheduled = await armMigrationOutboxBatch(
      batchId: batchId,
      expectedDigests: expectedDigests,
    );
    if (!armedAndScheduled) {
      throw StateError('Failed to schedule the Ironwood migration outbox.');
    }
    _scheduledBackgroundMigrations.add(_credentialKey(context));

    final foregroundRun = await runMigrationOutboxOnceNow();
    final reconciledTxids = await _reconcileMigrationOutboxReceipts(
      context: context,
    );
    _validateForegroundOutboxRun(
      batch: batch,
      run: foregroundRun,
      reconciledTxids: reconciledTxids,
    );
    return _MigrationOutboxRefreshResult(
      staged: true,
      reconciledReceipt: reconciledTxids.isNotEmpty,
    );
  }

  void _validateForegroundOutboxRun({
    required rust_sync.MigrationOutboxBatch batch,
    required IronwoodMigrationOutboxRunResult run,
    required Set<String> reconciledTxids,
  }) {
    final observedHeight = run.observedHeight;
    final hadDueItem =
        observedHeight != null &&
        batch.items.any((item) => item.scheduledHeight <= observedHeight);

    switch (run.outcome) {
      case IronwoodMigrationOutboxRunOutcome.accepted:
        final reconciledCurrentBatch = batch.items.any(
          (item) => reconciledTxids.contains(item.txidHex.toLowerCase()),
        );
        if (!reconciledCurrentBatch) {
          throw StateError(
            'Migration broadcast was accepted but not reconciled.',
          );
        }
        return;
      case IronwoodMigrationOutboxRunOutcome.needsUserAction:
        throw StateError('Migration broadcast needs user action.');
      case IronwoodMigrationOutboxRunOutcome.temporarilyUnavailable:
        throw StateError('Migration broadcast is temporarily unavailable.');
      case IronwoodMigrationOutboxRunOutcome.cancelled:
        throw StateError('Migration broadcast was cancelled.');
      case IronwoodMigrationOutboxRunOutcome.noWork:
        if (hadDueItem) {
          throw StateError(
            'Migration broadcast did not submit a due transfer.',
          );
        }
        return;
      case IronwoodMigrationOutboxRunOutcome.waiting:
        if (hadDueItem) {
          throw StateError('Migration broadcast is waiting to retry.');
        }
        return;
    }
  }

  Future<Set<String>> _reconcileMigrationOutboxReceipts({
    required _MigrationCredentialContext context,
  }) async {
    final rawReceipts = await listMigrationOutboxReceipts();
    final acknowledgedReceiptIds = <String>[];
    final reconciledTxids = <String>{};
    var failedReceiptCount = 0;

    for (final rawReceipt in rawReceipts) {
      try {
        final receipt = _MigrationOutboxReceipt.fromMap(rawReceipt);
        if (receipt.network != context.network ||
            receipt.accountUuid != context.accountUuid) {
          continue;
        }
        await reconcileMigrationOutboxReceipt(
          dbPath: context.dbPath,
          network: context.network,
          accountUuid: context.accountUuid,
          runId: receipt.runId,
          txidHex: receipt.txidHex,
          outcome: receipt.outcome,
          remoteHeight: receipt.remoteHeight,
          responseMessage: receipt.responseMessage,
          scheduleUpdates: receipt.scheduleUpdates,
          acceptedRawTransaction: receipt.acceptedRawTransaction,
        );
        acknowledgedReceiptIds.add(receipt.receiptId);
        reconciledTxids.add(receipt.txidHex.toLowerCase());
      } catch (error) {
        failedReceiptCount++;
        debugPrint(
          'Failed to reconcile an Ironwood migration outbox receipt: $error',
        );
      }
    }

    if (acknowledgedReceiptIds.isNotEmpty) {
      await acknowledgeMigrationOutboxReceipts(acknowledgedReceiptIds);
    }
    if (failedReceiptCount > 0) {
      debugPrint(
        'Skipped $failedReceiptCount unreconciled Ironwood migration '
        'outbox receipt(s).',
      );
    }
    return reconciledTxids;
  }

  Future<T> _serializeCredentialState<T>(
    _MigrationCredentialContext context,
    Future<T> Function() operation,
  ) async {
    final credentialKey = _credentialKey(context);
    final previous =
        _credentialOperationTails[credentialKey] ?? Future<void>.value();
    final release = Completer<void>();
    final current = previous.then((_) => release.future);
    _credentialOperationTails[credentialKey] = current;

    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_credentialOperationTails[credentialKey], current)) {
        _credentialOperationTails.remove(credentialKey);
      }
    }
  }

  String _credentialKey(_MigrationCredentialContext context) =>
      '${context.network}:${context.accountUuid}';

  Future<void> _cancelBackgroundMigrationBestEffort() async {
    try {
      await cancelBackgroundMigration();
    } catch (error) {
      debugPrint('Failed to cancel Ironwood background migration: $error');
    }
  }

  Future<void> _requestNotificationAuthorizationBestEffort() async {
    if (!isIOS()) return;
    try {
      await requestNotificationAuthorization();
    } catch (error) {
      debugPrint(
        'Failed to request Ironwood migration notification authorization: '
        '$error',
      );
    }
  }

  Future<void> _reconcileBackgroundPreparationBestEffort(
    rust_sync.MigrationStatus status,
  ) async {
    if (!isIOS() || !isMobile()) return;
    if (status.phase != kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return;
    }
    try {
      await startBackgroundPreparation();
    } catch (error) {
      debugPrint(
        'Failed to continue Ironwood migration preparation in background: '
        '$error',
      );
    }
  }

  Future<void> _resumeBoundBackgroundPreparationIfNeeded({
    required _MigrationCredentialContext context,
    required rust_sync.MigrationStatus status,
  }) async {
    if (status.phase != kIronwoodMigrationWaitingDenomConfirmationsPhase ||
        status.activeRunId == null) {
      return;
    }
    final manifest = await backgroundCredentialStore.read(
      network: context.network,
      accountUuid: context.accountUuid,
    );
    if (manifest == null || manifest.expectedRunId != status.activeRunId) {
      return;
    }
    await _resolveManifestContext(manifest, context);
    await _reconcileBackgroundPreparationBestEffort(status);
  }

  Future<void> discardKeystonePrivateMigrationRequest({
    required String accountUuid,
    required String requestId,
  }) {
    final endpoint = getEndpoint();
    return operationRegistry.run(
      network: endpoint.networkName,
      accountUuid: accountUuid,
      operation: () => discardKeystoneMigrationRequest(requestId: requestId),
    );
  }

  Future<rust_sync.KeystoneMigrationProofStatus> keystoneProofStatus({
    required String requestId,
  }) {
    return getKeystoneProofStatus(requestId: requestId);
  }
}

final ironwoodMigrationServiceProvider = Provider<IronwoodMigrationService>((
  ref,
) {
  return IronwoodMigrationService(
    getWalletDbPath: getWalletDbPath,
    getStatus: rust_sync.getOrchardMigrationStatus,
    getPrivatePlan: rust_sync.getOrchardMigrationPrivatePlan,
    secureStore: AppSecureStore.instance,
    getEndpoint: () => ref.read(rpcEndpointFailoverProvider).current,
    getSessionPassword: () => ref
        .read(appSecurityProvider.notifier)
        .requireSessionPasswordForNativeSecretUse(),
    getMnemonicBytesForAccount: (accountUuid) => ref
        .read(accountProvider.notifier)
        .getMnemonicBytesForAccount(accountUuid),
    isHardwareAccount: (accountUuid) {
      final state = ref.read(accountProvider).value;
      for (final account in state?.accounts ?? const <AccountInfo>[]) {
        if (account.uuid == accountUuid) return account.isHardware;
      }
      return false;
    },
  );
});

RpcEndpointConfig _missingEndpoint() {
  throw StateError('Ironwood migration endpoint getter is not configured.');
}

String _missingSessionPassword() {
  throw StateError('Ironwood migration password getter is not configured.');
}

Future<List<int>?> _missingMnemonicBytesForAccount(String accountUuid) {
  throw StateError('Ironwood migration mnemonic getter is not configured.');
}

bool _defaultIsMacOS() => Platform.isMacOS;
bool _defaultIsMobile() => Platform.isIOS || Platform.isAndroid;
bool _defaultIsIOS() => Platform.isIOS;
bool _alwaysTrue() => true;
bool _defaultIsHardwareAccount(String _) => false;

const _backgroundMigrationChannel = MethodChannel(
  'com.zcash.wallet/background_migration',
);

Future<bool> _defaultScheduleBackgroundMigration() async {
  if (!Platform.isIOS) return false;
  return await _backgroundMigrationChannel.invokeMethod<bool>('schedule') ??
      false;
}

Future<bool> _defaultStartBackgroundPreparation() async {
  if (!Platform.isIOS) return false;
  return await _backgroundMigrationChannel.invokeMethod<bool>(
        'startPreparation',
      ) ??
      false;
}

Future<void> _defaultCancelBackgroundMigration() async {
  if (!Platform.isIOS) return;
  await _backgroundMigrationChannel.invokeMethod<void>('cancel');
}

Future<bool> _defaultRequestNotificationAuthorization() async {
  final authorized = await _backgroundMigrationChannel.invokeMethod<bool>(
    'requestNotificationAuthorization',
  );
  return authorized ?? false;
}

Future<Map<String, String>> _defaultStageMigrationOutboxBatch(
  Map<String, Object?> payload,
) async {
  final result = await _backgroundMigrationChannel
      .invokeMethod<Map<Object?, Object?>>('stageOutboxBatch', payload);
  if (result == null) return const {};
  return result.map((key, value) => MapEntry(key as String, value as String));
}

Future<bool> _defaultArmMigrationOutboxBatch({
  required String batchId,
  required Map<String, String> expectedDigests,
}) async {
  return await _backgroundMigrationChannel.invokeMethod<bool>(
        'armOutboxBatch',
        {'batchId': batchId, 'expectedDigests': expectedDigests},
      ) ??
      false;
}

Future<bool> _defaultRecoverMigrationOutboxBatch({
  required String batchId,
  required String network,
  required String accountUuid,
  required String runId,
  required String lightwalletdUrl,
  required List<String> expectedTxids,
}) async {
  return await _backgroundMigrationChannel
          .invokeMethod<bool>('recoverOutboxBatch', {
            'batchId': batchId,
            'network': network,
            'accountUuid': accountUuid,
            'runId': runId,
            'lightwalletdUrl': lightwalletdUrl,
            'expectedTxids': expectedTxids,
          }) ??
      false;
}

Future<List<Map<Object?, Object?>>>
_defaultListMigrationOutboxReceipts() async {
  final result = await _backgroundMigrationChannel.invokeMethod<List<Object?>>(
    'listOutboxReceipts',
  );
  if (result == null) return const [];
  return result
      .map((receipt) => receipt as Map<Object?, Object?>)
      .toList(growable: false);
}

Future<void> _defaultAcknowledgeMigrationOutboxReceipts(
  List<String> receiptIds,
) async {
  await _backgroundMigrationChannel.invokeMethod<void>('ackOutboxReceipts', {
    'receiptIds': receiptIds,
  });
}

Future<IronwoodMigrationOutboxRunResult>
_defaultRunMigrationOutboxOnceNow() async {
  final result = await _backgroundMigrationChannel
      .invokeMethod<Map<Object?, Object?>>('runOutboxOnceNow');
  if (result == null) {
    throw const FormatException(
      'Ironwood migration outbox returned no result.',
    );
  }
  return IronwoodMigrationOutboxRunResult.fromMap(result);
}

bool _isTerminalCredentialCleanupPhase(String phase) =>
    phase == 'complete' || phase == 'abandoned';

class _MigrationCredentialContext {
  const _MigrationCredentialContext({
    required this.dbPath,
    required this.network,
    required this.accountUuid,
    this.lightwalletdUrl,
  });

  final String dbPath;
  final String network;
  final String accountUuid;
  final String? lightwalletdUrl;
}

String? _fileName(String path) {
  final segments = Uri.file(
    path,
  ).pathSegments.where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? null : segments.last;
}

class _MigrationCredential {
  const _MigrationCredential({
    required this.password,
    required this.saltBase64,
  });

  final String password;
  final String saltBase64;
}

class _MigrationOutboxRefreshResult {
  const _MigrationOutboxRefreshResult({
    this.staged = false,
    this.reconciledReceipt = false,
  });

  final bool staged;
  final bool reconciledReceipt;
}

class _MigrationOutboxReceipt {
  const _MigrationOutboxReceipt({
    required this.receiptId,
    required this.network,
    required this.accountUuid,
    required this.runId,
    required this.txidHex,
    required this.outcome,
    required this.remoteHeight,
    required this.responseMessage,
    required this.scheduleUpdates,
    required this.acceptedRawTransaction,
  });

  factory _MigrationOutboxReceipt.fromMap(Map<Object?, Object?> values) {
    final rawUpdates = values['scheduleUpdates'];
    if (rawUpdates is! List<Object?>) {
      throw const FormatException(
        'Ironwood migration outbox receipt has invalid schedule updates.',
      );
    }
    return _MigrationOutboxReceipt(
      receiptId: _requiredOutboxString(values, 'receiptId'),
      network: _requiredOutboxString(values, 'network'),
      accountUuid: _requiredOutboxString(values, 'accountUuid'),
      runId: _requiredOutboxString(values, 'runId'),
      txidHex: _requiredOutboxString(values, 'txidHex'),
      outcome: _requiredOutboxString(values, 'outcome'),
      remoteHeight: _requiredOutboxInt(values, 'remoteHeight'),
      responseMessage: values['responseMessage'] as String?,
      acceptedRawTransaction: values['rawTransaction'] as Uint8List?,
      scheduleUpdates: rawUpdates
          .map((rawUpdate) {
            if (rawUpdate is! Map<Object?, Object?>) {
              throw const FormatException(
                'Ironwood migration outbox receipt has an invalid schedule update.',
              );
            }
            return rust_sync.MigrationOutboxScheduleUpdate(
              itemId: _requiredOutboxString(rawUpdate, 'itemId'),
              scheduledHeight: _requiredOutboxInt(rawUpdate, 'scheduledHeight'),
              scheduleStartHeight: _requiredOutboxInt(
                rawUpdate,
                'scheduleStartHeight',
              ),
            );
          })
          .toList(growable: false),
    );
  }

  final String receiptId;
  final String network;
  final String accountUuid;
  final String runId;
  final String txidHex;
  final String outcome;
  final int remoteHeight;
  final String? responseMessage;
  final List<rust_sync.MigrationOutboxScheduleUpdate> scheduleUpdates;
  final Uint8List? acceptedRawTransaction;
}

String _migrationOutboxBatchId(
  _MigrationCredentialContext context,
  String runId,
) => '${context.network}:${context.accountUuid}:$runId';

String _requiredOutboxString(Map<Object?, Object?> values, String key) {
  final value = values[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Ironwood migration outbox value is invalid: $key.');
}

int _requiredOutboxInt(Map<Object?, Object?> values, String key) {
  final value = values[key];
  if (value is int && value >= 0) return value;
  throw FormatException('Ironwood migration outbox value is invalid: $key.');
}
