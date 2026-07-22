import 'dart:async' show Completer;
import 'dart:io' show Platform;

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
typedef IronwoodMigrationSingleDueBroadcaster =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required String password,
      required String saltBase64,
    });
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
    IronwoodMigrationBackgroundCanceler? cancelBackgroundMigration,
    IronwoodMigrationNotificationAuthorizationRequester?
    requestNotificationAuthorization,
    IronwoodMigrationSoftwareStarter? startSoftwareMigration,
    IronwoodMigrationMacosSoftwareStarter? startMacosSoftwareMigration,
    IronwoodMigrationDueBroadcaster? broadcastDueMigration,
    IronwoodMigrationSingleDueBroadcaster? broadcastOneDueMigration,
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
       broadcastOneDueMigration =
           broadcastOneDueMigration ??
           rust_sync.broadcastOneDueOrchardMigrationTransaction,
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
  final IronwoodMigrationBackgroundCanceler cancelBackgroundMigration;
  final IronwoodMigrationNotificationAuthorizationRequester
  requestNotificationAuthorization;
  final IronwoodMigrationSoftwareStarter startSoftwareMigration;
  final IronwoodMigrationMacosSoftwareStarter startMacosSoftwareMigration;
  final IronwoodMigrationDueBroadcaster broadcastDueMigration;
  final IronwoodMigrationSingleDueBroadcaster broadcastOneDueMigration;
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

    return _runCredentialOperation(
      context: context,
      mayCreateRun: true,
      enrollNotificationsOnActiveRun: true,
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

    final broadcastResult = await _runCredentialOperation(
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
    if (isHardwareAccount(accountUuid) ||
        broadcastResult.status != 'ready_to_migrate') {
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

  Future<rust_sync.IronwoodMigrationResult> sendOneDuePrivateMigration({
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
    return _runCredentialOperation(
      context: context,
      mayCreateRun: false,
      operation: (credential) => broadcastOneDueMigration(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        password: credential.password,
        saltBase64: credential.saltBase64,
      ),
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

          late T result;
          Object? operationError;
          StackTrace? operationStackTrace;
          try {
            result = await operation(credential);
          } catch (error, stackTrace) {
            operationError = error;
            operationStackTrace = stackTrace;
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
      await _ensureBackgroundMigrationScheduled(context);
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
      await _ensureBackgroundMigrationScheduled(context);
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

  Future<void> _ensureBackgroundMigrationScheduled(
    _MigrationCredentialContext context,
  ) async {
    final credentialKey = _credentialKey(context);
    if (_scheduledBackgroundMigrations.contains(credentialKey)) return;

    try {
      if (await scheduleBackgroundMigration()) {
        _scheduledBackgroundMigrations.add(credentialKey);
      } else {
        debugPrint('Failed to schedule Ironwood background migration.');
      }
    } catch (error) {
      debugPrint('Failed to schedule Ironwood background migration: $error');
    }
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
