/// Which of the Migration tab's four resting states to render.
enum MigrationViewState { softwareRequired, idle, inProgress, complete }

/// Pure selector for the tab state. Kept out of the widget so it is trivially
/// testable without stubbing the account/sync provider stack.
MigrationViewState migrationViewState({
  required bool isHardware,
  required bool hasPendingMigration,
  required bool hasCompletedMigration,
  required BigInt orchardBalance,
  required BigInt ironwoodBalance,
}) {
  if (isHardware) return MigrationViewState.softwareRequired;
  if (hasPendingMigration) return MigrationViewState.inProgress;
  if (orchardBalance > BigInt.zero) return MigrationViewState.idle;
  if (hasCompletedMigration || ironwoodBalance > BigInt.zero) {
    return MigrationViewState.complete;
  }
  return MigrationViewState.idle;
}
