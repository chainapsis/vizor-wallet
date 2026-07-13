/// User-facing copy for the migration tab. Sentence case per AGENTS.md.
abstract final class MigrationCopy {
  // Header / entry
  static const idleTitle = 'Migration';
  static const idleBody =
      'Move your Orchard funds into the Ironwood pool. Vizor splits them into '
      'standard notes, then sends them over a short window.';
  static const readyToMigrateLabel = 'Ready to migrate';
  static const poolFlow = 'Orchard pool → Ironwood pool';
  static const migrateCta = 'Migrate';
  static const noFundsNote = 'No Orchard funds to migrate.';
  static const unspendableNote =
      'Waiting for Orchard funds to become spendable. Keep Vizor syncing.';

  // Warning dialog
  static const warningTitle = 'Keep Vizor open during migration';
  static String warningBody(String window) =>
      'Vizor will split your funds, wait for them to confirm, then send them to '
      'Ironwood over $window. Keep Vizor open the whole time — closing early '
      'interrupts the transfers and the run has to resume later.';
  static const warningOversizedLine =
      'This is a large migration — you\'ll scan once more after the split '
      'confirms.';
  static const warningStartCta = 'Start migration';
  static const warningCancelCta = 'Cancel';

  static String migrationWindowText(int seconds) {
    if (seconds == 60) return 'about one minute';
    if (seconds < 90) return 'about $seconds seconds';
    return 'about ${(seconds / 60).round()} minutes';
  }

  // Timeline nodes
  static const splitTitle = 'Split funds';
  static const splitActive = 'Splitting funds…';
  static String splitDone(int count) => 'Done · $count standard notes';
  static const splitDoneGeneric = 'Done';
  static String splitTransactionsPrepared(int count) =>
      '$count split ${count == 1 ? 'transaction' : 'transactions'} prepared';
  static String confirmTitle(int splitTotal) =>
      splitTotal > 1 ? 'Confirm splits' : 'Confirm split';
  static String splitProgress(int completed, int total) {
    if (total <= 0) return 'No splits needed';
    final safeCompleted = completed.clamp(0, total).toInt();
    final splitNoun = total == 1 ? 'split' : 'splits';
    final remaining = total - safeCompleted;
    final remainingNoun = remaining == 1 ? 'split' : 'splits';
    final progress = '$safeCompleted of $total $splitNoun complete';
    return remaining > 0
        ? '$progress · $remaining $remainingNoun remaining'
        : progress;
  }

  static String confirmActive(int count, int target) =>
      currentSplitConfirmations(count, target);
  static String currentSplitConfirmations(
    int confirmationCount,
    int confirmationTarget,
  ) {
    final confirmationNoun = confirmationTarget == 1
        ? 'confirmation'
        : 'confirmations';
    return 'Current confirmation round · $confirmationCount of '
        '$confirmationTarget $confirmationNoun';
  }

  static String confirmDone(int completed, int total) =>
      total > 0 ? splitProgress(completed, total) : 'Confirmed';
  static const sendTitle = 'Send shares';
  static const sendConfirmingTitle = 'Confirming shares';
  static const sendScanCta = 'Scan to sign the sends';
  static const sendResumeCta = 'Resume migration';
  static String sendProgress(int confirmed, int total) =>
      '$confirmed of $total confirmed';

  // Per-share rows
  static String shareLabel(int index) => 'Share $index';
  static const shareConfirmed = 'Confirmed';
  static const shareSending = 'Sending…';
  static const shareScheduled = 'Scheduled';
  static const shareScheduledNow = 'Scheduled now';
  static String shareScheduledIn(String remaining) => 'Scheduled in $remaining';
  static const shareFailed = 'Failed';

  // Done
  static const doneTitle = 'Migration complete';
  static String doneBody(String amount, int count) =>
      '$amount moved to Ironwood across $count transfers.';
  static const doneBodyGeneric = 'Your migration transactions have finished.';

  // Status / errors (preserved)
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
  static const partialBroadcastError =
      'Migration transactions were created locally but not fully broadcast. '
      'Keep Vizor open and do not start another migration.';
  static const globalKeepOpenWarning =
      'Migration is in progress. Keep Vizor open until the Ironwood migration finishes.';

  // Keystone scan (preserved)
  static const scanTitle = 'Scan the signed migration';
  static const scanBody =
      'Point your camera at the signed result QR on your Keystone.';
  static const scanDecodingLabel = 'Reading signed migration...';
  static const scanUnavailable =
      'Scanning the signed migration uses camera QR scanning only. Connect a '
      'camera and try again.';

  // Countdown helper text
  static String migratingAmount(String amount) => 'Migrating $amount';
}
