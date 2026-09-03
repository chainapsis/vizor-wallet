import '../../providers/network_privacy_provider.dart';
import '../../providers/sync_failure.dart';
import '../../providers/sync_provider.dart';

/// Presentation of the wallet sync state shared by the desktop sidebar
/// status row and the mobile top nav sync widget.
enum SyncStatusKind { syncing, failed, synced }

/// Shown while the wallet is waiting on Tor: the embedded client is still
/// bootstrapping, or it is up and the sync's first lightwalletd connection
/// over it has not answered yet. Both look identical from the outside — the
/// status row sits on "1% Syncing..." (the preflight display floor) with
/// nothing to say why — and on a warm device the bootstrap is over in a
/// second while that first circuit can take a minute. Copy is provisional.
const kSyncStatusConnectingToTorLabel = 'Connecting to Tor…';
const kSyncStatusConnectingToTorSemanticsLabel = 'Connecting to Tor';

/// Shown once the Tor bootstrap has failed. Nothing retries on its own from
/// there: every request fails until Tor connects on a later toggle or the
/// user turns it off, so this is a paused state, not a transient one.
const kSyncStatusTorFailedLabel = "Tor couldn't connect...";
const kSyncStatusTorFailedSemanticsLabel = "Tor couldn't connect";

class SyncStatusLabel {
  const SyncStatusLabel({
    required this.kind,
    required this.label,
    required this.semanticsLabel,
  });

  final SyncStatusKind kind;
  final String label;
  final String semanticsLabel;

  /// [networkPrivacy] wins over every sync-derived state. A failed Tor
  /// route is the root cause of whatever the sync last recorded, and while
  /// the route is still coming up — or the sync is still waiting for its
  /// first answer over it — a failure or "synced" carried over from the
  /// previous session is stale for as long as that lasts.
  factory SyncStatusLabel.from(
    SyncState sync, {
    int? displayWholePercentage,
    NetworkPrivacyState? networkPrivacy,
  }) {
    if (networkPrivacy != null) {
      if (networkPrivacy.status == NetworkPrivacyConnectionStatus.failed) {
        return const SyncStatusLabel(
          kind: SyncStatusKind.failed,
          label: kSyncStatusTorFailedLabel,
          semanticsLabel: kSyncStatusTorFailedSemanticsLabel,
        );
      }
      if (syncIsWaitingOnTor(networkPrivacy, sync)) {
        return const SyncStatusLabel(
          kind: SyncStatusKind.syncing,
          label: kSyncStatusConnectingToTorLabel,
          semanticsLabel: kSyncStatusConnectingToTorSemanticsLabel,
        );
      }
    }
    final failure = sync.failure;
    if (failure != null) {
      final reason = _syncFailureReason(failure.kind);
      return SyncStatusLabel(
        kind: SyncStatusKind.failed,
        label: 'Syncing failed. $reason...',
        semanticsLabel: 'Syncing failed. $reason',
      );
    }

    final complete =
        !sync.isSyncing &&
        (sync.percentage >= 1.0 ||
            (sync.chainTipHeight > 0 &&
                sync.scannedHeight >= sync.chainTipHeight));
    if (!complete && (sync.isSyncing || sync.isBackgroundMode)) {
      final pct =
          displayWholePercentage?.clamp(0, 99).toString() ??
          formatSyncStatusPercentage(sync.percentage);
      return SyncStatusLabel(
        kind: SyncStatusKind.syncing,
        label: '$pct% Syncing...',
        semanticsLabel: 'Syncing $pct percent',
      );
    }

    return const SyncStatusLabel(
      kind: SyncStatusKind.synced,
      label: 'Vizor is synced',
      semanticsLabel: 'Vizor is synced',
    );
  }
}

/// Whether the sync is blocked on Tor rather than on chain work: the route
/// is still bootstrapping, or it is connected and the sync has not received
/// its first event — that first lightwalletd connection over a fresh circuit
/// is the slow part on a warm device. Direct-route preflight is not covered:
/// it is over in well under a second and needs no explanation.
bool syncIsWaitingOnTor(NetworkPrivacyState networkPrivacy, SyncState sync) {
  if (!networkPrivacy.torEnabled) return false;
  return switch (networkPrivacy.status) {
    NetworkPrivacyConnectionStatus.connecting => true,
    NetworkPrivacyConnectionStatus.connected =>
      sync.isSyncing &&
          sync.failure == null &&
          sync.phase == kSyncPhasePreflight,
    NetworkPrivacyConnectionStatus.off ||
    NetworkPrivacyConnectionStatus.failed => false,
  };
}

/// Whole-percent progress capped at 99 so the label never claims 100%
/// while a sync pass is still running.
String formatSyncStatusPercentage(double progress) {
  final pct = (progress.clamp(0.0, 1.0) * 100).toDouble();
  return pct.clamp(0.0, 99.0).toStringAsFixed(0);
}

String _syncFailureReason(SyncFailureKind kind) {
  return switch (kind) {
    SyncFailureKind.network => 'Network error',
    SyncFailureKind.torUnavailable => kSyncStatusTorFailedSemanticsLabel,
    SyncFailureKind.endpoint => 'Endpoint error',
    SyncFailureKind.databaseBusy => 'Wallet data busy',
    SyncFailureKind.databaseFatal => 'Wallet data error',
    SyncFailureKind.chainRecovery => 'Chain recovery',
    SyncFailureKind.parseFatal => 'Data error',
    SyncFailureKind.unknown => 'Unknown error',
  };
}
