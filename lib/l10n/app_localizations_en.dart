// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accountsActionsLabel => 'Account actions';

  @override
  String get accountsAdd => 'Add account';

  @override
  String get accountsAddressLoadFailed => 'Couldn\'t load the account address';

  @override
  String get accountsChangeProfilePicture => 'Change profile picture';

  @override
  String get accountsClearName => 'Clear account name';

  @override
  String get accountsCurrent => 'Current';

  @override
  String get accountsEdit => 'Edit account';

  @override
  String get accountsEditFailed => 'Couldn\'t update account.';

  @override
  String get accountsEditNameHint => '1-20 characters';

  @override
  String get accountsEditNameLabel => 'Account name';

  @override
  String get accountsManage => 'Manage accounts';

  @override
  String accountsOptionsFor(String name) {
    return 'Account options for $name';
  }

  @override
  String get accountsOther => 'Other';

  @override
  String get accountsOtherAccounts => 'Other accounts';

  @override
  String get accountsRemove => 'Remove account';

  @override
  String get accountsRemoveBackupWarning =>
      'If you haven’t backed up this account’s secret passphrase, you can’t recover its funds after removal.';

  @override
  String accountsRemoveBlockedByGiftCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This account is receiving $count gift cards. Wait for them to finish before removing this account.',
      one:
          'This account is receiving a gift card. Wait for it to finish before removing this account.',
    );
    return '$_temp0';
  }

  @override
  String accountsRemoveBlockedBySwaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This account has $count active swaps. Complete or remove them from swap activity before removing this account.',
      one:
          'This account has 1 active swap. Complete or remove them from swap activity before removing this account.',
    );
    return '$_temp0';
  }

  @override
  String get accountsRemoveBody =>
      'Removing this account deletes its local data from Vizor. Make sure you can re-import it before continuing.';

  @override
  String get accountsRemoveCheckingGiftCards =>
      'Checking this account for incoming gift cards before removal.';

  @override
  String get accountsRemoveCheckingPassword => 'Checking password...';

  @override
  String get accountsRemoveCheckingSwaps =>
      'Checking this account for active swaps before removal.';

  @override
  String get accountsRemoveConfirm => 'Remove';

  @override
  String get accountsRemoveFailed => 'Couldn\'t remove account.';

  @override
  String get accountsRemoveFailedToast => 'Couldn\'t remove the account';

  @override
  String get accountsRemoveGiftCardsCheckFailed =>
      'Couldn\'t check this account for incoming gift cards. Try again before removing it.';

  @override
  String get accountsRemoveMigrationBody =>
      'This account\'s migration will no longer continue in Vizor. Transactions already submitted to the Zcash network may still complete. After re-importing, let the account fully sync before starting migration again.';

  @override
  String get accountsRemoveModalBody =>
      'Are you sure you want to remove this account? This action can\'t be reverted.\nYou will have to re-import your account.';

  @override
  String get accountsRemovePasswordCheckFailed =>
      'Couldn\'t check your password. Please try again.';

  @override
  String get accountsRemovePasswordHint => 'Enter your password';

  @override
  String get accountsRemovePasswordIncorrect =>
      'Incorrect password. Please try again.';

  @override
  String get accountsRemovePasswordLabel => 'Password';

  @override
  String get accountsRemoveStoppingSync => 'Stopping sync...';

  @override
  String get accountsRemoveSwapsCheckFailed =>
      'Couldn\'t check this account for active swaps. Try again before removing it.';

  @override
  String get accountsRemoving => 'Removing account...';

  @override
  String get accountsResetBody =>
      'Resetting Vizor deletes every account and all local wallet data. Make sure you can re-import your accounts before continuing.';

  @override
  String get accountsResetFailed => 'Couldn\'t reset Vizor.';

  @override
  String get accountsResetFailedToast => 'Couldn\'t reset Vizor';

  @override
  String get accountsResetMigrationBody =>
      'Resetting Vizor stops migrations on this device and deletes every account and all local wallet data. Transactions already submitted to the Zcash network may still complete. After re-importing, let each account fully sync before starting migration again.';

  @override
  String get accountsResetModalBody =>
      'Removing this account will completely reset the Vizor app. This means deleting all accounts and requiring you to import accounts again.\nUnshared gift card links will also be permanently lost.\nThis cannot be undone.';

  @override
  String get accountsResetVizor => 'Reset Vizor';

  @override
  String get accountsResetting => 'Resetting...';

  @override
  String get accountsSaveEdits => 'Save edits';

  @override
  String get accountsSaveFailed => 'Couldn\'t save the account changes';

  @override
  String get accountsSelectProfilePicture => 'Select profile picture';

  @override
  String get accountsSendFailed => 'Send couldn\'t be started';

  @override
  String get accountsSendZec => 'Send ZEC';

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get accountsUpdatePicture => 'Update picture';

  @override
  String get accountsViewSecretPhrase => 'View secret phrase';

  @override
  String get accountsViewViewingKey => 'View viewing key';

  @override
  String get appBackAddAccount => 'Add account';

  @override
  String get appBackHardwareWallets => 'Hardware wallets';

  @override
  String get appBackImportMethods => 'Import methods';

  @override
  String get appBackWalletBirthdayHeight => 'Wallet Birthday Height';

  @override
  String get appBackWelcome => 'Welcome';

  @override
  String get appExitBackHint => 'Go back again to exit';

  @override
  String get appGiftCloseCardFailed => 'Couldn’t close the card. Try again.';

  @override
  String appLinuxUpdateAvailable(String version) {
    return 'Vizor $version is available.';
  }

  @override
  String appLinuxUpdateAvailableTor(String version) {
    return 'Vizor $version is available. The release page opens in your browser, outside Vizor’s Tor connection.';
  }

  @override
  String get appLinuxUpdateOpenInBrowser => 'Open in browser';

  @override
  String get appLinuxUpdateViewRelease => 'View release';

  @override
  String get appPrivacyPolicyTitle => 'Privacy Policy';

  @override
  String get appTermsOfUseTitle => 'Terms of Use';

  @override
  String get appUpdateApplyingMessage => 'Applying after Vizor closes.';

  @override
  String get appUpdateAvailableMessage => 'Download now or keep working.';

  @override
  String get appUpdateAvailableTitle => 'Update available';

  @override
  String appUpdateAvailableVersionTitle(String version) {
    return 'Update $version available';
  }

  @override
  String get appUpdateDismiss => 'Dismiss';

  @override
  String get appUpdateDownload => 'Download';

  @override
  String get appUpdateDownloading => 'Downloading';

  @override
  String appUpdateDownloadingMessage(int percent) {
    return '$percent% downloaded.';
  }

  @override
  String get appUpdateDownloadingTitle => 'Downloading update';

  @override
  String get appUpdateFailedMessage =>
      'Couldn\'t complete the update. Try again.';

  @override
  String get appUpdateFailedTitle => 'Update failed';

  @override
  String get appUpdateLater => 'Later';

  @override
  String get appUpdateReadyMessage => 'Restart when you are ready.';

  @override
  String get appUpdateReadyTitle => 'Update ready';

  @override
  String get appUpdateRestart => 'Restart';

  @override
  String get appUpdateRestarting => 'Restarting';

  @override
  String get appUpdateRestartingTitle => 'Restarting Vizor';

  @override
  String get appUpdateTryAgain => 'Try again';

  @override
  String carouselPageSemantics(
    String name,
    int page,
    int count,
    String message,
  ) {
    return '$name $page of $count. $message';
  }

  @override
  String carouselShowPage(String name, int page, int count) {
    return 'Show $name $page of $count';
  }

  @override
  String get commonAddressCopied => 'Address copied';

  @override
  String get commonBack => 'Back';

  @override
  String commonBackTo(String destination) {
    return 'Back to $destination';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonCancellationFailed =>
      'Could not finish cancellation. Try again.';

  @override
  String get commonClearText => 'Clear text';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonCopyAddress => 'Copy address';

  @override
  String get commonDismissNotification => 'Dismiss notification';

  @override
  String get commonFeatureInProgress => 'This feature is still in progress.';

  @override
  String get commonInformation => 'Information';

  @override
  String get commonNotAvailableYet => 'Not available yet';

  @override
  String get commonOk => 'OK';

  @override
  String get commonSensitiveContentHidden => 'Sensitive content hidden';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonUpdating => 'Updating...';

  @override
  String get homeActivityEmpty => 'No activity, yet...';

  @override
  String get homeActivityEmptyHint => 'How about running your first ZEC tx?';

  @override
  String get homeActivityEmptyHintMobile =>
      'How about running your\nfirst ZEC tx?';

  @override
  String get homeActivityLoading => 'Loading activity';

  @override
  String get homeActivityUnavailable => 'Unable to load activity.';

  @override
  String get homeBackupSubtitle => 'Back up your secret passphrase\nLast step';

  @override
  String get homeBackupTitle => 'Secure your wallet';

  @override
  String get homeDismiss => 'Dismiss';

  @override
  String get homeEducationSubtitle =>
      'Privacy, address types, and what to expect';

  @override
  String get homeEducationTitle => 'Learn about Zcash';

  @override
  String get homeImportingBodyMobile =>
      'Hang tight ... It might take some time. Keep Vizor open & running.';

  @override
  String get homeImportingDetail =>
      'It might take some time.\nKeep Vizor open & running.';

  @override
  String homeImportingDetailNamed(String name) {
    return 'Importing $name\nKeep Vizor open & running.';
  }

  @override
  String get homeImportingTitle => 'We\'re importing\nyour wallet...';

  @override
  String get homeImportingTitleMobile => 'We\'re importing your wallet...';

  @override
  String get homeKeepAwakeBody =>
      'Your phone pauses syncing when screen is off. This allows sync to finish faster.';

  @override
  String get homeKeepAwakeEnable => 'Keep screen awake';

  @override
  String get homeKeepAwakeLater => 'Maybe later';

  @override
  String get homeKeepAwakeLockNote =>
      'The app locks after 1 minute of inactivity. Syncing continues behind the lock.';

  @override
  String get homeKeepAwakeSettingsNote =>
      'You can change this anytime in the Settings.';

  @override
  String get homeKeepAwakeTitle => 'Stay awake to sync?';

  @override
  String get homeLedgerActionNeeded => 'Action needed';

  @override
  String get homeLedgerApprovalNotAccepted =>
      'Your Ledger couldn’t accept this approval. Earlier approvals were already sent.';

  @override
  String get homeLedgerBroadcastNotStored =>
      'The shield transaction reached the network but was not stored locally. Do not try again until sync confirms it.';

  @override
  String get homeLedgerBroadcastUnknown =>
      'The shield transaction may have reached the network. Check activity before trying again.';

  @override
  String get homeLedgerCancelShielding => 'Cancel shielding';

  @override
  String get homeLedgerContextChanged =>
      'The selected account or network changed. Return to your wallet.';

  @override
  String get homeLedgerInputsRemaining => 'Inputs remaining';

  @override
  String get homeLedgerNoFundsRemain =>
      'No spendable transparent funds remain. Return to your wallet.';

  @override
  String get homeLedgerNoSapling =>
      'This Ledger preview does not support Sapling inputs or outputs.';

  @override
  String get homeLedgerPausedBelowThreshold =>
      'The remaining funds are below the shielding threshold.';

  @override
  String get homeLedgerPausedTitle => 'Shielding paused';

  @override
  String get homeLedgerPausedWalletChanges =>
      'Shielding paused while wallet changes finish. Return to your wallet.';

  @override
  String get homeLedgerRejected =>
      'The shield transaction was rejected on your Ledger.';

  @override
  String get homeLedgerRoundFeeNotice =>
      'Each approval creates a separate transaction with its own network fee.';

  @override
  String homeLedgerRoundSentBelowThreshold(int round) {
    return 'Round $round was sent. The remaining funds are below the shielding threshold.';
  }

  @override
  String homeLedgerRoundSentNoReduction(int round) {
    return 'Round $round was sent, but no reduction in spendable inputs could be confirmed. Wait for sync before shielding again.';
  }

  @override
  String homeLedgerRoundSentUnchecked(int round) {
    return 'Round $round was sent, but the remaining funds could not be checked. Return to your wallet and try again after sync.';
  }

  @override
  String get homeLedgerShieldTitle => 'Shield with Ledger';

  @override
  String get homeLedgerShieldingFailed =>
      'Ledger shielding could not be completed.';

  @override
  String get homeLedgerSigningFailedTitle => 'Ledger signing failed';

  @override
  String homeLoadFailed(String details) {
    return 'Something went wrong. Try again in a moment.\n\nDetails: $details';
  }

  @override
  String get homeMigrateToIronwood => 'Migrate to Ironwood';

  @override
  String get homeMigrationRequired => 'Migration required';

  @override
  String get homeMigrationRequiredTitle => 'Migration Required';

  @override
  String homeMigrationStillMigrating(String amount) {
    return '$amount still migrating';
  }

  @override
  String get homeMigrationStoppedByUpgrade =>
      'Migration stopped by network upgrade';

  @override
  String get homeMigrationWaitingConfirmation => 'Waiting for confirmation...';

  @override
  String get homeNu7FasterBody =>
      'Average wait for first confirmation drops from ~75s to ~25s.';

  @override
  String get homeNu7FasterTitle => '~3× faster blocks';

  @override
  String get homeNu7GotIt => 'Got it';

  @override
  String get homeNu7ThroughputBody =>
      'Network can handle 2.3x more shielded transactions per block.';

  @override
  String get homeNu7ThroughputTitle => 'Higher shielded throughput';

  @override
  String get homeNu7Title => 'NU7 Update is live.\nWhat does this mean?';

  @override
  String get homePasswordChangeUnverified =>
      'We couldn\'t verify the previous password change. Try again or restart Vizor.';

  @override
  String get homePayInUsdc => 'Pay in USDC';

  @override
  String get homeReceive => 'Receive';

  @override
  String get homeReceiveFirstZec => 'Receive your first ZEC';

  @override
  String get homeRecentActivity => 'Recent activity';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get homeSend => 'Send';

  @override
  String get homeSetupBackupMessage =>
      'Back up your wallet. Keep your secret passphrase safe.';

  @override
  String get homeSetupCarouselLabel => 'Wallet setup';

  @override
  String get homeSetupCarouselName => 'wallet setup banner';

  @override
  String get homeSetupEducationMessage =>
      'Learn how Zcash protects your privacy and which address to use.';

  @override
  String get homeShield => 'Shield';

  @override
  String get homeShieldAfterScan => 'After you scanned, click Get Signature.';

  @override
  String get homeShieldApproveTitle => 'Approve with Keystone';

  @override
  String get homeShieldAttentionTitle => 'Shielding needs attention';

  @override
  String get homeShieldBackToWallet => 'Back to wallet';

  @override
  String get homeShieldBackToWalletTitleCase => 'Back to Wallet';

  @override
  String get homeShieldBalanceTitle => 'Transparent Balance';

  @override
  String get homeShieldBroadcastNotStored =>
      'The shield transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';

  @override
  String get homeShieldBroadcastUnknown =>
      'The shield transaction may have reached the network, but confirmation timed out. Check activity before trying again.';

  @override
  String get homeShieldBroadcastingTitle => 'Broadcasting shield tx';

  @override
  String get homeShieldCameraDenied =>
      'Allow camera access in Settings to scan Keystone signatures.';

  @override
  String get homeShieldCameraUnavailable =>
      'The camera is unavailable right now.';

  @override
  String get homeShieldCancelFailed =>
      'Could not finish cancelling. Please try again.';

  @override
  String get homeShieldCancelled => 'Shielding was cancelled.';

  @override
  String get homeShieldCancelledBeforeParams =>
      'Shielding was cancelled before proving parameters were downloaded.';

  @override
  String get homeShieldComplete => 'Complete';

  @override
  String get homeShieldDrag => 'Drag to shield';

  @override
  String get homeShieldErrorBroadcast =>
      'Shield transaction could not be broadcast.';

  @override
  String get homeShieldErrorGeneric =>
      'Shield balance failed. Please try again.';

  @override
  String get homeShieldErrorNotFinalized =>
      'Shield transaction could not be finalized.';

  @override
  String get homeShieldErrorProvingParams =>
      'Required proving parameters could not be prepared.';

  @override
  String get homeShieldErrorSignatureNotApplied =>
      'Keystone signature could not be applied.';

  @override
  String get homeShieldErrorSigningNotPrepared =>
      'Keystone signing could not be prepared.';

  @override
  String get homeShieldErrorSyncFirst =>
      'Sync the wallet before shielding transparent balance.';

  @override
  String get homeShieldErrorTooSmall =>
      'Transparent balance is too small to shield after fees.';

  @override
  String get homeShieldFailedTitle => 'Shielding could not be completed';

  @override
  String get homeShieldGetSignature => 'Get Signature';

  @override
  String get homeShieldKeepOpen =>
      'Keep Vizor open while the transaction is sent.';

  @override
  String get homeShieldKeystoneQrSemantics => 'Keystone transaction QR';

  @override
  String get homeShieldNextStep => 'Next step';

  @override
  String get homeShieldNoActiveAccount => 'No active account.';

  @override
  String get homeShieldNow => 'Shield now';

  @override
  String get homeShieldQueuedTitle => 'Shielding queued';

  @override
  String get homeShieldReadingSignature => 'Reading signature…';

  @override
  String get homeShieldReject => 'Reject';

  @override
  String get homeShieldScanDecodeFailed =>
      'This QR code could not be decoded as a Keystone signature.';

  @override
  String get homeShieldScanHold => 'Keep the QR code steady and fully visible.';

  @override
  String get homeShieldScanTitle => 'Scan your Keystone signature';

  @override
  String get homeShieldScanToSign => 'Scan the QR code to sign';

  @override
  String get homeShieldScanWrongQr =>
      'Open the signed shield QR on Keystone, then scan again.';

  @override
  String homeShieldScanning(int progress) {
    return 'Scanning… $progress%';
  }

  @override
  String get homeShieldShowQr => 'Show QR';

  @override
  String get homeShieldSignTitle => 'Sign tx on your Keystone';

  @override
  String get homeShieldStatusUncertain =>
      'The shield transaction status is uncertain. Check activity before trying again.';

  @override
  String get homeShieldSubmitting => 'Submitting transaction';

  @override
  String get homeShieldSucceededTitle => 'Shielded successfully';

  @override
  String get homeShieldToggleFlashlight => 'Toggle flashlight';

  @override
  String get homeShieldTryAgain => 'Try again';

  @override
  String get homeShieldedBalance => 'Shielded balance';

  @override
  String get homeShieldingBalance => 'Shielding your balance…';

  @override
  String get homeShieldingProgress => 'Shielding...';

  @override
  String homeTransparentBalance(String balance) {
    return 'Transparent: $balance';
  }

  @override
  String get homeVotingSemantics => 'Open coinholder voting';

  @override
  String get homeVotingSubtitle => 'Help to shape the network';

  @override
  String get homeVotingTitle => 'Coinholder voting';

  @override
  String get keyringLockedBody =>
      'Vizor cannot access your system keyring. Unlock the keyring, then choose Retry. A system prompt may ask for your keyring password.';

  @override
  String get keyringNoResponse => 'The keyring did not respond. Try again.';

  @override
  String get keyringOpenFailedTitle => 'Unable to open Vizor';

  @override
  String get keyringOpeningTitle => 'Opening Vizor';

  @override
  String get keyringPromptBody =>
      'Complete any system keyring prompt to continue in Vizor.';

  @override
  String get keyringQuit => 'Quit';

  @override
  String get keyringRestartHint => 'Quit and restart Vizor to try again.';

  @override
  String get keyringRetry => 'Retry';

  @override
  String get keyringSaveUnconfirmedBody =>
      'Vizor could not confirm whether your changes were saved. Quit and restart Vizor before continuing.';

  @override
  String get keyringSaveUnconfirmedTitle => 'Unable to confirm the save';

  @override
  String get keyringTryingTitle => 'Trying secure storage';

  @override
  String get keyringUnavailableBody =>
      'Vizor cannot connect to the system keyring. Try again, or quit and restart Vizor.';

  @override
  String get keyringUnavailableTitle => 'Secure storage is unavailable';

  @override
  String get keyringUnlockTitle => 'Unlock your keyring';

  @override
  String get keyringUnreadableBody =>
      'Vizor could not read the data in your system keyring. Retry after restoring access, or quit Vizor.';

  @override
  String get keyringUnreadableTitle => 'Unable to read secure storage';

  @override
  String keystoneAccountsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts found',
      one: '1 account found',
    );
    return '$_temp0';
  }

  @override
  String get keystoneBackWelcome => 'Welcome';

  @override
  String get keystoneBirthdayDatePlaceholder => 'mm/dd/yyyy';

  @override
  String get keystoneBirthdayEstimateError =>
      'Could not estimate the wallet birthday height.';

  @override
  String get keystoneBirthdayEstimating => 'Estimating...';

  @override
  String get keystoneBirthdayHeightHint => 'Block height';

  @override
  String get keystoneBirthdayInvalidHeight =>
      'That doesn\'t look like a valid block height.';

  @override
  String get keystoneBirthdayMetadataError =>
      'Could not load wallet birthday metadata.';

  @override
  String get keystoneBirthdayStopSyncing => 'Stop syncing...';

  @override
  String get keystoneBirthdaySubtitle =>
      'It helps us import your wallet faster.';

  @override
  String get keystoneBirthdayTabBlockHeight => 'Enter the block height';

  @override
  String get keystoneBirthdayTabDate => 'Enter the date';

  @override
  String get keystoneBirthdayTitle => 'Around when did you create your wallet?';

  @override
  String get keystoneBirthdayUnknown => 'I can’t remember';

  @override
  String get keystoneCameraDeniedBody =>
      'Request again, or enable manually\nin the System settings.';

  @override
  String get keystoneCameraDeniedTitle => 'You\'ve denied camera access';

  @override
  String get keystoneCameraEnableBody =>
      'A camera is required to connect Keystone.\nYou can revert this in settings anytime later.';

  @override
  String get keystoneCameraEnableTitle => 'Enable camera access';

  @override
  String get keystoneCameraRequestAgain => 'Request again';

  @override
  String get keystoneCameraRestrictedBody =>
      'Screen Time or device management\nis blocking the camera.';

  @override
  String get keystoneCameraRestrictedTitle => 'Camera access is restricted';

  @override
  String get keystoneCameraTryAgain => 'Try again';

  @override
  String get keystoneCameraUnavailableBody =>
      'Keystone import uses camera QR scanning only.\nConnect a camera and try again.';

  @override
  String get keystoneCameraUnavailableTitle => 'Camera unavailable';

  @override
  String get keystoneConfirmSelection => 'Confirm selection';

  @override
  String get keystoneConnectTitle => 'Connect Keystone';

  @override
  String get keystoneContinue => 'Continue';

  @override
  String get keystoneFirmwareBody =>
      'Make sure your Keystone is on the latest Cypherpunk firmware. ';

  @override
  String get keystoneFirmwareDownloadSemantics => 'Download Keystone firmware';

  @override
  String get keystoneFirmwareLinkLabel => 'link';

  @override
  String get keystoneFirmwareTitle => 'Check Keystone firmware';

  @override
  String get keystoneImReadyNow => 'I\'m ready now';

  @override
  String get keystoneImporting => 'Importing...';

  @override
  String get keystoneOnVizor => 'On Vizor';

  @override
  String get keystoneOnYourKeystone => 'On your Keystone';

  @override
  String get keystonePrepareSubtitle => 'Prepare your Keystone wallet';

  @override
  String get keystonePrepareToConnectTitle => 'Prepare to connect';

  @override
  String get keystoneScanCameraRequired =>
      'Keystone import uses camera QR scanning only. Connect a camera and try again.';

  @override
  String get keystoneScanCaption => 'Scan the Keystone account QR';

  @override
  String get keystoneScanDecodeFailed =>
      'This QR code could not be decoded as a Keystone Zcash account.';

  @override
  String get keystoneScanKeepSteady =>
      'Keep the QR code steady and fully visible.';

  @override
  String get keystoneScanNoAccounts =>
      'No Zcash accounts were found on this Keystone QR.';

  @override
  String get keystoneScanOpenAccountQr =>
      'Open the Zcash account QR on Keystone, then scan again.';

  @override
  String keystoneScanProgress(int progress) {
    return 'Scanning... $progress%';
  }

  @override
  String get keystoneScanReadingAccounts => 'Reading accounts...';

  @override
  String get keystoneScanTitle => 'Scan QR Code';

  @override
  String get keystoneSelectAccountTitle => 'Select account';

  @override
  String get keystoneStepCustomiseWallet => 'Customise wallet';

  @override
  String get keystoneStepHowToConnect => 'How to Connect';

  @override
  String get keystoneStepOpenSoftwareWallet =>
      'Tap ••• (top right), then Connect software wallet.';

  @override
  String get keystoneStepScanDynamicQr =>
      'Scan the dynamic QR code on your Keystone.';

  @override
  String get keystoneStepSelectAccount => 'Select Account';

  @override
  String get keystoneStepSelectVizor => 'Select Vizor (or ZODL)';

  @override
  String get keystoneStepSetPassword => 'Set Password';

  @override
  String get keystoneStepWalletBirthdayHeight => 'Wallet Birthday Height';

  @override
  String languageSystemOption(String language) {
    return 'System ($language)';
  }

  @override
  String get ledgerAccountIndexHint =>
      'Keep 0 unless you used a different index for this Ledger account.';

  @override
  String get ledgerAccountIndexLabel => 'Account index (0–100)';

  @override
  String get ledgerAddAccountNote =>
      'View your balance and activity in Vizor. Transactions still need approval on Ledger.';

  @override
  String get ledgerAddAccountTitle => 'Add Ledger account';

  @override
  String get ledgerAdvancedOptions => 'Advanced options';

  @override
  String get ledgerBackAddAccount => 'Add account';

  @override
  String get ledgerBalanceActivityNote =>
      'See your balance and activity in Vizor.\nApprove transactions on Ledger.';

  @override
  String get ledgerBleDeclinedOpen =>
      'Opening Zcash was declined on Ledger. Try again when you’re ready.';

  @override
  String get ledgerBleDeclinedShare =>
      'Sharing was declined on Ledger. Try again when you’re ready.';

  @override
  String get ledgerBleReadFailedTryAgain =>
      'Vizor could not read this Ledger account. Try again.';

  @override
  String get ledgerBleReadFailedUsb =>
      'Vizor could not read this Ledger account. Reconnect Ledger with a USB cable, unlock it with your PIN, and open the Zcash app. Then try again.';

  @override
  String get ledgerBluetoothConnection => 'Bluetooth connection';

  @override
  String get ledgerBluetoothPermissionRequired =>
      'Bluetooth permission is required to find your Ledger. Allow it in Settings, then try again.';

  @override
  String get ledgerCancelFailed => 'Could not finish cancelling. Try again.';

  @override
  String get ledgerCancellingRequest => 'Cancelling request';

  @override
  String get ledgerCancellingTheRequest => 'Cancelling the Ledger request…';

  @override
  String get ledgerCheckingBluetoothAccess => 'Checking Bluetooth access…';

  @override
  String get ledgerChooseAnother => 'Choose another Ledger';

  @override
  String get ledgerCleanupFailed => 'Could not finish cleanup. Try again.';

  @override
  String get ledgerConfirmOpeningZcash => 'Confirm opening Zcash on Ledger.';

  @override
  String get ledgerConnect => 'Connect Ledger';

  @override
  String get ledgerConnectSubtitle => 'Prepare your Ledger wallet.';

  @override
  String get ledgerConnectUsbCable => 'Connect with a USB cable.';

  @override
  String ledgerConnectingTo(String device) {
    return 'Connecting to $device';
  }

  @override
  String get ledgerConnectionHelp => 'Connection help';

  @override
  String get ledgerCouldNotConnect => 'Could not connect Ledger';

  @override
  String get ledgerDiscoveryErrorFallback => 'Try again.';

  @override
  String get ledgerDiscoveryErrorTitle => 'Could not connect to your Ledger';

  @override
  String get ledgerDiscoveryFailed =>
      'Vizor could not find Ledger devices. Try again.';

  @override
  String get ledgerEnableBluetoothNearby =>
      'Enable Bluetooth and keep Ledger nearby.';

  @override
  String get ledgerErrorAlreadyAdded =>
      'This Ledger account is already in Vizor.';

  @override
  String get ledgerErrorCannotReadCheckConnection =>
      'Vizor could not read this Ledger account. Check the connection and try again.';

  @override
  String ledgerErrorCannotReadWithInstruction(String instruction) {
    return 'Vizor could not read this Ledger account. $instruction Then try again.';
  }

  @override
  String ledgerErrorConnectAndUnlock(String instruction) {
    return 'Connect and unlock your Ledger. $instruction';
  }

  @override
  String ledgerErrorUnlock(String instruction) {
    return 'Unlock your Ledger. $instruction';
  }

  @override
  String get ledgerErrorViewingKeyDeclined =>
      'The viewing key request was declined on Ledger. Try again when you’re ready.';

  @override
  String get ledgerErrorViewingKeyRejected =>
      'The viewing-key request was rejected on your Ledger.';

  @override
  String get ledgerFind => 'Find Ledger';

  @override
  String get ledgerFindMyLedger => 'Find my Ledger';

  @override
  String ledgerKeepAppOpen(String appName) {
    return 'Keep $appName open.';
  }

  @override
  String get ledgerKeepConnectedUntilCancelled =>
      'Keep Ledger connected until the current request is cancelled.';

  @override
  String get ledgerKeepConnectedWhileChecking =>
      'Keep Ledger connected while Vizor checks the app.';

  @override
  String get ledgerKeepNearbyUnlocked =>
      'Keep your Ledger nearby and unlocked, with Bluetooth turned on.';

  @override
  String get ledgerKeepZcashOpen => 'Keep Zcash open.';

  @override
  String get ledgerMacosBluetoothPrompt =>
      'macOS may ask for Bluetooth access. If prompted, allow access for Vizor.';

  @override
  String get ledgerNoDevicesFound => 'No Ledger devices found';

  @override
  String get ledgerNoDevicesFoundHint =>
      'Check that your Ledger is unlocked and try again.';

  @override
  String get ledgerNoneFoundDesktop =>
      'No Ledger found. Unlock Ledger, enable Bluetooth and keep it nearby. Then search again.';

  @override
  String get ledgerOnYourLedger => 'On your Ledger';

  @override
  String get ledgerOpenBluetoothSettingsManually =>
      'Open Bluetooth settings manually to remove the old pairing.';

  @override
  String get ledgerOpenZcashThenTryAgain =>
      'Open the Zcash app, then try again.';

  @override
  String get ledgerReturningToOptions => 'Returning to connection options…';

  @override
  String get ledgerSearchAgain => 'Search again';

  @override
  String get ledgerSearchTakesAWhile => 'This can take a few seconds.';

  @override
  String get ledgerSearchingDevices => 'Searching for Ledger devices…';

  @override
  String get ledgerSearchingNearby => 'Searching for nearby Ledgers…';

  @override
  String get ledgerSelectYourLedger => 'Select your Ledger.';

  @override
  String get ledgerSheetAddFailedTitle => 'Could not add Ledger account';

  @override
  String get ledgerSheetCancelFailedTitle => 'Could not cancel Ledger request';

  @override
  String get ledgerSheetDeclinedTitle => 'Request declined';

  @override
  String get ledgerStepAddAccount => 'Add account';

  @override
  String get ledgerStepApproveViewingKey => 'Approve viewing key';

  @override
  String get ledgerStepCustomiseWallet => 'Customise wallet';

  @override
  String ledgerStepOpenApp(String appName) {
    return 'Open $appName';
  }

  @override
  String get ledgerStepOpenZcash => 'Open Zcash';

  @override
  String get ledgerStepSetPassword => 'Set Password';

  @override
  String get ledgerStepWalletBirthdayHeight => 'Wallet Birthday Height';

  @override
  String get ledgerStoppingSearch => 'Stopping search';

  @override
  String get ledgerSupportedDevices => 'Supported devices';

  @override
  String get ledgerTransportBluetooth => 'Bluetooth';

  @override
  String get ledgerTransportUsb => 'USB';

  @override
  String get ledgerTryAgain => 'Try again';

  @override
  String get ledgerUnlockBluetoothNearby =>
      'Unlock Ledger, turn on Bluetooth, and keep it nearby.';

  @override
  String get ledgerUnlockWithPin => 'Unlock with your PIN.';

  @override
  String get ledgerVizorCheckingZcash => 'Vizor is checking the Zcash app.';

  @override
  String get lockBodyPaused => 'Sync paused. Unlock Vizor to continue.';

  @override
  String get lockBodySynced => 'Synced successfully. Unlock Vizor to continue.';

  @override
  String get lockCheckingPasscode => 'Checking passcode...';

  @override
  String get lockConfirmPasscodeSemantics => 'Confirm passcode to unlock Vizor';

  @override
  String get lockNavSynced => 'Synced';

  @override
  String lockNavSyncing(int percent) {
    return '$percent% Syncing...';
  }

  @override
  String get lockPasscodeIncorrect => 'Incorrect Passcode';

  @override
  String get lockSyncCompleteTitle => 'Sync Complete';

  @override
  String get lockSyncPausedSemantics => 'Vizor sync is paused';

  @override
  String get lockSyncPausedTitle => 'Sync paused';

  @override
  String get lockSyncedSemantics => 'Vizor is synced';

  @override
  String get lockSyncingMessage => 'Vizor is syncing';

  @override
  String get lockUnlockToContinue => 'Unlock to continue';

  @override
  String get lockUnlockToContinueBody => 'Unlock Vizor to continue';

  @override
  String get lockUnlockToContinuePausedBody => 'Unlock Vizor to continue.';

  @override
  String get lockUnlockVizor => 'Unlock Vizor';

  @override
  String get lockWelcomeBack => 'Welcome Back';

  @override
  String get navActivity => 'Activity';

  @override
  String get navHome => 'Home';

  @override
  String get navPay => 'Pay';

  @override
  String get navSettings => 'Settings';

  @override
  String get navSignOut => 'Sign out';

  @override
  String get navSwap => 'Swap';

  @override
  String get navVote => 'Vote';

  @override
  String get poolShielded => 'Shielded';

  @override
  String get poolTransparent => 'Transparent';

  @override
  String get profilePictureUpdateFailed => 'Couldn\'t update profile picture.';

  @override
  String get receiptMessageLabel => 'Message';

  @override
  String get settingsAccountChangedPasscode =>
      'Selected account changed. Enter your passcode again.';

  @override
  String get settingsAccountChangedPassword =>
      'Selected account changed. Enter your password again.';

  @override
  String get settingsAccountSaveFailed => 'Couldn\'t save the account changes';

  @override
  String get settingsAccountUnavailable =>
      'The selected account is no longer available.';

  @override
  String get settingsBackToAccounts => 'Back to accounts';

  @override
  String settingsBiometricOffToast(String feature) {
    return '$feature off';
  }

  @override
  String settingsBiometricOnToast(String feature) {
    return '$feature on';
  }

  @override
  String settingsBiometricSetupFirst(String biometric) {
    return 'Set up $biometric in your device settings first.';
  }

  @override
  String settingsBiometricTurnOffBody(String feature) {
    return 'You will use your passcode to unlock Vizor. You can turn $feature back on in settings anytime.';
  }

  @override
  String settingsBiometricTurnOffTitle(String feature) {
    return 'Turn off $feature?';
  }

  @override
  String settingsBiometricUpdateFailed(String feature) {
    return 'Couldn\'t update $feature.';
  }

  @override
  String get settingsBip39PassphraseCopied => 'BIP39 passphrase copied';

  @override
  String get settingsBip39PassphraseCopy => 'Copy BIP39 passphrase';

  @override
  String get settingsBip39PassphraseTitle => 'BIP39 Passphrase';

  @override
  String settingsBip39PassphraseValue(String passphrase) {
    return 'BIP39 Passphrase: $passphrase';
  }

  @override
  String get settingsBirthdayBlockHeight => 'Birthday block height';

  @override
  String get settingsBirthdayDate => 'Birthday date';

  @override
  String get settingsBirthdayDateCopied => 'Birthday date copied';

  @override
  String get settingsBirthdayHeightCopied => 'Birthday height copied';

  @override
  String get settingsChangePasscodeIncorrect => 'Incorrect Passcode';

  @override
  String get settingsConfirmAccessSubtitle => 'Confirm your access';

  @override
  String get settingsConfirmAccessTitle => 'Confirm access';

  @override
  String get settingsConfirmPasscodeTitle => 'Confirm Passcode';

  @override
  String get settingsConfirmPasswordLabel => 'Confirm password';

  @override
  String get settingsContinue => 'Continue';

  @override
  String get settingsCopy => 'Copy';

  @override
  String settingsCopyLabel(String label) {
    return 'Copy $label';
  }

  @override
  String settingsCopyLabelCopied(String label) {
    return '$label copied';
  }

  @override
  String settingsEndpointBalanceNote(String ticker) {
    return 'The wallet will show the balance from the last time it was successfully connected. It won\'t show any $ticker you recently received.';
  }

  @override
  String get settingsEndpointCloseSettings => 'Close endpoint settings';

  @override
  String get settingsEndpointConnectFailed =>
      'Couldn\'t connect to that endpoint. Check the host and port.';

  @override
  String settingsEndpointCurrent(String endpoint) {
    return 'Current: $endpoint';
  }

  @override
  String get settingsEndpointCurrentPrefix => 'Current: ';

  @override
  String get settingsEndpointCustom => 'Custom endpoint';

  @override
  String get settingsEndpointCustomise => 'Customise endpoint';

  @override
  String get settingsEndpointCustomize => 'Customize endpoint';

  @override
  String get settingsEndpointDefaultMarker => '(Default)';

  @override
  String get settingsEndpointNetworkSettings => 'Network settings';

  @override
  String get settingsEndpointSelectFromList => 'Select from the list';

  @override
  String get settingsEndpointTitle => 'Endpoint';

  @override
  String get settingsEndpointUpdate => 'Update endpoint';

  @override
  String get settingsEndpointUpdatedToast => 'Endpoint updated';

  @override
  String get settingsEndpointUpdating => 'Updating endpoint...';

  @override
  String get settingsEndpointWarningBlockchain =>
      'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash blockchain.';

  @override
  String get settingsEndpointWarningNetwork =>
      'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash network.';

  @override
  String get settingsEndpointsTitle => 'Endpoints';

  @override
  String get settingsEnterCurrentPasswordAgain =>
      'Enter your current password again.';

  @override
  String get settingsEnterCurrentPasswordFirst =>
      'Enter your current password first.';

  @override
  String get settingsEnterPasscodeTitle => 'Enter Passcode';

  @override
  String settingsExplorerCurrent(String explorer) {
    return 'Current: $explorer';
  }

  @override
  String settingsExplorerCurrentDefault(String host) {
    return 'Current: $host (default)';
  }

  @override
  String get settingsExplorerCustom => 'Custom';

  @override
  String get settingsExplorerCustomSubtitle => 'Any explorer you prefer';

  @override
  String get settingsExplorerSaveFailed => 'Couldn\'t save that explorer URL.';

  @override
  String get settingsExplorerTitle => 'Explorer';

  @override
  String get settingsExplorerUpdate => 'Update explorer';

  @override
  String get settingsExplorerUrlLabel => 'Explorer URL';

  @override
  String get settingsIncorrectPasscode => 'Incorrect passcode';

  @override
  String get settingsIncorrectPassword =>
      'Incorrect password. Please try again.';

  @override
  String get settingsKeepAwakeDescription =>
      'Prevents your phone from sleeping so sync can finish faster. The app still locks after 1 minute of inactivity.';

  @override
  String get settingsKeepAwakeLabel => 'Keep screen awake';

  @override
  String get settingsKeepAwakeUpdateFailed =>
      'Couldn\'t update screen awake setting.';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsLanguageUpdateFailed => 'Couldn\'t update language.';

  @override
  String get settingsNewBadge => 'New';

  @override
  String get settingsNoActiveAccount => 'No active account is selected.';

  @override
  String get settingsPasscodeCheckFailed =>
      'Couldn\'t check your passcode. Please try again.';

  @override
  String get settingsPasscodeLengthHint => '6 digits length';

  @override
  String get settingsPasscodeMustDiffer =>
      'Your new passcode must be different.';

  @override
  String get settingsPasscodeRotationRecoveryFailed =>
      'We couldn\'t verify the previous passcode change. Keep your secret passphrase available before trying again.';

  @override
  String get settingsPasscodeUpdateFailed =>
      'Couldn\'t update your passcode. Please try again.';

  @override
  String get settingsPasscodeUpdatedToast => 'Passcode updated';

  @override
  String get settingsPasscodeVerifyFailed =>
      'Couldn\'t verify the passcode. Try again.';

  @override
  String get settingsPasscodesMismatch => 'Passcodes didn\'t match. Try again.';

  @override
  String get settingsPasswordCheckFailed =>
      'Couldn\'t check your password. Please try again.';

  @override
  String get settingsPasswordHint => 'Your password...';

  @override
  String get settingsPasswordLabel => 'Password';

  @override
  String get settingsPasswordMinimumHint =>
      'Minimum 8 characters. Add numbers and symbols, or make it longer, for stronger security.';

  @override
  String get settingsPasswordRotationRecoveryFailed =>
      'We couldn\'t verify the previous password change. Please keep your secret passphrase available before trying again.';

  @override
  String get settingsPasswordUpdateFailed =>
      'Couldn\'t update your password. Please try again.';

  @override
  String get settingsPasswordsMismatch => 'Passwords do not match.';

  @override
  String get settingsPfpKnight => 'Knight';

  @override
  String get settingsPfpSamurai => 'Samurai';

  @override
  String get settingsPfpViking => 'Viking';

  @override
  String get settingsPfpWizard => 'Wizard';

  @override
  String get settingsPirCheckingUpdates => 'Checking for updates…';

  @override
  String get settingsPirChooseServer => 'Choose a server';

  @override
  String get settingsPirConfigOpenFailed =>
      'Couldn\'t open the config repository.';

  @override
  String get settingsPirCustomInvalid =>
      'The saved custom server is invalid. Edit it or choose another server.';

  @override
  String get settingsPirCustomServer => 'Custom server';

  @override
  String get settingsPirCustomServerEllipsis => 'Custom server…';

  @override
  String get settingsPirCustomUrlInvalid =>
      'Enter an HTTPS base URL without credentials, a query or a fragment.';

  @override
  String get settingsPirEditCustomServer => 'Edit custom server…';

  @override
  String get settingsPirListLoadFailed =>
      'Couldn\'t load the server list. Try again or enter a custom server.';

  @override
  String get settingsPirListUpdateFailed =>
      'Couldn\'t update the server list. Using the last list loaded.';

  @override
  String get settingsPirListUpdateFailedCustom =>
      'Couldn\'t update the list. Your custom server is still selected.';

  @override
  String get settingsPirLoadingServers => 'Loading the server list…';

  @override
  String get settingsPirNoServers =>
      'No servers are offered yet. You can enter a custom server.';

  @override
  String get settingsPirPingChecking => 'Checking...';

  @override
  String get settingsPirServerChangeFailed =>
      'Couldn\'t change server. Try again.';

  @override
  String get settingsPirServerCloseLabel =>
      'Close private query server settings';

  @override
  String get settingsPirServerRemoved =>
      'The server you chose is no longer offered. Choose another to resume private queries.';

  @override
  String get settingsPirServerSettingsLabel => 'Private query server settings';

  @override
  String get settingsPirServerTitle => 'Private query server';

  @override
  String get settingsPirSettingsReadFailed =>
      'Couldn\'t read the private query server settings.';

  @override
  String get settingsPirShareServer => 'Share your server';

  @override
  String get settingsPirUnavailable =>
      'Private queries are unavailable on this network.';

  @override
  String get settingsPirUpdatingServer => 'Updating server…';

  @override
  String get settingsPirUseCustomServer => 'Use custom server';

  @override
  String get settingsPrivacyTitle => 'Privacy';

  @override
  String get settingsPrivateQueriesLabel => 'Private queries';

  @override
  String get settingsPrivateQueriesTurnOffBody =>
      'Vizor will rebuild your transparent history publicly, allowing the server to learn all your addresses.';

  @override
  String get settingsPrivateQueriesTurnOffConfirm => 'Turn off';

  @override
  String get settingsPrivateQueriesTurnOffDisclosure =>
      'The server receives every transparent address of every account and the IDs of transactions private recovery found. It can link them to each other and, without Tor, to your IP address.';

  @override
  String get settingsPrivateQueriesTurnOffTitle => 'Turn off private queries?';

  @override
  String get settingsProfilePictureCustom => 'Custom';

  @override
  String get settingsRowAboutVizor => 'About Vizor';

  @override
  String get settingsRowAccountName => 'Account name';

  @override
  String get settingsRowAccountNameMobile => 'Account Name';

  @override
  String get settingsRowAddressBook => 'Address book';

  @override
  String get settingsRowChangePasscode => 'Change passcode';

  @override
  String get settingsRowChangePassword => 'Change password';

  @override
  String get settingsRowCoinholderVoting => 'Coinholder voting';

  @override
  String get settingsRowLinkMobile => 'Link Vizor mobile';

  @override
  String get settingsRowMyGiftCards => 'My gift cards';

  @override
  String get settingsRowProfilePicture => 'Profile picture';

  @override
  String get settingsRowProfilePictureMobile => 'Profile Picture';

  @override
  String get settingsRowSecretPassphrase => 'Secret passphrase';

  @override
  String get settingsRowSupportVizor => 'Support Vizor';

  @override
  String get settingsRowUpdates => 'Updates';

  @override
  String get settingsRowViewingKeyMobile => 'Viewing Key';

  @override
  String get settingsSecretPassphraseTitle => 'Secret Passphrase';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionDangerZone => 'Danger zone';

  @override
  String get settingsSectionMisc => 'Misc';

  @override
  String get settingsSectionPersonal => 'Personal';

  @override
  String get settingsSectionSyncing => 'Syncing';

  @override
  String get settingsSectionSystem => 'System';

  @override
  String get settingsSeedBackupSaveFailed => 'Couldn’t save that. Try again.';

  @override
  String get settingsSeedBiometricReason =>
      'Confirm access to your secret passphrase';

  @override
  String get settingsSeedCopiedToast => 'Secret passphrase copied';

  @override
  String get settingsSeedCopyLabel => 'Copy secret passphrase';

  @override
  String get settingsSeedHeadingSubtitle =>
      'This is the master key to your wallet.\nDon’t share it with anyone.';

  @override
  String get settingsSeedLoadFailed =>
      'Couldn\'t load your secret passphrase. Please try again.';

  @override
  String get settingsSeedPasswordSubtitle => 'To view the secret passphrase.';

  @override
  String get settingsSeedRemindLater => 'Remind me later';

  @override
  String get settingsSeedScreenshotAck => 'I understand';

  @override
  String get settingsSeedScreenshotBodyLead => 'Screenshots are not reliable';

  @override
  String get settingsSeedScreenshotBodyRest =>
      '. Anyone who has access to your phone or your photo library will be able to see your Secret Passphrase. Write down your Phrase on a piece of paper instead.';

  @override
  String get settingsSeedScreenshotTitle =>
      'Don’t take screenshots of your Secret Passphrase';

  @override
  String get settingsSeedUnavailableAccount =>
      'Secret passphrase is not available for this account.';

  @override
  String get settingsSeedUnavailableHardware =>
      'Secret passphrase is not available for hardware accounts.';

  @override
  String get settingsSeedWrittenDown => 'I’ve written it down';

  @override
  String get settingsSetNewPasscodeTitle => 'Set New Passcode';

  @override
  String get settingsStatusOff => 'Off';

  @override
  String get settingsStatusOn => 'On';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeSystemAuto => 'System (Auto)';

  @override
  String get settingsThemeTitle => 'Theme';

  @override
  String get settingsThemeUpdateFailed => 'Couldn\'t update theme.';

  @override
  String get settingsTorDescBootstrapFailed =>
      'Vizor could not connect to Tor. Requests stay blocked until it connects or you turn Tor off.';

  @override
  String get settingsTorDescConnected =>
      'Vizor’s network requests go through Tor. Links opened in other apps use those apps’ network settings.';

  @override
  String get settingsTorDescConnectedIos =>
      'Vizor’s network requests go through Tor. Ironwood private migration uses a direct connection while Vizor is closed. Links opened in other apps use those apps’ network settings.';

  @override
  String get settingsTorDescConnectedNoUpdates =>
      'Vizor’s network requests go through Tor, but software updates are unavailable.';

  @override
  String get settingsTorDescConnecting =>
      'New requests wait until the Tor connection is ready. Turn Tor off to stop connecting and use a direct connection.';

  @override
  String get settingsTorDescConnectingLinux =>
      'New requests wait until the Tor connection is ready. Turn Tor off to stop connecting and use a direct connection. Update pages and downloads opened in another app use that app’s connection.';

  @override
  String get settingsTorDescConnectionFailed =>
      'Direct requests remain blocked. Try again or turn off Tor.';

  @override
  String get settingsTorDescDirectNoUpdates =>
      'Network requests connect directly. Software updates are unavailable.';

  @override
  String get settingsTorDescDisableNotSaved =>
      'Requests now use a direct connection, but Vizor could not save the change. Tor turns back on the next time you open the app.';

  @override
  String get settingsTorDescEnableNotSaved =>
      'Vizor could not save the change, so Tor was not turned on. Requests keep using a direct connection.';

  @override
  String get settingsTorDescOff =>
      'Tor is off. Requests to the Zcash network, in-app services, and software updates connect directly.';

  @override
  String get settingsTorDescOffLinux =>
      'Tor is off. Vizor requests, including software update checks, connect directly. Update pages and downloads open in another app.';

  @override
  String get settingsTorDescOffMobile =>
      'Wallet sync and in-app requests connect directly. Turn Tor on to hide your IP address from the servers Vizor talks to.';

  @override
  String get settingsTorDescSwitchFailed =>
      'Vizor could not switch to a direct connection. Try again.';

  @override
  String get settingsTorDescSwitchFailedStillOn =>
      'Vizor could not switch to a direct connection. Tor is still on and requests keep going through it.';

  @override
  String get settingsTorDescSwitching =>
      'Vizor is switching network requests and software updates to a direct connection.';

  @override
  String get settingsTorDescSwitchingLinux =>
      'Vizor is switching its requests, including software update checks, to a direct connection.';

  @override
  String get settingsTorDescSwitchingMobile =>
      'Vizor is switching network requests to a direct connection.';

  @override
  String get settingsTorGeneralDescription =>
      'Use Tor to hide your IP address from servers. Other apps use their own network settings.';

  @override
  String get settingsTorGeneralIosSuffix =>
      ' Ironwood private migration connects directly while Vizor is closed.';

  @override
  String get settingsTorRetryUpdates => 'Retry updates';

  @override
  String get settingsTorStatusConnected => 'Connected';

  @override
  String get settingsTorStatusConnecting => 'Connecting…';

  @override
  String get settingsTorStatusConnectionFailed => 'Connection failed';

  @override
  String get settingsTorStatusDirect => 'Direct';

  @override
  String get settingsTorStatusFailed => 'Failed';

  @override
  String get settingsTorStatusNotSaved => 'Setting not saved';

  @override
  String get settingsTorStatusSwitchFailed => 'Switch failed';

  @override
  String get settingsTorStatusSwitching => 'Switching…';

  @override
  String get settingsTorStatusSwitchingDirect => 'Switching to direct…';

  @override
  String get settingsTorStopConnecting => 'Stop connecting to Tor';

  @override
  String get settingsTorTryDirect => 'Try direct connection';

  @override
  String get settingsTorUse => 'Use Tor';

  @override
  String get settingsTryAgain => 'Try again';

  @override
  String settingsUninstallActiveSwaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active swaps',
      one: '1 active swap',
    );
    return 'This wallet has $_temp0. Wait for them to complete before uninstalling.';
  }

  @override
  String get settingsUninstallCannotUndo => 'This cannot be undone.';

  @override
  String get settingsUninstallChecking => 'Checking...';

  @override
  String get settingsUninstallClaimCheckFailed =>
      'Couldn\'t check for incoming gift cards. Try again before uninstalling.';

  @override
  String get settingsUninstallCloseApp => 'Close Vizor';

  @override
  String get settingsUninstallDeviceGeneric => 'this device';

  @override
  String get settingsUninstallDeviceMac => 'this Mac';

  @override
  String get settingsUninstallDevicePc => 'this PC';

  @override
  String get settingsUninstallDoneTitle => 'Your data has been removed';

  @override
  String get settingsUninstallFinishGeneric =>
      'To finish uninstallation, remove the Vizor app from this device.';

  @override
  String get settingsUninstallFinishMac =>
      'To finish uninstallation, remove the Vizor app from Applications.';

  @override
  String get settingsUninstallFinishWindows =>
      'To finish uninstallation, uninstall Vizor from Windows settings.';

  @override
  String get settingsUninstallPasswordSubtitle => 'To uninstall Vizor.';

  @override
  String get settingsUninstallRemovingTitle => 'Removing data...';

  @override
  String get settingsUninstallSwapCheckFailed =>
      'Couldn\'t check for active swaps. Try again before uninstalling.';

  @override
  String get settingsUninstallTitle => 'Uninstall Vizor';

  @override
  String get settingsUninstallWipeFailed =>
      'Couldn\'t finish removing data. Please try again.';

  @override
  String settingsUninstallWipeSubtitle(String device) {
    return 'Vizor will delete wallet data and secure storage from $device. Unshared gift card links will be permanently lost.';
  }

  @override
  String get settingsUpdateApplying => 'Applying';

  @override
  String get settingsUpdateAvailable => 'Available';

  @override
  String get settingsUpdateCheck => 'Check';

  @override
  String get settingsUpdateCheckForUpdates => 'Check for updates';

  @override
  String get settingsUpdateChecking => 'Checking';

  @override
  String get settingsUpdateCheckingButton => 'Checking…';

  @override
  String get settingsUpdateCurrentLabel => 'Current';

  @override
  String get settingsUpdateDownloadButton => 'Download update';

  @override
  String get settingsUpdateDownloadingButton => 'Downloading…';

  @override
  String get settingsUpdateFailed => 'Failed';

  @override
  String get settingsUpdatePasswordTitle => 'Update password';

  @override
  String get settingsUpdateRestart => 'Restart';

  @override
  String get settingsUpdateRestartButton => 'Restart to update';

  @override
  String get settingsUpdateRestartingButton => 'Restarting…';

  @override
  String settingsUpdateStatusAvailable(String version) {
    return 'Version $version is available.';
  }

  @override
  String get settingsUpdateStatusChecking => 'Checking for updates.';

  @override
  String settingsUpdateStatusDownloading(String percent) {
    return 'Downloading $percent%.';
  }

  @override
  String get settingsUpdateStatusFailed =>
      'Couldn\'t complete the update. Try again.';

  @override
  String get settingsUpdateStatusIdle => 'Ready to check for updates.';

  @override
  String settingsUpdateStatusReady(String version) {
    return 'Version $version is ready.';
  }

  @override
  String get settingsUpdateStatusRestarting => 'Restarting Vizor.';

  @override
  String get settingsUpdateStatusUnsupported =>
      'Updates are available in the installed Windows app.';

  @override
  String get settingsUpdateStatusUpToDate => 'Vizor is up to date.';

  @override
  String get settingsUpdateUnavailable => 'Unavailable';

  @override
  String get settingsUpdateUpToDate => 'Up to date';

  @override
  String get settingsUpdatingPassword => 'Updating password...';

  @override
  String settingsVersionFooterLabel(String version) {
    return 'Vizor, version $version';
  }

  @override
  String get settingsViewingKeyBiometricReason =>
      'Confirm access to your viewing key';

  @override
  String get settingsViewingKeyChoiceSharingWarning =>
      'Share only with trusted parties. Both keys may reveal transparent balances and spending.';

  @override
  String get settingsViewingKeyChooseTitle => 'Choose what others can view';

  @override
  String get settingsViewingKeyConfirmAgain =>
      'Confirm access again to try loading this key.';

  @override
  String get settingsViewingKeyCopy => 'Copy viewing key';

  @override
  String get settingsViewingKeyExplanation =>
      'Reveals your balance and all past and future transactions. It cannot spend ZEC.';

  @override
  String get settingsViewingKeyFormatQr => 'QR code';

  @override
  String get settingsViewingKeyFormatText => 'Text';

  @override
  String get settingsViewingKeyFullDescription =>
      'Balance, incoming and outgoing transactions.';

  @override
  String get settingsViewingKeyIncomingExplanation =>
      'Reveals past and future incoming payments. It cannot spend ZEC.';

  @override
  String get settingsViewingKeyIncomingOnly => 'Incoming only';

  @override
  String get settingsViewingKeyIncomingOnlyDescription =>
      'Incoming transactions only.';

  @override
  String get settingsViewingKeyIncomingWarningTitle =>
      'This key reveals incoming payments';

  @override
  String get settingsViewingKeyLoadFailedTitle =>
      'Couldn\'t load the viewing key';

  @override
  String get settingsViewingKeyPasswordSubtitle => 'To view the viewing key.';

  @override
  String get settingsViewingKeyQrFull => 'Full viewing key QR code';

  @override
  String get settingsViewingKeyQrIncoming => 'Incoming viewing key QR code';

  @override
  String get settingsViewingKeyTitle => 'Viewing key';

  @override
  String get settingsViewingKeyTryCopyAgain => 'Try copying again';

  @override
  String get settingsViewingKeyTypeFull => 'Full viewing key';

  @override
  String get settingsViewingKeyTypeIncoming => 'Incoming key';

  @override
  String get settingsViewingKeyWarningTitle =>
      'This key reveals your transactions';

  @override
  String get settingsWalletSessionChanged =>
      'The wallet session changed. Enter your password again.';

  @override
  String get settingsWinUpdateContinueTor => 'Continue with Tor';

  @override
  String get settingsWinUpdateStartFailedTitle => 'Couldn\'t start the update';

  @override
  String get settingsWinUpdateTorBlockedBody =>
      'Vizor kept direct requests blocked. Retry updates in Settings, or turn off Tor and try the download again.';

  @override
  String get settingsWinUpdateTorBlockedTitle =>
      'Software updates unavailable over Tor';

  @override
  String get settingsWinUpdateTorChoiceBody =>
      'Updating over Tor may take longer. Turning Tor off switches all Vizor network requests to a direct connection.';

  @override
  String get settingsWinUpdateTorChoiceTitle => 'Use Tor for this update?';

  @override
  String get settingsWinUpdateTorOffFailedBody =>
      'Tor remains on, so Vizor kept the update blocked. Try again, or turn off Tor in Settings before downloading.';

  @override
  String get settingsWinUpdateTorOffFailedTitle => 'Couldn\'t turn off Tor';

  @override
  String get settingsWinUpdateTurnOffTorAndUpdate => 'Turn off Tor and update';

  @override
  String get settingsWinUpdateUnavailableBody =>
      'Tor is off, but software updates are still unavailable. Retry updates in Settings before downloading.';

  @override
  String get settingsWinUpdateUnavailableTitle =>
      'Software updates unavailable';

  @override
  String get sidebarAccountNameFallback => 'Username';

  @override
  String get sidebarAddressCopyFailed => 'Address couldn\'t be copied';

  @override
  String get sidebarCopyShieldedAddress => 'Copy shielded address';

  @override
  String get sidebarHideBalance => 'Hide balance';

  @override
  String get sidebarImporting => 'Importing...';

  @override
  String get sidebarManageAccounts => 'Manage';

  @override
  String get sidebarMigrating => 'Migrating...';

  @override
  String get sidebarMigrationNeedsInput => 'Needs input';

  @override
  String get sidebarMigrationStopped => 'Migration stopped';

  @override
  String get sidebarMyAccounts => 'My accounts';

  @override
  String get sidebarShieldedAddressCopied => 'Shielded address copied';

  @override
  String get sidebarShowBalance => 'Show balance';

  @override
  String get syncSynced => 'Synced';

  @override
  String syncSyncedAtBlock(String height) {
    return 'Synced at block $height';
  }

  @override
  String get txFeeInfoDescription =>
      'The network fee is set by the Zcash protocol (ZIP 317) based on the transaction size. Vizor adds no extra fee.';

  @override
  String get txFeeInfoTitle => 'Tx fee';

  @override
  String walletLinkAccountsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
    );
    return '$_temp0 found';
  }

  @override
  String walletLinkAccountsReadySubtitle(int ready, int imported) {
    String _temp0 = intl.Intl.pluralLogic(
      ready,
      locale: localeName,
      other: '$ready accounts',
      one: '1 account',
    );
    return '$_temp0 ready to import, $imported already imported.';
  }

  @override
  String walletLinkAlreadyImported(int count) {
    return '$count already imported';
  }

  @override
  String get walletLinkCameraRequired =>
      'Desktop link scanning needs a camera on this device.';

  @override
  String walletLinkContactsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contacts',
      one: '1 contact',
    );
    return '$_temp0 found';
  }

  @override
  String walletLinkContactsReadySubtitle(int found, int imported) {
    String _temp0 = intl.Intl.pluralLogic(
      found,
      locale: localeName,
      other: '$found contacts',
      one: '1 contact',
    );
    return '$_temp0 found, $imported already imported.';
  }

  @override
  String get walletLinkContinue => 'Continue';

  @override
  String get walletLinkDeselectAll => 'Deselect all';

  @override
  String get walletLinkErrorExpiredBody =>
      'The code on your computer timed out. On desktop, choose Generate new code and scan it again.';

  @override
  String get walletLinkErrorExpiredTitle => 'Link expired';

  @override
  String get walletLinkErrorFailedBody =>
      'Check that the desktop code is still visible, then scan it again.';

  @override
  String get walletLinkErrorFailedTitle => 'Couldn\'t open this link';

  @override
  String get walletLinkErrorInvalidBody =>
      'The code you scanned isn\'t a Vizor desktop link. On your computer, open Settings → Link Vizor Mobile.';

  @override
  String get walletLinkErrorInvalidTitle => 'Invalid QR code';

  @override
  String get walletLinkGoBack => 'Go back';

  @override
  String walletLinkImportContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Import $count contacts',
      one: 'Import 1 contact',
    );
    return '$_temp0';
  }

  @override
  String get walletLinkImportContactsTitle => 'Import contacts';

  @override
  String get walletLinkImporting => 'Importing...';

  @override
  String get walletLinkIntroNotice =>
      'This copies the wallet and contacts to the phone. Nothing on the computer changes, and you can use both.';

  @override
  String get walletLinkIntroReady => 'I\'m ready to scan';

  @override
  String get walletLinkIntroSubtitle =>
      'Copy your desktop wallet to this phone';

  @override
  String get walletLinkIntroTitle => 'Link with Desktop';

  @override
  String walletLinkLinkAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Link $count accounts',
      one: 'Link 1 account',
    );
    return '$_temp0';
  }

  @override
  String get walletLinkNothingNewSubtitle =>
      'There is nothing new to import from this desktop link.';

  @override
  String get walletLinkNothingToImportBody =>
      'Everything in this desktop link is already on this phone.';

  @override
  String get walletLinkNothingToImportTitle => 'Nothing to import';

  @override
  String get walletLinkReadingLink => 'Reading link...';

  @override
  String get walletLinkScanAgain => 'Scan again';

  @override
  String get walletLinkScanCaption => 'Scan the Vizor desktop QR';

  @override
  String get walletLinkScanSubtitleDesktop => 'Scan the code on your desktop';

  @override
  String get walletLinkScanTitle => 'Scan QR Code';

  @override
  String get walletLinkSelectAccountTitle => 'Select account';

  @override
  String get walletLinkSelectAll => 'Select all';

  @override
  String get walletLinkStepOpenSettings => 'Go to Settings → Link Vizor Mobile';

  @override
  String get walletLinkStepScanQr =>
      'Scan the QR code on your desktop from the next screen.';

  @override
  String get walletLinkStepUnlockDesktop =>
      'Open & unlock your Vizor desktop app';
}
