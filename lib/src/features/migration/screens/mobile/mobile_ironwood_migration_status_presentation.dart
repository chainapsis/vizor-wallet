part of 'mobile_ironwood_migration_flow_screen.dart';

enum MobileIronwoodMigrationPartStatus { complete, needsInput, active, pending }

class MobileIronwoodMigrationPartPresentation {
  const MobileIronwoodMigrationPartPresentation({
    required this.label,
    required this.status,
    this.detail,
    this.eta,
    // ignore: unused_element_parameter
    this.progress,
    this.valueZatoshi,
  });

  final String label;
  final MobileIronwoodMigrationPartStatus status;
  final String? detail;
  final String? eta;
  final BigInt? valueZatoshi;

  /// Only used for an explicitly supplied fixture or a future API contract.
  final double? progress;
}

List<MobileIronwoodMigrationPartPresentation>
_mobileMigrationPartPresentations({
  required rust_sync.MigrationStatus? status,
  required rust_sync.OrchardMigrationPrivatePlan? previewPlan,
  required List<MobileIronwoodMigrationPartPresentation>? explicitParts,
  int? currentHeight,
}) {
  if (explicitParts != null) return explicitParts;

  final statusParts = status?.parts ?? const [];
  if (statusParts.isNotEmpty) {
    final orderedParts = [...statusParts]
      ..sort((left, right) => left.partIndex.compareTo(right.partIndex));
    return [
      for (final part in orderedParts)
        MobileIronwoodMigrationPartPresentation(
          label: 'Part ${part.partIndex + 1}',
          status: _mobileMigrationPartStatus(part.state),
          detail: '${_compactZec(part.valueZatoshi)} ZEC',
          eta: _mobileMigrationPartDetail(
            part,
            status: status,
            currentHeight: currentHeight,
          ),
          progress: _mobileMigrationPartProgress(part),
          valueZatoshi: part.valueZatoshi,
        ),
    ];
  }

  final broadcasts = status?.scheduledBroadcasts ?? const [];
  if (broadcasts.isNotEmpty) {
    return [
      for (var index = 0; index < broadcasts.length; index++)
        MobileIronwoodMigrationPartPresentation(
          label: 'Part ${index + 1}',
          status: switch (broadcasts[index].status.toLowerCase()) {
            'confirmed' => MobileIronwoodMigrationPartStatus.complete,
            'needs_input' => MobileIronwoodMigrationPartStatus.needsInput,
            'broadcasted' ||
            'submitted' ||
            'mined' => MobileIronwoodMigrationPartStatus.active,
            _ => MobileIronwoodMigrationPartStatus.pending,
          },
          detail: '${_compactZec(broadcasts[index].valueZatoshi)} ZEC',
          valueZatoshi: broadcasts[index].valueZatoshi,
          eta: switch (broadcasts[index].status.toLowerCase()) {
            'confirmed' ||
            'broadcasted' ||
            'submitted' ||
            'mined' ||
            'needs_input' => null,
            _ =>
              currentHeight == null || currentHeight <= 0
                  ? 'Waiting'
                  : 'Waiting · ${migrationHeightTimingLabel(broadcasts[index].scheduledHeight, currentHeight: currentHeight)}',
          },
        ),
    ];
  }

  final targetValues = status?.targetValuesZatoshi ?? const [];
  if (targetValues.isNotEmpty) {
    final confirmedCount = status!.confirmedTxCount.clamp(
      0,
      targetValues.length,
    );
    final activeCount = math.max(
      confirmedCount,
      status.broadcastedTxCount.clamp(0, targetValues.length),
    );
    return [
      for (var index = 0; index < targetValues.length; index++)
        MobileIronwoodMigrationPartPresentation(
          label: 'Part ${index + 1}',
          status: index < confirmedCount
              ? MobileIronwoodMigrationPartStatus.complete
              : index < activeCount
              ? MobileIronwoodMigrationPartStatus.active
              : MobileIronwoodMigrationPartStatus.pending,
          detail: '${_compactZec(targetValues[index])} ZEC',
          valueZatoshi: targetValues[index],
          eta: index == status.nextActionPartIndex
              ? _mobileWaitingLabel(status, currentHeight: currentHeight)
              : 'Queued',
        ),
    ];
  }

  final transfers = previewPlan?.scheduledTransfers ?? const [];
  return [
    for (var index = 0; index < transfers.length; index++)
      MobileIronwoodMigrationPartPresentation(
        label: 'Part ${index + 1}',
        status: MobileIronwoodMigrationPartStatus.pending,
        detail: '${_compactZec(transfers[index].valueZatoshi)} ZEC',
        valueZatoshi: transfers[index].valueZatoshi,
        eta: '+${transfers[index].blockOffset} blocks',
      ),
  ];
}

