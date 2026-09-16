import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/ledger.dart' as rust_ledger;
import 'ledger_signing_service.dart' show ledgerWalletDbPathProvider;

enum LedgerSignedOperationKind {
  send('send'),
  swapDeposit('swap_deposit'),
  payDeposit('pay_deposit'),
  shield('shield');

  const LedgerSignedOperationKind(this.wireName);

  final String wireName;

  static LedgerSignedOperationKind parse(String value) {
    return values.firstWhere(
      (candidate) => candidate.wireName == value,
      orElse: () => throw StateError('Unknown Ledger operation kind: $value'),
    );
  }
}

class LedgerSignedOperationMetadata {
  const LedgerSignedOperationMetadata({
    required this.operationId,
    required this.accountUuid,
    required this.kind,
    required this.state,
    this.externalRef,
    this.expiryHeight,
    this.txid,
    this.status,
    this.message,
  });

  final String operationId;
  final String accountUuid;
  final LedgerSignedOperationKind kind;
  final String? externalRef;
  final int? expiryHeight;
  final String state;
  final String? txid;
  final String? status;
  final String? message;
}

class LedgerSignedOperationBroadcastResult {
  const LedgerSignedOperationBroadcastResult({
    required this.operationId,
    required this.txid,
    required this.status,
    required this.requiresAck,
    this.message,
  });

  final String operationId;
  final String txid;
  final String status;
  final String? message;
  final bool requiresAck;
}

abstract interface class LedgerSignedOperationService {
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  });

  Future<List<LedgerSignedOperationMetadata>> list();

  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  });

  Future<void> acknowledge(String operationId);
}

/// Optional capability for operations that contain dependent PCZT rounds.
/// Existing one-round callers and test doubles keep the singular interface.
abstract interface class LedgerSignedOperationBatchCheckpointService {
  Future<void> checkpointBatch({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<List<int>> pcztsWithProofs,
    required List<List<int>> pcztsWithSignatures,
    String? externalRef,
  });
}

final ledgerSignedOperationServiceProvider =
    Provider<LedgerSignedOperationService>((ref) {
      final endpoint = ref.watch(rpcEndpointProvider);
      return RustLedgerSignedOperationService(
        network: endpoint.networkName,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        loadWalletDbPath: ref.watch(ledgerWalletDbPathProvider),
        readBroadcastEndpoint: () =>
            ref.read(rpcEndpointFailoverProvider).current,
        reportBroadcastFailure: (error, attemptedEndpoint) async {
          final switched = await ref
              .read(rpcEndpointFailoverProvider.notifier)
              .switchToFallbackFor(
                error,
                endpoint: attemptedEndpoint,
                operation: 'ledger signed operation broadcast',
              );
          if (switched) {
            unawaited(
              ref
                  .read(syncProvider.notifier)
                  .restartSync()
                  .catchError(
                    (Object error) =>
                        log('LedgerBroadcast: sync restart failed: $error'),
                  ),
            );
          }
        },
      );
    });

