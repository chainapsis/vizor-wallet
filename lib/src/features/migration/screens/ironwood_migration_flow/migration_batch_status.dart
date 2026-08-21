part of '../ironwood_migration_flow_screen.dart';

enum _MigrationBatchStatus {
  none,
  preparing,
  scheduled,
  migrating,
  confirming,
  complete,
  needsInput,
}

String _migrationPercentage(BigInt value, BigInt total) {
  if (total <= BigInt.zero) return '';
  final tenths = ((value * BigInt.from(1000)) ~/ total).toInt();
  final whole = tenths ~/ 10;
  final decimal = tenths % 10;
  return decimal == 0 ? '$whole%' : '$whole.$decimal%';
}

List<rust_sync.MigrationPartStatus> _displayMigrationParts(
  rust_sync.MigrationStatus status,
) {
  final parts = [...status.parts];
  if (status.phase != kIronwoodMigrationReadyToMigratePhase) {
    return parts;
  }

  final hasTransferProgress =
      status.pendingTxCount > 0 ||
      status.broadcastedTxCount > 0 ||
      status.confirmedTxCount > 0 ||
      status.scheduledBroadcasts.isNotEmpty ||
      parts.any(
        (part) =>
            part.state == rust_sync.MigrationPartState.scheduled ||
            part.state == rust_sync.MigrationPartState.migrating ||
            part.state == rust_sync.MigrationPartState.confirming ||
            part.state == rust_sync.MigrationPartState.needsInput ||
            part.scheduleStartHeight != null ||
            part.scheduledHeight != null,
      );
  if (hasTransferProgress) return parts;
  return const <rust_sync.MigrationPartStatus>[];
}
