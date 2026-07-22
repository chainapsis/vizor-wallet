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
      required String password,
      required String saltBase64,
    });
typedef IronwoodMigrationOutboxBatchStager =
    Future<Map<String, String>> Function(Map<String, Object?> payload);
typedef IronwoodMigrationOutboxBatchArmer =
    Future<bool> Function({
      required String batchId,
      required Map<String, String> expectedDigests,
    });
typedef IronwoodMigrationOutboxReceiptLister =
    Future<List<Map<Object?, Object?>>> Function();
typedef IronwoodMigrationOutboxReceiptAcknowledger =
    Future<void> Function(List<String> receiptIds);
typedef IronwoodMigrationOutboxForegroundRunner = Future<void> Function();
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
    IronwoodMigrationNotificationAuthorizationRequester?
    requestNotificationAuthorization,
    IronwoodMigrationSoftwareStarter? startSoftwareMigration,
    IronwoodMigrationMacosSoftwareStarter? startMacosSoftwareMigration,
    IronwoodMigrationDueBroadcaster? broadcastDueMigration,
    IronwoodMigrationOutboxPreparer? prepareMigrationOutbox,
    IronwoodMigrationOutboxExporter? exportMigrationOutbox,
    IronwoodMigrationOutboxReceiptReconciler? reconcileMigrationOutboxReceipt,
    IronwoodMigrationOutboxBatchStager? stageMigrationOutboxBatch,
    IronwoodMigrationOutboxBatchArmer? armMigrationOutboxBatch,
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
       requestNotificationAuthorization =
           requestNotificationAuthorization ??
           _defaultRequestNotificationAuthorization,
       startSoftwareMigration =
           startSoftwareMigration ?? rust_sync.migrateOrchardToIronwood,
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
  final IronwoodMigrationNotificationAuthorizationRequester
  requestNotificationAuthorization;
  final IronwoodMigrationSoftwareStarter startSoftwareMigration;
  final IronwoodMigrationMacosSoftwareStarter startMacosSoftwareMigration;
  final IronwoodMigrationDueBroadcaster broadcastDueMigration;
  final IronwoodMigrationOutboxPreparer prepareMigrationOutbox;
  final IronwoodMigrationOutboxExporter exportMigrationOutbox;
  final IronwoodMigrationOutboxReceiptReconciler
  reconcileMigrationOutboxReceipt;
  final IronwoodMigrationOutboxBatchStager stageMigrationOutboxBatch;
  final IronwoodMigrationOutboxBatchArmer armMigrationOutboxBatch;
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
          final status = await _getStatusForContext(context);
          await _reconcileBackgroundCredential(
            context: context,
            status: status,
          );
          return status;
        });
      },
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

  /// Starts a user-attended migration broadcast without enrolling the run in
  /// iOS background preparation or the migration outbox. This is deliberately
  /// separate from [startSoftwarePrivateMigration]: Immediate migration is a
  /// foreground action and must not acquire background credentials.
  Future<rust_sync.IronwoodMigrationResult> startSoftwareImmediateMigration({
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

    return operationRegistry.run(
      network: context.network,
      accountUuid: context.accountUuid,
      operation: () async {
        final credential = await _legacyCredential(context);
        if (isMacOS()) {
          return startMacosSoftwareMigration(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            password: credential.password,
            saltBase64: credential.saltBase64,
            approvedSchedule: approvedSchedule,
          );
        }

        final mnemonicBytes = await getMnemonicBytesForAccount(accountUuid);
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          throw Exception('Mnemonic not found for the migration account.');
        }
        try {
          return await startSoftwareMigration(
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
        if (manifest == null) return false;
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
          await _reconcileMigrationOutboxReceipts(
            context: context,
            credential: credential,
          );
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
            await _reconcileMigrationOutboxReceipts(
              context: context,
              credential: credential,
            );
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
              await _reconcileMigrationOutboxReceipts(
                context: context,
                credential: credential,
              );
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
          if (isIOS() && currentStatus.activeRunId != null) {
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
          await onCurrentStatus?.call(currentStatus);
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
      if (manifest == null) return _legacyCredential(context);
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

    try {
      await runMigrationOutboxOnceNow();
    } catch (error) {
      debugPrint(
        'Failed to run Ironwood migration outbox in foreground: $error',
      );
    }
    final reconciledReceipt = await _reconcileMigrationOutboxReceipts(
      context: context,
      credential: credential,
    );
    return _MigrationOutboxRefreshResult(
      staged: true,
      reconciledReceipt: reconciledReceipt,
    );
  }

  Future<bool> _reconcileMigrationOutboxReceipts({
    required _MigrationCredentialContext context,
    required _MigrationCredential credential,
  }) async {
    final rawReceipts = await listMigrationOutboxReceipts();
    final acknowledgedReceiptIds = <String>[];
    Object? firstError;
    StackTrace? firstStackTrace;

    for (final rawReceipt in rawReceipts) {
      final receipt = _MigrationOutboxReceipt.fromMap(rawReceipt);
      if (receipt.network != context.network ||
          receipt.accountUuid != context.accountUuid) {
        continue;
      }
      try {
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
          password: credential.password,
          saltBase64: credential.saltBase64,
        );
        acknowledgedReceiptIds.add(receipt.receiptId);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
        break;
      }
    }

    if (acknowledgedReceiptIds.isNotEmpty) {
      await acknowledgeMigrationOutboxReceipts(acknowledgedReceiptIds);
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
    return acknowledgedReceiptIds.isNotEmpty;
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

Future<void> _defaultRunMigrationOutboxOnceNow() async {
  await _backgroundMigrationChannel.invokeMethod<Map<Object?, Object?>>(
    'runOutboxOnceNow',
  );
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
