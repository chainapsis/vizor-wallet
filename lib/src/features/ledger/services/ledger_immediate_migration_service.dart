import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../migration/services/ironwood_migration_service.dart';
import '../widgets/ledger_signing_modal.dart';
import 'ledger_signing_service.dart';

typedef LedgerImmediateMigrationDelay =
    Future<void> Function(Duration duration);
typedef LedgerImmediateMigrationClock = DateTime Function();
typedef LedgerImmediateMigrationPhaseChanged =
    void Function(LedgerSigningModalPhase phase);
typedef LedgerImmediateMigrationPreparer =
    Future<rust_sync.KeystoneMigrationSigningRequest> Function({
      required String accountUuid,
      required rust_sync.OrchardMigrationImmediatePlan approvedPlan,
    });
typedef LedgerImmediateMigrationCompleter =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String accountUuid,
      required String requestId,
      required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
    });
typedef LedgerImmediateMigrationProofStatusLoader =
    Future<rust_sync.KeystoneMigrationProofStatus> Function({
      required String requestId,
    });
typedef LedgerImmediateMigrationRequestDiscarder =
    Future<void> Function({
      required String accountUuid,
      required String requestId,
    });

const kLedgerImmediateMigrationProofPollInterval = Duration(seconds: 1);
const kLedgerImmediateMigrationProofTimeout = Duration(minutes: 10);

class LedgerImmediateMigrationCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const LedgerImmediateMigrationCancelled();
    }
  }
}

class LedgerImmediateMigrationCancelled implements Exception {
  const LedgerImmediateMigrationCancelled();

  @override
  String toString() => 'Ledger Immediate migration was cancelled.';
}

class LedgerImmediateMigrationService {
  LedgerImmediateMigrationService({
    required this.prepare,
    required this.complete,
    required this.loadProofStatus,
    required this.discard,
    required this.signPczt,
    this.proofPollInterval = kLedgerImmediateMigrationProofPollInterval,
    this.proofTimeout = kLedgerImmediateMigrationProofTimeout,
    LedgerImmediateMigrationDelay? delay,
    LedgerImmediateMigrationClock? now,
  }) : _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final LedgerImmediateMigrationPreparer prepare;
  final LedgerImmediateMigrationCompleter complete;
  final LedgerImmediateMigrationProofStatusLoader loadProofStatus;
  final LedgerImmediateMigrationRequestDiscarder discard;
  final LedgerVotingPcztSigner signPczt;
  final Duration proofPollInterval;
  final Duration proofTimeout;
  final LedgerImmediateMigrationDelay _delay;
  final LedgerImmediateMigrationClock _now;

  Future<rust_sync.IronwoodMigrationResult> migrate({
    required String accountUuid,
    required rust_sync.OrchardMigrationImmediatePlan approvedPlan,
    required LedgerImmediateMigrationCancellation cancellation,
    required LedgerImmediateMigrationPhaseChanged onPhaseChanged,
  }) async {
    String? requestId;
    var completed = false;
    try {
      cancellation.throwIfCancelled();
      onPhaseChanged(LedgerSigningModalPhase.preparing);
      final request = await prepare(
        accountUuid: accountUuid,
        approvedPlan: approvedPlan,
      );
      requestId = request.requestId;
      cancellation.throwIfCancelled();
      if (request.messages.length != 1) {
        throw StateError(
          'Ledger Immediate migration requires exactly one transaction.',
        );
      }

      final message = request.messages.single;
      onPhaseChanged(LedgerSigningModalPhase.awaitingDevice);
      final signatures = await signPczt(accountUuid, message.redactedPczt);
      cancellation.throwIfCancelled();
      final signedMessage = _signedMessage(message, signatures);

      // Ledger interaction is complete. Proof completion and broadcast are not
      // safe to abandon because the request already contains an approved spend.
      onPhaseChanged(LedgerSigningModalPhase.broadcasting);
      await _waitForProofs(request.requestId);
      final result = await complete(
        accountUuid: accountUuid,
        requestId: request.requestId,
        signedMessages: [signedMessage],
      );
      completed = true;
      return result;
    } finally {
      if (!completed && requestId != null) {
        await discard(accountUuid: accountUuid, requestId: requestId);
      }
    }
  }

  rust_sync.KeystoneSignedMigrationMessage _signedMessage(
    rust_sync.KeystoneMigrationMessage message,
    List<LedgerVotingSignature> signatures,
  ) {
    if (signatures.length != message.expectedSignatureCount) {
      throw StateError(
        'Ledger returned a different number of migration signatures than requested.',
      );
    }
    final locations = <(int, int)>{};
    final mapped = <rust_keystone.KeystoneActionSig>[];
    for (final signature in signatures) {
      if (signature.signature.length != 64 ||
          !locations.add((signature.pool, signature.actionIndex))) {
        throw StateError(
          'Ledger returned an invalid migration spend signature.',
        );
      }
      mapped.add(
        rust_keystone.KeystoneActionSig(
          pool: signature.pool,
          actionIndex: signature.actionIndex,
          sig: Uint8List.fromList(signature.signature),
        ),
      );
    }
    return rust_sync.KeystoneSignedMigrationMessage(
      id: message.id,
      sigs: mapped,
    );
  }

  Future<void> _waitForProofs(String requestId) async {
    final deadline = _now().add(proofTimeout);
    while (true) {
      final status = await loadProofStatus(requestId: requestId);
      if (status.isFailed) {
        throw StateError(
          status.message ?? 'Vizor could not prepare migration proofs.',
        );
      }
      if (status.isReady) return;
      if (!_now().isBefore(deadline)) {
        throw StateError('Timed out while preparing migration proofs.');
      }
      await _delay(proofPollInterval);
    }
  }
}

final ledgerImmediateMigrationServiceProvider =
    Provider<LedgerImmediateMigrationService>((ref) {
      final migrationService = ref.watch(ironwoodMigrationServiceProvider);
      return LedgerImmediateMigrationService(
        prepare: migrationService.prepareHardwareImmediateMigrationRequest,
        complete: migrationService.completeHardwareImmediateMigrationRequest,
        loadProofStatus: migrationService.hardwareMigrationProofStatus,
        discard: migrationService.discardHardwareMigrationRequest,
        signPczt: ref.watch(ledgerActionPcztSignerProvider),
      );
    });
