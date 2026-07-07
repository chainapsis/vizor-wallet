import '../../../l10n/app_localizations.dart';
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

  factory SyncStatusLabel.from(SyncState sync, AppLocalizations l10n) {
    final failure = sync.failure;
    if (failure != null) {
      final reason = syncFailureReason(failure.kind, l10n);
      return SyncStatusLabel(
        kind: SyncStatusKind.failed,
        label: l10n.syncStatusFailedLabel(reason),
        semanticsLabel: l10n.syncStatusFailedSemantics(reason),
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
        label: l10n.syncStatusSyncingLabel(pct),
        semanticsLabel: l10n.syncStatusSyncingSemantics(pct),
      );
    }

    return SyncStatusLabel(
      kind: SyncStatusKind.synced,
      label: l10n.syncStatusSynced,
      semanticsLabel: l10n.syncStatusSynced,
    );
  }
}

/// Whole-percent progress capped at 99 so the label never claims 100%
/// while a sync pass is still running.
String formatSyncStatusPercentage(double progress) {
  final pct = (progress.clamp(0.0, 1.0) * 100).toDouble();
  return pct.clamp(0.0, 99.0).toStringAsFixed(0);
}

/// Localized long-form guidance for a sync failure, shown by the home
/// notice banner. `SyncFailure.userMessage` keeps the English original for
/// logs; UI reads this instead.
String syncFailureUserMessage(SyncFailureKind kind, AppLocalizations l10n) {
  return switch (kind) {
    SyncFailureKind.network => l10n.syncUserMessageNetwork,
    SyncFailureKind.endpoint => l10n.syncUserMessageEndpoint,
    SyncFailureKind.databaseBusy => l10n.syncUserMessageDatabaseBusy,
    SyncFailureKind.databaseFatal => l10n.syncUserMessageDatabaseFatal,
    SyncFailureKind.chainRecovery => l10n.syncUserMessageChainRecovery,
    SyncFailureKind.parseFatal => l10n.syncUserMessageParse,
    SyncFailureKind.unknown => l10n.syncUserMessageUnknown,
  };
}

String syncFailureReason(SyncFailureKind kind, AppLocalizations l10n) {
  return switch (kind) {
    SyncFailureKind.network => l10n.syncFailureNetwork,
    SyncFailureKind.endpoint => l10n.syncFailureEndpoint,
    SyncFailureKind.databaseBusy => l10n.syncFailureDatabaseBusy,
    SyncFailureKind.databaseFatal => l10n.syncFailureDatabaseFatal,
    SyncFailureKind.chainRecovery => l10n.syncFailureChainRecovery,
    SyncFailureKind.parseFatal => l10n.syncFailureParse,
    SyncFailureKind.unknown => l10n.syncFailureUnknown,
  };
}
