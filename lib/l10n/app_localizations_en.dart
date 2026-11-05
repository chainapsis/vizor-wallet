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
  String languageSystemOption(String language) {
    return 'System ($language)';
  }

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
}
