import '../../../rust/api/sync.dart' show ReservedPcztBatchItem;
import '../../../rust/wallet/keystone.dart' show ZcashBatchSignResult;

/// User-facing error for the migration batch flow. Its [message] is safe to
/// show directly.
class MigrationBatchError implements Exception {
  MigrationBatchError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Throws if any two batch items reserve the same shielded note, which would
/// make the batch invalid. Mirrors PR 72's collision guard.
void verifyDistinctNotes(List<ReservedPcztBatchItem> items) {
  final owners = <String, String>{};
  for (final item in items) {
    for (final nullifier in item.spendNullifiers) {
      if (owners.containsKey(nullifier)) {
        throw MigrationBatchError(
          'This demo needs at least 3 spendable notes. Receive a few '
          'payments, let Vizor sync, then try again.',
        );
      }
      owners[nullifier] = item.id;
    }
  }
}

/// Throws if the scanned sign-result does not correspond to the batch we sent.
void verifySignResult(
  ZcashBatchSignResult result,
  String expectedRequestId,
  Set<String> expectedIds,
) {
  if (result.requestId != expectedRequestId) {
    throw MigrationBatchError('Scanned result is for a different request.');
  }
  final ids = result.results.map((m) => m.id).toSet();
  if (result.results.length != expectedIds.length ||
      !ids.containsAll(expectedIds)) {
    throw MigrationBatchError('Scanned result does not match this migration.');
  }
}
