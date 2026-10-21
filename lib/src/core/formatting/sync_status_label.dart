import 'package:flutter/painting.dart';

import '../../providers/network_privacy_provider.dart';
import '../../providers/sync_failure.dart';
import '../../providers/sync_provider.dart';

/// Presentation of the wallet sync state shared by the desktop sidebar
/// status row and the mobile top nav sync widget.
enum SyncStatusKind {
  syncing,
  failed,
  synced,

  /// A synced wallet's short catch-up (`syncShortCatchUpProvider`): the
  /// label says it is syncing, but the status keeps the synced look (color,
  /// no shimmer, the sidebar block height) so a routine catch-up does not
  /// flash the syncing state every block.
  catchingUp,
}

/// The status label of a synced wallet. The mobile top nav reserves its
/// width, the widest label it shows for long, so shorter labels do not move
/// the nav.
const kSyncStatusSyncedLabel = 'Vizor is synced';

/// Shown while the wallet waits on Tor: the client is still bootstrapping, or
/// the sync's first lightwalletd connection over it has not answered yet
/// (otherwise the row sits on "0% Syncing…" through preflight). Copy is
/// provisional.
const kSyncStatusConnectingToTorLabel = 'Connecting to Tor…';
const kSyncStatusConnectingToTorSemanticsLabel = 'Connecting to Tor';

/// Shown once the Tor bootstrap has failed: nothing retries on its own, so
/// this is a paused state, not a transient one.
const kSyncStatusTorFailedLabel = "Tor couldn't connect...";
const kSyncStatusTorFailedSemanticsLabel = "Tor couldn't connect";

/// Shown while a synced wallet catches up to new blocks and the catch-up is
/// still short (`syncShortCatchUpProvider`): its percentage would start
/// from zero for a few blocks.
const kSyncStatusCatchingUpLabel = 'Syncing…';
const kSyncStatusCatchingUpSemanticsLabel = 'Syncing';

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
  /// [shortCatchUp] (`syncShortCatchUpProvider`) shows a synced wallet's
  /// catch-up without a percentage while it is short. Checking keeps its
  /// label.
  factory SyncStatusLabel.from(
    SyncState sync, {
    int? displayWholePercentage,
    NetworkPrivacyState? networkPrivacy,
    bool shortCatchUp = false,
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
      // Over a connected route, a short catch-up's wait for its first answer
      // is part of the catch-up; only a bootstrap reads as connecting.
      final shortCatchUpOverConnectedTor =
          shortCatchUp &&
          networkPrivacy.status == NetworkPrivacyConnectionStatus.connected;
      if (syncIsWaitingOnTor(networkPrivacy, sync) &&
          !shortCatchUpOverConnectedTor) {
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
    if (shortCatchUp && !sync.isChecking) {
      return const SyncStatusLabel(
        kind: SyncStatusKind.catchingUp,
        label: kSyncStatusCatchingUpLabel,
        semanticsLabel: kSyncStatusCatchingUpSemanticsLabel,
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
        label: formatSyncProgressLabel(pct, isChecking: sync.isChecking),
        semanticsLabel: formatSyncProgressSemanticsLabel(
          pct,
          isChecking: sync.isChecking,
        ),
      );
    }

    return const SyncStatusLabel(
      kind: SyncStatusKind.synced,
      label: kSyncStatusSyncedLabel,
      semanticsLabel: kSyncStatusSyncedLabel,
    );
  }
}

String formatSyncProgressLabel(Object percentage, {required bool isChecking}) =>
    isChecking ? '$percentage% checking' : '$percentage% Syncing…';

/// [formatSyncProgressLabel] as read by a screen reader: the same words,
/// without the trailing ellipsis.
String formatSyncProgressSemanticsLabel(
  Object percentage, {
  required bool isChecking,
}) => isChecking ? '$percentage% checking' : '$percentage% Syncing';

/// [style] with tabular figures, so a changing percentage keeps its width.
TextStyle withTabularFigures(TextStyle style) => style.copyWith(
  fontFeatures: [...?style.fontFeatures, const FontFeature.tabularFigures()],
);

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
    SyncFailureKind.privateStatusCoverage => 'Private lookup',
    SyncFailureKind.endpoint => 'Endpoint error',
    SyncFailureKind.databaseBusy => 'Wallet data busy',
    SyncFailureKind.databaseFatal => 'Wallet data error',
    SyncFailureKind.chainRecovery => 'Chain recovery',
    SyncFailureKind.parseFatal => 'Data error',
    SyncFailureKind.unknown => 'Unknown error',
  };
}