class RustLedgerSignedOperationService
    implements
        LedgerSignedOperationService,
        LedgerSignedOperationBatchCheckpointService {
  const RustLedgerSignedOperationService({
    required this.network,
    required this.lightwalletdUrl,
    required this.loadWalletDbPath,
    this.readBroadcastEndpoint,
    this.reportBroadcastFailure,
  });

  final String network;
  final String lightwalletdUrl;
  final Future<String> Function() loadWalletDbPath;
  // Resolve after loading the DB, on every call, including when startup recovery
  // holds this service across multiple operations. Fixed URLs remain available
  // to standalone integration harnesses.
  final RpcEndpointConfig Function()? readBroadcastEndpoint;
  final Future<void> Function(Object, RpcEndpointConfig)?
  reportBroadcastFailure;

  Future<void> _reportFailure(Object error, RpcEndpointConfig? endpoint) async {
    if (endpoint == null) return;
    try {
      await reportBroadcastFailure?.call(error, endpoint);
    } catch (reportError) {
      // Endpoint bookkeeping must not replace a durable transaction outcome.
      log('LedgerBroadcast: could not report RPC failure: $reportError');
    }
  }

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {
    final dbPath = await loadWalletDbPath();
    await rust_ledger.ledgerCheckpointSignedOperation(
      dbPath: dbPath,
      network: network,
      operationId: operationId,
      accountUuid: accountUuid,
      kind: kind.wireName,
      externalRef: externalRef,
      pcztWithProofsBytes: pcztWithProofsBytes,
      pcztWithSignaturesBytes: pcztWithSignaturesBytes,
    );
  }

  @override
  Future<void> checkpointBatch({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<List<int>> pcztsWithProofs,
    required List<List<int>> pcztsWithSignatures,
    String? externalRef,
  }) async {
    final dbPath = await loadWalletDbPath();
    await rust_ledger.ledgerCheckpointSignedOperationBatch(
      dbPath: dbPath,
      network: network,
      operationId: operationId,
      accountUuid: accountUuid,
      kind: kind.wireName,
      externalRef: externalRef,
      pcztWithProofs: pcztsWithProofs.map(Uint8List.fromList).toList(),
      pcztWithSignatures: pcztsWithSignatures.map(Uint8List.fromList).toList(),
    );
  }

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async {
    final dbPath = await loadWalletDbPath();
    final operations = await rust_ledger.ledgerListSignedOperations(
      dbPath: dbPath,
      network: network,
    );
    return [for (final operation in operations) _metadataFromRust(operation)];
  }

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    final dbPath = await loadWalletDbPath();
    final endpoint = readBroadcastEndpoint?.call();
    if (endpoint != null && endpoint.networkName != network) {
      throw StateError('Ledger operation belongs to a different network.');
    }
    try {
      final result = await rust_ledger.ledgerBroadcastSignedOperation(
        dbPath: dbPath,
        lightwalletdUrl: endpoint?.normalizedLightwalletdUrl ?? lightwalletdUrl,
        network: network,
        operationId: operationId,
        spendParamsPath: spendParamsPath,
        outputParamsPath: outputParamsPath,
      );
      if (result.status != 'broadcasted' && result.message != null) {
        await _reportFailure(result.message!, endpoint);
      }
      // Do not replay partial/unknown outcomes: Rust checkpoints them for
      // acknowledgement and reconciliation. Only future attempts use fallback.
      return LedgerSignedOperationBroadcastResult(
        operationId: result.operationId,
        txid: result.txid,
        status: result.status,
        message: result.message,
        requiresAck: result.requiresAck,
      );
    } catch (error) {
      await _reportFailure(error, endpoint);
      rethrow;
    }
  }

  @override
  Future<void> acknowledge(String operationId) async {
    final dbPath = await loadWalletDbPath();
    await rust_ledger.ledgerAckSignedOperation(
      dbPath: dbPath,
      network: network,
      operationId: operationId,
    );
  }
}

LedgerSignedOperationMetadata _metadataFromRust(
  rust_ledger.LedgerSignedOperation operation,
) {
  return LedgerSignedOperationMetadata(
    operationId: operation.operationId,
    accountUuid: operation.accountUuid,
    kind: LedgerSignedOperationKind.parse(operation.kind),
    externalRef: operation.externalRef,
    expiryHeight: operation.expiryHeight,
    state: operation.state,
    txid: operation.txid,
    status: operation.status,
    message: operation.message,
  );
}

String newLedgerSignedOperationId({
  required LedgerSignedOperationKind kind,
  required String accountUuid,
  String? externalRef,
}) {
  final correlation = externalRef?.trim();
  if (correlation != null && correlation.isNotEmpty) {
    return '${kind.wireName}:$accountUuid:$correlation';
  }
  final random = Random.secure();
  final nonce = List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${kind.wireName}:$accountUuid:$nonce';
}

bool isTerminalLedgerSignedOperationError(Object error) {
  return error.toString().toLowerCase().contains(
    'ledger signed operation cannot be retried',
  );
}
