import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

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
    Locale('zh'),
  ];

  /// Back-link label shown during desktop onboarding that returns to the Add account screen.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get appBackAddAccount;

  /// Back-link label shown during desktop import that returns to the hardware wallet list.
  ///
  /// In en, this message translates to:
  /// **'Hardware wallets'**
  String get appBackHardwareWallets;

  /// Back-link label shown during desktop import that returns to the list of import methods.
  ///
  /// In en, this message translates to:
  /// **'Import methods'**
  String get appBackImportMethods;

  /// Back-link label on the Ledger account customisation screen that returns to the wallet birthday height step.
  ///
  /// In en, this message translates to:
  /// **'Wallet Birthday Height'**
  String get appBackWalletBirthdayHeight;

  /// Back-link label shown during desktop onboarding that returns to the Welcome screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get appBackWelcome;

  /// Hint shown on Android after the first Back press at the root, telling the user to press Back again to exit the app.
  ///
  /// In en, this message translates to:
  /// **'Go back again to exit'**
  String get appExitBackHint;

  /// Toast shown when cancelling a gift card claim during wallet setup fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t close the card. Try again.'**
  String get appGiftCloseCardFailed;

  /// Snackbar on Linux announcing a new version is available.
  ///
  /// In en, this message translates to:
  /// **'Vizor {version} is available.'**
  String appLinuxUpdateAvailable(String version);

  /// Snackbar on Linux announcing a new version when Tor is on; warns that the release page opens in the browser outside Tor.
  ///
  /// In en, this message translates to:
  /// **'Vizor {version} is available. The release page opens in your browser, outside Vizor’s Tor connection.'**
  String appLinuxUpdateAvailableTor(String version);

  /// Snackbar action on Linux that opens the release page in the browser (shown when Tor is on).
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get appLinuxUpdateOpenInBrowser;

  /// Snackbar action on Linux that opens the release page.
  ///
  /// In en, this message translates to:
  /// **'View release'**
  String get appLinuxUpdateViewRelease;

  /// Title of the Privacy Policy legal screen on mobile.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get appPrivacyPolicyTitle;

  /// Title of the Terms of Use legal screen on mobile.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get appTermsOfUseTitle;

  /// Message of the in-app update prompt while the update is applied after the app closes.
  ///
  /// In en, this message translates to:
  /// **'Applying after Vizor closes.'**
  String get appUpdateApplyingMessage;

  /// Message of the in-app update prompt when an update can be downloaded.
  ///
  /// In en, this message translates to:
  /// **'Download now or keep working.'**
  String get appUpdateAvailableMessage;

  /// Fallback title of the in-app update prompt when an update is available.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get appUpdateAvailableTitle;

  /// Title of the in-app update prompt (Windows) when a specific version can be downloaded.
  ///
  /// In en, this message translates to:
  /// **'Update {version} available'**
  String appUpdateAvailableVersionTitle(String version);

  /// Button on the in-app update prompt that hides it after a failed update.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get appUpdateDismiss;

  /// Button on the in-app update prompt that starts downloading the update.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get appUpdateDownload;

  /// Disabled button label on the in-app update prompt while the update downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get appUpdateDownloading;

  /// Message of the in-app update prompt showing download progress as a percentage.
  ///
  /// In en, this message translates to:
  /// **'{percent}% downloaded.'**
  String appUpdateDownloadingMessage(int percent);

  /// Title of the in-app update prompt while the update downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloading update'**
  String get appUpdateDownloadingTitle;

  /// Message of the in-app update prompt when the update failed and no detail is available.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the update. Try again.'**
  String get appUpdateFailedMessage;

  /// Title of the in-app update prompt when the update failed.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get appUpdateFailedTitle;

  /// Button on the in-app update prompt that postpones the update.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get appUpdateLater;

  /// Message of the in-app update prompt when the update is ready to install.
  ///
  /// In en, this message translates to:
  /// **'Restart when you are ready.'**
  String get appUpdateReadyMessage;

  /// Title of the in-app update prompt once the update is downloaded and ready to install.
  ///
  /// In en, this message translates to:
  /// **'Update ready'**
  String get appUpdateReadyTitle;

  /// Button on the in-app update prompt that restarts the app to apply the update.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get appUpdateRestart;

  /// Disabled button label on the in-app update prompt while the app restarts.
  ///
  /// In en, this message translates to:
  /// **'Restarting'**
  String get appUpdateRestarting;

  /// Title of the in-app update prompt while the app restarts to apply the update.
  ///
  /// In en, this message translates to:
  /// **'Restarting Vizor'**
  String get appUpdateRestartingTitle;

  /// Button on the in-app update prompt that retries a failed update.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get appUpdateTryAgain;

  /// Screen-reader label of a carousel card. {name} is the carousel name, e.g. Information.
  ///
  /// In en, this message translates to:
  /// **'{name} {page} of {count}. {message}'**
  String carouselPageSemantics(
    String name,
    int page,
    int count,
    String message,
  );

  /// Screen-reader label of a carousel page dot. {name} is the lowercase carousel name.
  ///
  /// In en, this message translates to:
  /// **'Show {name} {page} of {count}'**
  String carouselShowPage(String name, int page, int count);

  /// Toast after an address is copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get commonAddressCopied;

  /// Screen-reader label of a back button.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Screen-reader label of a back link that names where it goes.
  ///
  /// In en, this message translates to:
  /// **'Back to {destination}'**
  String commonBackTo(String destination);

  /// Button that closes a modal or sheet without applying a change.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Toast when leaving a flow could not cancel its pending work.
  ///
  /// In en, this message translates to:
  /// **'Could not finish cancellation. Try again.'**
  String get commonCancellationFailed;

  /// Screen-reader label of the clear button in a text field.
  ///
  /// In en, this message translates to:
  /// **'Clear text'**
  String get commonClearText;

  /// Button or screen-reader label that closes a sheet or modal.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Toast after a value is copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// Button that copies an address to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get commonCopyAddress;

  /// Screen-reader label of the close button on a toast.
  ///
  /// In en, this message translates to:
  /// **'Dismiss notification'**
  String get commonDismissNotification;

  /// Body of the sheet for a feature that is not available on this platform yet.
  ///
  /// In en, this message translates to:
  /// **'This feature is still in progress.'**
  String get commonFeatureInProgress;

  /// Default screen-reader name of a carousel of information cards.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get commonInformation;

  /// Title of the sheet for a feature that is not available on this platform yet.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get commonNotAvailableYet;

  /// Button that acknowledges a message and closes it.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Screen-reader label of the lock icon covering secret content while the app is in the background.
  ///
  /// In en, this message translates to:
  /// **'Sensitive content hidden'**
  String get commonSensitiveContentHidden;

  /// Button that applies a setting chosen in a picker modal or sheet (theme, language).
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// The Update button label while the change is being saved.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get commonUpdating;

  /// [security] Body of the Linux keyring screen when the system keyring is locked; mentions the keyring password prompt.
  ///
  /// In en, this message translates to:
  /// **'Vizor cannot access your system keyring. Unlock the keyring, then choose Retry. A system prompt may ask for your keyring password.'**
  String get keyringLockedBody;

  /// Message on the Linux keyring screen when a retry or cancel request failed.
  ///
  /// In en, this message translates to:
  /// **'The keyring did not respond. Try again.'**
  String get keyringNoResponse;

  /// Title of the startup screen on Linux when the app failed to start.
  ///
  /// In en, this message translates to:
  /// **'Unable to open Vizor'**
  String get keyringOpenFailedTitle;

  /// Title of the startup screen on Linux while the app loads.
  ///
  /// In en, this message translates to:
  /// **'Opening Vizor'**
  String get keyringOpeningTitle;

  /// Body of the Linux keyring screen while waiting for the user to answer a system keyring prompt.
  ///
  /// In en, this message translates to:
  /// **'Complete any system keyring prompt to continue in Vizor.'**
  String get keyringPromptBody;

  /// Button on the Linux startup and keyring screens that quits the app.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get keyringQuit;

  /// Body of the startup failure screen on Linux.
  ///
  /// In en, this message translates to:
  /// **'Quit and restart Vizor to try again.'**
  String get keyringRestartHint;

  /// Button on the Linux keyring screen that retries accessing the system keyring.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get keyringRetry;

  /// Body of the Linux keyring screen when it is unknown whether a save succeeded.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not confirm whether your changes were saved. Quit and restart Vizor before continuing.'**
  String get keyringSaveUnconfirmedBody;

  /// Title of the Linux keyring screen when it is unknown whether a save to secure storage succeeded.
  ///
  /// In en, this message translates to:
  /// **'Unable to confirm the save'**
  String get keyringSaveUnconfirmedTitle;

  /// Title of the Linux keyring screen while access to secure storage is retried.
  ///
  /// In en, this message translates to:
  /// **'Trying secure storage'**
  String get keyringTryingTitle;

  /// Body of the Linux keyring screen when the system keyring service is unreachable.
  ///
  /// In en, this message translates to:
  /// **'Vizor cannot connect to the system keyring. Try again, or quit and restart Vizor.'**
  String get keyringUnavailableBody;

  /// Title of the Linux keyring screen when the system keyring service cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Secure storage is unavailable'**
  String get keyringUnavailableTitle;

  /// [security] Title of the Linux keyring screen asking the user to unlock the system keyring.
  ///
  /// In en, this message translates to:
  /// **'Unlock your keyring'**
  String get keyringUnlockTitle;

  /// Body of the Linux keyring screen when the stored keyring data is unreadable.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not read the data in your system keyring. Retry after restoring access, or quit Vizor.'**
  String get keyringUnreadableBody;

  /// Title of the Linux keyring screen when the stored keyring data is unreadable.
  ///
  /// In en, this message translates to:
  /// **'Unable to read secure storage'**
  String get keyringUnreadableTitle;

  /// Language picker option that follows the device language. Shown in Settings > System > Language and the Welcome language picker.
  ///
  /// In en, this message translates to:
  /// **'System ({language})'**
  String languageSystemOption(String language);

  /// [security] Body of the passcode entry screen after sync was interrupted.
  ///
  /// In en, this message translates to:
  /// **'Sync paused. Unlock Vizor to continue.'**
  String get lockBodyPaused;

  /// [security] Body of the passcode entry screen after sync has finished.
  ///
  /// In en, this message translates to:
  /// **'Synced successfully. Unlock Vizor to continue.'**
  String get lockBodySynced;

  /// [security] Body of the passcode entry screen while the entered passcode is verified.
  ///
  /// In en, this message translates to:
  /// **'Checking passcode...'**
  String get lockCheckingPasscode;

  /// [security] Screen-reader label of the passcode entry screen that unlocks the wallet.
  ///
  /// In en, this message translates to:
  /// **'Confirm passcode to unlock Vizor'**
  String get lockConfirmPasscodeSemantics;

  /// Top bar title of the passcode entry screen when sync has finished.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get lockNavSynced;

  /// Top bar title of the passcode entry screen while sync runs, with the percentage complete.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Syncing...'**
  String lockNavSyncing(int percent);

  /// [security] Error under the passcode dots when the entered unlock passcode is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect Passcode'**
  String get lockPasscodeIncorrect;

  /// Title on the sync lock screen when sync has finished.
  ///
  /// In en, this message translates to:
  /// **'Sync Complete'**
  String get lockSyncCompleteTitle;

  /// Screen-reader label of the sync lock screen when sync was interrupted.
  ///
  /// In en, this message translates to:
  /// **'Vizor sync is paused'**
  String get lockSyncPausedSemantics;

  /// Title on the sync lock screen and passcode screen header when sync was interrupted.
  ///
  /// In en, this message translates to:
  /// **'Sync paused'**
  String get lockSyncPausedTitle;

  /// Screen-reader label of the sync lock screen when sync has finished.
  ///
  /// In en, this message translates to:
  /// **'Vizor is synced'**
  String get lockSyncedSemantics;

  /// Screen-reader label and caption on the sync lock screen while sync is running.
  ///
  /// In en, this message translates to:
  /// **'Vizor is syncing'**
  String get lockSyncingMessage;

  /// [security] Body of the passcode entry screen while sync is running.
  ///
  /// In en, this message translates to:
  /// **'Unlock to continue'**
  String get lockUnlockToContinue;

  /// [security] Body on the sync lock screen asking the user to unlock the wallet to continue.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor to continue'**
  String get lockUnlockToContinueBody;

  /// [security] Body on the sync lock screen after an interrupted sync asking the user to unlock the wallet.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor to continue.'**
  String get lockUnlockToContinuePausedBody;

  /// [security] Button label on the sync lock screen, and the reason text of the system biometric prompt, that unlocks the wallet.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor'**
  String get lockUnlockVizor;

  /// [security] Heading of the passcode entry screen shown to unlock the wallet.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get lockWelcomeBack;

  /// Sidebar and tab bar destination: transaction history.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get navActivity;

  /// Sidebar and tab bar destination: wallet home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Sidebar destination: pay with ZEC.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get navPay;

  /// Sidebar and tab bar destination: settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Sidebar action that locks the wallet.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get navSignOut;

  /// Sidebar and tab bar destination: swap assets.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get navSwap;

  /// Sidebar destination: coinholder voting.
  ///
  /// In en, this message translates to:
  /// **'Vote'**
  String get navVote;

  /// Badge naming a shielded pool or address. See the glossary entry for shielded.
  ///
  /// In en, this message translates to:
  /// **'Shielded'**
  String get poolShielded;

  /// Badge naming a transparent pool or address.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get poolTransparent;

  /// Error in the profile picture picker when saving failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update profile picture.'**
  String get profilePictureUpdateFailed;

  /// Label of the memo row while a receipt is loading.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get receiptMessageLabel;

  /// Settings > System row label and picker title for choosing the app language. Also the screen-reader label of the Welcome language button.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageLabel;

  /// Error under the language options when saving the choice failed. The modal stays open.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update language.'**
  String get settingsLanguageUpdateFailed;

  /// Sidebar account name shown before an account has loaded.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get sidebarAccountNameFallback;

  /// Toast when copying the account address from the sidebar failed.
  ///
  /// In en, this message translates to:
  /// **'Address couldn\'t be copied'**
  String get sidebarAddressCopyFailed;

  /// Screen-reader label of the sidebar copy-address button.
  ///
  /// In en, this message translates to:
  /// **'Copy shielded address'**
  String get sidebarCopyShieldedAddress;

  /// Screen-reader label of the sidebar button that hides amounts.
  ///
  /// In en, this message translates to:
  /// **'Hide balance'**
  String get sidebarHideBalance;

  /// Sidebar Home item label while an imported account scans.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get sidebarImporting;

  /// Button in the sidebar account menu that opens account management.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get sidebarManageAccounts;

  /// Sidebar Ironwood migration item while the migration runs.
  ///
  /// In en, this message translates to:
  /// **'Migrating...'**
  String get sidebarMigrating;

  /// Sidebar Ironwood migration item when the user must act.
  ///
  /// In en, this message translates to:
  /// **'Needs input'**
  String get sidebarMigrationNeedsInput;

  /// Sidebar Ironwood migration item after a network upgrade stopped it.
  ///
  /// In en, this message translates to:
  /// **'Migration stopped'**
  String get sidebarMigrationStopped;

  /// Heading of the sidebar account menu.
  ///
  /// In en, this message translates to:
  /// **'My accounts'**
  String get sidebarMyAccounts;

  /// Toast after the account's shielded address is copied.
  ///
  /// In en, this message translates to:
  /// **'Shielded address copied'**
  String get sidebarShieldedAddressCopied;

  /// Screen-reader label of the sidebar button that shows hidden amounts.
  ///
  /// In en, this message translates to:
  /// **'Show balance'**
  String get sidebarShowBalance;

  /// Sync status when the wallet is up to date.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncSynced;

  /// Screen-reader sync status with the scanned block height.
  ///
  /// In en, this message translates to:
  /// **'Synced at block {height}'**
  String syncSyncedAtBlock(String height);

  /// Body of the transaction fee info sheet.
  ///
  /// In en, this message translates to:
  /// **'The network fee is set by the Zcash protocol (ZIP 317) based on the transaction size. Vizor adds no extra fee.'**
  String get txFeeInfoDescription;

  /// Title of the transaction fee info sheet.
  ///
  /// In en, this message translates to:
  /// **'Tx fee'**
  String get txFeeInfoTitle;
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
      <String>['en', 'ko', 'zh'].contains(locale.languageCode);

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
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
