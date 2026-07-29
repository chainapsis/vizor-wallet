import '../../../rust/api/sync.dart' as rust_sync;

class MobileIronwoodMigrationStatusEntry {
  const MobileIronwoodMigrationStatusEntry({this.approvedPlan});

  final rust_sync.OrchardMigrationPrivatePlan? approvedPlan;
}