MobileIronwoodMigrationPartStatus _mobileMigrationPartStatus(
  rust_sync.MigrationPartState state,
) => switch (state) {
  rust_sync.MigrationPartState.completed =>
    MobileIronwoodMigrationPartStatus.complete,
  rust_sync.MigrationPartState.needsInput =>
    MobileIronwoodMigrationPartStatus.needsInput,
  rust_sync.MigrationPartState.scheduled =>
    MobileIronwoodMigrationPartStatus.pending,
  rust_sync.MigrationPartState.preparing ||
  rust_sync.MigrationPartState.migrating ||
  rust_sync.MigrationPartState.confirming =>
    MobileIronwoodMigrationPartStatus.active,
};

String? _mobileMigrationPartDetail(
  rust_sync.MigrationPartStatus part, {
  required rust_sync.MigrationStatus? status,
  required int? currentHeight,
}) {
  if (part.state == rust_sync.MigrationPartState.completed) return null;
  if (part.state == rust_sync.MigrationPartState.confirming &&
      part.confirmationTarget > 0) {
    return 'Confirming · '
        '${part.confirmationCount.clamp(0, part.confirmationTarget)}/'
        '${part.confirmationTarget}';
  }
  if (part.state == rust_sync.MigrationPartState.preparing) {
    if (status?.nextActionPartIndex == part.partIndex) {
      return _mobileWaitingLabel(status!, currentHeight: currentHeight);
    }
    return 'Queued';
  }
  return switch (part.state) {
    rust_sync.MigrationPartState.scheduled => _mobileScheduledPartLabel(
      part,
      status: status,
      currentHeight: currentHeight,
    ),
    rust_sync.MigrationPartState.migrating => 'Sending',
    rust_sync.MigrationPartState.needsInput => 'Action needed',
    _ => null,
  };
}

String _mobileScheduledPartLabel(
  rust_sync.MigrationPartStatus part, {
  required rust_sync.MigrationStatus? status,
  required int? currentHeight,
}) {
  final scheduledHeight = part.scheduledHeight;
  if (scheduledHeight == null || currentHeight == null || currentHeight <= 0) {
    return 'Waiting';
  }
  final timing = migrationHeightTimingLabel(
    scheduledHeight,
    currentHeight: currentHeight,
  );
  return 'Waiting · $timing';
}

String _mobileWaitingLabel(
  rust_sync.MigrationStatus status, {
  required int? currentHeight,
}) {
  final timing = migrationNextActionTimingLabel(
    status,
    currentHeight: currentHeight,
  );
  return timing == null ? 'Waiting' : 'Waiting · $timing';
}

double? _mobileMigrationPartProgress(rust_sync.MigrationPartStatus part) {
  if (part.state == rust_sync.MigrationPartState.completed) return 1;
  final confirmationProgress = part.confirmationTarget <= 0
      ? 0.0
      : (part.confirmationCount / part.confirmationTarget).clamp(0.0, 1.0);
  return switch (part.state) {
    rust_sync.MigrationPartState.preparing => confirmationProgress * 0.2,
    rust_sync.MigrationPartState.scheduled => 0.25,
    rust_sync.MigrationPartState.migrating => 0.7,
    rust_sync.MigrationPartState.confirming =>
      0.7 + (confirmationProgress * 0.3),
    rust_sync.MigrationPartState.needsInput => null,
    _ => null,
  };
}

/// Reusable waiting card for the mobile migration status design.
///
/// [partCount] and confirmation values are data-driven. In particular, the
/// Figma sample amount/counts are never used as production defaults.
// ignore: unused_element
