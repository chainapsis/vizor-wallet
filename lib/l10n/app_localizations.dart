import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// No description provided for @settingsSectionSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSectionSystem;

  /// No description provided for @settingsSectionMisc.
  ///
  /// In en, this message translates to:
  /// **'Misc'**
  String get settingsSectionMisc;

  /// No description provided for @settingsSectionDangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get settingsSectionDangerZone;

  /// No description provided for @settingsSecretPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Secret passphrase'**
  String get settingsSecretPassphrase;

  /// No description provided for @settingsPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get settingsPassword;

  /// No description provided for @settingsProfilePicture.
  ///
  /// In en, this message translates to:
  /// **'Profile picture'**
  String get settingsProfilePicture;

  /// No description provided for @settingsProfilePictureCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsProfilePictureCustom;

  /// No description provided for @settingsAccountName.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get settingsAccountName;

  /// No description provided for @settingsContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get settingsContacts;

  /// No description provided for @settingsEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get settingsEndpoint;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdates;

  /// No description provided for @settingsAboutVizor.
  ///
  /// In en, this message translates to:
  /// **'About Vizor'**
  String get settingsAboutVizor;

  /// No description provided for @settingsUninstallVizor.
  ///
  /// In en, this message translates to:
  /// **'Uninstall Vizor'**
  String get settingsUninstallVizor;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeSystemAuto.
  ///
  /// In en, this message translates to:
  /// **'System (Auto)'**
  String get settingsThemeSystemAuto;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeUpdateError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update theme.'**
  String get settingsThemeUpdateError;

  /// No description provided for @settingsLanguageUpdateError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update language.'**
  String get settingsLanguageUpdateError;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get commonUpdating;

  /// No description provided for @settingsUpdateCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get settingsUpdateCurrent;

  /// No description provided for @settingsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get settingsUpdateAvailable;

  /// No description provided for @settingsUpdateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get settingsUpdateUnavailable;

  /// No description provided for @settingsUpdateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get settingsUpdateChecking;

  /// No description provided for @settingsUpdateRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get settingsUpdateRestart;

  /// No description provided for @settingsUpdateApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying'**
  String get settingsUpdateApplying;

  /// No description provided for @settingsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settingsUpdateFailed;

  /// No description provided for @settingsUpdateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get settingsUpdateUpToDate;

  /// No description provided for @settingsUpdateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get settingsUpdateCheck;

  /// No description provided for @settingsUpdateActionCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsUpdateActionCheck;

  /// No description provided for @settingsUpdateActionChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get settingsUpdateActionChecking;

  /// No description provided for @settingsUpdateActionDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get settingsUpdateActionDownloading;

  /// No description provided for @settingsUpdateActionRestarting.
  ///
  /// In en, this message translates to:
  /// **'Restarting...'**
  String get settingsUpdateActionRestarting;

  /// No description provided for @settingsUpdateActionDownload.
  ///
  /// In en, this message translates to:
  /// **'Download update'**
  String get settingsUpdateActionDownload;

  /// No description provided for @settingsUpdateActionRestartToUpdate.
  ///
  /// In en, this message translates to:
  /// **'Restart to update'**
  String get settingsUpdateActionRestartToUpdate;

  /// No description provided for @settingsUpdateActionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get settingsUpdateActionTryAgain;

  /// No description provided for @settingsUpdateStatusWindowsOnly.
  ///
  /// In en, this message translates to:
  /// **'Updates are available in the installed Windows app.'**
  String get settingsUpdateStatusWindowsOnly;

  /// No description provided for @settingsUpdateStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates.'**
  String get settingsUpdateStatusChecking;

  /// No description provided for @settingsUpdateStatusUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Vizor is up to date.'**
  String get settingsUpdateStatusUpToDate;

  /// No description provided for @settingsUpdateStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available.'**
  String settingsUpdateStatusAvailable(String version);

  /// No description provided for @settingsUpdateStatusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {progress}%.'**
  String settingsUpdateStatusDownloading(int progress);

  /// No description provided for @settingsUpdateStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is ready.'**
  String settingsUpdateStatusReady(String version);

  /// No description provided for @settingsUpdateStatusApplying.
  ///
  /// In en, this message translates to:
  /// **'Restarting Vizor.'**
  String get settingsUpdateStatusApplying;

  /// No description provided for @settingsUpdateStatusCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates.'**
  String get settingsUpdateStatusCheckFailed;

  /// No description provided for @settingsUpdateStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Ready to check for updates.'**
  String get settingsUpdateStatusIdle;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @homeNoticePasswordRotationFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify the previous password change. Try again or restart Vizor.'**
  String get homeNoticePasswordRotationFailed;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get navSend;

  /// No description provided for @navReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get navReceive;

  /// No description provided for @navSwap.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get navSwap;

  /// No description provided for @navVote.
  ///
  /// In en, this message translates to:
  /// **'Vote'**
  String get navVote;

  /// No description provided for @navActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get navActivity;

  /// No description provided for @navAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get navAccounts;

  /// No description provided for @navSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get navSignOut;

  /// No description provided for @navAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get navAmount;

  /// No description provided for @navReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get navReview;

  /// No description provided for @navStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get navStatus;

  /// No description provided for @navTransaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get navTransaction;

  /// No description provided for @navChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get navChangePassword;

  /// No description provided for @navConnectKeystone.
  ///
  /// In en, this message translates to:
  /// **'Connect Keystone'**
  String get navConnectKeystone;

  /// No description provided for @navVotingRound.
  ///
  /// In en, this message translates to:
  /// **'Voting round'**
  String get navVotingRound;

  /// No description provided for @navSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get navSubmitted;

  /// No description provided for @navResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get navResults;

  /// No description provided for @navImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get navImporting;

  /// No description provided for @sidebarMyAccounts.
  ///
  /// In en, this message translates to:
  /// **'My accounts'**
  String get sidebarMyAccounts;

  /// No description provided for @sidebarManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get sidebarManage;

  /// No description provided for @sidebarShowBalance.
  ///
  /// In en, this message translates to:
  /// **'Show balance'**
  String get sidebarShowBalance;

  /// No description provided for @sidebarHideBalance.
  ///
  /// In en, this message translates to:
  /// **'Hide balance'**
  String get sidebarHideBalance;

  /// No description provided for @sidebarCopyShieldedAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy shielded address'**
  String get sidebarCopyShieldedAddress;

  /// No description provided for @toastCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get toastCopied;

  /// No description provided for @toastAddressCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get toastAddressCopied;

  /// No description provided for @toastAddressCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Address couldn\'t be copied'**
  String get toastAddressCopyFailed;

  /// No description provided for @toastShieldedAddressCopied.
  ///
  /// In en, this message translates to:
  /// **'Shielded address copied'**
  String get toastShieldedAddressCopied;

  /// No description provided for @syncStatusSyncingLabel.
  ///
  /// In en, this message translates to:
  /// **'{pct}% Syncing...'**
  String syncStatusSyncingLabel(String pct);

  /// No description provided for @syncStatusSyncingSemantics.
  ///
  /// In en, this message translates to:
  /// **'Syncing {pct} percent'**
  String syncStatusSyncingSemantics(String pct);

  /// No description provided for @syncStatusFailedLabel.
  ///
  /// In en, this message translates to:
  /// **'Syncing failed. {reason}...'**
  String syncStatusFailedLabel(String reason);

  /// No description provided for @syncStatusFailedSemantics.
  ///
  /// In en, this message translates to:
  /// **'Syncing failed. {reason}'**
  String syncStatusFailedSemantics(String reason);

  /// No description provided for @syncStatusSynced.
  ///
  /// In en, this message translates to:
  /// **'Vizor is synced'**
  String get syncStatusSynced;

  /// No description provided for @syncFailureNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get syncFailureNetwork;

  /// No description provided for @syncFailureEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint error'**
  String get syncFailureEndpoint;

  /// No description provided for @syncFailureDatabaseBusy.
  ///
  /// In en, this message translates to:
  /// **'Wallet data busy'**
  String get syncFailureDatabaseBusy;

  /// No description provided for @syncFailureDatabaseFatal.
  ///
  /// In en, this message translates to:
  /// **'Wallet data error'**
  String get syncFailureDatabaseFatal;

  /// No description provided for @syncFailureChainRecovery.
  ///
  /// In en, this message translates to:
  /// **'Chain recovery'**
  String get syncFailureChainRecovery;

  /// No description provided for @syncFailureParse.
  ///
  /// In en, this message translates to:
  /// **'Data error'**
  String get syncFailureParse;

  /// No description provided for @syncFailureUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get syncFailureUnknown;

  /// No description provided for @syncUserMessageNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network connection lost. We\'ll keep trying automatically.'**
  String get syncUserMessageNetwork;

  /// No description provided for @syncUserMessageEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the configured Zcash endpoint. Check your endpoint settings.'**
  String get syncUserMessageEndpoint;

  /// No description provided for @syncUserMessageDatabaseBusy.
  ///
  /// In en, this message translates to:
  /// **'Wallet data is busy. We\'ll try syncing again automatically.'**
  String get syncUserMessageDatabaseBusy;

  /// No description provided for @syncUserMessageDatabaseFatal.
  ///
  /// In en, this message translates to:
  /// **'Wallet data could not be read. Restart the app and retry sync.'**
  String get syncUserMessageDatabaseFatal;

  /// No description provided for @syncUserMessageChainRecovery.
  ///
  /// In en, this message translates to:
  /// **'The chain changed while syncing. We\'ll keep trying to recover.'**
  String get syncUserMessageChainRecovery;

  /// No description provided for @syncUserMessageParse.
  ///
  /// In en, this message translates to:
  /// **'Sync data could not be processed. Retry sync or check your endpoint.'**
  String get syncUserMessageParse;

  /// No description provided for @syncUserMessageUnknown.
  ///
  /// In en, this message translates to:
  /// **'Sync failed. Retry sync to continue.'**
  String get syncUserMessageUnknown;

  /// No description provided for @homeShieldNoActiveAccount.
  ///
  /// In en, this message translates to:
  /// **'No active account.'**
  String get homeShieldNoActiveAccount;

  /// No description provided for @homeErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again in a moment.\n\nDetails: {details}'**
  String homeErrorGeneric(String details);

  /// No description provided for @homeTransparentBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Transparent: {balance}'**
  String homeTransparentBalanceLabel(String balance);

  /// No description provided for @homeShielding.
  ///
  /// In en, this message translates to:
  /// **'Shielding...'**
  String get homeShielding;

  /// No description provided for @homeShieldNow.
  ///
  /// In en, this message translates to:
  /// **'Shield now'**
  String get homeShieldNow;

  /// No description provided for @homeImportingAccount.
  ///
  /// In en, this message translates to:
  /// **'Importing {name}\nKeep Vizor open & running.'**
  String homeImportingAccount(String name);

  /// No description provided for @homeImportingGeneric.
  ///
  /// In en, this message translates to:
  /// **'It might take some time.\nKeep Vizor open & running.'**
  String get homeImportingGeneric;

  /// No description provided for @homeShieldedBalance.
  ///
  /// In en, this message translates to:
  /// **'Shielded balance'**
  String get homeShieldedBalance;

  /// No description provided for @homeReceiveFirstZec.
  ///
  /// In en, this message translates to:
  /// **'Receive your first ZEC'**
  String get homeReceiveFirstZec;

  /// No description provided for @homeLoadingActivity.
  ///
  /// In en, this message translates to:
  /// **'Loading activity...'**
  String get homeLoadingActivity;

  /// No description provided for @homeNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity, yet...'**
  String get homeNoActivity;

  /// No description provided for @homeFirstTxPrompt.
  ///
  /// In en, this message translates to:
  /// **'How about running your first ZEC tx?'**
  String get homeFirstTxPrompt;

  /// No description provided for @homeRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get homeRecentActivity;

  /// No description provided for @homeSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get homeSeeAll;

  /// No description provided for @shieldQueuedRetry.
  ///
  /// In en, this message translates to:
  /// **'Shielding queued for retry. Check Activity.'**
  String get shieldQueuedRetry;

  /// No description provided for @homeShieldComplete.
  ///
  /// In en, this message translates to:
  /// **'Shielding complete'**
  String get homeShieldComplete;

  /// No description provided for @shieldErrorNoPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Secret Passphrase isn\'t available for this account.'**
  String get shieldErrorNoPassphrase;

  /// No description provided for @shieldErrorWaitForSync.
  ///
  /// In en, this message translates to:
  /// **'Wait for sync to finish, then shield.'**
  String get shieldErrorWaitForSync;

  /// No description provided for @shieldErrorTooSmall.
  ///
  /// In en, this message translates to:
  /// **'Transparent balance is too small to shield after fees.'**
  String get shieldErrorTooSmall;

  /// No description provided for @shieldErrorBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t broadcast your shielding transaction. Try again.'**
  String get shieldErrorBroadcast;

  /// No description provided for @shieldErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t shield your balance. Try again.'**
  String get shieldErrorGeneric;

  /// No description provided for @shieldTxBroadcastUnknown.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction may have reached the network, but confirmation timed out. Check activity before trying again.'**
  String get shieldTxBroadcastUnknown;

  /// No description provided for @shieldTxStorageFailed.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.'**
  String get shieldTxStorageFailed;

  /// No description provided for @shieldTxUncertain.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction status is uncertain. Check activity before trying again.'**
  String get shieldTxUncertain;

  /// No description provided for @keystoneShieldParamsError.
  ///
  /// In en, this message translates to:
  /// **'Required proving parameters could not be prepared.'**
  String get keystoneShieldParamsError;

  /// No description provided for @keystoneShieldSignatureError.
  ///
  /// In en, this message translates to:
  /// **'Keystone signature could not be applied.'**
  String get keystoneShieldSignatureError;

  /// No description provided for @keystoneShieldFinalizeError.
  ///
  /// In en, this message translates to:
  /// **'Shield transaction could not be finalized.'**
  String get keystoneShieldFinalizeError;

  /// No description provided for @keystoneShieldPrepareError.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared.'**
  String get keystoneShieldPrepareError;

  /// No description provided for @keystoneShieldQrDecodeError.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone signature.'**
  String get keystoneShieldQrDecodeError;

  /// No description provided for @keystoneShieldOpenSignedQr.
  ///
  /// In en, this message translates to:
  /// **'Open the signed shield QR on Keystone, then scan again.'**
  String get keystoneShieldOpenSignedQr;

  /// No description provided for @keystoneScanHoldSteady.
  ///
  /// In en, this message translates to:
  /// **'Keep the QR code steady and fully visible.'**
  String get keystoneScanHoldSteady;

  /// No description provided for @keystoneToggleFlashlight.
  ///
  /// In en, this message translates to:
  /// **'Toggle flashlight'**
  String get keystoneToggleFlashlight;

  /// No description provided for @keystoneCancelSigning.
  ///
  /// In en, this message translates to:
  /// **'Cancel signing'**
  String get keystoneCancelSigning;

  /// No description provided for @keystoneShieldBroadcasting.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting shield tx'**
  String get keystoneShieldBroadcasting;

  /// No description provided for @keystoneShieldTransparentBalance.
  ///
  /// In en, this message translates to:
  /// **'Shield transparent balance'**
  String get keystoneShieldTransparentBalance;

  /// No description provided for @keystoneShieldKeepOpen.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open while the transaction is sent.'**
  String get keystoneShieldKeepOpen;

  /// No description provided for @keystoneShieldScanInstructions.
  ///
  /// In en, this message translates to:
  /// **'Use your Keystone wallet to scan this shielding QR code. Follow the steps on your device.'**
  String get keystoneShieldScanInstructions;

  /// No description provided for @keystoneCameraDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. Allow it in Settings to scan Keystone signatures.'**
  String get keystoneCameraDenied;

  /// No description provided for @keystoneCameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The camera is unavailable right now.'**
  String get keystoneCameraUnavailable;

  /// No description provided for @keystoneReadingSignature.
  ///
  /// In en, this message translates to:
  /// **'Reading signature...'**
  String get keystoneReadingSignature;

  /// No description provided for @keystoneScanningProgress.
  ///
  /// In en, this message translates to:
  /// **'Scanning... {progress}%'**
  String keystoneScanningProgress(int progress);

  /// No description provided for @keystoneScanSignedQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the signed QR on your Keystone'**
  String get keystoneScanSignedQr;

  /// No description provided for @keystoneBackToWallet.
  ///
  /// In en, this message translates to:
  /// **'Back to wallet'**
  String get keystoneBackToWallet;

  /// No description provided for @keystoneShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR'**
  String get keystoneShowQr;

  /// No description provided for @keystoneBroadcastingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting...'**
  String get keystoneBroadcastingEllipsis;

  /// No description provided for @keystoneNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get keystoneNextStep;

  /// No description provided for @homeShield.
  ///
  /// In en, this message translates to:
  /// **'Shield'**
  String get homeShield;

  /// No description provided for @homeFirstTxPromptWrapped.
  ///
  /// In en, this message translates to:
  /// **'How about running your\nfirst ZEC tx?'**
  String get homeFirstTxPromptWrapped;

  /// No description provided for @homeHangTight.
  ///
  /// In en, this message translates to:
  /// **'Hang tight ... It might take some time. Keep Vizor open & running.'**
  String get homeHangTight;

  /// No description provided for @receiveNoActiveAccount.
  ///
  /// In en, this message translates to:
  /// **'No active account'**
  String get receiveNoActiveAccount;

  /// No description provided for @receiveRenewShieldedError.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t refresh your shielded address. Try again, or use your current one.'**
  String get receiveRenewShieldedError;

  /// No description provided for @receiveRenewShieldedErrorDetails.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t refresh your shielded address. Try again, or use your current one.\nDetails: {details}'**
  String receiveRenewShieldedErrorDetails(String details);

  /// No description provided for @receiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive {ticker}'**
  String receiveTitle(String ticker);

  /// No description provided for @receiveCopyTransparentAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy transparent address'**
  String get receiveCopyTransparentAddress;

  /// No description provided for @receiveShareShieldedAddress.
  ///
  /// In en, this message translates to:
  /// **'Share shielded address'**
  String get receiveShareShieldedAddress;

  /// No description provided for @receiveShareTransparentAddress.
  ///
  /// In en, this message translates to:
  /// **'Share transparent address'**
  String get receiveShareTransparentAddress;

  /// No description provided for @receiveShielded.
  ///
  /// In en, this message translates to:
  /// **'Shielded'**
  String get receiveShielded;

  /// No description provided for @receiveTransparent.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get receiveTransparent;

  /// No description provided for @receiveQrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'QR unavailable'**
  String get receiveQrUnavailable;

  /// No description provided for @previewUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get previewUsername;

  /// No description provided for @aboutKeplrTeamHeading.
  ///
  /// In en, this message translates to:
  /// **'Built by the Keplr team'**
  String get aboutKeplrTeamHeading;

  /// No description provided for @aboutKeplrTeamBody.
  ///
  /// In en, this message translates to:
  /// **'We built Keplr, the wallet used by millions across Cosmos, Ethereum, and Bitcoin. Vizor is our take on what a Zcash wallet should feel like.'**
  String get aboutKeplrTeamBody;

  /// No description provided for @aboutShieldedHeading.
  ///
  /// In en, this message translates to:
  /// **'Designed for shielded Zcash'**
  String get aboutShieldedHeading;

  /// No description provided for @aboutShieldedBody.
  ///
  /// In en, this message translates to:
  /// **'Vizor is built around shielded transactions, where the sender, recipient, and amount stay private. Transparent Zcash works too, but private is the default.'**
  String get aboutShieldedBody;

  /// No description provided for @aboutOpenSourceHeading.
  ///
  /// In en, this message translates to:
  /// **'Open source, self-custodied'**
  String get aboutOpenSourceHeading;

  /// No description provided for @aboutOpenSourceBody.
  ///
  /// In en, this message translates to:
  /// **'Vizor is Apache licensed. Your keys stay on your device.\nWe don\'t see your balances or your transactions.'**
  String get aboutOpenSourceBody;

  /// No description provided for @aboutLegalPlaceholderHeading.
  ///
  /// In en, this message translates to:
  /// **'From the team that brought you Keplr Wallet.'**
  String get aboutLegalPlaceholderHeading;

  /// No description provided for @aboutLegalPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount.'**
  String get aboutLegalPlaceholderBody;

  /// No description provided for @aboutTermsOfUsage.
  ///
  /// In en, this message translates to:
  /// **'Terms of Usage'**
  String get aboutTermsOfUsage;

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get aboutPrivacyPolicy;

  /// No description provided for @aboutVizorWallet.
  ///
  /// In en, this message translates to:
  /// **'About Vizor Wallet'**
  String get aboutVizorWallet;

  /// No description provided for @aboutWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get aboutWelcome;

  /// No description provided for @aboutOpenGithub.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor GitHub'**
  String get aboutOpenGithub;

  /// No description provided for @aboutWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// No description provided for @aboutOpenWebsite.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor website'**
  String get aboutOpenWebsite;

  /// No description provided for @activitySendFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed'**
  String get activitySendFailed;

  /// No description provided for @activitySending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get activitySending;

  /// No description provided for @activityReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get activityReceiving;

  /// No description provided for @activityReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get activityReceived;

  /// No description provided for @activitySent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get activitySent;

  /// No description provided for @activityShielded.
  ///
  /// In en, this message translates to:
  /// **'Shielded'**
  String get activityShielded;

  /// No description provided for @activityRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get activityRefunded;

  /// No description provided for @activityFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get activityFailed;

  /// No description provided for @activityInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get activityInProgress;

  /// No description provided for @activityCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get activityCompleted;

  /// No description provided for @activityMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get activityMixed;

  /// No description provided for @activityEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get activityEarlier;

  /// No description provided for @activityJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get activityJustNow;

  /// No description provided for @activityMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String activityMinutesAgo(int minutes);

  /// No description provided for @activityThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get activityThisWeek;

  /// No description provided for @activityTodayAt.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String activityTodayAt(String time);

  /// No description provided for @activityYesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String activityYesterdayAt(String time);

  /// No description provided for @activityDateAt.
  ///
  /// In en, this message translates to:
  /// **'{date}, {time}'**
  String activityDateAt(String date, String time);

  /// No description provided for @activityNoActiveAccount.
  ///
  /// In en, this message translates to:
  /// **'No active account.'**
  String get activityNoActiveAccount;

  /// No description provided for @activityTxLoadError.
  ///
  /// In en, this message translates to:
  /// **'Transaction could not be loaded.'**
  String get activityTxLoadError;

  /// No description provided for @activityTxRefreshError.
  ///
  /// In en, this message translates to:
  /// **'Latest transaction status could not be refreshed.'**
  String get activityTxRefreshError;

  /// No description provided for @activityTxHashCopied.
  ///
  /// In en, this message translates to:
  /// **'Transaction hash copied'**
  String get activityTxHashCopied;

  /// No description provided for @activityLoadingTx.
  ///
  /// In en, this message translates to:
  /// **'Loading transaction…'**
  String get activityLoadingTx;

  /// No description provided for @activityLoadError.
  ///
  /// In en, this message translates to:
  /// **'Activity could not be loaded.'**
  String get activityLoadError;

  /// No description provided for @activityTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get activityTimestamp;

  /// No description provided for @activityTxId.
  ///
  /// In en, this message translates to:
  /// **'Tx ID'**
  String get activityTxId;

  /// No description provided for @activityFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get activityFrom;

  /// No description provided for @activityTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get activityTo;

  /// No description provided for @activityShowFullAddress.
  ///
  /// In en, this message translates to:
  /// **'Show full address'**
  String get activityShowFullAddress;

  /// No description provided for @activityFromTransparentBalance.
  ///
  /// In en, this message translates to:
  /// **'From transparent balance'**
  String get activityFromTransparentBalance;

  /// No description provided for @activityReceivingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Receiving...'**
  String get activityReceivingEllipsis;

  /// No description provided for @activitySendingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get activitySendingEllipsis;

  /// No description provided for @activitySentSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Sent successfully'**
  String get activitySentSuccessfully;

  /// No description provided for @swapFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Swap failed'**
  String get swapFailedTitle;

  /// No description provided for @swapReviewQuote.
  ///
  /// In en, this message translates to:
  /// **'Review quote'**
  String get swapReviewQuote;

  /// No description provided for @shieldReceiptInProgress.
  ///
  /// In en, this message translates to:
  /// **'Shielding in progress...'**
  String get shieldReceiptInProgress;

  /// No description provided for @shieldReceiptCompleted.
  ///
  /// In en, this message translates to:
  /// **'Shielded successfully'**
  String get shieldReceiptCompleted;

  /// No description provided for @shieldReceiptFailed.
  ///
  /// In en, this message translates to:
  /// **'Shielding failed'**
  String get shieldReceiptFailed;

  /// No description provided for @receiveReceiptInProgress.
  ///
  /// In en, this message translates to:
  /// **'Receive in progress...'**
  String get receiveReceiptInProgress;

  /// No description provided for @receiveReceiptCompleted.
  ///
  /// In en, this message translates to:
  /// **'Received successfully'**
  String get receiveReceiptCompleted;

  /// No description provided for @receiveReceiptFailed.
  ///
  /// In en, this message translates to:
  /// **'Receive failed'**
  String get receiveReceiptFailed;

  /// No description provided for @receivedFeeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Network fee paid by the sender to process this transaction.'**
  String get receivedFeeTooltip;

  /// No description provided for @activityNetworkFee.
  ///
  /// In en, this message translates to:
  /// **'Network fee'**
  String get activityNetworkFee;

  /// No description provided for @activityMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get activityMessage;

  /// No description provided for @activityFailedFundsReturned.
  ///
  /// In en, this message translates to:
  /// **'Failed, funds returned'**
  String get activityFailedFundsReturned;

  /// No description provided for @sendTitle.
  ///
  /// In en, this message translates to:
  /// **'Send {ticker}'**
  String sendTitle(String ticker);

  /// No description provided for @sendKeystoneNoTex.
  ///
  /// In en, this message translates to:
  /// **'Keystone does not support TEX sends yet.'**
  String get sendKeystoneNoTex;

  /// No description provided for @sendInsufficientBalance.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance'**
  String get sendInsufficientBalance;

  /// No description provided for @sendInsufficientShieldedBalance.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance'**
  String get sendInsufficientShieldedBalance;

  /// No description provided for @sendInsufficientBalanceCoverFee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance to cover fee'**
  String get sendInsufficientBalanceCoverFee;

  /// No description provided for @sendInsufficientShieldedBalanceCoverFee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance to cover fee'**
  String get sendInsufficientShieldedBalanceCoverFee;

  /// No description provided for @sendInsufficientBalanceIncludingFee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance including fee'**
  String get sendInsufficientBalanceIncludingFee;

  /// No description provided for @sendInsufficientShieldedBalanceIncludingFee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance including fee'**
  String get sendInsufficientShieldedBalanceIncludingFee;

  /// No description provided for @sendInsufficientBalanceWithFee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance (fee: {fee})'**
  String sendInsufficientBalanceWithFee(String fee);

  /// No description provided for @sendInsufficientShieldedBalanceWithFee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance (fee: {fee})'**
  String sendInsufficientShieldedBalanceWithFee(String fee);

  /// No description provided for @sendMessageTooLong.
  ///
  /// In en, this message translates to:
  /// **'Message is too long'**
  String get sendMessageTooLong;

  /// No description provided for @sendMessageShieldedOnly.
  ///
  /// In en, this message translates to:
  /// **'Message is only available for shielded addresses'**
  String get sendMessageShieldedOnly;

  /// No description provided for @sendNoActiveAccount.
  ///
  /// In en, this message translates to:
  /// **'No active account'**
  String get sendNoActiveAccount;

  /// No description provided for @sendEnterValidAddressForMax.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid address to use Max'**
  String get sendEnterValidAddressForMax;

  /// No description provided for @sendMaxUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Max amount unavailable'**
  String get sendMaxUnavailable;

  /// No description provided for @sendInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Invalid amount'**
  String get sendInvalidAmount;

  /// No description provided for @sendCalculatingMax.
  ///
  /// In en, this message translates to:
  /// **'Calculating max amount'**
  String get sendCalculatingMax;

  /// No description provided for @sendEnterValidAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid address'**
  String get sendEnterValidAddress;

  /// No description provided for @sendInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid address'**
  String get sendInvalidAddress;

  /// No description provided for @sendAddressValidationFailed.
  ///
  /// In en, this message translates to:
  /// **'Address validation failed'**
  String get sendAddressValidationFailed;

  /// No description provided for @sendSendTo.
  ///
  /// In en, this message translates to:
  /// **'Send to'**
  String get sendSendTo;

  /// No description provided for @sendZcashAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Zcash address'**
  String get sendZcashAddressHint;

  /// No description provided for @sendZcashAddressHintMobile.
  ///
  /// In en, this message translates to:
  /// **'Zcash Address'**
  String get sendZcashAddressHintMobile;

  /// No description provided for @sendAddMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Add a message'**
  String get sendAddMessageHint;

  /// No description provided for @sendCloseMessage.
  ///
  /// In en, this message translates to:
  /// **'Close message'**
  String get sendCloseMessage;

  /// No description provided for @sendContactsZcashTitle.
  ///
  /// In en, this message translates to:
  /// **'Contacts Zcash'**
  String get sendContactsZcashTitle;

  /// No description provided for @sendNoZcashContacts.
  ///
  /// In en, this message translates to:
  /// **'No Zcash contacts'**
  String get sendNoZcashContacts;

  /// No description provided for @sendOpenContacts.
  ///
  /// In en, this message translates to:
  /// **'Open contacts'**
  String get sendOpenContacts;

  /// No description provided for @sendSpendableTooltipTitle.
  ///
  /// In en, this message translates to:
  /// **'Your spendable balance may be lower than your total balance.'**
  String get sendSpendableTooltipTitle;

  /// No description provided for @sendSpendableTooltipBody.
  ///
  /// In en, this message translates to:
  /// **'Funds need confirmations before they can be spent: 3 for change from your own wallet, 10 for funds received from others. Shielded notes also need to be fully scanned. They\'ll become available shortly.'**
  String get sendSpendableTooltipBody;

  /// No description provided for @sendMaxLabel.
  ///
  /// In en, this message translates to:
  /// **'Max: {amount}'**
  String sendMaxLabel(String amount);

  /// No description provided for @sendUseMaxBalance.
  ///
  /// In en, this message translates to:
  /// **'Use maximum spendable balance'**
  String get sendUseMaxBalance;

  /// No description provided for @sendSpendableInfo.
  ///
  /// In en, this message translates to:
  /// **'Spendable balance info'**
  String get sendSpendableInfo;

  /// No description provided for @sendAddMemo.
  ///
  /// In en, this message translates to:
  /// **'Add a memo'**
  String get sendAddMemo;

  /// No description provided for @sendEncryptedShieldedOnly.
  ///
  /// In en, this message translates to:
  /// **'Encrypted, for shielded addresses only.'**
  String get sendEncryptedShieldedOnly;

  /// No description provided for @sendScanKeystoneQr.
  ///
  /// In en, this message translates to:
  /// **'Scan your Keystone QR Code'**
  String get sendScanKeystoneQr;

  /// No description provided for @keystoneSendQrDecodeError.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone transaction signature.'**
  String get keystoneSendQrDecodeError;

  /// No description provided for @keystoneOpenSignedTxQr.
  ///
  /// In en, this message translates to:
  /// **'Open the signed transaction QR on Keystone, then scan again.'**
  String get keystoneOpenSignedTxQr;

  /// No description provided for @keystoneScanQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get keystoneScanQrTitle;

  /// No description provided for @keystoneHoldQrSteady.
  ///
  /// In en, this message translates to:
  /// **'Hold the QR code steady in front of your camera'**
  String get keystoneHoldQrSteady;

  /// No description provided for @keystoneCameraOnly.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing uses camera QR scanning only. Connect a camera and try again.'**
  String get keystoneCameraOnly;

  /// No description provided for @sendSigningCancelledParams.
  ///
  /// In en, this message translates to:
  /// **'Signing was cancelled before proving parameters were downloaded.'**
  String get sendSigningCancelledParams;

  /// No description provided for @sendTxExpired.
  ///
  /// In en, this message translates to:
  /// **'Transaction expired before it could be signed.'**
  String get sendTxExpired;

  /// No description provided for @sendKeystonePrepareError.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared. Return to Send and try again.'**
  String get sendKeystonePrepareError;

  /// No description provided for @sendKeystonePrepareErrorGoBack.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared. Go back and try again.'**
  String get sendKeystonePrepareErrorGoBack;

  /// No description provided for @sendConfirmWithKeystone.
  ///
  /// In en, this message translates to:
  /// **'Confirm with Keystone'**
  String get sendConfirmWithKeystone;

  /// No description provided for @sendConfirmAndSend.
  ///
  /// In en, this message translates to:
  /// **'Confirm & send'**
  String get sendConfirmAndSend;

  /// No description provided for @sendConfirmAndSendMobile.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Send'**
  String get sendConfirmAndSendMobile;

  /// No description provided for @sendScanWithKeystone.
  ///
  /// In en, this message translates to:
  /// **'Scan with your Keystone'**
  String get sendScanWithKeystone;

  /// No description provided for @sendAfterScanGetSignature.
  ///
  /// In en, this message translates to:
  /// **'After you scanned, click Get signature.'**
  String get sendAfterScanGetSignature;

  /// No description provided for @sendScanNowProofs.
  ///
  /// In en, this message translates to:
  /// **'Scan now. Signature import unlocks after proofs are ready.'**
  String get sendScanNowProofs;

  /// No description provided for @sendPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get sendPreparing;

  /// No description provided for @sendPreparingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get sendPreparingEllipsis;

  /// No description provided for @sendStatusQueuedTitle.
  ///
  /// In en, this message translates to:
  /// **'Queued to send'**
  String get sendStatusQueuedTitle;

  /// No description provided for @sendStatusSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Sent!'**
  String get sendStatusSentTitle;

  /// No description provided for @sendStatusSendingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Submitting your transaction to the network...'**
  String get sendStatusSendingSubtitle;

  /// No description provided for @sendStatusQueuedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your transaction was created and will be submitted automatically. Check the Activity page before sending again.'**
  String get sendStatusQueuedSubtitle;

  /// No description provided for @sendStatusSucceededSubtitle.
  ///
  /// In en, this message translates to:
  /// **'It will confirm on-chain shortly. Track it in Activity.'**
  String get sendStatusSucceededSubtitle;

  /// No description provided for @sendStatusFailedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent, your funds haven\'t moved. Try again.'**
  String get sendStatusFailedSubtitle;

  /// No description provided for @sendStatusReturnHome.
  ///
  /// In en, this message translates to:
  /// **'Return home'**
  String get sendStatusReturnHome;

  /// No description provided for @sendGetSignature.
  ///
  /// In en, this message translates to:
  /// **'Get signature'**
  String get sendGetSignature;

  /// No description provided for @sendNotEnoughZec.
  ///
  /// In en, this message translates to:
  /// **'Not enough ZEC'**
  String get sendNotEnoughZec;

  /// No description provided for @sendFinishReview.
  ///
  /// In en, this message translates to:
  /// **'Finish & review'**
  String get sendFinishReview;

  /// No description provided for @sendEnterAmountToContinue.
  ///
  /// In en, this message translates to:
  /// **'Enter amount to continue'**
  String get sendEnterAmountToContinue;

  /// No description provided for @sendEnterAddressToContinue.
  ///
  /// In en, this message translates to:
  /// **'Enter address to continue'**
  String get sendEnterAddressToContinue;

  /// No description provided for @addressTex.
  ///
  /// In en, this message translates to:
  /// **'TEX address'**
  String get addressTex;

  /// No description provided for @sendSelectRecipient.
  ///
  /// In en, this message translates to:
  /// **'Select Recipient'**
  String get sendSelectRecipient;

  /// No description provided for @sendEnterAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter Amount'**
  String get sendEnterAmount;

  /// No description provided for @sendReviewSend.
  ///
  /// In en, this message translates to:
  /// **'Review Send'**
  String get sendReviewSend;

  /// No description provided for @sendScanAQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan a QR Code'**
  String get sendScanAQrCode;

  /// No description provided for @sendScanAddressUsingCamera.
  ///
  /// In en, this message translates to:
  /// **'Scan an address using camera'**
  String get sendScanAddressUsingCamera;

  /// No description provided for @sendContactCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 contact} other{{count} contacts}}'**
  String sendContactCount(int count);

  /// No description provided for @sendPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get sendPaste;

  /// No description provided for @sendClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get sendClear;

  /// No description provided for @sendSendingTo.
  ///
  /// In en, this message translates to:
  /// **'Sending to'**
  String get sendSendingTo;

  /// No description provided for @sendMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get sendMax;

  /// No description provided for @sendEnterAmountInZec.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in ZEC'**
  String get sendEnterAmountInZec;

  /// No description provided for @sendEnterAmountInUsd.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in USD'**
  String get sendEnterAmountInUsd;

  /// No description provided for @sendFullAddress.
  ///
  /// In en, this message translates to:
  /// **'Full address'**
  String get sendFullAddress;

  /// No description provided for @sendAddShortEncryptedMessage.
  ///
  /// In en, this message translates to:
  /// **'Add short encrypted message'**
  String get sendAddShortEncryptedMessage;

  /// No description provided for @sendAboutTxFee.
  ///
  /// In en, this message translates to:
  /// **'About the transaction fee'**
  String get sendAboutTxFee;

  /// No description provided for @sendAddMemoTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Memo'**
  String get sendAddMemoTitle;

  /// No description provided for @sendOnlyRecipientCanRead.
  ///
  /// In en, this message translates to:
  /// **'Only the recipient can read this'**
  String get sendOnlyRecipientCanRead;

  /// No description provided for @sendClearMemo.
  ///
  /// In en, this message translates to:
  /// **'Clear memo'**
  String get sendClearMemo;

  /// No description provided for @sendReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review send'**
  String get sendReviewTitle;

  /// No description provided for @sendCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get sendCollapse;

  /// No description provided for @sendTexAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'TEX - {address}'**
  String sendTexAddressLabel(String address);

  /// No description provided for @sendInProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Send in progress...'**
  String get sendInProgressTitle;

  /// No description provided for @sendAmountToRecipient.
  ///
  /// In en, this message translates to:
  /// **'{amount} to {recipient}'**
  String sendAmountToRecipient(String amount, String recipient);

  /// No description provided for @sendConfirmTransaction.
  ///
  /// In en, this message translates to:
  /// **'Confirm transaction'**
  String get sendConfirmTransaction;

  /// No description provided for @sendErrorInsufficientForAmountFee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance to cover amount and fee.'**
  String get sendErrorInsufficientForAmountFee;

  /// No description provided for @sendErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection and try again.'**
  String get sendErrorNetwork;

  /// No description provided for @sendErrorPartialBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Some parts of this transaction were sent. Open Activity to see what went through before you try again.'**
  String get sendErrorPartialBroadcast;

  /// No description provided for @sendErrorBroadcastRejected.
  ///
  /// In en, this message translates to:
  /// **'The network rejected this transaction. Try again.'**
  String get sendErrorBroadcastRejected;

  /// No description provided for @sendErrorBroadcastRejectedLater.
  ///
  /// In en, this message translates to:
  /// **'The network rejected this transaction. Try again later.'**
  String get sendErrorBroadcastRejectedLater;

  /// No description provided for @sendErrorExpiredTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Transaction expired before it could be sent. Try again.'**
  String get sendErrorExpiredTryAgain;

  /// No description provided for @sendErrorExpired.
  ///
  /// In en, this message translates to:
  /// **'Transaction expired before it could be sent.'**
  String get sendErrorExpired;

  /// No description provided for @sendErrorGenericShort.
  ///
  /// In en, this message translates to:
  /// **'Send failed. Try again.'**
  String get sendErrorGenericShort;

  /// No description provided for @sendErrorCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'Transaction couldn\'t be sent. Go back to your wallet and check the latest status.'**
  String get sendErrorCheckStatus;

  /// No description provided for @saplingDownloadRequired.
  ///
  /// In en, this message translates to:
  /// **'Download Required'**
  String get saplingDownloadRequired;

  /// No description provided for @saplingDownloadBody.
  ///
  /// In en, this message translates to:
  /// **'To create this private transaction, your wallet needs to download about 50MB of cryptographic parameters.'**
  String get saplingDownloadBody;

  /// No description provided for @saplingDownloadOnce.
  ///
  /// In en, this message translates to:
  /// **'This happens once, then it\'s done.\nNetwork data charges may apply.'**
  String get saplingDownloadOnce;

  /// No description provided for @saplingDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get saplingDownload;

  /// No description provided for @accountsAddAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get accountsAddAccount;

  /// No description provided for @accountsCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get accountsCurrent;

  /// No description provided for @accountsOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get accountsOther;

  /// No description provided for @accountsAccountActions.
  ///
  /// In en, this message translates to:
  /// **'Account actions'**
  String get accountsAccountActions;

  /// No description provided for @accountsEditAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get accountsEditAccount;

  /// No description provided for @accountsCopyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get accountsCopyAddress;

  /// No description provided for @accountsSendZec.
  ///
  /// In en, this message translates to:
  /// **'Send ZEC'**
  String get accountsSendZec;

  /// No description provided for @accountsRemoveAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get accountsRemoveAccount;

  /// No description provided for @accountsOptionsFor.
  ///
  /// In en, this message translates to:
  /// **'Account options for {name}'**
  String accountsOptionsFor(String name);

  /// No description provided for @accountsRemoveResetWarning.
  ///
  /// In en, this message translates to:
  /// **'Removing this account will completely reset the Vizor app. This means deleting all accounts and requiring you to import accounts again.\nThis cannot be undone.'**
  String get accountsRemoveResetWarning;

  /// No description provided for @accountsRemoveWarning.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove this account? This action can\'t be reverted.\nYou will have to re-import your account.'**
  String get accountsRemoveWarning;

  /// No description provided for @accountsResetVizor.
  ///
  /// In en, this message translates to:
  /// **'Reset Vizor'**
  String get accountsResetVizor;

  /// No description provided for @accountsCheckingSwaps.
  ///
  /// In en, this message translates to:
  /// **'Checking this account for active swaps before removal.'**
  String get accountsCheckingSwaps;

  /// No description provided for @accountsSwapCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check this account for active swaps. Try again before removing it.'**
  String get accountsSwapCheckFailed;

  /// No description provided for @accountsActiveSwaps.
  ///
  /// In en, this message translates to:
  /// **'This account has {count, plural, =1{1 active swap} other{{count} active swaps}}. Complete or remove them from swap activity before removing this account.'**
  String accountsActiveSwaps(int count);

  /// No description provided for @accountsIncorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Please try again.'**
  String get accountsIncorrectPassword;

  /// No description provided for @accountsEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get accountsEnterPassword;

  /// No description provided for @accountsCheckingPassword.
  ///
  /// In en, this message translates to:
  /// **'Checking password...'**
  String get accountsCheckingPassword;

  /// No description provided for @accountsStoppingSync.
  ///
  /// In en, this message translates to:
  /// **'Stopping sync...'**
  String get accountsStoppingSync;

  /// No description provided for @accountsResetting.
  ///
  /// In en, this message translates to:
  /// **'Resetting...'**
  String get accountsResetting;

  /// No description provided for @accountsRemoving.
  ///
  /// In en, this message translates to:
  /// **'Removing account...'**
  String get accountsRemoving;

  /// No description provided for @accountsChangeProfilePicture.
  ///
  /// In en, this message translates to:
  /// **'Change profile picture'**
  String get accountsChangeProfilePicture;

  /// No description provided for @accountsSelectProfilePicture.
  ///
  /// In en, this message translates to:
  /// **'Select profile picture'**
  String get accountsSelectProfilePicture;

  /// No description provided for @accountsClearAccountName.
  ///
  /// In en, this message translates to:
  /// **'Clear account name'**
  String get accountsClearAccountName;

  /// No description provided for @accountsSaveEdits.
  ///
  /// In en, this message translates to:
  /// **'Save edits'**
  String get accountsSaveEdits;

  /// No description provided for @accountsUpdatePicture.
  ///
  /// In en, this message translates to:
  /// **'Update picture'**
  String get accountsUpdatePicture;

  /// No description provided for @accountsOtherAccounts.
  ///
  /// In en, this message translates to:
  /// **'Other accounts'**
  String get accountsOtherAccounts;

  /// No description provided for @accountsManageAccounts.
  ///
  /// In en, this message translates to:
  /// **'Manage accounts'**
  String get accountsManageAccounts;

  /// No description provided for @accountsNameHint.
  ///
  /// In en, this message translates to:
  /// **'1-20 characters'**
  String get accountsNameHint;

  /// No description provided for @accountsNameLengthMessage.
  ///
  /// In en, this message translates to:
  /// **'Use up to 20 characters.'**
  String get accountsNameLengthMessage;

  /// No description provided for @accountsUpdateError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update account.'**
  String get accountsUpdateError;

  /// No description provided for @abSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get abSearch;

  /// No description provided for @abSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for label or network'**
  String get abSearchHint;

  /// No description provided for @abEditContact.
  ///
  /// In en, this message translates to:
  /// **'Edit contact'**
  String get abEditContact;

  /// No description provided for @abRemoveContact.
  ///
  /// In en, this message translates to:
  /// **'Remove contact'**
  String get abRemoveContact;

  /// No description provided for @abNoContactsYet.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get abNoContactsYet;

  /// No description provided for @abAddFirstContact.
  ///
  /// In en, this message translates to:
  /// **'Add your first contact to get started.'**
  String get abAddFirstContact;

  /// No description provided for @abNoContactsFound.
  ///
  /// In en, this message translates to:
  /// **'No contacts were found'**
  String get abNoContactsFound;

  /// No description provided for @abModifySearch.
  ///
  /// In en, this message translates to:
  /// **'Try to modify your search'**
  String get abModifySearch;

  /// No description provided for @abAddContact.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get abAddContact;

  /// No description provided for @abAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address label'**
  String get abAddressLabel;

  /// No description provided for @abAddLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Add label 1-20 characters'**
  String get abAddLabelHint;

  /// No description provided for @abAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get abAddress;

  /// No description provided for @abAddAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get abAddAddressHint;

  /// No description provided for @abScanAddressQr.
  ///
  /// In en, this message translates to:
  /// **'Scan address QR'**
  String get abScanAddressQr;

  /// No description provided for @abChangeContactPicture.
  ///
  /// In en, this message translates to:
  /// **'Change contact picture'**
  String get abChangeContactPicture;

  /// No description provided for @abChainAndAddress.
  ///
  /// In en, this message translates to:
  /// **'Chain & address'**
  String get abChainAndAddress;

  /// No description provided for @abSelectNetwork.
  ///
  /// In en, this message translates to:
  /// **'Select network'**
  String get abSelectNetwork;

  /// No description provided for @abSelectContactPicture.
  ///
  /// In en, this message translates to:
  /// **'Select contact picture'**
  String get abSelectContactPicture;

  /// No description provided for @abSearchNetworkHint.
  ///
  /// In en, this message translates to:
  /// **'Search network'**
  String get abSearchNetworkHint;

  /// No description provided for @abNoNetworksFound.
  ///
  /// In en, this message translates to:
  /// **'No networks found'**
  String get abNoNetworksFound;

  /// No description provided for @abContactWillBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'This contact will be removed.'**
  String get abContactWillBeRemoved;

  /// No description provided for @abNamedContactWillBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} will be removed from your contacts.'**
  String abNamedContactWillBeRemoved(String name);

  /// No description provided for @abLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your contacts. Try again, or contact support if this keeps happening.'**
  String get abLoadError;

  /// No description provided for @abSaveError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save contact. Try again.'**
  String get abSaveError;

  /// No description provided for @abRemoveError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove contact. Try again.'**
  String get abRemoveError;

  /// No description provided for @abNoContactsFoundShort.
  ///
  /// In en, this message translates to:
  /// **'No contacts found'**
  String get abNoContactsFoundShort;

  /// No description provided for @abSearchContacts.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get abSearchContacts;

  /// No description provided for @abCloseContacts.
  ///
  /// In en, this message translates to:
  /// **'Close contacts'**
  String get abCloseContacts;

  /// No description provided for @abClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get abClearSearch;

  /// No description provided for @abQrNoAddress.
  ///
  /// In en, this message translates to:
  /// **'QR code did not include an address.'**
  String get abQrNoAddress;

  /// No description provided for @abClearName.
  ///
  /// In en, this message translates to:
  /// **'Clear name'**
  String get abClearName;

  /// No description provided for @abClearAddress.
  ///
  /// In en, this message translates to:
  /// **'Clear address'**
  String get abClearAddress;

  /// No description provided for @abNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get abNetwork;

  /// No description provided for @abName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get abName;

  /// No description provided for @abAddNameHint.
  ///
  /// In en, this message translates to:
  /// **'Add a name'**
  String get abAddNameHint;

  /// No description provided for @abAddAnAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Add an address'**
  String get abAddAnAddressHint;

  /// No description provided for @abSaveContact.
  ///
  /// In en, this message translates to:
  /// **'Save contact'**
  String get abSaveContact;

  /// No description provided for @abRemoveContactQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove contact?'**
  String get abRemoveContactQuestion;

  /// No description provided for @abNoPastTxEffect.
  ///
  /// In en, this message translates to:
  /// **'This does not affect any past transactions.'**
  String get abNoPastTxEffect;

  /// No description provided for @abInvalidEvm.
  ///
  /// In en, this message translates to:
  /// **'Invalid EVM address'**
  String get abInvalidEvm;

  /// No description provided for @abInvalidBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Invalid Bitcoin address'**
  String get abInvalidBitcoin;

  /// No description provided for @abInvalidSolana.
  ///
  /// In en, this message translates to:
  /// **'Invalid Solana address'**
  String get abInvalidSolana;

  /// No description provided for @abInvalidZcash.
  ///
  /// In en, this message translates to:
  /// **'Invalid Zcash address'**
  String get abInvalidZcash;

  /// No description provided for @abInvalidNear.
  ///
  /// In en, this message translates to:
  /// **'Invalid NEAR address'**
  String get abInvalidNear;

  /// No description provided for @abNearHint.
  ///
  /// In en, this message translates to:
  /// **'NEAR accounts usually end in .near — double-check this address'**
  String get abNearHint;

  /// No description provided for @abAddLabelError.
  ///
  /// In en, this message translates to:
  /// **'Add a label'**
  String get abAddLabelError;

  /// No description provided for @abLabelLength.
  ///
  /// In en, this message translates to:
  /// **'Use 1-20 characters'**
  String get abLabelLength;

  /// No description provided for @abAddAddressError.
  ///
  /// In en, this message translates to:
  /// **'Add an address'**
  String get abAddAddressError;

  /// No description provided for @abScanNetworkQr.
  ///
  /// In en, this message translates to:
  /// **'Scan {network} QR code'**
  String abScanNetworkQr(String network);

  /// No description provided for @keystoneScanReadingQr.
  ///
  /// In en, this message translates to:
  /// **'Reading QR...'**
  String get keystoneScanReadingQr;

  /// No description provided for @cameraNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No camera found'**
  String get cameraNoneFound;

  /// No description provided for @cameraLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading camera...'**
  String get cameraLoading;

  /// No description provided for @cameraDefault.
  ///
  /// In en, this message translates to:
  /// **'Default camera'**
  String get cameraDefault;

  /// No description provided for @cameraDefaultSuffix.
  ///
  /// In en, this message translates to:
  /// **'{name} (Default)'**
  String cameraDefaultSuffix(String name);

  /// No description provided for @cameraOpenError.
  ///
  /// In en, this message translates to:
  /// **'No camera could be opened. Check that a camera is connected and not in use by another app.'**
  String get cameraOpenError;

  /// No description provided for @cameraDeniedWindowsTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Windows camera access'**
  String get cameraDeniedWindowsTitle;

  /// No description provided for @cameraDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve denied the Camera access'**
  String get cameraDeniedTitle;

  /// No description provided for @cameraDeniedWindowsDesc.
  ///
  /// In en, this message translates to:
  /// **'Turn on Camera access and Let desktop apps access your camera in Windows Settings.'**
  String get cameraDeniedWindowsDesc;

  /// No description provided for @cameraDeniedDesc.
  ///
  /// In en, this message translates to:
  /// **'Request again, or enable manually\nin the System settings.'**
  String get cameraDeniedDesc;

  /// No description provided for @cameraAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow camera'**
  String get cameraAllow;

  /// No description provided for @cameraRequestAgain.
  ///
  /// In en, this message translates to:
  /// **'Request again'**
  String get cameraRequestAgain;

  /// No description provided for @cameraOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get cameraOpenSettings;

  /// No description provided for @cameraEnableAccess.
  ///
  /// In en, this message translates to:
  /// **'Enable camera access'**
  String get cameraEnableAccess;

  /// No description provided for @cameraKeystoneRequired.
  ///
  /// In en, this message translates to:
  /// **'A camera is required to connect Keystone.\nYou can revert this in settings anytime later.'**
  String get cameraKeystoneRequired;

  /// No description provided for @cameraUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get cameraUnavailableTitle;

  /// No description provided for @troubleScanning.
  ///
  /// In en, this message translates to:
  /// **'Trouble scanning?'**
  String get troubleScanning;

  /// No description provided for @troubleTipFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Tap the QR code on your Keystone to show it full screen. This is the easiest fix.'**
  String get troubleTipFullScreen;

  /// No description provided for @troubleTipDistance.
  ///
  /// In en, this message translates to:
  /// **'Move your Keystone a few inches further from the camera so it can focus.'**
  String get troubleTipDistance;

  /// No description provided for @troubleTipLighting.
  ///
  /// In en, this message translates to:
  /// **'Make sure the room is well-lit and the QR code isn\'t reflecting glare.'**
  String get troubleTipLighting;

  /// No description provided for @troubleTipContinuity.
  ///
  /// In en, this message translates to:
  /// **'On a Mac, you can use Continuity Camera to scan with your iPhone instead.'**
  String get troubleTipContinuity;

  /// No description provided for @cameraLabel.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraLabel;

  /// No description provided for @cameraSelect.
  ///
  /// In en, this message translates to:
  /// **'Select Camera'**
  String get cameraSelect;

  /// No description provided for @cameraDetailDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get cameraDetailDefault;

  /// No description provided for @cameraDetailExternal.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get cameraDetailExternal;

  /// No description provided for @cameraDetailFront.
  ///
  /// In en, this message translates to:
  /// **'Front'**
  String get cameraDetailFront;

  /// No description provided for @cameraDetailBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get cameraDetailBack;

  /// No description provided for @cameraDetailNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get cameraDetailNormal;

  /// No description provided for @cameraDetailWide.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get cameraDetailWide;

  /// No description provided for @cameraDetailZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get cameraDetailZoom;

  /// No description provided for @keystonePrepareWallet.
  ///
  /// In en, this message translates to:
  /// **'Prepare your Keystone wallet'**
  String get keystonePrepareWallet;

  /// No description provided for @keystoneStepCheckFirmware.
  ///
  /// In en, this message translates to:
  /// **'1. Check Keystone firmware'**
  String get keystoneStepCheckFirmware;

  /// No description provided for @keystoneStepPrepareConnect.
  ///
  /// In en, this message translates to:
  /// **'2. Prepare to connect'**
  String get keystoneStepPrepareConnect;

  /// No description provided for @keystoneOnYourKeystone.
  ///
  /// In en, this message translates to:
  /// **'On your Keystone'**
  String get keystoneOnYourKeystone;

  /// No description provided for @keystoneStepTapConnect.
  ///
  /// In en, this message translates to:
  /// **'Tap ••• (top right), then Connect software wallet.'**
  String get keystoneStepTapConnect;

  /// No description provided for @keystoneStepSelectVizor.
  ///
  /// In en, this message translates to:
  /// **'Select Vizor (or ZODL)'**
  String get keystoneStepSelectVizor;

  /// No description provided for @keystoneOnVizor.
  ///
  /// In en, this message translates to:
  /// **'On Vizor'**
  String get keystoneOnVizor;

  /// No description provided for @keystoneStepScanDynamicQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the dynamic QR code on your Keystone.'**
  String get keystoneStepScanDynamicQr;

  /// No description provided for @keystoneFirmwareNote.
  ///
  /// In en, this message translates to:
  /// **'Make sure your Keystone is on the latest Cypherpunk firmware. '**
  String get keystoneFirmwareNote;

  /// No description provided for @keystoneDownloadFirmware.
  ///
  /// In en, this message translates to:
  /// **'Download Keystone firmware'**
  String get keystoneDownloadFirmware;

  /// No description provided for @keystoneNoZcashAccounts.
  ///
  /// In en, this message translates to:
  /// **'No Zcash accounts were found on this Keystone QR.'**
  String get keystoneNoZcashAccounts;

  /// No description provided for @keystoneAccountQrDecodeError.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone Zcash account.'**
  String get keystoneAccountQrDecodeError;

  /// No description provided for @keystoneOpenAccountQr.
  ///
  /// In en, this message translates to:
  /// **'Open the Zcash account QR on Keystone, then scan again.'**
  String get keystoneOpenAccountQr;

  /// No description provided for @keystoneReadingAccounts.
  ///
  /// In en, this message translates to:
  /// **'Reading accounts...'**
  String get keystoneReadingAccounts;

  /// No description provided for @keystoneImportCameraOnly.
  ///
  /// In en, this message translates to:
  /// **'Keystone import uses camera QR scanning only. Connect a camera and try again.'**
  String get keystoneImportCameraOnly;

  /// No description provided for @keystoneSelectAccount.
  ///
  /// In en, this message translates to:
  /// **'Select account'**
  String get keystoneSelectAccount;

  /// No description provided for @keystoneAccountsFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account found} other{{count} accounts found}}'**
  String keystoneAccountsFound(int count);

  /// No description provided for @keystoneAccountFallback.
  ///
  /// In en, this message translates to:
  /// **'Account {index}'**
  String keystoneAccountFallback(int index);

  /// No description provided for @keystoneScanAccountQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the Keystone account QR'**
  String get keystoneScanAccountQr;

  /// No description provided for @onbEstimatingHeight.
  ///
  /// In en, this message translates to:
  /// **'Estimating height...'**
  String get onbEstimatingHeight;

  /// No description provided for @onbCheckingAccounts.
  ///
  /// In en, this message translates to:
  /// **'Checking accounts...'**
  String get onbCheckingAccounts;

  /// No description provided for @onbPausingSync.
  ///
  /// In en, this message translates to:
  /// **'Pausing sync...'**
  String get onbPausingSync;

  /// No description provided for @onbImportingWallet.
  ///
  /// In en, this message translates to:
  /// **'Importing wallet...'**
  String get onbImportingWallet;

  /// No description provided for @onbSelectMonth.
  ///
  /// In en, this message translates to:
  /// **'Select month'**
  String get onbSelectMonth;

  /// No description provided for @onbSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get onbSelectDate;

  /// No description provided for @onbBirthdayTitle.
  ///
  /// In en, this message translates to:
  /// **'Around when did you create your wallet?'**
  String get onbBirthdayTitle;

  /// No description provided for @onbBirthdaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'An estimate is enough — sync starts\nfrom there.'**
  String get onbBirthdaySubtitle;

  /// No description provided for @onbDontRemember.
  ///
  /// In en, this message translates to:
  /// **'I don’t remember'**
  String get onbDontRemember;

  /// No description provided for @onbEnterMonth.
  ///
  /// In en, this message translates to:
  /// **'Enter the month'**
  String get onbEnterMonth;

  /// No description provided for @onbEnterDate.
  ///
  /// In en, this message translates to:
  /// **'Enter the date'**
  String get onbEnterDate;

  /// No description provided for @onbEnterBlockHeight.
  ///
  /// In en, this message translates to:
  /// **'Enter the block height'**
  String get onbEnterBlockHeight;

  /// No description provided for @onbBlockHeight.
  ///
  /// In en, this message translates to:
  /// **'Block height'**
  String get onbBlockHeight;

  /// No description provided for @onbAtLeastHeight.
  ///
  /// In en, this message translates to:
  /// **'At least {height}.'**
  String onbAtLeastHeight(String height);

  /// No description provided for @onbBetweenHeights.
  ///
  /// In en, this message translates to:
  /// **'Between {min} and {max}.'**
  String onbBetweenHeights(String min, String max);

  /// No description provided for @onbPickMonth.
  ///
  /// In en, this message translates to:
  /// **'Pick a month'**
  String get onbPickMonth;

  /// No description provided for @onbPickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get onbPickDate;

  /// No description provided for @onbEstimateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t estimate a height for that date. Enter a block height instead.'**
  String get onbEstimateFailed;

  /// No description provided for @scanZcashQrCaption.
  ///
  /// In en, this message translates to:
  /// **'Scan a Zcash QR code to continue'**
  String get scanZcashQrCaption;

  /// No description provided for @scanAddressQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan the address QR code'**
  String get scanAddressQrTitle;

  /// No description provided for @scanNeedsCamera.
  ///
  /// In en, this message translates to:
  /// **'QR scanning needs a camera on this device.'**
  String get scanNeedsCamera;

  /// No description provided for @scanAddressNeedsCamera.
  ///
  /// In en, this message translates to:
  /// **'Address QR scanning needs a camera on this device.'**
  String get scanAddressNeedsCamera;

  /// No description provided for @scanAddressRequiresCamera.
  ///
  /// In en, this message translates to:
  /// **'Address QR scanning requires a camera on this device.'**
  String get scanAddressRequiresCamera;

  /// No description provided for @scanCloseScanner.
  ///
  /// In en, this message translates to:
  /// **'Close scanner'**
  String get scanCloseScanner;

  /// No description provided for @scanLoadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get scanLoadingEllipsis;

  /// No description provided for @scanLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get scanLoading;

  /// No description provided for @scanGrantCameraAccess.
  ///
  /// In en, this message translates to:
  /// **'Grant access to your camera'**
  String get scanGrantCameraAccess;

  /// No description provided for @scanQrNoAddress.
  ///
  /// In en, this message translates to:
  /// **'QR code did not include an address.'**
  String get scanQrNoAddress;

  /// No description provided for @scanCameraDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve denied camera access'**
  String get scanCameraDeniedTitle;

  /// No description provided for @keystoneLoadingQr.
  ///
  /// In en, this message translates to:
  /// **'Loading QR code ...'**
  String get keystoneLoadingQr;

  /// No description provided for @keystoneSignQrDecodeError.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone signature.'**
  String get keystoneSignQrDecodeError;

  /// No description provided for @keystoneSignPrepareError.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared.'**
  String get keystoneSignPrepareError;

  /// No description provided for @keystoneScanSignedKeystoneQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the signed Keystone QR'**
  String get keystoneScanSignedKeystoneQr;

  /// No description provided for @keystoneSignNeedsCamera.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing needs a camera on this device.'**
  String get keystoneSignNeedsCamera;

  /// No description provided for @keystoneCloseSigning.
  ///
  /// In en, this message translates to:
  /// **'Close Keystone signing'**
  String get keystoneCloseSigning;

  /// No description provided for @keystoneSignStepOne.
  ///
  /// In en, this message translates to:
  /// **'Step 1/2'**
  String get keystoneSignStepOne;

  /// No description provided for @keystoneSignStepTwo.
  ///
  /// In en, this message translates to:
  /// **'Step 2/2'**
  String get keystoneSignStepTwo;

  /// No description provided for @keystoneSignScanWithKeystone.
  ///
  /// In en, this message translates to:
  /// **'Scan with Keystone'**
  String get keystoneSignScanWithKeystone;

  /// No description provided for @keystoneSignTryAgainWithKeystone.
  ///
  /// In en, this message translates to:
  /// **'Try again with Keystone'**
  String get keystoneSignTryAgainWithKeystone;

  /// No description provided for @keystoneShowTransactionQr.
  ///
  /// In en, this message translates to:
  /// **'Show transaction QR'**
  String get keystoneShowTransactionQr;

  /// No description provided for @keystoneScanCaptionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to confirm'**
  String get keystoneScanCaptionConfirm;

  /// No description provided for @keystoneScanCaptionFinishSending.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to finish sending'**
  String get keystoneScanCaptionFinishSending;

  /// No description provided for @keystoneScanCaptionFinishZecDeposit.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to finish the ZEC deposit'**
  String get keystoneScanCaptionFinishZecDeposit;

  /// No description provided for @keystonePromptTapBeforeIcon.
  ///
  /// In en, this message translates to:
  /// **'Tap'**
  String get keystonePromptTapBeforeIcon;

  /// No description provided for @keystonePromptTapAfterIcon.
  ///
  /// In en, this message translates to:
  /// **'on your Keystone,'**
  String get keystonePromptTapAfterIcon;

  /// No description provided for @keystonePromptThenScanQr.
  ///
  /// In en, this message translates to:
  /// **'then scan this QR code'**
  String get keystonePromptThenScanQr;

  /// No description provided for @onbWelcomeToVizor.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Vizor'**
  String get onbWelcomeToVizor;

  /// No description provided for @onbSelectMethod.
  ///
  /// In en, this message translates to:
  /// **'Select the method you want.'**
  String get onbSelectMethod;

  /// No description provided for @onbCreateWallet.
  ///
  /// In en, this message translates to:
  /// **'Create Wallet'**
  String get onbCreateWallet;

  /// No description provided for @onbImportWallet.
  ///
  /// In en, this message translates to:
  /// **'Import Wallet'**
  String get onbImportWallet;

  /// No description provided for @onbLinkVizorDesktop.
  ///
  /// In en, this message translates to:
  /// **'Link Vizor Desktop'**
  String get onbLinkVizorDesktop;

  /// No description provided for @onbImportContacts.
  ///
  /// In en, this message translates to:
  /// **'Import contacts'**
  String get onbImportContacts;

  /// No description provided for @onbAgreePrefix.
  ///
  /// In en, this message translates to:
  /// **'By using Vizor you agree to our '**
  String get onbAgreePrefix;

  /// No description provided for @onbTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get onbTerms;

  /// No description provided for @onbPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get onbPrivacy;

  /// No description provided for @onbEndpointSettings.
  ///
  /// In en, this message translates to:
  /// **'Endpoint settings'**
  String get onbEndpointSettings;

  /// No description provided for @onbPrivateMoney.
  ///
  /// In en, this message translates to:
  /// **'Private money.\nBy default'**
  String get onbPrivateMoney;

  /// No description provided for @onbGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started\nwith Vizor'**
  String get onbGetStarted;

  /// No description provided for @onbCreateAWallet.
  ///
  /// In en, this message translates to:
  /// **'Create a wallet'**
  String get onbCreateAWallet;

  /// No description provided for @onbImportAWallet.
  ///
  /// In en, this message translates to:
  /// **'Import a wallet'**
  String get onbImportAWallet;

  /// No description provided for @onbIncorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Try again.'**
  String get onbIncorrectPassword;

  /// No description provided for @onbWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get onbWelcomeBack;

  /// No description provided for @onbEnterPasswordToOpen.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to open Vizor.'**
  String get onbEnterPasswordToOpen;

  /// No description provided for @onbEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get onbEnterPassword;

  /// No description provided for @onbUnlockVizor.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor'**
  String get onbUnlockVizor;

  /// No description provided for @onbForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get onbForgotPassword;

  /// No description provided for @onbResetAfterSeconds.
  ///
  /// In en, this message translates to:
  /// **'Reset after {seconds}s...'**
  String onbResetAfterSeconds(int seconds);

  /// No description provided for @onbCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get onbCannotBeUndone;

  /// No description provided for @onbLostPassword.
  ///
  /// In en, this message translates to:
  /// **'Lost password?'**
  String get onbLostPassword;

  /// No description provided for @onbLostPasswordBodyPrefix.
  ///
  /// In en, this message translates to:
  /// **'If you\'ve lost your password, the only way to recover\nyour account is to '**
  String get onbLostPasswordBodyPrefix;

  /// No description provided for @onbLostPasswordReset.
  ///
  /// In en, this message translates to:
  /// **'completely reset Vizor app'**
  String get onbLostPasswordReset;

  /// No description provided for @onbLostPasswordBodyMiddle.
  ///
  /// In en, this message translates to:
  /// **', which\nmeans deleting all accounts and requiring you to\n'**
  String get onbLostPasswordBodyMiddle;

  /// No description provided for @onbLostPasswordReimport.
  ///
  /// In en, this message translates to:
  /// **'import accounts again'**
  String get onbLostPasswordReimport;

  /// No description provided for @walletResetFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset Vizor. Please try again.'**
  String get walletResetFailed;

  /// No description provided for @storageDbUpdateStillFailed.
  ///
  /// In en, this message translates to:
  /// **'The wallet database update still failed.'**
  String get storageDbUpdateStillFailed;

  /// No description provided for @storageStillUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Secure storage is still unavailable.'**
  String get storageStillUnavailable;

  /// No description provided for @storageRetrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying'**
  String get storageRetrying;

  /// No description provided for @storageQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get storageQuit;

  /// No description provided for @storageDbUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to update wallet database'**
  String get storageDbUpdateTitle;

  /// No description provided for @storageOpenFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to open Vizor'**
  String get storageOpenFailedTitle;

  /// No description provided for @storageUnlockKeyring.
  ///
  /// In en, this message translates to:
  /// **'Unlock your keyring'**
  String get storageUnlockKeyring;

  /// No description provided for @storageLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Secure storage is locked'**
  String get storageLockedTitle;

  /// No description provided for @storageDbUpdateBody.
  ///
  /// In en, this message translates to:
  /// **'Vizor needs to update the local wallet database before opening this version. Try again, or quit and restart Vizor.'**
  String get storageDbUpdateBody;

  /// No description provided for @storageStartupBody.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not load the local startup state. Try again, or quit and restart Vizor.'**
  String get storageStartupBody;

  /// No description provided for @storageKeyringBody.
  ///
  /// In en, this message translates to:
  /// **'Vizor needs access to the system keyring before it can open your wallet. Unlock the keyring, then try again.'**
  String get storageKeyringBody;

  /// No description provided for @storageSecureBody.
  ///
  /// In en, this message translates to:
  /// **'Vizor needs access to secure storage before it can open your wallet. Unlock secure storage, then try again.'**
  String get storageSecureBody;

  /// No description provided for @onbPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get onbPasswordsDoNotMatch;

  /// No description provided for @onbPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Min. 8 characters and symbols'**
  String get onbPasswordHint;

  /// No description provided for @onbConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get onbConfirmPassword;

  /// No description provided for @onbSetPassword.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get onbSetPassword;

  /// No description provided for @onbSetPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set password for signing in to Vizor wallet.'**
  String get onbSetPasswordSubtitle;

  /// No description provided for @onbStopSyncing.
  ///
  /// In en, this message translates to:
  /// **'Stop syncing...'**
  String get onbStopSyncing;

  /// No description provided for @onbSettingPassword.
  ///
  /// In en, this message translates to:
  /// **'Setting password...'**
  String get onbSettingPassword;

  /// No description provided for @onbSetPasswordFinish.
  ///
  /// In en, this message translates to:
  /// **'Set password & finish'**
  String get onbSetPasswordFinish;

  /// No description provided for @onbSecretPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Secret Passphrase'**
  String get onbSecretPassphrase;

  /// No description provided for @onbMasterKeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'The master key to your wallet.'**
  String get onbMasterKeySubtitle;

  /// No description provided for @onbCreatingWallet.
  ///
  /// In en, this message translates to:
  /// **'Creating wallet...'**
  String get onbCreatingWallet;

  /// No description provided for @onbRevealPhrase.
  ///
  /// In en, this message translates to:
  /// **'Reveal the phrase'**
  String get onbRevealPhrase;

  /// No description provided for @onbAboutToSeePrefix.
  ///
  /// In en, this message translates to:
  /// **'You are about to see your '**
  String get onbAboutToSeePrefix;

  /// No description provided for @onbAboutToSeeSuffix.
  ///
  /// In en, this message translates to:
  /// **'Secret Passphrase.'**
  String get onbAboutToSeeSuffix;

  /// No description provided for @onbPhraseWarning.
  ///
  /// In en, this message translates to:
  /// **'This phrase is the master key to your funds. Keep it safe, keep it secret. If you lose it, no one can help you recover your wallet. Not even us.'**
  String get onbPhraseWarning;

  /// No description provided for @onbCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get onbCopied;

  /// No description provided for @onbWelcomeStep.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get onbWelcomeStep;

  /// No description provided for @onbShieldedWorld.
  ///
  /// In en, this message translates to:
  /// **'The Shielded World'**
  String get onbShieldedWorld;

  /// No description provided for @onbZecIntro.
  ///
  /// In en, this message translates to:
  /// **'Zcash (ZEC) built around financial privacy & self-custody.'**
  String get onbZecIntro;

  /// No description provided for @onbZecPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount — verified by cryptography, not trust.'**
  String get onbZecPrivacyBody;

  /// No description provided for @onbTellMeHow.
  ///
  /// In en, this message translates to:
  /// **'Tell me how Zcash works'**
  String get onbTellMeHow;

  /// No description provided for @onbIKnowZcash.
  ///
  /// In en, this message translates to:
  /// **'I know how to use Zcash'**
  String get onbIKnowZcash;

  /// No description provided for @onbStepIntro.
  ///
  /// In en, this message translates to:
  /// **'Intro to Zcash'**
  String get onbStepIntro;

  /// No description provided for @onbStepAddressTypes.
  ///
  /// In en, this message translates to:
  /// **'Address types'**
  String get onbStepAddressTypes;

  /// No description provided for @onbStepThingsToKnow.
  ///
  /// In en, this message translates to:
  /// **'Things to know'**
  String get onbStepThingsToKnow;

  /// No description provided for @onbZcashAddressTypes.
  ///
  /// In en, this message translates to:
  /// **'Zcash Address Types'**
  String get onbZcashAddressTypes;

  /// No description provided for @onbTwoAddressTypes.
  ///
  /// In en, this message translates to:
  /// **'Zcash has two address types.\nOne for privacy, one for transparency.'**
  String get onbTwoAddressTypes;

  /// No description provided for @onbAddressStartsWith.
  ///
  /// In en, this message translates to:
  /// **'Address starts with '**
  String get onbAddressStartsWith;

  /// No description provided for @onbShieldedAddressSuffix.
  ///
  /// In en, this message translates to:
  /// **' for legacy). Only you can see your account balance and transaction history.'**
  String get onbShieldedAddressSuffix;

  /// No description provided for @onbShieldedAddressOr.
  ///
  /// In en, this message translates to:
  /// **' (or '**
  String get onbShieldedAddressOr;

  /// No description provided for @onbTransparentAddressBody.
  ///
  /// In en, this message translates to:
  /// **'Address starts with t, similar to Bitcoin, your address\' balance and transaction history are publicly visible.'**
  String get onbTransparentAddressBody;

  /// No description provided for @onbThingsToKnow.
  ///
  /// In en, this message translates to:
  /// **'Things to know'**
  String get onbThingsToKnow;

  /// No description provided for @onbTimeToSync.
  ///
  /// In en, this message translates to:
  /// **'Time to sync'**
  String get onbTimeToSync;

  /// No description provided for @onbTimeToSyncBody.
  ///
  /// In en, this message translates to:
  /// **'Your wallet syncs directly with the Zcash network instead of relying on a server. This protects your privacy, but takes a moment. Your funds are safe while the app catches up.'**
  String get onbTimeToSyncBody;

  /// No description provided for @onbKeepPrivacy.
  ///
  /// In en, this message translates to:
  /// **'How to keep privacy'**
  String get onbKeepPrivacy;

  /// No description provided for @onbKeepPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Some exchanges can\'t send to shielded addresses. If you\'re withdrawing from an exchange, use your transparent address. You can shield your ZEC after it arrives.'**
  String get onbKeepPrivacyBody;

  /// No description provided for @keystoneSendScanInstructions.
  ///
  /// In en, this message translates to:
  /// **'Use your Keystone wallet to scan this transaction QR code. Follow the steps on your device.'**
  String get keystoneSendScanInstructions;

  /// No description provided for @activityNoActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get activityNoActivityYet;

  /// No description provided for @activityShieldedSender.
  ///
  /// In en, this message translates to:
  /// **'Shielded sender'**
  String get activityShieldedSender;

  /// No description provided for @activityUnknownSender.
  ///
  /// In en, this message translates to:
  /// **'Unknown sender'**
  String get activityUnknownSender;

  /// No description provided for @addressUnified.
  ///
  /// In en, this message translates to:
  /// **'Unified address'**
  String get addressUnified;

  /// No description provided for @addressZcash.
  ///
  /// In en, this message translates to:
  /// **'Zcash address'**
  String get addressZcash;

  /// No description provided for @receiveGenerateNewShielded.
  ///
  /// In en, this message translates to:
  /// **'Generate new shielded address'**
  String get receiveGenerateNewShielded;

  /// No description provided for @receiveAboutAddressType.
  ///
  /// In en, this message translates to:
  /// **'About this address type'**
  String get receiveAboutAddressType;

  /// No description provided for @receiveShieldedAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'Shielded address'**
  String get receiveShieldedAddressTitle;

  /// No description provided for @receiveTransparentAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'Transparent address'**
  String get receiveTransparentAddressTitle;

  /// No description provided for @receiveShieldedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Strong privacy by default.'**
  String get receiveShieldedSubtitle;

  /// No description provided for @receiveTransparentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Publicly visible'**
  String get receiveTransparentSubtitle;

  /// No description provided for @receiveShieldedInfoPrivacyTouch.
  ///
  /// In en, this message translates to:
  /// **'Tx details — sender, receiver, and amount — are encrypted on-chain & hidden.'**
  String get receiveShieldedInfoPrivacyTouch;

  /// No description provided for @receiveShieldedInfoPrivacyPointer.
  ///
  /// In en, this message translates to:
  /// **'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.'**
  String get receiveShieldedInfoPrivacyPointer;

  /// No description provided for @receiveShieldedInfoRenewTap.
  ///
  /// In en, this message translates to:
  /// **'A new Zcash shielded address is generated only when you tap the renew button.'**
  String get receiveShieldedInfoRenewTap;

  /// No description provided for @receiveShieldedInfoRenewClick.
  ///
  /// In en, this message translates to:
  /// **'A new Zcash shielded address is generated only when you click the renew button.'**
  String get receiveShieldedInfoRenewClick;

  /// No description provided for @receiveShieldedInfoDiversified.
  ///
  /// In en, this message translates to:
  /// **'Each new address is a diversified address derived from the same key. They all receive to the same wallet.'**
  String get receiveShieldedInfoDiversified;

  /// No description provided for @receiveTransparentInfoPublicTouch.
  ///
  /// In en, this message translates to:
  /// **'All tx details — sender, receiver, and amount — are publicly visible on-chain.'**
  String get receiveTransparentInfoPublicTouch;

  /// No description provided for @receiveTransparentInfoPublicPointer.
  ///
  /// In en, this message translates to:
  /// **'All tx details - sender, receiver, and amount - are publicly visible on-chain.'**
  String get receiveTransparentInfoPublicPointer;

  /// No description provided for @receiveTransparentInfoExchanges.
  ///
  /// In en, this message translates to:
  /// **'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.'**
  String get receiveTransparentInfoExchanges;

  /// No description provided for @receiveTransparentInfoRotation.
  ///
  /// In en, this message translates to:
  /// **'After this address receives ZEC and Vizor syncs, your next transparent address will automatically change. Previous addresses still belong to this wallet.'**
  String get receiveTransparentInfoRotation;

  /// No description provided for @receiveTransparentInfoShieldGuide.
  ///
  /// In en, this message translates to:
  /// **'After receiving {ticker} to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.'**
  String receiveTransparentInfoShieldGuide(String ticker);

  /// No description provided for @inputClearText.
  ///
  /// In en, this message translates to:
  /// **'Clear text'**
  String get inputClearText;

  /// No description provided for @backToLabel.
  ///
  /// In en, this message translates to:
  /// **'Back to {label}'**
  String backToLabel(String label);

  /// No description provided for @txFeeHelpTooltip.
  ///
  /// In en, this message translates to:
  /// **'Fee paid to the Zcash network to process this transaction.'**
  String get txFeeHelpTooltip;

  /// No description provided for @txFeeSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Tx fee'**
  String get txFeeSheetTitle;

  /// No description provided for @txFeeSheetBody.
  ///
  /// In en, this message translates to:
  /// **'The network fee is set by the Zcash protocol (ZIP 317) based on the transaction size. Vizor adds no extra fee.'**
  String get txFeeSheetBody;

  /// No description provided for @sheetNotAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get sheetNotAvailableTitle;

  /// No description provided for @sheetNotAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'This feature is still in progress.'**
  String get sheetNotAvailableBody;

  /// No description provided for @onbStepWalletBirthdayHeight.
  ///
  /// In en, this message translates to:
  /// **'Wallet Birthday Height'**
  String get onbStepWalletBirthdayHeight;

  /// No description provided for @onbStepHowToConnect.
  ///
  /// In en, this message translates to:
  /// **'How to Connect'**
  String get onbStepHowToConnect;

  /// No description provided for @onbStepScanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get onbStepScanQrCode;

  /// No description provided for @onbStepSelectAccount.
  ///
  /// In en, this message translates to:
  /// **'Select Account'**
  String get onbStepSelectAccount;

  /// No description provided for @onbBirthdayMetadataError.
  ///
  /// In en, this message translates to:
  /// **'Could not load wallet birthday metadata.'**
  String get onbBirthdayMetadataError;

  /// No description provided for @onbBirthdayEstimateError.
  ///
  /// In en, this message translates to:
  /// **'Could not estimate the wallet birthday height.'**
  String get onbBirthdayEstimateError;

  /// No description provided for @onbImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get onbImporting;

  /// No description provided for @onbEstimating.
  ///
  /// In en, this message translates to:
  /// **'Estimating...'**
  String get onbEstimating;

  /// No description provided for @onbCantRemember.
  ///
  /// In en, this message translates to:
  /// **'I can’t remember'**
  String get onbCantRemember;

  /// No description provided for @onbDateHint.
  ///
  /// In en, this message translates to:
  /// **'mm/dd/yyyy'**
  String get onbDateHint;

  /// No description provided for @onbBlockHeightHint.
  ///
  /// In en, this message translates to:
  /// **'Block height'**
  String get onbBlockHeightHint;

  /// No description provided for @onbUnknownHeightTitle.
  ///
  /// In en, this message translates to:
  /// **'Import from the earliest height?'**
  String get onbUnknownHeightTitle;

  /// No description provided for @onbUnknownHeightBody.
  ///
  /// In en, this message translates to:
  /// **'If you continue without a wallet birthday, Vizor will scan from the earliest supported shielded height. This is safe, but the first sync can take a very long time.'**
  String get onbUnknownHeightBody;

  /// No description provided for @onbUnknownHeightHint.
  ///
  /// In en, this message translates to:
  /// **'Choosing even an approximate date will be much faster.'**
  String get onbUnknownHeightHint;

  /// No description provided for @onbContinueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue Anyway'**
  String get onbContinueAnyway;

  /// No description provided for @onbGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get onbGoBack;

  /// No description provided for @onbErrorDuplicateAccount.
  ///
  /// In en, this message translates to:
  /// **'This account is already in your wallet.'**
  String get onbErrorDuplicateAccount;

  /// No description provided for @onbErrorDuplicateKeystoneAccount.
  ///
  /// In en, this message translates to:
  /// **'This Keystone account is already in your wallet.'**
  String get onbErrorDuplicateKeystoneAccount;

  /// No description provided for @onbErrorCurrentBlockHeight.
  ///
  /// In en, this message translates to:
  /// **'We need the current Zcash block height to create your wallet. Check your network connection and try again.'**
  String get onbErrorCurrentBlockHeight;

  /// No description provided for @onbZecIntroMobile.
  ///
  /// In en, this message translates to:
  /// **'Zcash (ZEC) built around financial\nprivacy & self-custody.'**
  String get onbZecIntroMobile;

  /// No description provided for @onbFewStepsAway.
  ///
  /// In en, this message translates to:
  /// **'You\'re a few steps away from your first private wallet. Let\'s get you set up.'**
  String get onbFewStepsAway;

  /// No description provided for @onbTwoAddressTypesMobile.
  ///
  /// In en, this message translates to:
  /// **'Zcash has two addresses types.\nOne for Privacy, one for Transparency.'**
  String get onbTwoAddressTypesMobile;

  /// No description provided for @onbShieldedAddress.
  ///
  /// In en, this message translates to:
  /// **'Shielded Address'**
  String get onbShieldedAddress;

  /// No description provided for @onbTransparentAddress.
  ///
  /// In en, this message translates to:
  /// **'Transparent Address'**
  String get onbTransparentAddress;

  /// No description provided for @onbShieldedAddressBodyMobile.
  ///
  /// In en, this message translates to:
  /// **'Address starts with u1 (or zs for legacy).\nOnly you can see your account balance and transaction history.'**
  String get onbShieldedAddressBodyMobile;

  /// No description provided for @onbBeforeYouDiveIn.
  ///
  /// In en, this message translates to:
  /// **'Before you dive in.'**
  String get onbBeforeYouDiveIn;

  /// No description provided for @onbInvalidPassphraseWordCount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid secret passphrase with 12, 15, 18, 21, or 24 words.'**
  String get onbInvalidPassphraseWordCount;

  /// No description provided for @onbWelcomeAdventurer.
  ///
  /// In en, this message translates to:
  /// **'Welcome, adventurer'**
  String get onbWelcomeAdventurer;

  /// No description provided for @onbImportByPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Import your wallet by entering your secret passphrase.'**
  String get onbImportByPassphrase;

  /// No description provided for @onbWordHint.
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get onbWordHint;

  /// No description provided for @onbPassphraseWordCountFound.
  ///
  /// In en, this message translates to:
  /// **'A secret passphrase has 12, 15, 18, 21, or 24 words — found {count}.'**
  String onbPassphraseWordCountFound(int count);

  /// No description provided for @onbPassphraseInvalidOrder.
  ///
  /// In en, this message translates to:
  /// **'These words are valid, but they do not form a valid secret passphrase. Check the order or replace any word that looks wrong.'**
  String get onbPassphraseInvalidOrder;

  /// No description provided for @onbPassphraseCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'That passphrase couldn\'t be checked. Try again.'**
  String get onbPassphraseCheckFailed;

  /// No description provided for @onbImportWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Wallet'**
  String get onbImportWalletTitle;

  /// No description provided for @onbImportWalletSubtitleMobile.
  ///
  /// In en, this message translates to:
  /// **'Paste your Secret Passphrase or\nenter it manually word by word.'**
  String get onbImportWalletSubtitleMobile;

  /// No description provided for @onbConfirmAndImport.
  ///
  /// In en, this message translates to:
  /// **'Confirm & import'**
  String get onbConfirmAndImport;

  /// No description provided for @onbClearSecretPhrase.
  ///
  /// In en, this message translates to:
  /// **'Clear secret phrase'**
  String get onbClearSecretPhrase;

  /// No description provided for @onbPasteSecretPhrase.
  ///
  /// In en, this message translates to:
  /// **'Paste secret phrase'**
  String get onbPasteSecretPhrase;

  /// No description provided for @onbEnterManually.
  ///
  /// In en, this message translates to:
  /// **'Enter manually'**
  String get onbEnterManually;

  /// No description provided for @onbEnterSecretPhraseManually.
  ///
  /// In en, this message translates to:
  /// **'Enter secret phrase manually'**
  String get onbEnterSecretPhraseManually;

  /// No description provided for @onbClipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get onbClipboardEmpty;

  /// No description provided for @onbClipboardReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Can\'t read clipboard data'**
  String get onbClipboardReadFailed;

  /// No description provided for @onbUnlockBiometricReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock your wallet'**
  String get onbUnlockBiometricReason;

  /// No description provided for @onbIncorrectPasscode.
  ///
  /// In en, this message translates to:
  /// **'Incorrect Passcode'**
  String get onbIncorrectPasscode;

  /// No description provided for @onbWelcomeBackMobile.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get onbWelcomeBackMobile;

  /// No description provided for @onbOpeningWallet.
  ///
  /// In en, this message translates to:
  /// **'Opening your wallet...'**
  String get onbOpeningWallet;

  /// No description provided for @onbEnterPasscodeToOpen.
  ///
  /// In en, this message translates to:
  /// **'Enter your passcode to open Vizor'**
  String get onbEnterPasscodeToOpen;

  /// No description provided for @onbMasterKeySubtitleMobile.
  ///
  /// In en, this message translates to:
  /// **'The Master Key to your wallet.'**
  String get onbMasterKeySubtitleMobile;

  /// No description provided for @onbRevealPhraseMobile.
  ///
  /// In en, this message translates to:
  /// **'Reveal phrase'**
  String get onbRevealPhraseMobile;

  /// No description provided for @onbAboutToSeeMobile.
  ///
  /// In en, this message translates to:
  /// **'You are about to see your\nSecret Passphrase.'**
  String get onbAboutToSeeMobile;

  /// No description provided for @keystoneConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Keystone'**
  String get keystoneConnectTitle;

  /// No description provided for @keystoneCheckFirmware.
  ///
  /// In en, this message translates to:
  /// **'Check Keystone firmware'**
  String get keystoneCheckFirmware;

  /// No description provided for @keystonePrepareToConnect.
  ///
  /// In en, this message translates to:
  /// **'Prepare to connect'**
  String get keystonePrepareToConnect;

  /// No description provided for @keystoneFirmwareBody.
  ///
  /// In en, this message translates to:
  /// **'Make sure your Keystone is on the latest Cypherpunk firmware. '**
  String get keystoneFirmwareBody;

  /// No description provided for @keystoneLink.
  ///
  /// In en, this message translates to:
  /// **'link'**
  String get keystoneLink;

  /// No description provided for @keystoneNoAccountsFound.
  ///
  /// In en, this message translates to:
  /// **'No Zcash accounts were found on this Keystone QR.'**
  String get keystoneNoAccountsFound;

  /// No description provided for @keystoneConfirmSelection.
  ///
  /// In en, this message translates to:
  /// **'Confirm selection'**
  String get keystoneConfirmSelection;

  /// No description provided for @biometricFaceId.
  ///
  /// In en, this message translates to:
  /// **'Face ID'**
  String get biometricFaceId;

  /// No description provided for @biometricFingerprintInline.
  ///
  /// In en, this message translates to:
  /// **'fingerprint'**
  String get biometricFingerprintInline;

  /// No description provided for @biometricBiometricsInline.
  ///
  /// In en, this message translates to:
  /// **'biometrics'**
  String get biometricBiometricsInline;

  /// No description provided for @biometricFingerprintStandalone.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get biometricFingerprintStandalone;

  /// No description provided for @biometricBiometricsStandalone.
  ///
  /// In en, this message translates to:
  /// **'Biometrics'**
  String get biometricBiometricsStandalone;

  /// No description provided for @biometricYourFingerprint.
  ///
  /// In en, this message translates to:
  /// **'your fingerprint'**
  String get biometricYourFingerprint;

  /// No description provided for @biometricUnlockFeatureFace.
  ///
  /// In en, this message translates to:
  /// **'Face ID unlock'**
  String get biometricUnlockFeatureFace;

  /// No description provided for @biometricUnlockFeatureFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint unlock'**
  String get biometricUnlockFeatureFingerprint;

  /// No description provided for @biometricUnlockFeatureNone.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometricUnlockFeatureNone;

  /// No description provided for @biometricUnlockFeatureInlineFingerprint.
  ///
  /// In en, this message translates to:
  /// **'fingerprint unlock'**
  String get biometricUnlockFeatureInlineFingerprint;

  /// No description provided for @biometricUnlockFeatureInlineNone.
  ///
  /// In en, this message translates to:
  /// **'biometric unlock'**
  String get biometricUnlockFeatureInlineNone;

  /// No description provided for @biometricChangedFace.
  ///
  /// In en, this message translates to:
  /// **'Face ID changed. Enter your passcode.'**
  String get biometricChangedFace;

  /// No description provided for @biometricChangedFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint changed. Enter your passcode.'**
  String get biometricChangedFingerprint;

  /// No description provided for @biometricChangedNone.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock changed. Enter your passcode.'**
  String get biometricChangedNone;

  /// No description provided for @biometricEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable {method}'**
  String biometricEnable(String method);

  /// No description provided for @biometricSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with {method}'**
  String biometricSignIn(String method);

  /// No description provided for @biometricFeatureOff.
  ///
  /// In en, this message translates to:
  /// **'{feature} off'**
  String biometricFeatureOff(String feature);

  /// No description provided for @biometricFeatureOn.
  ///
  /// In en, this message translates to:
  /// **'{feature} on'**
  String biometricFeatureOn(String feature);

  /// No description provided for @biometricSetUpFirst.
  ///
  /// In en, this message translates to:
  /// **'Set up {method} in your device settings first.'**
  String biometricSetUpFirst(String method);

  /// No description provided for @biometricUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update {feature}.'**
  String biometricUpdateFailed(String feature);

  /// No description provided for @biometricTurnOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off {feature}?'**
  String biometricTurnOffTitle(String feature);

  /// No description provided for @biometricTurnOffBody.
  ///
  /// In en, this message translates to:
  /// **'You will use your passcode to unlock Vizor. You can turn {feature} back on in settings anytime.'**
  String biometricTurnOffBody(String feature);

  /// No description provided for @biometricEnableFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t enable {method}. You can try again in settings.'**
  String biometricEnableFailed(String method);

  /// No description provided for @onbBiometricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock your wallet\nwith {method}'**
  String onbBiometricsTitle(String method);

  /// No description provided for @onbBiometricsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This is an easy and fast way to sign in.\nYou can switch back to passcode anytime.'**
  String get onbBiometricsSubtitle;

  /// No description provided for @onbNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get onbNotNow;

  /// No description provided for @passcodeDigitLabel.
  ///
  /// In en, this message translates to:
  /// **'Digit {digit}'**
  String passcodeDigitLabel(int digit);

  /// No description provided for @passcodeHelpLabel.
  ///
  /// In en, this message translates to:
  /// **'Passcode help'**
  String get passcodeHelpLabel;

  /// No description provided for @passcodeDeleteDigit.
  ///
  /// In en, this message translates to:
  /// **'Delete digit'**
  String get passcodeDeleteDigit;

  /// No description provided for @onbCopySecretPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Copy secret passphrase'**
  String get onbCopySecretPassphrase;

  /// No description provided for @onbPrivateMoneyMobile.
  ///
  /// In en, this message translates to:
  /// **'Private Money.\nBy default'**
  String get onbPrivateMoneyMobile;

  /// No description provided for @onbGetStartedShort.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onbGetStartedShort;

  /// No description provided for @onbAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get onbAnd;

  /// No description provided for @onbOr.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get onbOr;

  /// No description provided for @keystoneSubmittingTransaction.
  ///
  /// In en, this message translates to:
  /// **'Submitting the transaction'**
  String get keystoneSubmittingTransaction;

  /// No description provided for @onbMonthHint.
  ///
  /// In en, this message translates to:
  /// **'mm/yyyy'**
  String get onbMonthHint;

  /// No description provided for @onbForgotPasscodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot Passcode?'**
  String get onbForgotPasscodeTitle;

  /// No description provided for @onbForgotPasscodeBody.
  ///
  /// In en, this message translates to:
  /// **'If you can\'t remember your passcode, the only way to recover your account is to completely reset the Vizor app, which means deleting all accounts and requiring you to import accounts again.'**
  String get onbForgotPasscodeBody;

  /// No description provided for @onbContinueToReset.
  ///
  /// In en, this message translates to:
  /// **'Continue to reset Vizor'**
  String get onbContinueToReset;

  /// No description provided for @onbResetVizor.
  ///
  /// In en, this message translates to:
  /// **'Reset Vizor'**
  String get onbResetVizor;

  /// No description provided for @onbAreYouSure.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get onbAreYouSure;

  /// No description provided for @onbCantBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.\n'**
  String get onbCantBeUndone;

  /// No description provided for @onbProceedResponsibility.
  ///
  /// In en, this message translates to:
  /// **'Proceed on your responsibility.'**
  String get onbProceedResponsibility;

  /// No description provided for @onbSettingUpWallet.
  ///
  /// In en, this message translates to:
  /// **'Setting up your wallet...'**
  String get onbSettingUpWallet;

  /// No description provided for @onbReenterPasscode.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your passcode.'**
  String get onbReenterPasscode;

  /// No description provided for @onbSixDigitsLength.
  ///
  /// In en, this message translates to:
  /// **'6 digits length'**
  String get onbSixDigitsLength;

  /// No description provided for @onbConfirmPasscode.
  ///
  /// In en, this message translates to:
  /// **'Confirm Passcode'**
  String get onbConfirmPasscode;

  /// No description provided for @onbCreatePasscode.
  ///
  /// In en, this message translates to:
  /// **'Create Passcode'**
  String get onbCreatePasscode;

  /// No description provided for @onbAdditionalAccountsFound.
  ///
  /// In en, this message translates to:
  /// **'Additional accounts found'**
  String get onbAdditionalAccountsFound;

  /// No description provided for @onbChooseAdditionalAccounts.
  ///
  /// In en, this message translates to:
  /// **'Choose the additional accounts to import.'**
  String get onbChooseAdditionalAccounts;

  /// No description provided for @onbImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get onbImportAction;

  /// No description provided for @onbBalanceLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get onbBalanceLoading;

  /// No description provided for @onbTransparentLabel.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get onbTransparentLabel;

  /// No description provided for @onbContinueAnywayLower.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get onbContinueAnywayLower;

  /// No description provided for @onbGoBackLower.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get onbGoBackLower;

  /// No description provided for @onbWordNotInList.
  ///
  /// In en, this message translates to:
  /// **'\'{word}\' isn\'t in the passphrase word list.'**
  String onbWordNotInList(String word);

  /// No description provided for @onbStoppedAtWord.
  ///
  /// In en, this message translates to:
  /// **'Stopped at \'{word}\' — it isn\'t in the passphrase word list.'**
  String onbStoppedAtWord(String word);

  /// No description provided for @onbNextWord.
  ///
  /// In en, this message translates to:
  /// **'Next word'**
  String get onbNextWord;

  /// No description provided for @onbEnterYourPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Enter your Secret Passphrase'**
  String get onbEnterYourPassphrase;

  /// No description provided for @onbAcceptWordCounts.
  ///
  /// In en, this message translates to:
  /// **'Accept 12, 15, 18, 21 or 24 words'**
  String get onbAcceptWordCounts;

  /// No description provided for @onbUndoLastWord.
  ///
  /// In en, this message translates to:
  /// **'Undo last word'**
  String get onbUndoLastWord;

  /// No description provided for @swapStatusAwaitingDeposit.
  ///
  /// In en, this message translates to:
  /// **'Awaiting deposit'**
  String get swapStatusAwaitingDeposit;

  /// No description provided for @swapStatusAwaitingExternalDeposit.
  ///
  /// In en, this message translates to:
  /// **'Awaiting external deposit'**
  String get swapStatusAwaitingExternalDeposit;

  /// No description provided for @swapStatusDepositObserved.
  ///
  /// In en, this message translates to:
  /// **'Deposit observed'**
  String get swapStatusDepositObserved;

  /// No description provided for @swapStatusProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get swapStatusProcessing;

  /// No description provided for @swapStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking status'**
  String get swapStatusChecking;

  /// No description provided for @swapStatusIncompleteDeposit.
  ///
  /// In en, this message translates to:
  /// **'Incomplete deposit'**
  String get swapStatusIncompleteDeposit;

  /// No description provided for @swapStatusComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get swapStatusComplete;

  /// No description provided for @swapStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get swapStatusRefunded;

  /// No description provided for @swapStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get swapStatusExpired;

  /// No description provided for @swapStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get swapStatusFailed;

  /// No description provided for @swapTitleCompleted.
  ///
  /// In en, this message translates to:
  /// **'Swap completed'**
  String get swapTitleCompleted;

  /// No description provided for @swapTitleFailed.
  ///
  /// In en, this message translates to:
  /// **'Swap failed'**
  String get swapTitleFailed;

  /// No description provided for @swapTitleInProgress.
  ///
  /// In en, this message translates to:
  /// **'Swap in progress...'**
  String get swapTitleInProgress;

  /// No description provided for @swapToAddressOnChain.
  ///
  /// In en, this message translates to:
  /// **'To: {address} on {chain}'**
  String swapToAddressOnChain(String address, String chain);

  /// No description provided for @swapRefundToAddress.
  ///
  /// In en, this message translates to:
  /// **'Refund to: {address}'**
  String swapRefundToAddress(String address);

  /// No description provided for @swapVerbSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get swapVerbSending;

  /// No description provided for @swapVerbDepositing.
  ///
  /// In en, this message translates to:
  /// **'Depositing'**
  String get swapVerbDepositing;

  /// No description provided for @swapSymbolSent.
  ///
  /// In en, this message translates to:
  /// **'{symbol} sent'**
  String swapSymbolSent(String symbol);

  /// No description provided for @swapSymbolDeposited.
  ///
  /// In en, this message translates to:
  /// **'{symbol} Deposited'**
  String swapSymbolDeposited(String symbol);

  /// No description provided for @swapDeliverSymbol.
  ///
  /// In en, this message translates to:
  /// **'Deliver {symbol}'**
  String swapDeliverSymbol(String symbol);

  /// No description provided for @swapSendSymbol.
  ///
  /// In en, this message translates to:
  /// **'Send {symbol}'**
  String swapSendSymbol(String symbol);

  /// No description provided for @swapDepositSymbol.
  ///
  /// In en, this message translates to:
  /// **'Deposit {symbol}'**
  String swapDepositSymbol(String symbol);

  /// No description provided for @swapLastCheckJustNow.
  ///
  /// In en, this message translates to:
  /// **'Last check: just now'**
  String get swapLastCheckJustNow;

  /// No description provided for @swapLastCheckMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Last check: {minutes}m ago'**
  String swapLastCheckMinutesAgo(int minutes);

  /// No description provided for @swapStepSourceDesc.
  ///
  /// In en, this message translates to:
  /// **'Confirm waiting for the source chain and provider to recognise the deposit'**
  String get swapStepSourceDesc;

  /// No description provided for @swapStepDepositConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Deposit confirmation'**
  String get swapStepDepositConfirmation;

  /// No description provided for @swapStepDepositConfirmationActive.
  ///
  /// In en, this message translates to:
  /// **'Deposit confirmation...'**
  String get swapStepDepositConfirmationActive;

  /// No description provided for @swapStepConfirmingDesc.
  ///
  /// In en, this message translates to:
  /// **'Confirming the deposit before the swap route starts.'**
  String get swapStepConfirmingDesc;

  /// No description provided for @swapStepSwapTitle.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get swapStepSwapTitle;

  /// No description provided for @swapStepSwapActive.
  ///
  /// In en, this message translates to:
  /// **'Swap...'**
  String get swapStepSwapActive;

  /// No description provided for @swapStepSwapDesc.
  ///
  /// In en, this message translates to:
  /// **'The provider is executing the swap route.'**
  String get swapStepSwapDesc;

  /// No description provided for @swapStepDeliveryDesc.
  ///
  /// In en, this message translates to:
  /// **'Delivering the output asset to the recipient address.'**
  String get swapStepDeliveryDesc;

  /// No description provided for @swapRealizedSlippageLabel.
  ///
  /// In en, this message translates to:
  /// **'Realized slippage'**
  String get swapRealizedSlippageLabel;

  /// No description provided for @swapNotReported.
  ///
  /// In en, this message translates to:
  /// **'Not reported'**
  String get swapNotReported;

  /// No description provided for @swapTimestampLabel.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get swapTimestampLabel;

  /// No description provided for @swapDepositTxLabel.
  ///
  /// In en, this message translates to:
  /// **'{symbol} deposit tx'**
  String swapDepositTxLabel(String symbol);

  /// No description provided for @swapRefundedToLabel.
  ///
  /// In en, this message translates to:
  /// **'{symbol} refunded to'**
  String swapRefundedToLabel(String symbol);

  /// No description provided for @swapTotalFeesLabel.
  ///
  /// In en, this message translates to:
  /// **'Total fees'**
  String get swapTotalFeesLabel;

  /// No description provided for @swapIncluded.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get swapIncluded;

  /// No description provided for @swapRecipientLabel.
  ///
  /// In en, this message translates to:
  /// **'{symbol} recipient'**
  String swapRecipientLabel(String symbol);

  /// No description provided for @swapRefundAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'{symbol} refund address'**
  String swapRefundAddressLabel(String symbol);

  /// No description provided for @swapDepositToLabel.
  ///
  /// In en, this message translates to:
  /// **'Deposit {symbol} to'**
  String swapDepositToLabel(String symbol);

  /// No description provided for @swapMemoLabel.
  ///
  /// In en, this message translates to:
  /// **'Memo'**
  String get swapMemoLabel;

  /// No description provided for @swapSlippageToleranceLabel.
  ///
  /// In en, this message translates to:
  /// **'Slippage tolerance'**
  String get swapSlippageToleranceLabel;

  /// No description provided for @swapConfiguredQuote.
  ///
  /// In en, this message translates to:
  /// **'Configured quote'**
  String get swapConfiguredQuote;

  /// No description provided for @swapGuaranteedMinimumLabel.
  ///
  /// In en, this message translates to:
  /// **'Guaranteed minimum'**
  String get swapGuaranteedMinimumLabel;

  /// No description provided for @swapDeliveryTxLabel.
  ///
  /// In en, this message translates to:
  /// **'{symbol} delivery tx'**
  String swapDeliveryTxLabel(String symbol);

  /// No description provided for @swapFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Swap fee'**
  String get swapFeeLabel;

  /// No description provided for @swapIncludedInRate.
  ///
  /// In en, this message translates to:
  /// **'Included in shown rate'**
  String get swapIncludedInRate;

  /// No description provided for @swapTxIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Tx ID'**
  String get swapTxIdLabel;

  /// No description provided for @swapMissingDepositLabel.
  ///
  /// In en, this message translates to:
  /// **'Missing deposit'**
  String get swapMissingDepositLabel;

  /// No description provided for @swapRequiredDepositLabel.
  ///
  /// In en, this message translates to:
  /// **'Required deposit'**
  String get swapRequiredDepositLabel;

  /// No description provided for @swapDetectedDepositLabel.
  ///
  /// In en, this message translates to:
  /// **'Detected deposit'**
  String get swapDetectedDepositLabel;

  /// No description provided for @swapDepositDeadlineRowLabel.
  ///
  /// In en, this message translates to:
  /// **'Deposit deadline'**
  String get swapDepositDeadlineRowLabel;

  /// No description provided for @swapRefundFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Refund fee'**
  String get swapRefundFeeLabel;

  /// No description provided for @swapHoursShort.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1hr} other{{count}hrs}}'**
  String swapHoursShort(int count);

  /// No description provided for @swapMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1min} other{{count}mins}}'**
  String swapMinutesShort(int count);

  /// No description provided for @swapSendFromSourceChain.
  ///
  /// In en, this message translates to:
  /// **'Send {symbol} from source chain'**
  String swapSendFromSourceChain(String symbol);

  /// No description provided for @swapDepositLabelShort.
  ///
  /// In en, this message translates to:
  /// **'{symbol} deposit'**
  String swapDepositLabelShort(String symbol);

  /// No description provided for @swapSourceDepositLabel.
  ///
  /// In en, this message translates to:
  /// **'{symbol} source deposit'**
  String swapSourceDepositLabel(String symbol);

  /// No description provided for @swapDepositTxHashLabel.
  ///
  /// In en, this message translates to:
  /// **'{symbol} deposit tx hash'**
  String swapDepositTxHashLabel(String symbol);

  /// No description provided for @swapDepositTxHashHint.
  ///
  /// In en, this message translates to:
  /// **'{symbol} source-chain transaction hash'**
  String swapDepositTxHashHint(String symbol);

  /// No description provided for @swapSubmitDeposit.
  ///
  /// In en, this message translates to:
  /// **'Submit {symbol} deposit'**
  String swapSubmitDeposit(String symbol);

  /// No description provided for @swapDoNotReuseAddress.
  ///
  /// In en, this message translates to:
  /// **'Do not reuse this address'**
  String get swapDoNotReuseAddress;

  /// No description provided for @swapMinReceiveTooltip.
  ///
  /// In en, this message translates to:
  /// **'The lowest amount of {symbol} you\'ll get after slippage. You may get more, never less.'**
  String swapMinReceiveTooltip(String symbol);

  /// No description provided for @swapGenericMinReceiveTooltip.
  ///
  /// In en, this message translates to:
  /// **'The lowest amount you\'ll get after slippage. You may get more, never less.'**
  String get swapGenericMinReceiveTooltip;

  /// No description provided for @swapFeeTooltipText.
  ///
  /// In en, this message translates to:
  /// **'Covers our fee and the route providers\' costs to process this swap. Already included in the rate above.'**
  String get swapFeeTooltipText;

  /// No description provided for @swapStatusDetailTooltipText.
  ///
  /// In en, this message translates to:
  /// **'Details are based on the latest swap record and provider status.'**
  String get swapStatusDetailTooltipText;

  /// No description provided for @swapProgressTab.
  ///
  /// In en, this message translates to:
  /// **'Swap progress'**
  String get swapProgressTab;

  /// No description provided for @swapTransactionDetailsTab.
  ///
  /// In en, this message translates to:
  /// **'Transaction details'**
  String get swapTransactionDetailsTab;

  /// No description provided for @swapStatusRowLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get swapStatusRowLabel;

  /// No description provided for @swapRefundsReturnedAs.
  ///
  /// In en, this message translates to:
  /// **'If the swap fails or the rate moves, you\'ll be refunded in {symbol} on {chain}, minus the fee.'**
  String swapRefundsReturnedAs(String symbol, String chain);

  /// No description provided for @swapReviewSwap.
  ///
  /// In en, this message translates to:
  /// **'Review swap'**
  String get swapReviewSwap;

  /// No description provided for @swapQuoteExpiredNotice.
  ///
  /// In en, this message translates to:
  /// **'Quote expired. Review again for an updated rate.'**
  String get swapQuoteExpiredNotice;

  /// No description provided for @swapYourePaying.
  ///
  /// In en, this message translates to:
  /// **'You\'re paying'**
  String get swapYourePaying;

  /// No description provided for @swapYoureReceiving.
  ///
  /// In en, this message translates to:
  /// **'You\'re receiving'**
  String get swapYoureReceiving;

  /// No description provided for @swapYouPaid.
  ///
  /// In en, this message translates to:
  /// **'You paid'**
  String get swapYouPaid;

  /// No description provided for @swapYouReceived.
  ///
  /// In en, this message translates to:
  /// **'You received'**
  String get swapYouReceived;

  /// No description provided for @swapVerbLockingQuote.
  ///
  /// In en, this message translates to:
  /// **'Locking quote'**
  String get swapVerbLockingQuote;

  /// No description provided for @swapReviewAgain.
  ///
  /// In en, this message translates to:
  /// **'Review again'**
  String get swapReviewAgain;

  /// No description provided for @swapReturnToSwap.
  ///
  /// In en, this message translates to:
  /// **'Return to swap'**
  String get swapReturnToSwap;

  /// No description provided for @swapNotEnoughZec.
  ///
  /// In en, this message translates to:
  /// **'Not enough ZEC'**
  String get swapNotEnoughZec;

  /// No description provided for @swapConfirmSwap.
  ///
  /// In en, this message translates to:
  /// **'Confirm swap'**
  String get swapConfirmSwap;

  /// No description provided for @swapToShort.
  ///
  /// In en, this message translates to:
  /// **'To: {address}'**
  String swapToShort(String address);

  /// No description provided for @swapRecipientAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'{symbol} recipient address'**
  String swapRecipientAddressTitle(String symbol);

  /// No description provided for @swapRefundAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'{symbol} refund address'**
  String swapRefundAddressTitle(String symbol);

  /// No description provided for @swapRecipientFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get swapRecipientFieldLabel;

  /// No description provided for @swapRefundToFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Refund to'**
  String get swapRefundToFieldLabel;

  /// No description provided for @swapDeliveredToAddress.
  ///
  /// In en, this message translates to:
  /// **'Your {symbol} will be delivered to this address.'**
  String swapDeliveredToAddress(String symbol);

  /// No description provided for @swapRememberRecipients.
  ///
  /// In en, this message translates to:
  /// **'Remember this address for recipients'**
  String get swapRememberRecipients;

  /// No description provided for @swapRememberRefunds.
  ///
  /// In en, this message translates to:
  /// **'Remember this address for refunds'**
  String get swapRememberRefunds;

  /// No description provided for @swapUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get swapUpdateAction;

  /// No description provided for @swapIveDepositedTokens.
  ///
  /// In en, this message translates to:
  /// **'I’ve deposited tokens'**
  String get swapIveDepositedTokens;

  /// No description provided for @swapIveDeposited.
  ///
  /// In en, this message translates to:
  /// **'I\'ve deposited'**
  String get swapIveDeposited;

  /// No description provided for @swapDepositZec.
  ///
  /// In en, this message translates to:
  /// **'Deposit ZEC'**
  String get swapDepositZec;

  /// No description provided for @swapDepositTokensTitle.
  ///
  /// In en, this message translates to:
  /// **'Deposit tokens'**
  String get swapDepositTokensTitle;

  /// No description provided for @swapChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get swapChecking;

  /// No description provided for @swapTimesUp.
  ///
  /// In en, this message translates to:
  /// **'Time’s up'**
  String get swapTimesUp;

  /// No description provided for @swapDepositExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'This deposit address is no longer valid.\nPlease, start another swap transaction.'**
  String get swapDepositExpiredBody;

  /// No description provided for @swapRestartSwap.
  ///
  /// In en, this message translates to:
  /// **'Restart swap'**
  String get swapRestartSwap;

  /// No description provided for @swapDepositWithin.
  ///
  /// In en, this message translates to:
  /// **'Deposit within'**
  String get swapDepositWithin;

  /// No description provided for @swapAmountToDeposit.
  ///
  /// In en, this message translates to:
  /// **'Amount to deposit'**
  String get swapAmountToDeposit;

  /// No description provided for @swapAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get swapAmountLabel;

  /// No description provided for @swapAmountCopiedMobile.
  ///
  /// In en, this message translates to:
  /// **'Amount copied'**
  String get swapAmountCopiedMobile;

  /// No description provided for @swapAmountCopiedDesktop.
  ///
  /// In en, this message translates to:
  /// **'Amount Copied'**
  String get swapAmountCopiedDesktop;

  /// No description provided for @swapOneTimeAddress.
  ///
  /// In en, this message translates to:
  /// **'One-time address'**
  String get swapOneTimeAddress;

  /// No description provided for @swapMemoCopied.
  ///
  /// In en, this message translates to:
  /// **'Memo copied'**
  String get swapMemoCopied;

  /// No description provided for @swapSigningCancelledBeforeParams.
  ///
  /// In en, this message translates to:
  /// **'Signing was cancelled before proving parameters were downloaded.'**
  String get swapSigningCancelledBeforeParams;

  /// No description provided for @swapTxStatusUncertain.
  ///
  /// In en, this message translates to:
  /// **'The transaction status is uncertain. Refresh activity before trying again.'**
  String get swapTxStatusUncertain;

  /// No description provided for @swapZecDepositAction.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit'**
  String get swapZecDepositAction;

  /// No description provided for @swapBroadcastingAction.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting {action}'**
  String swapBroadcastingAction(String action);

  /// No description provided for @swapSignActionOnKeystone.
  ///
  /// In en, this message translates to:
  /// **'Sign {action} on Keystone'**
  String swapSignActionOnKeystone(String action);

  /// No description provided for @swapSubmittingTransaction.
  ///
  /// In en, this message translates to:
  /// **'Submitting transaction'**
  String get swapSubmittingTransaction;

  /// No description provided for @swapScanToSign.
  ///
  /// In en, this message translates to:
  /// **'Scan to sign'**
  String get swapScanToSign;

  /// No description provided for @swapAfterScannedClickGetSignature.
  ///
  /// In en, this message translates to:
  /// **'After you scanned, click Get signature.'**
  String get swapAfterScannedClickGetSignature;

  /// No description provided for @swapGetSignature.
  ///
  /// In en, this message translates to:
  /// **'Get signature'**
  String get swapGetSignature;

  /// No description provided for @swapBackToActivity.
  ///
  /// In en, this message translates to:
  /// **'Back to activity'**
  String get swapBackToActivity;

  /// No description provided for @swapTxCouldNotBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Transaction could not be broadcast.'**
  String get swapTxCouldNotBroadcast;

  /// No description provided for @swapZecDepositSigningFailed.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit signing could not be completed.'**
  String get swapZecDepositSigningFailed;

  /// No description provided for @swapYouPay.
  ///
  /// In en, this message translates to:
  /// **'You pay'**
  String get swapYouPay;

  /// No description provided for @swapYouReceive.
  ///
  /// In en, this message translates to:
  /// **'You receive'**
  String get swapYouReceive;

  /// No description provided for @swapZcashLabel.
  ///
  /// In en, this message translates to:
  /// **'Zcash'**
  String get swapZcashLabel;

  /// No description provided for @swapAddRefundAddress.
  ///
  /// In en, this message translates to:
  /// **'Add refund address...'**
  String get swapAddRefundAddress;

  /// No description provided for @swapAddRecipientAddress.
  ///
  /// In en, this message translates to:
  /// **'Add recipient address...'**
  String get swapAddRecipientAddress;

  /// No description provided for @swapMaxAvailable.
  ///
  /// In en, this message translates to:
  /// **'Max: {amount}'**
  String swapMaxAvailable(String amount);

  /// No description provided for @swapZecDepositSent.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit sent'**
  String get swapZecDepositSent;

  /// No description provided for @swapCheckingZecDeposit.
  ///
  /// In en, this message translates to:
  /// **'Checking ZEC deposit'**
  String get swapCheckingZecDeposit;

  /// No description provided for @swapToTruncated.
  ///
  /// In en, this message translates to:
  /// **'To: {address}'**
  String swapToTruncated(String address);

  /// No description provided for @swapCouldntLoad.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this swap. Try again or pull to refresh.'**
  String get swapCouldntLoad;

  /// No description provided for @swapReturnToActivity.
  ///
  /// In en, this message translates to:
  /// **'Return to Activity and select a saved swap.'**
  String get swapReturnToActivity;

  /// No description provided for @swapSignZecDeposit.
  ///
  /// In en, this message translates to:
  /// **'Sign ZEC deposit'**
  String get swapSignZecDeposit;

  /// No description provided for @swapKeystoneSigningFailed.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing failed'**
  String get swapKeystoneSigningFailed;

  /// No description provided for @swapScanTxQrInstructions.
  ///
  /// In en, this message translates to:
  /// **'Use your Keystone wallet to scan this transaction QR code. Follow the steps on your device.'**
  String get swapScanTxQrInstructions;

  /// No description provided for @swapBroadcastingZecDeposit.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting ZEC deposit...'**
  String get swapBroadcastingZecDeposit;

  /// No description provided for @swapAlreadyInContacts.
  ///
  /// In en, this message translates to:
  /// **'Already in your contacts'**
  String get swapAlreadyInContacts;

  /// No description provided for @swapAlreadyInAddressBook.
  ///
  /// In en, this message translates to:
  /// **'Already in your address book'**
  String get swapAlreadyInAddressBook;

  /// No description provided for @swapTitle.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get swapTitle;

  /// No description provided for @swapGettingQuote.
  ///
  /// In en, this message translates to:
  /// **'Getting quote'**
  String get swapGettingQuote;

  /// No description provided for @swapAddRecipientAddressAction.
  ///
  /// In en, this message translates to:
  /// **'Add recipient address'**
  String get swapAddRecipientAddressAction;

  /// No description provided for @swapAddRefundAddressAction.
  ///
  /// In en, this message translates to:
  /// **'Add refund address'**
  String get swapAddRefundAddressAction;

  /// No description provided for @swapContinueToReview.
  ///
  /// In en, this message translates to:
  /// **'Continue to review'**
  String get swapContinueToReview;

  /// No description provided for @swapQrNoAddress.
  ///
  /// In en, this message translates to:
  /// **'QR code did not include an address.'**
  String get swapQrNoAddress;

  /// No description provided for @swapSelectAsset.
  ///
  /// In en, this message translates to:
  /// **'Select asset'**
  String get swapSelectAsset;

  /// No description provided for @swapSearchTokenOrChain.
  ///
  /// In en, this message translates to:
  /// **'Search token or chain'**
  String get swapSearchTokenOrChain;

  /// No description provided for @swapNoTokensFound.
  ///
  /// In en, this message translates to:
  /// **'No tokens or chains found'**
  String get swapNoTokensFound;

  /// No description provided for @swapSlippage.
  ///
  /// In en, this message translates to:
  /// **'Slippage'**
  String get swapSlippage;

  /// No description provided for @swapSlippageRange.
  ///
  /// In en, this message translates to:
  /// **'Slippage must be 0.1 - 5%'**
  String get swapSlippageRange;

  /// No description provided for @swapCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get swapCustom;

  /// No description provided for @swapTimeoutInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'This deposit address is no longer valid'**
  String get swapTimeoutInvalidAddress;

  /// No description provided for @swapTimeoutStartAnother.
  ///
  /// In en, this message translates to:
  /// **'Please, start another swap transaction.'**
  String get swapTimeoutStartAnother;

  /// No description provided for @swapToPrefix.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get swapToPrefix;

  /// No description provided for @swapFromPrefix.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get swapFromPrefix;

  /// No description provided for @swapConfirmAndSwap.
  ///
  /// In en, this message translates to:
  /// **'Confirm & swap'**
  String get swapConfirmAndSwap;

  /// No description provided for @swapPoweredBy.
  ///
  /// In en, this message translates to:
  /// **'Powered by'**
  String get swapPoweredBy;

  /// No description provided for @swapErrAmountTooLow.
  ///
  /// In en, this message translates to:
  /// **'Amount is too low for this swap.\nTry a larger amount.'**
  String get swapErrAmountTooLow;

  /// No description provided for @swapErrAmountPrecision.
  ///
  /// In en, this message translates to:
  /// **'Amount has too many decimal places.\nUse fewer decimals and try again.'**
  String get swapErrAmountPrecision;

  /// No description provided for @swapErrInvalidRoute.
  ///
  /// In en, this message translates to:
  /// **'This route or address was rejected.\nEdit the details and request a new quote.'**
  String get swapErrInvalidRoute;

  /// No description provided for @swapErrNoQuote.
  ///
  /// In en, this message translates to:
  /// **'No quote is available for this route or amount.\nAdjust the amount, slippage, or asset and try again.'**
  String get swapErrNoQuote;

  /// No description provided for @swapErrZecDepositFunding.
  ///
  /// In en, this message translates to:
  /// **'Not enough spendable ZEC to cover this swap and its network fee.\nTry a smaller amount or use Max.'**
  String get swapErrZecDepositFunding;

  /// No description provided for @swapErrWalletPreflight.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit could not be prepared.\nCheck your balance and try again.'**
  String get swapErrWalletPreflight;

  /// No description provided for @swapErrDepositNotFound.
  ///
  /// In en, this message translates to:
  /// **'Deposit is not indexed yet.\nCheck again in a few minutes.'**
  String get swapErrDepositNotFound;

  /// No description provided for @swapErrDepositRejected.
  ///
  /// In en, this message translates to:
  /// **'Deposit transaction was rejected.\nCheck the address, memo, and tx hash.'**
  String get swapErrDepositRejected;

  /// No description provided for @swapErrUnsupportedPairNoResend.
  ///
  /// In en, this message translates to:
  /// **'Swap status uses an unsupported asset pair.\nDo not resend funds. Try again later.'**
  String get swapErrUnsupportedPairNoResend;

  /// No description provided for @swapErrAssetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This asset is not available for swap right now.\nChoose another asset or try again later.'**
  String get swapErrAssetUnavailable;

  /// No description provided for @swapErrServiceUnavailableNoResend.
  ///
  /// In en, this message translates to:
  /// **'Swap service is temporarily unavailable.\nDo not resend funds. Try again later.'**
  String get swapErrServiceUnavailableNoResend;

  /// No description provided for @swapErrServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Swap service is temporarily unavailable.\nTry again later.'**
  String get swapErrServiceUnavailable;

  /// No description provided for @swapErrQuoteTimeout.
  ///
  /// In en, this message translates to:
  /// **'Quote request timed out.\nCheck your connection and try again.'**
  String get swapErrQuoteTimeout;

  /// No description provided for @swapErrTimeoutNoResend.
  ///
  /// In en, this message translates to:
  /// **'Request timed out.\nDo not resend funds. Try again later.'**
  String get swapErrTimeoutNoResend;

  /// No description provided for @swapErrTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timed out.\nCheck your connection and try again.'**
  String get swapErrTimeout;

  /// No description provided for @swapErrProcessingNoResend.
  ///
  /// In en, this message translates to:
  /// **'Swap service is still processing.\nDo not resend funds. Try again later.'**
  String get swapErrProcessingNoResend;

  /// No description provided for @swapErrProcessing.
  ///
  /// In en, this message translates to:
  /// **'Swap service is still processing.\nWait a moment and try again.'**
  String get swapErrProcessing;

  /// No description provided for @swapErrQuoteUnverified.
  ///
  /// In en, this message translates to:
  /// **'Quote response could not be verified.\nTry again later.'**
  String get swapErrQuoteUnverified;

  /// No description provided for @swapErrResponseUnverified.
  ///
  /// In en, this message translates to:
  /// **'Swap response could not be verified.\nTry again later.'**
  String get swapErrResponseUnverified;

  /// No description provided for @swapErrTokenList.
  ///
  /// In en, this message translates to:
  /// **'Swap tokens could not be loaded.\nTry again later.'**
  String get swapErrTokenList;

  /// No description provided for @swapErrQuoteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Quote is unavailable right now.\nTry again later.'**
  String get swapErrQuoteUnavailable;

  /// No description provided for @swapErrStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Swap could not be started.\nTry again later.'**
  String get swapErrStartFailed;

  /// No description provided for @swapErrRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh swap status.\nTry again later.'**
  String get swapErrRefreshFailed;

  /// No description provided for @swapErrSubmitDepositFailed.
  ///
  /// In en, this message translates to:
  /// **'Deposit status could not be submitted.\nTry again later.'**
  String get swapErrSubmitDepositFailed;

  /// No description provided for @swapErrSendZecDepositFailed.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit could not be sent.\nTry again later.'**
  String get swapErrSendZecDepositFailed;

  /// No description provided for @swapErrNoActiveAccount.
  ///
  /// In en, this message translates to:
  /// **'No active account'**
  String get swapErrNoActiveAccount;

  /// No description provided for @swapErrInsufficientShieldedForFee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance to cover fee'**
  String get swapErrInsufficientShieldedForFee;

  /// No description provided for @swapErrMaxUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Max amount unavailable'**
  String get swapErrMaxUnavailable;

  /// No description provided for @swapBadgeCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get swapBadgeCompleted;

  /// No description provided for @swapBadgeNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get swapBadgeNeedsAttention;

  /// No description provided for @swapBadgeInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get swapBadgeInProgress;

  /// No description provided for @swapZcashAddress.
  ///
  /// In en, this message translates to:
  /// **'Zcash address'**
  String get swapZcashAddress;

  /// No description provided for @swapChainAddress.
  ///
  /// In en, this message translates to:
  /// **'{chain} address'**
  String swapChainAddress(String chain);

  /// No description provided for @swapFullAddress.
  ///
  /// In en, this message translates to:
  /// **'Full address'**
  String get swapFullAddress;

  /// No description provided for @votingNotEligibleNoFunds.
  ///
  /// In en, this message translates to:
  /// **'This account is not eligible for this voting round. It had no eligible shielded funds at {snapshot}. Switch to an eligible account to vote.'**
  String votingNotEligibleNoFunds(String snapshot);

  /// No description provided for @votingRequiresMinimumBundle.
  ///
  /// In en, this message translates to:
  /// **'Voting requires at least one eligible shielded note bundle with 0.125 ZEC at {snapshot}. Switch to an eligible account to vote.'**
  String votingRequiresMinimumBundle(String snapshot);

  /// No description provided for @votingSnapshotBlockFallback.
  ///
  /// In en, this message translates to:
  /// **'the voting round snapshot block'**
  String get votingSnapshotBlockFallback;

  /// No description provided for @votingSnapshotBlock.
  ///
  /// In en, this message translates to:
  /// **'snapshot block {height}'**
  String votingSnapshotBlock(String height);

  /// No description provided for @votingSessionActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Voting session action failed.'**
  String get votingSessionActionFailed;

  /// No description provided for @votingTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get votingTryAgain;

  /// No description provided for @votingNoRounds.
  ///
  /// In en, this message translates to:
  /// **'No voting rounds available'**
  String get votingNoRounds;

  /// No description provided for @votingNoRoundsBody.
  ///
  /// In en, this message translates to:
  /// **'There are no token holder voting rounds to display yet.'**
  String get votingNoRoundsBody;

  /// No description provided for @votingVoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Vote'**
  String get votingVoteTitle;

  /// No description provided for @votingConfigTooltip.
  ///
  /// In en, this message translates to:
  /// **'Voting config'**
  String get votingConfigTooltip;

  /// No description provided for @votingConfigSemantics.
  ///
  /// In en, this message translates to:
  /// **'Voting config settings'**
  String get votingConfigSemantics;

  /// No description provided for @votingBeta.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get votingBeta;

  /// No description provided for @votingCloses.
  ///
  /// In en, this message translates to:
  /// **'Closes'**
  String get votingCloses;

  /// No description provided for @votingClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get votingClosed;

  /// No description provided for @votingClosesOn.
  ///
  /// In en, this message translates to:
  /// **'{label} {date}'**
  String votingClosesOn(String label, String date);

  /// No description provided for @votingStartsOn.
  ///
  /// In en, this message translates to:
  /// **'Starts {date}'**
  String votingStartsOn(String date);

  /// No description provided for @votingStateInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get votingStateInProgress;

  /// No description provided for @votingStateActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get votingStateActive;

  /// No description provided for @votingStateVoted.
  ///
  /// In en, this message translates to:
  /// **'Voted'**
  String get votingStateVoted;

  /// No description provided for @votingStateTallying.
  ///
  /// In en, this message translates to:
  /// **'Tallying'**
  String get votingStateTallying;

  /// No description provided for @votingResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get votingResume;

  /// No description provided for @votingStartVoting.
  ///
  /// In en, this message translates to:
  /// **'Start voting'**
  String get votingStartVoting;

  /// No description provided for @votingReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get votingReview;

  /// No description provided for @votingViewResults.
  ///
  /// In en, this message translates to:
  /// **'View results'**
  String get votingViewResults;

  /// No description provided for @votingRoundUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voting round unavailable'**
  String get votingRoundUnavailable;

  /// No description provided for @votingRoundLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The selected voting round could not be loaded.'**
  String get votingRoundLoadFailed;

  /// No description provided for @votingTokenHolderVoting.
  ///
  /// In en, this message translates to:
  /// **'Token holder voting'**
  String get votingTokenHolderVoting;

  /// No description provided for @votingPowerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voting power unavailable.'**
  String get votingPowerUnavailable;

  /// No description provided for @votingPreparingPower.
  ///
  /// In en, this message translates to:
  /// **'Preparing voting power.'**
  String get votingPreparingPower;

  /// No description provided for @votingNoProposals.
  ///
  /// In en, this message translates to:
  /// **'No proposals'**
  String get votingNoProposals;

  /// No description provided for @votingNoProposalsBody.
  ///
  /// In en, this message translates to:
  /// **'This voting round does not contain any proposals.'**
  String get votingNoProposalsBody;

  /// No description provided for @votingRetryEligibility.
  ///
  /// In en, this message translates to:
  /// **'Retry eligibility'**
  String get votingRetryEligibility;

  /// No description provided for @votingNotEligible.
  ///
  /// In en, this message translates to:
  /// **'Not eligible'**
  String get votingNotEligible;

  /// No description provided for @votingReviewAnswers.
  ///
  /// In en, this message translates to:
  /// **'Review answers'**
  String get votingReviewAnswers;

  /// No description provided for @votingSkipUnanswered.
  ///
  /// In en, this message translates to:
  /// **'Skip unanswered questions?'**
  String get votingSkipUnanswered;

  /// No description provided for @votingSkipUnansweredBody.
  ///
  /// In en, this message translates to:
  /// **'You have not answered {skipped} of {total} questions. The review screen will mark them as skipped, and skipped questions will not be submitted.'**
  String votingSkipUnansweredBody(int skipped, int total);

  /// No description provided for @votingContinueToReview.
  ///
  /// In en, this message translates to:
  /// **'Continue to review'**
  String get votingContinueToReview;

  /// No description provided for @votingKeepVoting.
  ///
  /// In en, this message translates to:
  /// **'Keep voting'**
  String get votingKeepVoting;

  /// No description provided for @votingNotEligibleRound.
  ///
  /// In en, this message translates to:
  /// **'Not eligible for this voting round'**
  String get votingNotEligibleRound;

  /// No description provided for @votingActive.
  ///
  /// In en, this message translates to:
  /// **'Voting active'**
  String get votingActive;

  /// No description provided for @votingEndsOn.
  ///
  /// In en, this message translates to:
  /// **'Ends {date}'**
  String votingEndsOn(String date);

  /// No description provided for @votingSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get votingSkipped;

  /// No description provided for @votingVoteInProgress.
  ///
  /// In en, this message translates to:
  /// **'Vote in progress'**
  String get votingVoteInProgress;

  /// No description provided for @votingUnfinishedVote.
  ///
  /// In en, this message translates to:
  /// **'You have an unfinished vote for this round. Resume to complete the submission.'**
  String get votingUnfinishedVote;

  /// No description provided for @votingContinueVoting.
  ///
  /// In en, this message translates to:
  /// **'Continue voting'**
  String get votingContinueVoting;

  /// No description provided for @votingForumDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Forum discussion'**
  String get votingForumDiscussion;

  /// No description provided for @votingChoiceLabel.
  ///
  /// In en, this message translates to:
  /// **'Choice {choice}'**
  String votingChoiceLabel(String choice);

  /// No description provided for @votingSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get votingSelected;

  /// No description provided for @votingChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get votingChoose;

  /// No description provided for @votingViewLess.
  ///
  /// In en, this message translates to:
  /// **'View less'**
  String get votingViewLess;

  /// No description provided for @votingViewMore.
  ///
  /// In en, this message translates to:
  /// **'View more'**
  String get votingViewMore;

  /// No description provided for @votingReviewYourAnswers.
  ///
  /// In en, this message translates to:
  /// **'Review your answers'**
  String get votingReviewYourAnswers;

  /// No description provided for @votingChooseAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one option before submitting.'**
  String get votingChooseAtLeastOne;

  /// No description provided for @votingConfirmSubmit.
  ///
  /// In en, this message translates to:
  /// **'Confirm & submit'**
  String get votingConfirmSubmit;

  /// No description provided for @votingResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get votingResults;

  /// No description provided for @votingNoProposalsInRound.
  ///
  /// In en, this message translates to:
  /// **'No proposals in this round.'**
  String get votingNoProposalsInRound;

  /// No description provided for @votingResultsPending.
  ///
  /// In en, this message translates to:
  /// **'Results pending...'**
  String get votingResultsPending;

  /// No description provided for @votingVotedLabel.
  ///
  /// In en, this message translates to:
  /// **'Voted: {label}'**
  String votingVotedLabel(String label);

  /// No description provided for @votingTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total: {amount}'**
  String votingTotalLabel(String amount);

  /// No description provided for @votingResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Voting results'**
  String get votingResultsTitle;

  /// No description provided for @votingSubmissionNotComplete.
  ///
  /// In en, this message translates to:
  /// **'Submission not complete'**
  String get votingSubmissionNotComplete;

  /// No description provided for @votingNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get votingNotAvailable;

  /// No description provided for @votingNotSubmittedBody.
  ///
  /// In en, this message translates to:
  /// **'This account has not completed submission for this voting round.'**
  String get votingNotSubmittedBody;

  /// No description provided for @votingCheckingEligibility.
  ///
  /// In en, this message translates to:
  /// **'Checking voting eligibility for this account.'**
  String get votingCheckingEligibility;

  /// No description provided for @votingEligibilityNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Voting eligibility has not been confirmed for this account.'**
  String get votingEligibilityNotConfirmed;

  /// No description provided for @votingSubmissionConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Submission confirmed!'**
  String get votingSubmissionConfirmed;

  /// No description provided for @votingSubmissionPublished.
  ///
  /// In en, this message translates to:
  /// **'Your vote was successfully published and cannot be changed.'**
  String get votingSubmissionPublished;

  /// No description provided for @votingRoundLabel.
  ///
  /// In en, this message translates to:
  /// **'Voting round'**
  String get votingRoundLabel;

  /// No description provided for @votingPowerLabel.
  ///
  /// In en, this message translates to:
  /// **'Voting power'**
  String get votingPowerLabel;

  /// No description provided for @votingUpdatingRounds.
  ///
  /// In en, this message translates to:
  /// **'Updating voting rounds...'**
  String get votingUpdatingRounds;

  /// No description provided for @votingGenericStatusError.
  ///
  /// In en, this message translates to:
  /// **'Voting could not continue for this account. Retry, or switch to an eligible account if this account cannot vote in this voting round.'**
  String get votingGenericStatusError;

  /// No description provided for @votingPirNotReady.
  ///
  /// In en, this message translates to:
  /// **'Voting PIR data is not ready for this voting round yet. Expected snapshot block {expected}; PIR endpoints report {highest}.'**
  String votingPirNotReady(String expected, String highest);

  /// No description provided for @votingPirNoEndpoint.
  ///
  /// In en, this message translates to:
  /// **'No PIR endpoint matched this voting round snapshot. Expected snapshot block {expected}.'**
  String votingPirNoEndpoint(String expected);

  /// No description provided for @votingQuestionProgress.
  ///
  /// In en, this message translates to:
  /// **'Question {current}/{total}'**
  String votingQuestionProgress(int current, int total);

  /// No description provided for @votingUseSignedBundlesOnly.
  ///
  /// In en, this message translates to:
  /// **'Use signed bundles only?'**
  String get votingUseSignedBundlesOnly;

  /// No description provided for @votingSignedBundlesBody.
  ///
  /// In en, this message translates to:
  /// **'Vizor can submit now using only signatures already scanned from Keystone.'**
  String get votingSignedBundlesBody;

  /// No description provided for @votingSignedBundlesWarning.
  ///
  /// In en, this message translates to:
  /// **'Unsigned bundles are skipped, which lowers voting power for this voting round.'**
  String get votingSignedBundlesWarning;

  /// No description provided for @votingKeepSigning.
  ///
  /// In en, this message translates to:
  /// **'Keep signing'**
  String get votingKeepSigning;

  /// No description provided for @votingSkipBundles.
  ///
  /// In en, this message translates to:
  /// **'Skip bundles'**
  String get votingSkipBundles;

  /// No description provided for @votingSubmittingVotes.
  ///
  /// In en, this message translates to:
  /// **'Submitting votes'**
  String get votingSubmittingVotes;

  /// No description provided for @votingSigningWithKeystone.
  ///
  /// In en, this message translates to:
  /// **'Signing with Keystone'**
  String get votingSigningWithKeystone;

  /// No description provided for @votingDelegatingAuthority.
  ///
  /// In en, this message translates to:
  /// **'Delegating voting authority'**
  String get votingDelegatingAuthority;

  /// No description provided for @votingCastingVotes.
  ///
  /// In en, this message translates to:
  /// **'Casting votes and submitting shares'**
  String get votingCastingVotes;

  /// No description provided for @votingFinalizingSubmission.
  ///
  /// In en, this message translates to:
  /// **'Finalizing submission'**
  String get votingFinalizingSubmission;

  /// No description provided for @votingFailed.
  ///
  /// In en, this message translates to:
  /// **'Voting failed.'**
  String get votingFailed;

  /// No description provided for @votingClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get votingClear;

  /// No description provided for @votingSyncedToBlock.
  ///
  /// In en, this message translates to:
  /// **'Synced to block {height}'**
  String votingSyncedToBlock(String height);

  /// No description provided for @votingSnapshotBlockPart.
  ///
  /// In en, this message translates to:
  /// **'snapshot block {height}'**
  String votingSnapshotBlockPart(String height);

  /// No description provided for @votingChainTipPart.
  ///
  /// In en, this message translates to:
  /// **'chain tip {height}'**
  String votingChainTipPart(String height);

  /// No description provided for @votingWaitingForSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting for wallet sync'**
  String get votingWaitingForSync;

  /// No description provided for @votingWaitingForSyncBody.
  ///
  /// In en, this message translates to:
  /// **'Your wallet is catching up to this voting round snapshot. Voting will continue automatically once the wallet has synced through the snapshot block.'**
  String get votingWaitingForSyncBody;

  /// No description provided for @votingBlocksRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} blocks remaining'**
  String votingBlocksRemaining(String count);

  /// No description provided for @votingSignBundle.
  ///
  /// In en, this message translates to:
  /// **'Sign bundle {current} of {total}'**
  String votingSignBundle(int current, int total);

  /// No description provided for @votingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get votingSkip;

  /// No description provided for @votingScanQrInstruction.
  ///
  /// In en, this message translates to:
  /// **'Scan QR on this screen with Keystone. Then, scan the signed voting QR displayed on Keystone with this device\'s camera'**
  String get votingScanQrInstruction;

  /// No description provided for @votingNowSigningBundle.
  ///
  /// In en, this message translates to:
  /// **'Now signing bundle {current} of {total}'**
  String votingNowSigningBundle(int current, int total);

  /// No description provided for @votingScanSignature.
  ///
  /// In en, this message translates to:
  /// **'Scan signature'**
  String get votingScanSignature;

  /// No description provided for @votingSoftwareAccountRequired.
  ///
  /// In en, this message translates to:
  /// **'Software account required'**
  String get votingSoftwareAccountRequired;

  /// No description provided for @votingSoftwareAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Token holder voting requires a software account. Switch to a software account to vote in this round.'**
  String get votingSoftwareAccountBody;

  /// No description provided for @votingSignatureQrDecodeError.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone voting signature.'**
  String get votingSignatureQrDecodeError;

  /// No description provided for @votingOpenSignedQr.
  ///
  /// In en, this message translates to:
  /// **'Open the signed voting QR on Keystone, then scan again.'**
  String get votingOpenSignedQr;

  /// No description provided for @votingScanVotingSignature.
  ///
  /// In en, this message translates to:
  /// **'Scan voting signature'**
  String get votingScanVotingSignature;

  /// No description provided for @votingHoldKeystoneQr.
  ///
  /// In en, this message translates to:
  /// **'Hold the Keystone QR code steady in front of your camera'**
  String get votingHoldKeystoneQr;

  /// No description provided for @votingCameraOnly.
  ///
  /// In en, this message translates to:
  /// **'Keystone voting uses camera QR scanning only. Connect a camera and try again.'**
  String get votingCameraOnly;

  /// No description provided for @votingTitleTooLong.
  ///
  /// In en, this message translates to:
  /// **'Title must be {max} characters or less.'**
  String votingTitleTooLong(int max);

  /// No description provided for @votingSourceAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'This source URL is already added.'**
  String get votingSourceAlreadyAdded;

  /// No description provided for @votingCustomSource.
  ///
  /// In en, this message translates to:
  /// **'Custom source'**
  String get votingCustomSource;

  /// No description provided for @votingSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get votingSaving;

  /// No description provided for @votingAddCustomSource.
  ///
  /// In en, this message translates to:
  /// **'Add custom source'**
  String get votingAddCustomSource;

  /// No description provided for @votingCopySourceUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy source URL'**
  String get votingCopySourceUrl;

  /// No description provided for @votingSourceUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'Source URL copied.'**
  String get votingSourceUrlCopied;

  /// No description provided for @votingEditSavedSource.
  ///
  /// In en, this message translates to:
  /// **'Edit saved source'**
  String get votingEditSavedSource;

  /// No description provided for @votingDeleteSavedSource.
  ///
  /// In en, this message translates to:
  /// **'Delete saved source'**
  String get votingDeleteSavedSource;

  /// No description provided for @votingEditCustomSource.
  ///
  /// In en, this message translates to:
  /// **'Edit custom source'**
  String get votingEditCustomSource;

  /// No description provided for @votingTitleField.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get votingTitleField;

  /// No description provided for @votingStaticConfigUrl.
  ///
  /// In en, this message translates to:
  /// **'Static config URL'**
  String get votingStaticConfigUrl;

  /// No description provided for @votingValidating.
  ///
  /// In en, this message translates to:
  /// **'Validating...'**
  String get votingValidating;

  /// No description provided for @votingDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get votingDefault;

  /// No description provided for @votingCloseConfigSettings.
  ///
  /// In en, this message translates to:
  /// **'Close voting config settings'**
  String get votingCloseConfigSettings;

  /// No description provided for @settingsAccountChangedReenterPassword.
  ///
  /// In en, this message translates to:
  /// **'Active account changed. Enter your password again.'**
  String get settingsAccountChangedReenterPassword;

  /// No description provided for @settingsNoActiveAccount.
  ///
  /// In en, this message translates to:
  /// **'No active account is selected.'**
  String get settingsNoActiveAccount;

  /// No description provided for @settingsSeedNotAvailableHardware.
  ///
  /// In en, this message translates to:
  /// **'Secret passphrase is not available for hardware accounts.'**
  String get settingsSeedNotAvailableHardware;

  /// No description provided for @settingsSeedNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Secret passphrase is not available for this account.'**
  String get settingsSeedNotAvailable;

  /// No description provided for @settingsSeedConfirmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'To view the secret passphrase.'**
  String get settingsSeedConfirmSubtitle;

  /// No description provided for @settingsSeedMasterKeyBody.
  ///
  /// In en, this message translates to:
  /// **'This is the master key to your wallet.\nDon\'t share it with anyone.'**
  String get settingsSeedMasterKeyBody;

  /// No description provided for @settingsBirthdayDate.
  ///
  /// In en, this message translates to:
  /// **'Birthday date'**
  String get settingsBirthdayDate;

  /// No description provided for @settingsBirthdayBlockHeight.
  ///
  /// In en, this message translates to:
  /// **'Birthday block height'**
  String get settingsBirthdayBlockHeight;

  /// No description provided for @settingsSeedBiometricReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm access to your secret passphrase'**
  String get settingsSeedBiometricReason;

  /// No description provided for @settingsIncorrectPasscode.
  ///
  /// In en, this message translates to:
  /// **'Incorrect passcode'**
  String get settingsIncorrectPasscode;

  /// No description provided for @settingsEnterPasscode.
  ///
  /// In en, this message translates to:
  /// **'Enter Passcode'**
  String get settingsEnterPasscode;

  /// No description provided for @settingsConfirmYourAccess.
  ///
  /// In en, this message translates to:
  /// **'Confirm your access'**
  String get settingsConfirmYourAccess;

  /// No description provided for @settingsSeedCopiedToast.
  ///
  /// In en, this message translates to:
  /// **'Secret passphrase copied'**
  String get settingsSeedCopiedToast;

  /// No description provided for @settingsBirthdayDateCopied.
  ///
  /// In en, this message translates to:
  /// **'Birthday date copied'**
  String get settingsBirthdayDateCopied;

  /// No description provided for @settingsBirthdayHeightCopied.
  ///
  /// In en, this message translates to:
  /// **'Birthday height copied'**
  String get settingsBirthdayHeightCopied;

  /// No description provided for @settingsCopyLabel.
  ///
  /// In en, this message translates to:
  /// **'Copy {label}'**
  String settingsCopyLabel(String label);

  /// No description provided for @settingsNoScreenshotsTitle.
  ///
  /// In en, this message translates to:
  /// **'Don’t take screenshots of your Secret Passphrase'**
  String get settingsNoScreenshotsTitle;

  /// No description provided for @settingsScreenshotsNotReliable.
  ///
  /// In en, this message translates to:
  /// **'Screenshots are not reliable'**
  String get settingsScreenshotsNotReliable;

  /// No description provided for @settingsNoScreenshotsBody.
  ///
  /// In en, this message translates to:
  /// **'. Anyone who has access to your phone or your photo library will be able to see your Secret Passphrase. Write down your Phrase on a piece of paper instead.'**
  String get settingsNoScreenshotsBody;

  /// No description provided for @settingsIUnderstand.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get settingsIUnderstand;

  /// No description provided for @settingsNewPasscodeMustDiffer.
  ///
  /// In en, this message translates to:
  /// **'Your new passcode must be different.'**
  String get settingsNewPasscodeMustDiffer;

  /// No description provided for @settingsPasscodeRotationRecoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify the previous passcode change. Keep your secret passphrase available before trying again.'**
  String get settingsPasscodeRotationRecoveryFailed;

  /// No description provided for @settingsSetNewPasscode.
  ///
  /// In en, this message translates to:
  /// **'Set New Passcode'**
  String get settingsSetNewPasscode;

  /// No description provided for @settingsEnterCurrentPasswordAgain.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password again.'**
  String get settingsEnterCurrentPasswordAgain;

  /// No description provided for @settingsKeepPassphraseAvailable.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify the previous password change. Please keep your secret passphrase available before trying again.'**
  String get settingsKeepPassphraseAvailable;

  /// No description provided for @settingsEnterCurrentPasswordFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password first.'**
  String get settingsEnterCurrentPasswordFirst;

  /// No description provided for @settingsUpdatePassword.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get settingsUpdatePassword;

  /// No description provided for @settingsPasswordHintLong.
  ///
  /// In en, this message translates to:
  /// **'Minimum 8 characters. Add numbers and symbols, or make it longer, for stronger security.'**
  String get settingsPasswordHintLong;

  /// No description provided for @settingsConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get settingsConfirmPassword;

  /// No description provided for @settingsUpdatingPassword.
  ///
  /// In en, this message translates to:
  /// **'Updating password...'**
  String get settingsUpdatingPassword;

  /// No description provided for @settingsAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// No description provided for @settingsSecretPassphraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Secret Passphrase'**
  String get settingsSecretPassphraseTitle;

  /// No description provided for @settingsProfilePictureTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile Picture'**
  String get settingsProfilePictureTitle;

  /// No description provided for @settingsAccountNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Name'**
  String get settingsAccountNameTitle;

  /// No description provided for @settingsSystemSection.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystemSection;

  /// No description provided for @settingsOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsOn;

  /// No description provided for @settingsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsOff;

  /// No description provided for @settingsPasscodeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Passcode updated'**
  String get settingsPasscodeUpdated;

  /// No description provided for @settingsTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get settingsTurnOff;

  /// No description provided for @settingsUninstallBody.
  ///
  /// In en, this message translates to:
  /// **'Vizor will delete wallet data and secure storage from {device}.'**
  String settingsUninstallBody(String device);

  /// No description provided for @settingsThisMac.
  ///
  /// In en, this message translates to:
  /// **'this Mac'**
  String get settingsThisMac;

  /// No description provided for @settingsThisPc.
  ///
  /// In en, this message translates to:
  /// **'this PC'**
  String get settingsThisPc;

  /// No description provided for @settingsThisDevice.
  ///
  /// In en, this message translates to:
  /// **'this device'**
  String get settingsThisDevice;

  /// No description provided for @settingsUninstallFinishMac.
  ///
  /// In en, this message translates to:
  /// **'To finish uninstallation, remove the Vizor app from Applications.'**
  String get settingsUninstallFinishMac;

  /// No description provided for @settingsUninstallFinishWindows.
  ///
  /// In en, this message translates to:
  /// **'To finish uninstallation, uninstall Vizor from Windows settings.'**
  String get settingsUninstallFinishWindows;

  /// No description provided for @settingsUninstallFinishOther.
  ///
  /// In en, this message translates to:
  /// **'To finish uninstallation, remove the Vizor app from this device.'**
  String get settingsUninstallFinishOther;

  /// No description provided for @settingsActiveSwapsBlockUninstall.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This wallet has 1 active swap. Wait for them to complete before uninstalling.} other{This wallet has {count} active swaps. Wait for them to complete before uninstalling.}}'**
  String settingsActiveSwapsBlockUninstall(int count);

  /// No description provided for @settingsCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get settingsCannotBeUndone;

  /// No description provided for @settingsCheckingSwaps.
  ///
  /// In en, this message translates to:
  /// **'Checking swaps...'**
  String get settingsCheckingSwaps;

  /// No description provided for @settingsToUninstall.
  ///
  /// In en, this message translates to:
  /// **'To uninstall Vizor.'**
  String get settingsToUninstall;

  /// No description provided for @settingsDataRemoved.
  ///
  /// In en, this message translates to:
  /// **'Your data has been removed'**
  String get settingsDataRemoved;

  /// No description provided for @settingsRemovingData.
  ///
  /// In en, this message translates to:
  /// **'Removing data...'**
  String get settingsRemovingData;

  /// No description provided for @settingsCloseVizor.
  ///
  /// In en, this message translates to:
  /// **'Close Vizor'**
  String get settingsCloseVizor;

  /// No description provided for @settingsConfirmAccess.
  ///
  /// In en, this message translates to:
  /// **'Confirm access'**
  String get settingsConfirmAccess;

  /// No description provided for @settingsYourPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Your password...'**
  String get settingsYourPasswordHint;

  /// No description provided for @endpointUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get endpointUpdating;

  /// No description provided for @endpointCloseSettings.
  ///
  /// In en, this message translates to:
  /// **'Close endpoint settings'**
  String get endpointCloseSettings;

  /// No description provided for @endpointDefaultSuffix.
  ///
  /// In en, this message translates to:
  /// **'(Default)'**
  String get endpointDefaultSuffix;

  /// No description provided for @endpointCurrentPrefix.
  ///
  /// In en, this message translates to:
  /// **'Current: '**
  String get endpointCurrentPrefix;

  /// No description provided for @endpointCustomEndpointTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Endpoint'**
  String get endpointCustomEndpointTitle;

  /// No description provided for @endpointHostPortHint.
  ///
  /// In en, this message translates to:
  /// **'<hostname>:<port>'**
  String get endpointHostPortHint;

  /// No description provided for @endpointSelectAnEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Select an endpoint.'**
  String get endpointSelectAnEndpoint;

  /// No description provided for @endpointUpdated.
  ///
  /// In en, this message translates to:
  /// **'Endpoint updated'**
  String get endpointUpdated;

  /// No description provided for @endpointsTitle.
  ///
  /// In en, this message translates to:
  /// **'Endpoints'**
  String get endpointsTitle;

  /// No description provided for @endpointSelectFromList.
  ///
  /// In en, this message translates to:
  /// **'Select from the list'**
  String get endpointSelectFromList;

  /// No description provided for @endpointCustomEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Custom endpoint'**
  String get endpointCustomEndpoint;

  /// No description provided for @endpointUpdateEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Update endpoint'**
  String get endpointUpdateEndpoint;

  /// No description provided for @endpointCustomiseEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Customise endpoint'**
  String get endpointCustomiseEndpoint;

  /// No description provided for @endpointCustomizeEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Customize endpoint'**
  String get endpointCustomizeEndpoint;

  /// No description provided for @endpointMisconfiguredNetwork.
  ///
  /// In en, this message translates to:
  /// **'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash network.'**
  String get endpointMisconfiguredNetwork;

  /// No description provided for @endpointMisconfiguredBlockchain.
  ///
  /// In en, this message translates to:
  /// **'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash blockchain.'**
  String get endpointMisconfiguredBlockchain;

  /// No description provided for @endpointMisconfiguredNetworkNewline.
  ///
  /// In en, this message translates to:
  /// **'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash network.\n'**
  String get endpointMisconfiguredNetworkNewline;

  /// No description provided for @endpointStaleBalanceWarning.
  ///
  /// In en, this message translates to:
  /// **'The wallet will show the balance from the last time it was successfully connected. It won\'t show any {ticker} you recently received.'**
  String endpointStaleBalanceWarning(String ticker);

  /// No description provided for @abCopyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get abCopyAddress;

  /// No description provided for @abSendZec.
  ///
  /// In en, this message translates to:
  /// **'Send ZEC'**
  String get abSendZec;

  /// No description provided for @abContactActions.
  ///
  /// In en, this message translates to:
  /// **'{name} actions'**
  String abContactActions(String name);

  /// No description provided for @cameraDeniedShortTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve denied Camera access'**
  String get cameraDeniedShortTitle;

  /// No description provided for @homeImportingWallet.
  ///
  /// In en, this message translates to:
  /// **'We\'re importing\nyour wallet...'**
  String get homeImportingWallet;

  /// No description provided for @homeImportingWalletMobile.
  ///
  /// In en, this message translates to:
  /// **'We\'re importing your wallet...'**
  String get homeImportingWalletMobile;

  /// No description provided for @profilePictureUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update profile picture.'**
  String get profilePictureUpdateFailed;

  /// No description provided for @settingsRemoveDataFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish removing data. Please try again.'**
  String get settingsRemoveDataFailed;

  /// No description provided for @settingsSwapCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for active swaps. Try again before uninstalling.'**
  String get settingsSwapCheckFailed;

  /// No description provided for @settingsPasswordCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your password. Please try again.'**
  String get settingsPasswordCheckFailed;

  /// No description provided for @endpointConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect to that endpoint. Check the host and port.'**
  String get endpointConnectFailed;

  /// No description provided for @settingsPasswordUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your password. Please try again.'**
  String get settingsPasswordUpdateFailed;

  /// No description provided for @settingsPasscodesDidntMatch.
  ///
  /// In en, this message translates to:
  /// **'Passcodes didn\'t match. Try again.'**
  String get settingsPasscodesDidntMatch;

  /// No description provided for @settingsPasscodeCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your passcode. Please try again.'**
  String get settingsPasscodeCheckFailed;

  /// No description provided for @settingsPasscodeUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your passcode. Please try again.'**
  String get settingsPasscodeUpdateFailed;

  /// No description provided for @settingsAppResetFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset the app. Please try again.'**
  String get settingsAppResetFailed;

  /// No description provided for @settingsAccountSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the account changes'**
  String get settingsAccountSaveFailed;

  /// No description provided for @settingsSeedLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your secret passphrase. Please try again.'**
  String get settingsSeedLoadFailed;

  /// No description provided for @settingsPasscodeVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the passcode. Try again.'**
  String get settingsPasscodeVerifyFailed;

  /// No description provided for @votingRoundsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting rounds'**
  String get votingRoundsLoadFailed;

  /// No description provided for @votingRoundLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting round'**
  String get votingRoundLoadFailedTitle;

  /// No description provided for @votingConfigLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting config from that source.'**
  String get votingConfigLoadFailed;

  /// No description provided for @votingConfigUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update voting config.'**
  String get votingConfigUpdateFailed;

  /// No description provided for @votingRoundDetailsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting round details: {error}'**
  String votingRoundDetailsLoadFailed(String error);

  /// No description provided for @votingDontCloseWindow.
  ///
  /// In en, this message translates to:
  /// **'Don\'t close the window. Generating zero-knowledge proofs can take a while; closing now may lose in-flight proof work.'**
  String get votingDontCloseWindow;

  /// No description provided for @votingPirUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach any configured PIR endpoint. Check your network and voting config, then try again.'**
  String get votingPirUnreachable;

  /// No description provided for @swapNotEnoughZecBody.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have enough ZEC for this swap. Try a smaller amount.'**
  String get swapNotEnoughZecBody;

  /// No description provided for @receiveTransparentShieldGuideBody.
  ///
  /// In en, this message translates to:
  /// **'After receiving ZEC to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.'**
  String get receiveTransparentShieldGuideBody;

  /// No description provided for @accountsAddressCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Address couldn\'t be copied'**
  String get accountsAddressCopyFailed;

  /// No description provided for @accountsAddressLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the account address'**
  String get accountsAddressLoadFailed;

  /// No description provided for @accountsResetVizorFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset Vizor'**
  String get accountsResetVizorFailed;

  /// No description provided for @accountsRemoveFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove the account'**
  String get accountsRemoveFailedShort;

  /// No description provided for @receiveAddressLoadFailedLong.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your address. Try again in a moment.'**
  String get receiveAddressLoadFailedLong;

  /// No description provided for @receiveAddressLoadFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Address couldn\'t be loaded. Try again.'**
  String get receiveAddressLoadFailedShort;

  /// No description provided for @accountsResetVizorFailedDot.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset Vizor.'**
  String get accountsResetVizorFailedDot;

  /// No description provided for @accountsRemoveFailedDot.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove account.'**
  String get accountsRemoveFailedDot;

  /// No description provided for @sendBroadcastRejectedRetrying.
  ///
  /// In en, this message translates to:
  /// **'Transaction was created locally but didn\'t reach the network. The wallet will keep retrying until it expires. Don\'t send again unless this one expires.'**
  String get sendBroadcastRejectedRetrying;

  /// No description provided for @sendQrNotZcash.
  ///
  /// In en, this message translates to:
  /// **'This QR code isn\'t a Zcash address.'**
  String get sendQrNotZcash;

  /// No description provided for @onbInvalidBlockHeight.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a valid block height.'**
  String get onbInvalidBlockHeight;

  /// No description provided for @onbNotLegitBlockHeight.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t seem like a legit block height'**
  String get onbNotLegitBlockHeight;

  /// No description provided for @onbUnlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open your wallet. Please try again.'**
  String get onbUnlockFailed;

  /// No description provided for @onbFewStepsAwayDesktop.
  ///
  /// In en, this message translates to:
  /// **'You\'re a few steps away from your first private wallet.\nLet\'s get you set up.'**
  String get onbFewStepsAwayDesktop;

  /// No description provided for @receivePreviewShieldedPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.'**
  String get receivePreviewShieldedPrivacy;

  /// No description provided for @receivePreviewShieldedRenew.
  ///
  /// In en, this message translates to:
  /// **'A new Zcash shielded address\ngenerated every time you open the\nreceive page or click renew button.'**
  String get receivePreviewShieldedRenew;

  /// No description provided for @receivePreviewShieldedDiversified.
  ///
  /// In en, this message translates to:
  /// **'Each new address is a diversified\naddress derived from the same key.\nThey all receive to the same wallet.'**
  String get receivePreviewShieldedDiversified;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {min} characters.'**
  String passwordTooShort(int min);

  /// Wallet Password Policy (AGENTS.md): this charset validation message must stay exactly this literal in every locale. Do not translate.
  ///
  /// In en, this message translates to:
  /// **'Use only English letters, numbers, and symbols.'**
  String get passwordAsciiOnly;

  /// No description provided for @passwordMustDiffer.
  ///
  /// In en, this message translates to:
  /// **'Use a different password.'**
  String get passwordMustDiffer;

  /// No description provided for @votingChooseAtLeastOneVote.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one vote before submitting.'**
  String get votingChooseAtLeastOneVote;

  /// No description provided for @votingVoteLocked.
  ///
  /// In en, this message translates to:
  /// **'Vote locked'**
  String get votingVoteLocked;

  /// No description provided for @votingVotedOn.
  ///
  /// In en, this message translates to:
  /// **'Voted {date}'**
  String votingVotedOn(String date);

  /// No description provided for @votingPowerUnavailableShort.
  ///
  /// In en, this message translates to:
  /// **'Voting power unavailable'**
  String get votingPowerUnavailableShort;

  /// No description provided for @votingPreparingPowerShort.
  ///
  /// In en, this message translates to:
  /// **'Preparing voting power'**
  String get votingPreparingPowerShort;

  /// No description provided for @votingPowerMeta.
  ///
  /// In en, this message translates to:
  /// **'Voting power {power}'**
  String votingPowerMeta(String power);

  /// No description provided for @keystonePreparingQr.
  ///
  /// In en, this message translates to:
  /// **'Preparing QR'**
  String get keystonePreparingQr;

  /// No description provided for @keystoneImReadyNow.
  ///
  /// In en, this message translates to:
  /// **'I\'m ready now'**
  String get keystoneImReadyNow;

  /// No description provided for @swapChainAddressOrAccount.
  ///
  /// In en, this message translates to:
  /// **'{chain} address or account'**
  String swapChainAddressOrAccount(String chain);

  /// No description provided for @swapNetworkErrorRetry.
  ///
  /// In en, this message translates to:
  /// **'Network error while sending. Check your connection and try again — your signature is safe to reuse.'**
  String get swapNetworkErrorRetry;

  /// No description provided for @activitySwapped.
  ///
  /// In en, this message translates to:
  /// **'Swapped'**
  String get activitySwapped;

  /// No description provided for @activitySwapFailed.
  ///
  /// In en, this message translates to:
  /// **'Swap failed'**
  String get activitySwapFailed;

  /// No description provided for @activitySwapping.
  ///
  /// In en, this message translates to:
  /// **'Swapping...'**
  String get activitySwapping;

  /// No description provided for @activitySymbolRefunded.
  ///
  /// In en, this message translates to:
  /// **'{symbol} refunded'**
  String activitySymbolRefunded(String symbol);

  /// No description provided for @activityReceivedSymbol.
  ///
  /// In en, this message translates to:
  /// **'Received {symbol}'**
  String activityReceivedSymbol(String symbol);

  /// No description provided for @activityDepositedSymbol.
  ///
  /// In en, this message translates to:
  /// **'Deposited {symbol}'**
  String activityDepositedSymbol(String symbol);

  /// No description provided for @legalTermsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get legalTermsOfUse;

  /// No description provided for @updateTitleAvailableVersion.
  ///
  /// In en, this message translates to:
  /// **'Update {version} available'**
  String updateTitleAvailableVersion(String version);

  /// No description provided for @updateTitleDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update'**
  String get updateTitleDownloading;

  /// No description provided for @updateTitleReady.
  ///
  /// In en, this message translates to:
  /// **'Update ready'**
  String get updateTitleReady;

  /// No description provided for @updateTitleApplying.
  ///
  /// In en, this message translates to:
  /// **'Restarting Vizor'**
  String get updateTitleApplying;

  /// No description provided for @updateTitleAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateTitleAvailable;

  /// No description provided for @updateBodyAvailable.
  ///
  /// In en, this message translates to:
  /// **'Download now or keep working.'**
  String get updateBodyAvailable;

  /// No description provided for @updateBodyDownloading.
  ///
  /// In en, this message translates to:
  /// **'{progress}% downloaded.'**
  String updateBodyDownloading(int progress);

  /// No description provided for @updateBodyReady.
  ///
  /// In en, this message translates to:
  /// **'Restart when you are ready.'**
  String get updateBodyReady;

  /// No description provided for @updateBodyApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying after Vizor closes.'**
  String get updateBodyApplying;

  /// No description provided for @updateActionDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateActionDownload;

  /// No description provided for @updateActionRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get updateActionRestart;

  /// No description provided for @updateActionDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get updateActionDownloading;

  /// No description provided for @updateActionRestarting.
  ///
  /// In en, this message translates to:
  /// **'Restarting'**
  String get updateActionRestarting;

  /// No description provided for @updateActionUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateActionUpdate;

  /// No description provided for @updateActionLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateActionLater;

  /// No description provided for @updateLinuxAvailable.
  ///
  /// In en, this message translates to:
  /// **'Vizor {version} is available.'**
  String updateLinuxAvailable(String version);

  /// No description provided for @updateViewRelease.
  ///
  /// In en, this message translates to:
  /// **'View Release'**
  String get updateViewRelease;

  /// No description provided for @endpointFailoverSwitched.
  ///
  /// In en, this message translates to:
  /// **'Selected endpoint is unstable. Switched to fallback endpoint.'**
  String get endpointFailoverSwitched;

  /// No description provided for @endpointFailoverRecovered.
  ///
  /// In en, this message translates to:
  /// **'Selected endpoint recovered. Switched back.'**
  String get endpointFailoverRecovered;

  /// No description provided for @activityIncompleteDeposit.
  ///
  /// In en, this message translates to:
  /// **'Incomplete deposit'**
  String get activityIncompleteDeposit;

  /// No description provided for @activityTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get activityTimeout;

  /// No description provided for @activityLoadErrorRetry.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load activity. Try again in a moment.'**
  String get activityLoadErrorRetry;

  /// No description provided for @keystoneShieldSignTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign tx on your Keystone'**
  String get keystoneShieldSignTitle;

  /// No description provided for @keystoneShieldScanToSign.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code to sign'**
  String get keystoneShieldScanToSign;

  /// No description provided for @keystoneShieldSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting transaction'**
  String get keystoneShieldSubmitting;

  /// No description provided for @keystoneShieldReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get keystoneShieldReject;

  /// No description provided for @keystoneShieldBackToWallet.
  ///
  /// In en, this message translates to:
  /// **'Back to Wallet'**
  String get keystoneShieldBackToWallet;

  /// No description provided for @shieldErrorSyncFirst.
  ///
  /// In en, this message translates to:
  /// **'Sync the wallet before shielding transparent balance.'**
  String get shieldErrorSyncFirst;

  /// No description provided for @shieldErrorBroadcastFailed.
  ///
  /// In en, this message translates to:
  /// **'Shield transaction could not be broadcast.'**
  String get shieldErrorBroadcastFailed;

  /// No description provided for @shieldErrorRetry.
  ///
  /// In en, this message translates to:
  /// **'Shield balance failed. Please try again.'**
  String get shieldErrorRetry;

  /// No description provided for @shieldCancelledParamsDownload.
  ///
  /// In en, this message translates to:
  /// **'Shielding was cancelled before proving parameters were downloaded.'**
  String get shieldCancelledParamsDownload;

  /// No description provided for @scanCameraPermissionOff.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. Allow it in Settings to scan addresses.'**
  String get scanCameraPermissionOff;

  /// No description provided for @swapQuoteChangedLower.
  ///
  /// In en, this message translates to:
  /// **'Live quote is {percent}% lower than the earlier estimate. Check the guaranteed minimum before you continue.'**
  String swapQuoteChangedLower(String percent);

  /// No description provided for @swapQuoteChangedHigher.
  ///
  /// In en, this message translates to:
  /// **'Live quote is {percent}% higher than the earlier estimate. Check the guaranteed minimum before you continue.'**
  String swapQuoteChangedHigher(String percent);

  /// No description provided for @swapPickerRecipientsTitle.
  ///
  /// In en, this message translates to:
  /// **'{symbol} recipients'**
  String swapPickerRecipientsTitle(String symbol);

  /// No description provided for @swapPickerRefundsTitle.
  ///
  /// In en, this message translates to:
  /// **'{symbol} refunds'**
  String swapPickerRefundsTitle(String symbol);

  /// No description provided for @swapPickerNoSavedRecipients.
  ///
  /// In en, this message translates to:
  /// **'No saved {symbol} recipients'**
  String swapPickerNoSavedRecipients(String symbol);

  /// No description provided for @swapPickerNoSavedRefunds.
  ///
  /// In en, this message translates to:
  /// **'No saved {symbol} refunds'**
  String swapPickerNoSavedRefunds(String symbol);

  /// No description provided for @swapErrAccountChanged.
  ///
  /// In en, this message translates to:
  /// **'Active account changed. Review the quote again before starting.'**
  String get swapErrAccountChanged;

  /// No description provided for @swapErrIntentMissing.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit was broadcast, but the saved swap intent was not found. Copy the transaction hash before leaving this screen.'**
  String get swapErrIntentMissing;

  /// No description provided for @swapDepositPartialBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Some deposit transactions may have reached the network. Check activity before trying again.'**
  String get swapDepositPartialBroadcast;

  /// No description provided for @swapDepositPendingBroadcast.
  ///
  /// In en, this message translates to:
  /// **'The deposit was created locally but could not be broadcast. Check activity before trying again.'**
  String get swapDepositPendingBroadcast;

  /// No description provided for @swapDepositBroadcastUnknown.
  ///
  /// In en, this message translates to:
  /// **'The transaction may have reached the network, but confirmation timed out. Check activity before trying again.'**
  String get swapDepositBroadcastUnknown;

  /// No description provided for @swapDepositStorageFailed.
  ///
  /// In en, this message translates to:
  /// **'The transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.'**
  String get swapDepositStorageFailed;

  /// No description provided for @swapDepositUncertain.
  ///
  /// In en, this message translates to:
  /// **'The deposit status is uncertain. Check activity before trying again.'**
  String get swapDepositUncertain;

  /// No description provided for @endpointRegionDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get endpointRegionDefault;

  /// No description provided for @endpointRegionAmericas.
  ///
  /// In en, this message translates to:
  /// **'Americas'**
  String get endpointRegionAmericas;

  /// No description provided for @endpointRegionEurope.
  ///
  /// In en, this message translates to:
  /// **'Europe'**
  String get endpointRegionEurope;

  /// No description provided for @endpointRegionAsiaPacific.
  ///
  /// In en, this message translates to:
  /// **'Asia Pacific'**
  String get endpointRegionAsiaPacific;

  /// No description provided for @endpointRegionGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get endpointRegionGlobal;

  /// No description provided for @endpointRegionCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get endpointRegionCommunity;

  /// No description provided for @endpointRegionTestnet.
  ///
  /// In en, this message translates to:
  /// **'Testnet'**
  String get endpointRegionTestnet;

  /// No description provided for @endpointRegionRegtest.
  ///
  /// In en, this message translates to:
  /// **'Regtest'**
  String get endpointRegionRegtest;

  /// No description provided for @endpointErrEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter an endpoint.'**
  String get endpointErrEnter;

  /// No description provided for @endpointErrSpaces.
  ///
  /// In en, this message translates to:
  /// **'Endpoint cannot contain spaces.'**
  String get endpointErrSpaces;

  /// No description provided for @endpointErrHostPort.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid hostname and port.'**
  String get endpointErrHostPort;

  /// No description provided for @endpointErrHttps.
  ///
  /// In en, this message translates to:
  /// **'Use an https:// endpoint.'**
  String get endpointErrHttps;

  /// No description provided for @endpointErrPort.
  ///
  /// In en, this message translates to:
  /// **'Include a valid port, for example us.zec.stardust.rest:443.'**
  String get endpointErrPort;

  /// No description provided for @endpointLatencyChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get endpointLatencyChecking;

  /// No description provided for @endpointLatencyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get endpointLatencyUnavailable;

  /// No description provided for @endpointLatencyWrongNetwork.
  ///
  /// In en, this message translates to:
  /// **'Wrong network'**
  String get endpointLatencyWrongNetwork;

  /// No description provided for @aboutVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version: {version} Public Beta'**
  String aboutVersionLabel(String version);

  /// No description provided for @privacySensitiveContentHidden.
  ///
  /// In en, this message translates to:
  /// **'Sensitive content hidden'**
  String get privacySensitiveContentHidden;

  /// No description provided for @sendUnknownShieldedAddress.
  ///
  /// In en, this message translates to:
  /// **'Unknown shielded address'**
  String get sendUnknownShieldedAddress;

  /// No description provided for @sendUnknownTransparentAddress.
  ///
  /// In en, this message translates to:
  /// **'Unknown transparent address'**
  String get sendUnknownTransparentAddress;

  /// No description provided for @accountsSendStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Send couldn\'t be started'**
  String get accountsSendStartFailed;

  /// No description provided for @abClearContactLabel.
  ///
  /// In en, this message translates to:
  /// **'Clear contact label'**
  String get abClearContactLabel;

  /// No description provided for @abSaveContactFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the contact. Please try again.'**
  String get abSaveContactFailed;

  /// No description provided for @abRemoveContactFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove the contact. Please try again.'**
  String get abRemoveContactFailed;

  /// No description provided for @abLoadContactsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load contacts. Try again.'**
  String get abLoadContactsFailed;

  /// No description provided for @sendTxCouldNotBeSent.
  ///
  /// In en, this message translates to:
  /// **'Transaction couldn\'t be sent.'**
  String get sendTxCouldNotBeSent;

  /// No description provided for @deviceAuthConfirmReset.
  ///
  /// In en, this message translates to:
  /// **'Confirm reset Vizor'**
  String get deviceAuthConfirmReset;

  /// No description provided for @deviceAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'Device authentication is required to reset Vizor.'**
  String get deviceAuthRequired;

  /// No description provided for @deviceAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify device ownership. Please try again.'**
  String get deviceAuthFailed;

  /// No description provided for @abPickerNoContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts found'**
  String get abPickerNoContacts;

  /// No description provided for @sendPartialBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Some transactions were broadcast and the rest will retry automatically. Check activity before sending again.'**
  String get sendPartialBroadcast;

  /// No description provided for @sendPendingBroadcastRetry.
  ///
  /// In en, this message translates to:
  /// **'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.'**
  String get sendPendingBroadcastRetry;

  /// No description provided for @sendBroadcastUnknown.
  ///
  /// In en, this message translates to:
  /// **'The transaction may have reached the network, but confirmation timed out. Check activity before sending again.'**
  String get sendBroadcastUnknown;

  /// No description provided for @sendBroadcastStorageFailed.
  ///
  /// In en, this message translates to:
  /// **'The transaction reached the network, but Vizor could not store it locally. Do not send again until sync or an explorer confirms the latest status.'**
  String get sendBroadcastStorageFailed;

  /// No description provided for @sendPcztRejected.
  ///
  /// In en, this message translates to:
  /// **'Transaction was rejected by the network. Please try again later.'**
  String get sendPcztRejected;

  /// No description provided for @sendCancelledParamsDownload.
  ///
  /// In en, this message translates to:
  /// **'Sending was cancelled before proving parameters were downloaded.'**
  String get sendCancelledParamsDownload;

  /// No description provided for @votingAccountLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load account'**
  String get votingAccountLoadError;

  /// No description provided for @votingResultsFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Voting results'**
  String get votingResultsFallbackTitle;

  /// No description provided for @votingLoadResultsError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load results: {message}'**
  String votingLoadResultsError(String message);

  /// No description provided for @votingLoadRoundDetailsError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting round details: {message}'**
  String votingLoadRoundDetailsError(String message);

  /// No description provided for @votingLoadReviewError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load review: {message}'**
  String votingLoadReviewError(String message);

  /// No description provided for @votingLoadSubmissionError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load submission details: {message}'**
  String votingLoadSubmissionError(String message);

  /// No description provided for @votingRoundsRefreshError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update voting rounds. Try again.'**
  String get votingRoundsRefreshError;

  /// No description provided for @votingRecoveryDelegationPending.
  ///
  /// In en, this message translates to:
  /// **'This vote has local progress, but delegation is not fully confirmed yet. The app should continue recovery before accepting another vote.'**
  String get votingRecoveryDelegationPending;

  /// No description provided for @votingRecoveryCommitmentPending.
  ///
  /// In en, this message translates to:
  /// **'This vote has been started, but its commitment transaction recovery data is not complete yet. Do not vote again from this account.'**
  String get votingRecoveryCommitmentPending;

  /// No description provided for @votingRecoverySharesPending.
  ///
  /// In en, this message translates to:
  /// **'This vote was submitted, but some helper-server shares are still waiting for confirmation. Do not vote again from this account.'**
  String get votingRecoverySharesPending;

  /// No description provided for @votingEndsToday.
  ///
  /// In en, this message translates to:
  /// **'Ends today'**
  String get votingEndsToday;

  /// No description provided for @votingOneDayLeft.
  ///
  /// In en, this message translates to:
  /// **'1 day left'**
  String get votingOneDayLeft;

  /// No description provided for @votingDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days} days left'**
  String votingDaysLeft(int days);

  /// No description provided for @mobileExitBackHint.
  ///
  /// In en, this message translates to:
  /// **'Go back again to exit'**
  String get mobileExitBackHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
