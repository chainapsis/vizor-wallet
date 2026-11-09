import '../../providers/network_privacy_provider.dart';
import '../l10n/l10n.dart';
import '../../providers/sync_failure.dart';
import '../../providers/sync_provider.dart';

/// Presentation of the wallet sync state shared by the desktop sidebar
/// status row and the mobile top nav sync widget.
enum SyncStatusKind { syncing, failed, synced }

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
  ///
  /// While the wallet waits on Tor (still bootstrapping, or the first
  /// lightwalletd connection over it has not answered) the label says so
  /// instead of the preflight "1% Syncing..." floor. A failed Tor bootstrap
  /// is a paused state: nothing retries on its own.
  factory SyncStatusLabel.from(
    AppLocalizations l10n,
    SyncState sync, {
    int? displayWholePercentage,
    NetworkPrivacyState? networkPrivacy,
  }) {
    if (networkPrivacy != null) {
      // `failed` is a Tor connection failure only while the runtime is on
      // Tor and not on its way off it (see `torRouteRetained`).
      if (networkPrivacy.torRouteRetained &&
          networkPrivacy.status == NetworkPrivacyConnectionStatus.failed) {
        return SyncStatusLabel(
          kind: SyncStatusKind.failed,
          label: l10n.syncTorFailed,
          semanticsLabel: l10n.syncTorFailedSemantics,
        );
      }
      if (syncIsWaitingOnTor(networkPrivacy, sync)) {
        return SyncStatusLabel(
          kind: SyncStatusKind.syncing,
          label: l10n.syncConnectingToTor,
          semanticsLabel: l10n.syncConnectingToTorSemantics,
        );
      }
    }
    final failure = sync.failure;
    if (failure != null) {
      final reason = _syncFailureReason(l10n, failure.kind);
      return SyncStatusLabel(
        kind: SyncStatusKind.failed,
        label: l10n.syncFailed(reason),
        semanticsLabel: l10n.syncFailedSemantics(reason),
      );
    }

    final complete =
        !sync.isSyncing &&
        !sync.isChecking &&
        (sync.percentage >= 1.0 ||
            (sync.chainTipHeight > 0 &&
                sync.scannedHeight >= sync.chainTipHeight));
    if (!complete &&
        (sync.isSyncing || sync.isBackgroundMode || sync.isChecking)) {
      final pct =
          displayWholePercentage?.clamp(0, 99).toString() ??
          formatSyncStatusPercentage(
            sync.checking?.percentage ?? sync.percentage,
          );
      return SyncStatusLabel(
        kind: SyncStatusKind.syncing,
        label: formatSyncProgressLabel(l10n, pct, isChecking: sync.isChecking),
        semanticsLabel: sync.isChecking
            ? l10n.syncCheckingPercentSemantics(pct)
            : l10n.syncSyncingPercentSemantics(pct),
      );
    }

    return SyncStatusLabel(
      kind: SyncStatusKind.synced,
      label: l10n.syncVizorSynced,
      semanticsLabel: l10n.syncVizorSynced,
    );
  }
}

String formatSyncProgressLabel(
  AppLocalizations l10n,
  String percentage, {
  required bool isChecking,
}) => isChecking
    ? l10n.syncCheckingProgress(percentage)
    : l10n.syncSyncingProgress(percentage);

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

String _syncFailureReason(AppLocalizations l10n, SyncFailureKind kind) {
  return switch (kind) {
    SyncFailureKind.network => l10n.syncErrorNetwork,
    SyncFailureKind.torUnavailable => l10n.syncTorFailedSemantics,
    SyncFailureKind.privateStatusCoverage => l10n.syncErrorPrivateLookup,
    SyncFailureKind.endpoint => l10n.syncErrorEndpoint,
    SyncFailureKind.databaseBusy => l10n.syncErrorWalletDataBusy,
    SyncFailureKind.databaseFatal => l10n.syncErrorWalletData,
    SyncFailureKind.chainRecovery => l10n.syncErrorChainRecovery,
    SyncFailureKind.parseFatal => l10n.syncErrorData,
    SyncFailureKind.unknown => l10n.syncErrorUnknown,
  };
}
