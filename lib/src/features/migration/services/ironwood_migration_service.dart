import 'dart:async' show Completer;
import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show MethodChannel;

import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/ironwood_migration_phases.dart';
import 'ironwood_migration_background_manifest_store.dart';
import 'ironwood_migration_operation_registry.dart';

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

typedef IronwoodMigrationImmediatePlanGetter =
    Future<rust_sync.OrchardMigrationImmediatePlan?> Function({
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
      required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
    });
typedef IronwoodMigrationImmediateStarter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required List<int> mnemonicBytes,
      required BigInt approvedTotalInputZatoshi,
      required BigInt approvedFeeZatoshi,
      required BigInt approvedMigratedZatoshi,
      required int approvedInputNoteCount,
    });
typedef IronwoodMigrationMacosSoftwareStarter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required String password,
      required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
    });
typedef IronwoodMigrationDueBroadcaster =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
    });
typedef IronwoodMigrationOutboxPreparer = IronwoodMigrationDueBroadcaster;
typedef IronwoodMigrationOutboxExporter =
    Future<rust_sync.MigrationOutboxBatch?> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
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
    });
typedef IronwoodMigrationKeystoneProofStatusGetter =
    Future<rust_sync.KeystoneMigrationProofStatus> Function({
      required String requestId,
    });
typedef IronwoodMigrationKeystoneRequestDiscarder =
    Future<void> Function({required String requestId});

Future<rust_sync.IronwoodMigrationResult> _defaultStartSoftwareMigration({
  required String dbPath,
  required String lightwalletdUrl,
  required String network,
  required String accountUuid,
  required List<int> mnemonicBytes,
  required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
}) => rust_sync.migrateOrchardToIronwood(
  dbPath: dbPath,
  lightwalletdUrl: lightwalletdUrl,
  network: network,
  accountUuid: accountUuid,
  mnemonicBytes: mnemonicBytes,
  approvedSchedule: approvedSchedule,
);

Future<rust_sync.IronwoodMigrationResult> _defaultStartMacosSoftwareMigration({
  required String dbPath,
  required String lightwalletdUrl,
  required String network,
  required String accountUuid,
  required String password,
  required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
}) => rust_sync.migrateOrchardToIronwoodWithMacosStoredMnemonic(
  dbPath: dbPath,
  lightwalletdUrl: lightwalletdUrl,
  network: network,
  accountUuid: accountUuid,
  password: password,
  approvedSchedule: approvedSchedule,
);

Future<rust_sync.IronwoodMigrationResult>
_defaultCompleteKeystoneDenominationMigration({
  required String dbPath,
  required String lightwalletdUrl,
  required String network,
  required String accountUuid,
  required String requestId,
  required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
}) => rust_sync.completeOrchardMigrationDenominationsPczt(
  dbPath: dbPath,
  lightwalletdUrl: lightwalletdUrl,
  network: network,
  accountUuid: accountUuid,
  requestId: requestId,
  signedMessages: signedMessages,
  approvedSchedule: approvedSchedule,
);

class IronwoodMigrationService {
  IronwoodMigrationService({
    required this.getWalletDbPath,
    required this.getStatus,
    required this.getPrivatePlan,
    IronwoodMigrationBackgroundManifestStore? backgroundManifestStore,
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
    IronwoodMigrationNotificationAuthorizationRequester?
    requestNotificationAuthorization,
    IronwoodMigrationSoftwareStarter? startSoftwareMigration,
    IronwoodMigrationImmediatePlanGetter? getImmediatePlan,
    IronwoodMigrationImmediateStarter? startImmediateMigration,
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
  }) : backgroundManifestStore =
           backgroundManifestStore ??
           IronwoodMigrationBackgroundManifestStore.instance,
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
       requestNotificationAuthorization =
           requestNotificationAuthorization ??
           _defaultRequestNotificationAuthorization,
       startSoftwareMigration =
           startSoftwareMigration ?? _defaultStartSoftwareMigration,
       getImmediatePlan =
           getImmediatePlan ?? rust_sync.getOrchardMigrationImmediatePlan,
       startImmediateMigration =
           startImmediateMigration ??
           rust_sync.migrateOrchardToIronwoodImmediately,
       startMacosSoftwareMigration =
           startMacosSoftwareMigration ?? _defaultStartMacosSoftwareMigration,
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
           _defaultCompleteKeystoneDenominationMigration,
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
  final IronwoodMigrationImmediatePlanGetter getImmediatePlan;
  final IronwoodMigrationBackgroundManifestStore backgroundManifestStore;
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
  final IronwoodMigrationNotificationAuthorizationRequester
  requestNotificationAuthorization;
  final IronwoodMigrationSoftwareStarter startSoftwareMigration;
  final IronwoodMigrationImmediateStarter startImmediateMigration;
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

