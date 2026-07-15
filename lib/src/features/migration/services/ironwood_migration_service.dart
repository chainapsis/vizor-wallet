import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

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
typedef IronwoodMigrationSoftwareStarter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required List<int> mnemonicBytes,
      required String password,
      required String saltBase64,
    });
typedef IronwoodMigrationMacosSoftwareStarter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required String accountUuid,
      required String password,
      required String saltBase64,
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
typedef IronwoodMigrationKeystoneRequestDiscarder =
    Future<void> Function({required String requestId});

class IronwoodMigrationService {
  IronwoodMigrationService({
    required this.getWalletDbPath,
    required this.getStatus,
    required this.getPrivatePlan,
    required this.secureStore,
    IronwoodMigrationEndpointGetter? getEndpoint,
    IronwoodMigrationPasswordGetter? getSessionPassword,
    IronwoodMigrationMnemonicBytesGetter? getMnemonicBytesForAccount,
    IronwoodMigrationPlatformCheck? isMacOS,
    IronwoodMigrationSoftwareStarter? startSoftwareMigration,
    IronwoodMigrationMacosSoftwareStarter? startMacosSoftwareMigration,
    IronwoodMigrationDueBroadcaster? broadcastDueMigration,
    IronwoodMigrationKeystoneDenominationPreparer?
    prepareKeystoneDenominationMigration,
    IronwoodMigrationKeystoneDenominationCompleter?
    completeKeystoneDenominationMigration,
    IronwoodMigrationKeystoneBatchPreparer? prepareKeystoneBatchMigration,
    IronwoodMigrationKeystoneBatchCompleter? completeKeystoneBatchMigration,
    IronwoodMigrationKeystoneRequestDiscarder? discardKeystoneMigrationRequest,
  }) : getEndpoint = getEndpoint ?? _missingEndpoint,
       getSessionPassword = getSessionPassword ?? _missingSessionPassword,
       getMnemonicBytesForAccount =
           getMnemonicBytesForAccount ?? _missingMnemonicBytesForAccount,
       isMacOS = isMacOS ?? _defaultIsMacOS,
       startSoftwareMigration =
           startSoftwareMigration ?? rust_sync.migrateOrchardToIronwood,
       startMacosSoftwareMigration =
           startMacosSoftwareMigration ??
           rust_sync.migrateOrchardToIronwoodWithMacosStoredMnemonic,
       broadcastDueMigration =
           broadcastDueMigration ??
           rust_sync.broadcastDueOrchardMigrationTransactions,
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
       discardKeystoneMigrationRequest =
           discardKeystoneMigrationRequest ??
           rust_sync.discardKeystoneMigrationRequest;

  final IronwoodMigrationWalletDbPathGetter getWalletDbPath;
  final IronwoodMigrationStatusGetter getStatus;
  final IronwoodMigrationPrivatePlanGetter getPrivatePlan;
  final AppSecureStore secureStore;
  final IronwoodMigrationEndpointGetter getEndpoint;
  final IronwoodMigrationPasswordGetter getSessionPassword;
  final IronwoodMigrationMnemonicBytesGetter getMnemonicBytesForAccount;
  final IronwoodMigrationPlatformCheck isMacOS;
  final IronwoodMigrationSoftwareStarter startSoftwareMigration;
  final IronwoodMigrationMacosSoftwareStarter startMacosSoftwareMigration;
  final IronwoodMigrationDueBroadcaster broadcastDueMigration;
  final IronwoodMigrationKeystoneDenominationPreparer
  prepareKeystoneDenominationMigration;
  final IronwoodMigrationKeystoneDenominationCompleter
  completeKeystoneDenominationMigration;
  final IronwoodMigrationKeystoneBatchPreparer prepareKeystoneBatchMigration;
  final IronwoodMigrationKeystoneBatchCompleter completeKeystoneBatchMigration;
  final IronwoodMigrationKeystoneRequestDiscarder
  discardKeystoneMigrationRequest;

  Future<rust_sync.MigrationStatus> status({
    required String network,
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    return getStatus(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
    );
  }

  Future<rust_sync.OrchardMigrationPrivatePlan?> privatePlan({
    required String network,
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    return getPrivatePlan(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
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
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final network = endpoint.networkName;
    final password = getSessionPassword();
    final saltBase64 = await pendingTxSaltBase64(
      network: network,
      accountUuid: accountUuid,
    );

    if (isMacOS()) {
      return startMacosSoftwareMigration(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: network,
        accountUuid: accountUuid,
        password: password,
        saltBase64: saltBase64,
      );
    }

    final mnemonicBytes = await getMnemonicBytesForAccount(accountUuid);
    if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
      throw Exception('Mnemonic not found for the migration account.');
    }

    late final Future<rust_sync.IronwoodMigrationResult> resultFuture;
    try {
      resultFuture = startSoftwareMigration(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: network,
        accountUuid: accountUuid,
        mnemonicBytes: mnemonicBytes,
        password: password,
        saltBase64: saltBase64,
      );
    } finally {
      mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
    }

    return resultFuture;
  }

  Future<rust_sync.IronwoodMigrationResult> continueSoftwarePrivateMigration({
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final network = endpoint.networkName;
    final password = getSessionPassword();
    final saltBase64 = await pendingTxSaltBase64(
      network: network,
      accountUuid: accountUuid,
    );

    return broadcastDueMigration(
      dbPath: dbPath,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      network: network,
      accountUuid: accountUuid,
      password: password,
      saltBase64: saltBase64,
    );
  }

  Future<rust_sync.KeystoneMigrationSigningRequest>
  prepareKeystoneDenominationPrivateMigration({
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    return prepareKeystoneDenominationMigration(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
    );
  }

  Future<rust_sync.IronwoodMigrationResult>
  completeKeystoneDenominationPrivateMigration({
    required String accountUuid,
    required String requestId,
    required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    final network = endpoint.networkName;
    final password = getSessionPassword();
    final saltBase64 = await pendingTxSaltBase64(
      network: network,
      accountUuid: accountUuid,
    );

    return completeKeystoneDenominationMigration(
      dbPath: dbPath,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      network: network,
      accountUuid: accountUuid,
      requestId: requestId,
      signedMessages: signedMessages,
      password: password,
      saltBase64: saltBase64,
    );
  }

  Future<rust_sync.KeystoneMigrationSigningRequest>
  prepareKeystoneBatchPrivateMigration({required String accountUuid}) async {
    final dbPath = await getWalletDbPath();
    final endpoint = getEndpoint();
    return prepareKeystoneBatchMigration(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
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
    final network = endpoint.networkName;
    final password = getSessionPassword();
    final saltBase64 = await pendingTxSaltBase64(
      network: network,
      accountUuid: accountUuid,
    );

    return completeKeystoneBatchMigration(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
      requestId: requestId,
      signedMessages: signedMessages,
      password: password,
      saltBase64: saltBase64,
    );
  }

  Future<void> discardKeystonePrivateMigrationRequest({
    required String requestId,
  }) {
    return discardKeystoneMigrationRequest(requestId: requestId);
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
