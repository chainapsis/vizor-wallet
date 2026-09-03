import '../../providers/network_privacy_provider.dart';
import '../../providers/sync_failure.dart';
import '../../providers/sync_provider.dart';

/// Presentation of the wallet sync state shared by the desktop sidebar
/// status row and the mobile top nav sync widget.
enum SyncStatusKind { syncing, failed, synced }

/// Shown while the wallet waits on Tor: the client is still bootstrapping, or
/// the sync's first lightwalletd connection over it has not answered yet
/// (otherwise the row sits on the preflight "1% Syncing..." floor). Copy is
/// provisional.
const kSyncStatusConnectingToTorLabel = 'Connecting to Tor…';
const kSyncStatusConnectingToTorSemanticsLabel = 'Connecting to Tor';

/// Shown once the Tor bootstrap has failed: nothing retries on its own, so
/// this is a paused state, not a transient one.
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

  /// [networkPrivacy] wins over the sync-derived state: a failed Tor route is
  /// the root cause of whatever the sync recorded, and while Tor is still
  /// coming up the carried-over sync state is stale.
  factory SyncStatusLabel.from(
    SyncState sync, {
    int? displayWholePercentage,
    NetworkPrivacyState? networkPrivacy,
  }) {
    if (networkPrivacy != null) {
      // `failed` is a Tor connection failure only while the runtime is on
      // Tor and not on its way off it (see `torRouteRetained`).
      if (networkPrivacy.torRouteRetained &&
          networkPrivacy.status == NetworkPrivacyConnectionStatus.failed) {
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

/// Whether Tor is where the route is heading. A disable in progress keeps
/// `torEnabled` true while it drains, so the flag alone would read a route
/// being turned off as one being connected.
bool torIsTargetRoute(NetworkPrivacyState networkPrivacy) =>
    networkPrivacy.targetTorEnabled ?? networkPrivacy.torEnabled;

/// Whether the sync is blocked on Tor rather than on chain work: the route is
/// still bootstrapping, or it is connected and the sync has not received its
/// first event (the first connection over a fresh circuit is the slow part).
/// Direct-route preflight and a disable in progress are not covered.
bool syncIsWaitingOnTor(NetworkPrivacyState networkPrivacy, SyncState sync) {
  if (!torIsTargetRoute(networkPrivacy)) return false;
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
