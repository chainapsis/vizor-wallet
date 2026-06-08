/// User-facing copy for the migration showcase. Sentence case per AGENTS.md.
abstract final class MigrationCopy {
  static const tabLabel = 'Migration';

  // Idle / landing
  static const idleTitle = 'Migration';
  static const idleBody =
      "Move your shielded ZEC to Ironwood, Zcash's next-generation shielded "
      'pool. This software-wallet test path creates real Ironwood migration '
      'transactions on the selected testnet endpoint.';
  static const fromPoolName = 'Orchard';
  static const fromPoolTag = 'Current pool';
  static const toPoolName = 'Ironwood';
  static const toPoolTag = 'New pool';
  static const readyToMigrateLabel = 'Ready to migrate';
  static const poolFlow = 'Orchard pool → Ironwood pool';
  static const bullet1 =
      'Software wallet migration sends Orchard funds to Ironwood.';
  static const bullet2 = 'Use a testnet endpoint that understands NU7 blocks.';
  static const bullet3 = 'Keystone and PCZT migration support will come later.';
  static const startCta = 'Start migration';

  // Hardware-account state
  static const softwareRequiredTitle = 'Migration';
  static const softwareRequiredBody =
      'Migration is available for software accounts in this build. Switch to '
      'a software account to test it.';

  // Broadcast
  static const signTitle = 'Starting migration';
  static const signSubtitle = 'Creating Ironwood transactions';
  static const signInstruction =
      'Keep Vizor open while the migration transactions are created and broadcast.';
  static const signCancel = 'Cancel';
  static const broadcastingTitle = 'Broadcasting migration';
  static const broadcastingSubtitle = 'Sending your transactions';
  static const broadcastingInstruction =
      'Keep Vizor open while your migration transactions are sent.';
  static const signBack = 'Back';

  // Scan
  static const scanTitle = 'Scan the signed migration';
  static const scanBody =
      'Point your camera at the signed result QR on your Keystone.';
  static const scanDecodingLabel = 'Reading signed migration...';
  static const scanUnavailable =
      'Scanning the signed migration uses camera QR scanning only. Connect a '
      'camera and try again.';

  // Completion popup
  static const completeTitle = 'Migration started';
  static const completeBody =
      'Your migration transactions were created and sent to the selected '
      'testnet endpoint.';
  static const completeButton = 'Got it';

  // In progress
  static const inProgressTitle = 'Migration in progress';
  static const inProgressBody =
      'Your funds are moving from Orchard to Ironwood.';
  static String migratingAmount(String amount) => 'Migrating $amount';
  static String transferLabel(int index, int total) =>
      'Transfer $index of $total';
  static const transferSent = 'Sent';
  static const keepOpenWarning =
      'Keep Vizor connected to the Ironwood testnet while these transactions confirm.';
  static const resetCta = 'Reset demo';

  // Done
  static const doneTitle = 'Migration complete';
  static const doneBody = 'Your migration transactions have finished.';
  static const doneButton = 'Done';

  // Errors
  static const genericError =
      'Migration could not be started. Please try again.';
}
