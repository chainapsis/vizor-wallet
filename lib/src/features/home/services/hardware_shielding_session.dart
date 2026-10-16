import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust;
import '../../ledger/services/ledger_operation_lifecycle.dart';
import '../../ledger/services/ledger_signed_operation_service.dart';
import '../../send/services/send_flow.dart' show discardSendProposal;

/// Owns only the process-scoped reservation. Signed checkpoints and submitted
/// transactions keep Rust's durable ownership even after this surface closes.
class HardwareShieldingSession {
  HardwareShieldingSession({
    required this.accountUuid,
    required this.sync,
    required this.lifecycle,
  });

  factory HardwareShieldingSession.forRef(WidgetRef ref, String accountUuid) =>
      HardwareShieldingSession(
        accountUuid: accountUuid,
        sync: ref.read(syncProvider.notifier),
        lifecycle: ref.read(ledgerOperationLifecycleProvider),
      );

  final String accountUuid;
  final SyncNotifier sync;
  final LedgerOperationLifecycle lifecycle;
  late final String flowId = newLedgerSignedOperationId(
    kind: LedgerSignedOperationKind.shield,
    accountUuid: accountUuid,
  );
  Future<rust.ShieldTransparentPcztResult>? _creation;
  rust.ShieldTransparentPcztResult? _prepared;
  Future<void>? _checkpoint;
  Future<rust.ExtractAndBroadcastPcztResult>? _broadcast;
  Future<bool>? _cleanup;
  bool _closed = false;
  bool _durable = false;
  String? _dbPath;
  String? _network;

  Future<rust.ShieldTransparentPcztResult> prepare({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
  }) {
    if (_closed) return Future.error(StateError('Shielding was cancelled.'));
    if (_creation != null && (dbPath != _dbPath || network != _network)) {
      return Future.error(StateError('The shielding wallet changed.'));
    }
    _dbPath = dbPath;
    _network = network;
    return _creation ??= lifecycle.run(() async {
      final prepared = await rust.createShieldTransparentPczt(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        network: network,
        accountUuid: accountUuid,
        sendFlowId: flowId,
      );
      _prepared = prepared;
      return prepared;
    });
  }

  Future<void> checkpoint(Future<void> Function() save) {
    if (_closed) return Future.error(StateError('Shielding was cancelled.'));
    return _checkpoint = lifecycle.run(() async {
      await save();
      _durable = true;
    });
  }

  Future<rust.ExtractAndBroadcastPcztResult> broadcast({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required List<int> proofs,
    required List<int> signatures,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    final prepared = _prepared;
    if (_closed ||
        prepared == null ||
        dbPath != _dbPath ||
        network != _network) {
      return Future.error(StateError('Shielding reservation is unavailable.'));
    }
    return _broadcast = lifecycle.run(() async {
      final result = await rust.storeAndBroadcastSignedPcztsForProposal(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        network: network,
        proposalId: prepared.proposalId,
        sendFlowId: flowId,
        pcztWithProofs: [Uint8List.fromList(proofs)],
        pcztWithSignatures: [Uint8List.fromList(signatures)],
        spendParamsPath: spendParamsPath,
        outputParamsPath: outputParamsPath,
      );
      return rust.ExtractAndBroadcastPcztResult(
        txid: result.txids,
        status: result.status,
        message: result.message,
      );
    });
  }

  Future<bool> close() {
    _closed = true;
    return _cleanup ??= _release().then((released) {
      if (!released) _cleanup = null;
      return released;
    });
  }

  Future<bool> _release() async {
    // Disposal can precede a late creator/checkpoint completion. Wait for its
    // ownership decision rather than losing the returned reservation handle.
    try {
      await _creation;
    } catch (_) {}
    try {
      await _checkpoint;
    } catch (_) {}
    try {
      await _broadcast;
    } catch (_) {}
    if (_durable) return true;
    final prepared = _prepared;
    if (prepared == null) return true;
    try {
      return await lifecycle.run(
        () => discardSendProposal(
          proposalId: prepared.proposalId,
          sendFlowId: flowId,
          logContext: 'HardwareShielding',
          syncNotifier: sync,
          accountUuid: accountUuid,
        ),
      );
    } catch (_) {
      // A wallet mutation may already be draining accepted work. Do not open
      // its database after deletion; Rust's shutdown/startup recovery owns it.
      return false;
    }
  }
}
