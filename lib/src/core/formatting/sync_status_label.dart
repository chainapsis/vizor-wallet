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

  factory SyncStatusLabel.from(SyncState sync) {
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
      final pct = formatSyncStatusPercentage(sync.displayPercentage);
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

/// Whole-percent progress capped at 99 so the label never claims 100%
/// while a sync pass is still running.
String formatSyncStatusPercentage(double progress) {
  final pct = (progress.clamp(0.0, 1.0) * 100).toDouble();
  return pct.clamp(0.0, 99.0).toStringAsFixed(0);
}

String _syncFailureReason(SyncFailureKind kind) {
  return switch (kind) {
    SyncFailureKind.network => 'Network error',
    SyncFailureKind.endpoint => 'Endpoint error',
    SyncFailureKind.databaseBusy => 'Wallet data busy',
    SyncFailureKind.databaseFatal => 'Wallet data error',
    SyncFailureKind.chainRecovery => 'Chain recovery',
    SyncFailureKind.parseFatal => 'Data error',
    SyncFailureKind.unknown => 'Unknown error',
  };
}
