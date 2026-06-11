import '../../../rust/api/sync.dart' as rust_sync;
import 'migration_view_state.dart';

/// Which run action the controller is currently (or was last) executing.
enum MigrationRunIntent { none, preparing, migrating }

enum MigrationStepOneState { blocked, active, running, waiting, done, error }

enum MigrationStepTwoState { locked, ready, running, confirming, done, error }

class MigrationStepsModel {
  const MigrationStepsModel({required this.stepOne, required this.stepTwo});

  final MigrationStepOneState stepOne;
  final MigrationStepTwoState stepTwo;
}

/// Pure selector mapping the rust-derived view state (plus the local run
/// intent) onto the two persistent step cards. Kept widget-free so it is
/// trivially testable, like [migrationViewState].
MigrationStepsModel migrationStepsModel({
  required MigrationViewState viewState,
  required rust_sync.MigrationStatus? status,
  required bool runInFlight,
  required MigrationRunIntent intent,
}) {
  // A run call in flight wins over (lagging) provider state.
  if (runInFlight && intent == MigrationRunIntent.preparing) {
    return const MigrationStepsModel(
      stepOne: MigrationStepOneState.running,
      stepTwo: MigrationStepTwoState.locked,
    );
  }
  if (runInFlight && intent == MigrationRunIntent.migrating) {
    return const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.running,
    );
  }

  final hasMigrationTxs =
      (status?.pendingTxCount ?? 0) > 0 ||
      (status?.broadcastedTxCount ?? 0) > 0;

  return switch (viewState) {
    MigrationViewState.noOrchardFunds ||
    MigrationViewState.waitingForSpendableOrchard => const MigrationStepsModel(
      stepOne: MigrationStepOneState.blocked,
      stepTwo: MigrationStepTwoState.locked,
    ),
    MigrationViewState.planningDenominations => const MigrationStepsModel(
      stepOne: MigrationStepOneState.active,
      stepTwo: MigrationStepTwoState.locked,
    ),
    MigrationViewState.preparingDenominations => const MigrationStepsModel(
      stepOne: MigrationStepOneState.running,
      stepTwo: MigrationStepTwoState.locked,
    ),
    MigrationViewState.waitingDenomConfirmations => const MigrationStepsModel(
      stepOne: MigrationStepOneState.waiting,
      stepTwo: MigrationStepTwoState.locked,
    ),
    MigrationViewState.readyToMigrate =>
      migrationHasSignedChildPczts(status)
          ? const MigrationStepsModel(
              stepOne: MigrationStepOneState.done,
              stepTwo: MigrationStepTwoState.running,
            )
          : const MigrationStepsModel(
              stepOne: MigrationStepOneState.done,
              stepTwo: MigrationStepTwoState.ready,
            ),
    MigrationViewState.paused => const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.ready,
    ),
    MigrationViewState.buildingSigningBatch ||
    MigrationViewState.signingBatch ||
    MigrationViewState.broadcastScheduled ||
    MigrationViewState.broadcasting => const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.running,
    ),
    MigrationViewState.waitingMigrationConfirmations =>
      const MigrationStepsModel(
        stepOne: MigrationStepOneState.done,
        stepTwo: MigrationStepTwoState.confirming,
      ),
    MigrationViewState.complete => const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.done,
    ),
    MigrationViewState.failedRecoverable =>
      hasMigrationTxs
          ? const MigrationStepsModel(
              stepOne: MigrationStepOneState.done,
              stepTwo: MigrationStepTwoState.error,
            )
          : const MigrationStepsModel(
              stepOne: MigrationStepOneState.error,
              stepTwo: MigrationStepTwoState.locked,
            ),
    MigrationViewState.failedTerminal ||
    MigrationViewState.abandoned => const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.error,
    ),
  };
}
