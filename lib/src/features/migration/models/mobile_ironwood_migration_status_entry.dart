import '../../../rust/api/sync.dart' as rust_sync;

class MobileIronwoodMigrationStatusEntry {
  const MobileIronwoodMigrationStatusEntry({
    this.approvedPlan,
    required this.synchronizeOnEntry,
  });

  final rust_sync.OrchardMigrationPrivatePlan? approvedPlan;
  final bool synchronizeOnEntry;
}
