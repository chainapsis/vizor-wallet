/// User-facing copy for the migration showcase. Sentence case per AGENTS.md.
abstract final class MigrationCopy {
  // Header
  static const idleTitle = 'Migration';
  static const idleBody =
      'Prepare Orchard funds as standard note amounts, then migrate those '
      'notes to Ironwood over a short submission window.';
  static const readyToMigrateLabel = 'Ready to prepare';
  static const poolFlow = 'Orchard pool → Ironwood pool';

  // Two-step layout
  static const stepOneTitle = 'Prepare migration';
  static const stepOneBody =
      'Split Orchard funds into standard note amounts and prepare the '
      'Ironwood migration.';
  static const stepOneCta = 'Prepare migration';
  static const stepOneRunning =
      'Creating, signing, and submitting the preparation transaction...';
  static String stepOneWaitingConfirmations(int count, int target) =>
      'Waiting for $target confirmations. Confirmation $count of $target.';
  static String stepOneDone(int count) => '$count prepared notes ready.';
  static const stepOneDoneGeneric = 'Prepared notes ready.';
  static String stepOnePreparedCounts(int prepared, int total) =>
      'Prepared notes: $prepared of $total';
  static const stepOneNoFunds = 'No Orchard funds to prepare.';
  static const stepOneUnspendable =
      'Waiting for Orchard funds to become spendable. Keep Vizor syncing.';
  static const stepTwoTitle = 'Submit to Ironwood';
  static const stepTwoLocked =
      'Vizor will continue once the prepared notes confirm.';
  static String stepTwoReady(int count, String window) =>
      'Vizor submits $count migration transactions over '
      '$window.';
  static const stepTwoCta = 'Submit migration';
  static const stepTwoSigning = 'Finalizing migration transactions...';
  static String stepTwoScheduled(String remaining) =>
      'Migration transactions are signed. Next submission $remaining.';
  static const stepTwoScheduledWaiting =
      'Migration transactions are signed and scheduled.';
  static String stepTwoSubmitting(int index, int total) =>
      'Submitting migration transaction $index of $total...';
  static const stepTwoPausedNote =
      'Migration paused. Start migration to resume this run.';
  static const partialBroadcastError =
      'Migration transactions were created locally but not fully broadcast. '
      'Keep Vizor open and do not start another migration.';

  static String migrationWindowText(int seconds) {
    if (seconds == 60) return 'about one minute';
    if (seconds < 90) return 'about $seconds seconds';
    return 'about ${(seconds / 60).round()} minutes';
  }

  // Status
  static const checkingTitle = 'Checking migration';
  static const checkingBody = 'Checking the current Orchard migration state.';
  static const retryCta = 'Retry migration';
  static const failedRecoverableTitle = 'Migration needs attention';
  static const failedRecoverableBody =
      'This migration run can be retried after the wallet is synced.';
  static const failedTerminalBody =
      'This migration run cannot continue automatically.';
  static const abandonedBody =
      'This migration run was abandoned. Future starts will reconcile wallet '
      'state from scratch.';

  // Scan
  static const scanTitle = 'Scan the signed migration';
  static const scanBody =
      'Point your camera at the signed result QR on your Keystone.';
  static const scanDecodingLabel = 'Reading signed migration...';
  static const scanUnavailable =
      'Scanning the signed migration uses camera QR scanning only. Connect a '
      'camera and try again.';

  // In progress
  static const inProgressBody =
      'Prepared notes are being submitted and confirmed on Ironwood.';
  static String migratingAmount(String amount) => 'Migrating $amount';
  static String transferLabel(int index, int total) =>
      'Transfer $index of $total';
  static String scheduledSubmissionLabel(int index, int total) =>
      'Submission $index of $total';
  static const globalKeepOpenWarning =
      'Migration is in progress. Keep Vizor open until the Ironwood migration finishes.';

  // Done
  static const doneBody = 'Your migration transactions have finished.';
}
