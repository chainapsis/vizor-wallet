import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/voting/voting_share_outbox_service.dart';
import 'voting_service_providers.dart';

/// The iOS background share outbox. Overridable in tests; a no-op service on
/// every other platform.
final votingShareOutboxProvider = Provider<VotingShareOutboxService>((ref) {
  return VotingShareOutboxService();
});

final votingShareOutboxReconcilerProvider = Provider<VotingShareOutboxReconciler>((
  ref,
) {
  return VotingShareOutboxReconciler(ref);
});

/// Applies background share-outbox receipts to the voting sidecar.
///
/// Runs before the foreground share-tracking restorer decides what is still
/// pending, so the restorer never re-submits work the background lane already
/// finished. Apply-then-ack: both sidecar writes are idempotent, so a crash
/// between apply and ack only re-applies on the next open.
class VotingShareOutboxReconciler {
  VotingShareOutboxReconciler(this._ref);

  final Ref _ref;

  Future<void> reconcile() async {
    final outbox = _ref.read(votingShareOutboxProvider);
    if (!outbox.isSupported) return;
    final receipts = await outbox.listShareReceipts();
    if (receipts.isEmpty) return;

    final dbPath = await _ref.read(votingWalletDbPathProvider).call();
    final rust = _ref.read(votingRustApiProvider);
    final recovery = _ref.read(votingRecoveryServiceProvider);
    final applied = <String>[];
    for (final receipt in receipts) {
      try {
        switch (receipt.outcome) {
          case 'confirmed':
            await rust.markShareConfirmed(
              dbPath: dbPath,
              accountUuid: receipt.accountUuid,
              roundId: receipt.roundId,
              bundleIndex: receipt.bundleIndex,
              proposalId: receipt.proposalId,
              shareIndex: receipt.shareIndex,
            );
          case 'resubmitted':
            final url = receipt.url;
            if (url != null && url.isNotEmpty) {
              await recovery.addSentServersForShareKey(
                dbPath: dbPath,
                accountUuid: receipt.accountUuid,
                roundId: receipt.roundId,
                bundleIndex: receipt.bundleIndex,
                proposalId: receipt.proposalId,
                shareIndex: receipt.shareIndex,
                newUrls: [url],
              );
            }
          case 'expired':
            // The sidecar already ignores shares of expired rounds; nothing
            // to write.
            break;
          default:
            // Unknown outcome from a newer native build: leave it unacked so
            // an updated app can still apply it.
            continue;
        }
        applied.add(receipt.receiptId);
      } catch (error) {
        debugPrint(
          '[zcash] Voting: share receipt apply failed '
          'receipt=${receipt.receiptId} error=$error',
        );
      }
    }
    await outbox.ackShareReceipts(applied);
  }
}