  final Map<String, Future<void>> _migrationOperationTails = {};

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
        final context = _MigrationContext(
          dbPath: dbPath,
          network: network,
          accountUuid: accountUuid,
        );
        if (!isMobile()) return _getStatusForContext(context);

        return _serializeMigrationState(context, () async {
          final resolvedContext = _contextWithCurrentEndpoint(context);
          var status = await _getStatusForContext(context);
          if (isIOS() && status.activeRunId != null) {
            final manifest = await backgroundManifestStore.read(
              network: context.network,
              accountUuid: context.accountUuid,
            );
            if (manifest == null &&
                await _recoverPersistedMigrationOutbox(
                  context: resolvedContext,
                  status: status,
                )) {
              status = await _getStatusForContext(context);
            }
          }
          await _ensureMobileManifest(
            context: resolvedContext,
            status: status,
            mayCreateRun: false,
          );
          return status;
        });
      },
    );
  }

  /// Restores native denomination preparation for an already-bound migration
  /// after an explicit lifecycle recovery point.
  ///
  /// Ordinary status reads intentionally do not schedule native work. Keeping
  /// this separate prevents account-list/status refreshes from unexpectedly
  /// restarting preparation while the wallet DB is being mutated.
  Future<void> resumeBackgroundPreparationIfNeeded({
    required String network,
    required String accountUuid,
  }) async {
    if (!isIOS() || !isMobile()) return;

    final dbPath = await getWalletDbPath();
    final context = _contextWithCurrentEndpoint(
      _MigrationContext(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      ),
    );
    await operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () => _serializeMigrationState(context, () async {
        final status = await _getStatusForContext(context);
        await _ensureMobileManifest(
          context: context,
          status: status,
          mayCreateRun: false,
        );
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

  Future<rust_sync.OrchardMigrationImmediatePlan?> immediatePlan({
    required String network,
    required String accountUuid,
  }) async {
    return operationRegistry.run(
      network: network,
      accountUuid: accountUuid,
      operation: () async {
        final dbPath = await getWalletDbPath();
        return getImmediatePlan(
          dbPath: dbPath,
          network: network,
          accountUuid: accountUuid,
        );
      },
    );
  }

  Future<rust_sync.IronwoodMigrationResult> startSoftwarePrivateMigration({
    required String accountUuid,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    if (isMacOS()) {
      return _runMigrationOperation(
        context: context,
        mayCreateRun: true,
        operation: () => startMacosSoftwareMigration(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
          password: getSessionPassword(),
          approvedSchedule: approvedSchedule,
        ),
      );
    }

    final result = await _runMigrationOperation(
      context: context,
      mayCreateRun: true,
      enrollNotificationsOnActiveRun: true,
      onCurrentStatus: _reconcileBackgroundPreparationBestEffort,
      operation: () async {
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
  /// background state, or migration outbox.
  Future<rust_sync.IronwoodMigrationResult> startSoftwareImmediateMigration({
    required String accountUuid,
    required rust_sync.OrchardMigrationImmediatePlan approvedPlan,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationContext(
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
            return await startImmediateMigration(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              accountUuid: accountUuid,
              mnemonicBytes: mnemonicBytes,
              approvedTotalInputZatoshi: approvedPlan.totalInputZatoshi,
              approvedFeeZatoshi: approvedPlan.feeZatoshi,
              approvedMigratedZatoshi: approvedPlan.migratedZatoshi,
              approvedInputNoteCount: approvedPlan.inputNoteCount,
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

  Future<rust_sync.IronwoodMigrationResult> continueSoftwarePrivateMigration({
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final context = _MigrationContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    final rust_sync.IronwoodMigrationResult broadcastResult;
    if (isIOS() && isMobile()) {
      broadcastResult = await _runMigrationOperation(
        context: context,
        mayCreateRun: false,
        prepareOutboxAfterOperation: false,
        onCurrentStatus: isHardwareAccount(accountUuid)
            ? null
            : _reconcileBackgroundPreparationBestEffort,
        operation: () => prepareMigrationOutbox(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
        ),
      );
    } else {
      broadcastResult = await _runMigrationOperation(
        context: context,
        mayCreateRun: false,
        operation: () => broadcastDueMigration(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
        ),
      );
    }
    final isHardware = isHardwareAccount(accountUuid);
    if (isHardware || broadcastResult.status != 'ready_to_migrate') {
      return broadcastResult;
    }

    if (isMacOS()) {
      return _runMigrationOperation(
        context: context,
        mayCreateRun: true,
        operation: () => startMacosSoftwareMigration(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
          password: getSessionPassword(),
          approvedSchedule: const [],
        ),
      );
    }

    return _runMigrationOperation(
      context: context,
      mayCreateRun: true,
      operation: () async {
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
    final context = _MigrationContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );
    return operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () => _serializeMigrationState(context, () async {
        final status = await _getStatusForContext(context);
        if (status.activeRunId == null) return false;
        await _ensureMobileManifest(
          context: context,
          status: status,
          mayCreateRun: false,
        );

        if (isIOS()) {
          await _reconcileMigrationOutboxReceipts(context: context);
          final refresh = await _refreshMigrationOutbox(
            context: context,
            prepare: true,
          );
          if (refresh.staged) {
            await _requestNotificationAuthorizationBestEffort();
          }
          return refresh.staged;
        }

        final scheduled = await scheduleBackgroundMigration();
        if (scheduled) {
          await _requestNotificationAuthorizationBestEffort();
        }
        return scheduled;
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
    final context = _MigrationContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    return _runMigrationOperation(
      context: context,
      mayCreateRun: true,
      enrollNotificationsOnActiveRun: true,
      onCurrentStatus: _reconcileBackgroundPreparationBestEffort,
      operation: () => completeKeystoneDenominationMigration(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        requestId: requestId,
        signedMessages: signedMessages,
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
    final context = _MigrationContext(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );

    return _runMigrationOperation(
      context: context,
      mayCreateRun: true,
      enrollNotificationsOnActiveRun: true,
      operation: () => completeKeystoneBatchMigration(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        requestId: requestId,
        signedMessages: signedMessages,
      ),
    );
  }

  Future<T> _runMigrationOperation<T>({
    required _MigrationContext context,
    required bool mayCreateRun,
    required Future<T> Function() operation,
    bool enrollNotificationsOnActiveRun = false,
    bool prepareOutboxAfterOperation = true,
    Future<void> Function(rust_sync.MigrationStatus status)? onCurrentStatus,
  }) async {
    return operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () async {
        if (!isMobile()) {
          return operation();
        }

        return _serializeMigrationState(context, () async {
          final initialStatus = await _getStatusForContext(context);
          await _ensureMobileManifest(
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
            result = await operation();
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
          await _reconcileBackgroundManifest(
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
                prepare: prepareOutboxAfterOperation,
              );
              if ((prepareOutboxAfterOperation && onCurrentStatus != null) ||
                  outboxRefresh.reconciledReceipt) {
                currentStatus = await _getStatusForContext(context);
                await _reconcileBackgroundManifest(
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

  Future<void> _ensureMobileManifest({
    required _MigrationContext context,
    required rust_sync.MigrationStatus status,
    required bool mayCreateRun,
  }) async {
    final activeRunId = status.activeRunId;
    if (activeRunId != null) {
      var manifest = await backgroundManifestStore.read(
        network: context.network,
        accountUuid: context.accountUuid,
      );
      if (manifest == null) {
        final lightwalletdUrl = context.lightwalletdUrl;
        if (lightwalletdUrl == null) {
          throw StateError(
            'Ironwood migration endpoint is unavailable for background setup.',
          );
        }
        manifest = await backgroundManifestStore.prepare(
          network: context.network,
          accountUuid: context.accountUuid,
          dbPath: context.dbPath,
          lightwalletdUrl: lightwalletdUrl,
        );
      }
      await _resolveManifestContext(manifest, context);
      await backgroundManifestStore.bindExpectedRunId(
        network: context.network,
        accountUuid: context.accountUuid,
        expectedRunId: activeRunId,
      );
      return;
    }

    await _reconcileBackgroundManifest(context: context, status: status);
    if (!mayCreateRun) return;
    await backgroundManifestStore.prepare(
      network: context.network,
      accountUuid: context.accountUuid,
      dbPath: context.dbPath,
      lightwalletdUrl: context.lightwalletdUrl!,
    );
  }

  Future<bool> _recoverPersistedMigrationOutbox({
    required _MigrationContext context,
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

    await runMigrationOutboxOnceNow();
    await _reconcileMigrationOutboxReceipts(context: context);
    await _requestNotificationAuthorizationBestEffort();
    return true;
  }

  _MigrationContext _contextWithCurrentEndpoint(_MigrationContext context) {
    if (context.lightwalletdUrl != null) return context;
    try {
      final endpoint = getEndpoint();
      if (endpoint.networkName != context.network) return context;
      return _MigrationContext(
        dbPath: context.dbPath,
        network: context.network,
        accountUuid: context.accountUuid,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      );
    } catch (_) {
      return context;
    }
  }

  Future<rust_sync.MigrationStatus> _getStatusForContext(
    _MigrationContext context,
  ) {
    return getStatus(
      dbPath: context.dbPath,
      network: context.network,
      accountUuid: context.accountUuid,
    );
  }

  Future<void> _reconcileBackgroundManifest({
    required _MigrationContext context,
    required rust_sync.MigrationStatus status,
  }) async {
    final activeRunId = status.activeRunId;
    if (activeRunId != null) {
      final manifest = await backgroundManifestStore.read(
        network: context.network,
        accountUuid: context.accountUuid,
      );
      if (manifest == null) {
        return;
      }
      await _resolveManifestContext(manifest, context);
      await backgroundManifestStore.bindExpectedRunId(
        network: context.network,
        accountUuid: context.accountUuid,
        expectedRunId: activeRunId,
      );
      return;
    }

    IronwoodMigrationBackgroundManifest? manifest;
    try {
      manifest = await backgroundManifestStore.read(
        network: context.network,
        accountUuid: context.accountUuid,
      );
    } on FormatException {
      await backgroundManifestStore.delete(
        network: context.network,
        accountUuid: context.accountUuid,
      );
      if (_isTerminalManifestCleanupPhase(status.phase)) {
        await _cancelBackgroundMigrationBestEffort();
      }
      return;
    }
    if (manifest == null) return;

    await backgroundManifestStore.delete(
      network: context.network,
      accountUuid: context.accountUuid,
    );
    if (manifest.expectedRunId != null ||
        _isTerminalManifestCleanupPhase(status.phase)) {
      await _cancelBackgroundMigrationBestEffort();
    }
  }

  Future<IronwoodMigrationBackgroundManifest> _resolveManifestContext(
    IronwoodMigrationBackgroundManifest manifest,
    _MigrationContext context,
  ) async {
    if (manifest.network == context.network &&
        manifest.accountUuid == context.accountUuid) {
      if (manifest.dbPath == context.dbPath) return manifest;

      final storedDbName = _fileName(manifest.dbPath);
      final currentDbName = _fileName(context.dbPath);
      if (isIOS() && storedDbName != null && storedDbName == currentDbName) {
        return backgroundManifestStore.replaceDbPath(
          network: context.network,
          accountUuid: context.accountUuid,
          expectedDbPath: manifest.dbPath,
          dbPath: context.dbPath,
        );
      }
    }

    throw StateError(
      'Ironwood migration background manifest does not match the active '
      'wallet context.',
    );
  }

  Future<_MigrationOutboxRefreshResult> _refreshMigrationOutbox({
    required _MigrationContext context,
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
      );
    }

    final batch = await exportMigrationOutbox(
      dbPath: context.dbPath,
      network: context.network,
      accountUuid: context.accountUuid,
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
    required _MigrationContext context,
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

  Future<T> _serializeMigrationState<T>(
    _MigrationContext context,
    Future<T> Function() operation,
  ) async {
    final migrationKey = _migrationKey(context);
    final previous =
        _migrationOperationTails[migrationKey] ?? Future<void>.value();
    final release = Completer<void>();
    final current = previous.then((_) => release.future);
    _migrationOperationTails[migrationKey] = current;

    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_migrationOperationTails[migrationKey], current)) {
        _migrationOperationTails.remove(migrationKey);
      }
    }
  }

  String _migrationKey(_MigrationContext context) =>
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
    required _MigrationContext context,
    required rust_sync.MigrationStatus status,
  }) async {
    if (status.phase != kIronwoodMigrationWaitingDenomConfirmationsPhase ||
        status.activeRunId == null) {
      return;
    }
    final manifest = await backgroundManifestStore.read(
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

bool _isTerminalManifestCleanupPhase(String phase) =>
    phase == 'complete' || phase == 'abandoned';

class _MigrationContext {
  const _MigrationContext({
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

String _migrationOutboxBatchId(_MigrationContext context, String runId) =>
    '${context.network}:${context.accountUuid}:$runId';

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
