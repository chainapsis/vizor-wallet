// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsLanguageUpdateFailed => 'Couldn\'t update language.';

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
