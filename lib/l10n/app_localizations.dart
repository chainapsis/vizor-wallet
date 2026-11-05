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

  /// Screen-reader label of the button that opens an account's action menu on desktop.
  ///
  /// In en, this message translates to:
  /// **'Account actions'**
  String get accountsActionsLabel;

  /// Button and screen-reader label that starts adding or creating another account.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get accountsAdd;

  /// Toast on the mobile Accounts screen when an account's address could not be loaded for sending.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the account address'**
  String get accountsAddressLoadFailed;

  /// Screen-reader label of the avatar button in the edit-account dialog and sheet that opens the profile picture picker.
  ///
  /// In en, this message translates to:
  /// **'Change profile picture'**
  String get accountsChangeProfilePicture;

  /// Screen-reader label of the clear button in the mobile account name field.
  ///
  /// In en, this message translates to:
  /// **'Clear account name'**
  String get accountsClearName;

  /// Section heading on the Accounts screen for the selected account.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get accountsCurrent;

  /// Account menu item that opens the account editor for name and picture.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get accountsEdit;

  /// Error in the desktop edit-account dialog when saving failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update account.'**
  String get accountsEditFailed;

  /// Placeholder of the account name field: the name must be 1 to 20 characters long.
  ///
  /// In en, this message translates to:
  /// **'1-20 characters'**
  String get accountsEditNameHint;

  /// Label of the account name field in the edit-account dialog and sheet.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountsEditNameLabel;

  /// Button in the mobile account switcher sheet that opens the Accounts screen.
  ///
  /// In en, this message translates to:
  /// **'Manage accounts'**
  String get accountsManage;

  /// Screen-reader label of the button that opens the options menu of an account. {name} is the account name the user chose.
  ///
  /// In en, this message translates to:
  /// **'Account options for {name}'**
  String accountsOptionsFor(String name);

  /// Section heading on the Accounts screen for the accounts that are not selected.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get accountsOther;

  /// Heading above the unselected accounts in the mobile account switcher sheet.
  ///
  /// In en, this message translates to:
  /// **'Other accounts'**
  String get accountsOtherAccounts;

  /// [security] Account menu item and sheet title for removing an account from the wallet; this deletes its local data.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get accountsRemove;

  /// [security] Warning in the mobile remove-account sheet when the account's secret passphrase was never backed up; its funds would be lost.
  ///
  /// In en, this message translates to:
  /// **'If you haven’t backed up this account’s secret passphrase, you can’t recover its funds after removal.'**
  String get accountsRemoveBackupWarning;

  /// Message in the desktop remove-account dialog when gift cards being received block removal. {count} is the number of incoming gift cards, at least 1.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This account is receiving a gift card. Wait for it to finish before removing this account.} other{This account is receiving {count} gift cards. Wait for them to finish before removing this account.}}'**
  String accountsRemoveBlockedByGiftCards(int count);

  /// Message in the desktop remove-account dialog when pending swaps block removal. {count} is the number of active swaps, at least 1.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This account has 1 active swap. Complete or remove them from swap activity before removing this account.} other{This account has {count} active swaps. Complete or remove them from swap activity before removing this account.}}'**
  String accountsRemoveBlockedBySwaps(int count);

  /// [security] Body of the mobile remove-account sheet. Removal deletes the account's local data irreversibly.
  ///
  /// In en, this message translates to:
  /// **'Removing this account deletes its local data from Vizor. Make sure you can re-import it before continuing.'**
  String get accountsRemoveBody;

  /// Message in the desktop remove-account dialog while the wallet looks for gift cards being received.
  ///
  /// In en, this message translates to:
  /// **'Checking this account for incoming gift cards before removal.'**
  String get accountsRemoveCheckingGiftCards;

  /// [security] Label of the confirm button in the desktop remove-account dialog while the password is checked.
  ///
  /// In en, this message translates to:
  /// **'Checking password...'**
  String get accountsRemoveCheckingPassword;

  /// Message in the desktop remove-account dialog while the wallet looks for pending swaps.
  ///
  /// In en, this message translates to:
  /// **'Checking this account for active swaps before removal.'**
  String get accountsRemoveCheckingSwaps;

  /// [security] Destructive button that confirms removing one account and its local data.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get accountsRemoveConfirm;

  /// [security] Error in the desktop remove-account dialog when removing the account failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove account.'**
  String get accountsRemoveFailed;

  /// [security] Toast on the mobile Accounts screen when removing an account failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove the account'**
  String get accountsRemoveFailedToast;

  /// Message in the desktop remove-account dialog when the incoming gift card check failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check this account for incoming gift cards. Try again before removing it.'**
  String get accountsRemoveGiftCardsCheckFailed;

  /// [security] Body of the mobile remove-account sheet when that account has an active Ironwood migration. Removal deletes the account's local data.
  ///
  /// In en, this message translates to:
  /// **'This account\'s migration will no longer continue in Vizor. Transactions already submitted to the Zcash network may still complete. After re-importing, let the account fully sync before starting migration again.'**
  String get accountsRemoveMigrationBody;

  /// [security] Body of the desktop remove-account confirmation dialog. Two lines; removal is irreversible.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove this account? This action can\'t be reverted.\nYou will have to re-import your account.'**
  String get accountsRemoveModalBody;

  /// [security] Error under the password field of the desktop remove-account dialog when the password check itself failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your password. Please try again.'**
  String get accountsRemovePasswordCheckFailed;

  /// [security] Placeholder of the wallet password field in the desktop remove-account dialog.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get accountsRemovePasswordHint;

  /// [security] Error under the password field of the desktop remove-account dialog when the password is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Please try again.'**
  String get accountsRemovePasswordIncorrect;

  /// [security] Label of the wallet password field in the desktop remove-account dialog.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get accountsRemovePasswordLabel;

  /// Label of the confirm button in the desktop remove-account dialog while sync is stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopping sync...'**
  String get accountsRemoveStoppingSync;

  /// Message in the desktop remove-account dialog when the pending-swap check failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check this account for active swaps. Try again before removing it.'**
  String get accountsRemoveSwapsCheckFailed;

  /// [security] Label of the confirm button in the desktop remove-account dialog while the account is removed.
  ///
  /// In en, this message translates to:
  /// **'Removing account...'**
  String get accountsRemoving;

  /// [security] Body of the mobile reset confirmation sheet shown when the last account is removed. Resetting deletes all local wallet data irreversibly.
  ///
  /// In en, this message translates to:
  /// **'Resetting Vizor deletes every account and all local wallet data. Make sure you can re-import your accounts before continuing.'**
  String get accountsResetBody;

  /// [security] Error in the desktop remove-account dialog when resetting the whole wallet failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset Vizor.'**
  String get accountsResetFailed;

  /// [security] Toast on the mobile Accounts screen when resetting the whole wallet failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset Vizor'**
  String get accountsResetFailedToast;

  /// [security] Body of the mobile reset confirmation sheet when an Ironwood migration is active. Resetting deletes all local wallet data irreversibly.
  ///
  /// In en, this message translates to:
  /// **'Resetting Vizor stops migrations on this device and deletes every account and all local wallet data. Transactions already submitted to the Zcash network may still complete. After re-importing, let each account fully sync before starting migration again.'**
  String get accountsResetMigrationBody;

  /// [security] Body of the desktop dialog for removing the last account, which resets the whole app. Three lines; the last says the deletion is irreversible.
  ///
  /// In en, this message translates to:
  /// **'Removing this account will completely reset the Vizor app. This means deleting all accounts and requiring you to import accounts again.\nUnshared gift card links will also be permanently lost.\nThis cannot be undone.'**
  String get accountsResetModalBody;

  /// [security] Destructive button that deletes every account and all local wallet data.
  ///
  /// In en, this message translates to:
  /// **'Reset Vizor'**
  String get accountsResetVizor;

  /// [security] Label of the confirm button in the desktop remove-account dialog while the wallet is reset.
  ///
  /// In en, this message translates to:
  /// **'Resetting...'**
  String get accountsResetting;

  /// Button in the mobile edit-account sheet that saves the name and picture.
  ///
  /// In en, this message translates to:
  /// **'Save edits'**
  String get accountsSaveEdits;

  /// Toast on the mobile Accounts screen when saving name or picture edits failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the account changes'**
  String get accountsSaveFailed;

  /// Title of the profile picture picker.
  ///
  /// In en, this message translates to:
  /// **'Select profile picture'**
  String get accountsSelectProfilePicture;

  /// Toast on the Accounts screen when sending to an account's address could not be started.
  ///
  /// In en, this message translates to:
  /// **'Send couldn\'t be started'**
  String get accountsSendFailed;

  /// Account menu item that starts a send to that account's address.
  ///
  /// In en, this message translates to:
  /// **'Send ZEC'**
  String get accountsSendZec;

  /// Title of the Accounts screen that lists the wallet's accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsTitle;

  /// Button in the mobile profile picture picker that confirms the selected picture.
  ///
  /// In en, this message translates to:
  /// **'Update picture'**
  String get accountsUpdatePicture;

  /// [security] Account menu item that shows the account's secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'View secret phrase'**
  String get accountsViewSecretPhrase;

  /// [security] Account menu item that shows the account's viewing key.
  ///
  /// In en, this message translates to:
  /// **'View viewing key'**
  String get accountsViewViewingKey;

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

  /// Empty-state title on Home when the wallet has no transactions.
  ///
  /// In en, this message translates to:
  /// **'No activity, yet...'**
  String get homeActivityEmpty;

  /// Hint under the desktop Home empty-state title; tx is short for transaction.
  ///
  /// In en, this message translates to:
  /// **'How about running your first ZEC tx?'**
  String get homeActivityEmptyHint;

  /// Two-line hint under the mobile Home empty-state title; tx is short for transaction.
  ///
  /// In en, this message translates to:
  /// **'How about running your\nfirst ZEC tx?'**
  String get homeActivityEmptyHintMobile;

  /// Screen-reader label of the Home recent-activity list while it loads.
  ///
  /// In en, this message translates to:
  /// **'Loading activity'**
  String get homeActivityLoading;

  /// Empty-state title on Home when the activity list could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Unable to load activity.'**
  String get homeActivityUnavailable;

  /// [security] Two-line subtitle of the mobile Home backup reminder card; the second line marks it as the last setup step.
  ///
  /// In en, this message translates to:
  /// **'Back up your secret passphrase\nLast step'**
  String get homeBackupSubtitle;

  /// [security] Title of the mobile Home card that reminds the user to back up their secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Secure your wallet'**
  String get homeBackupTitle;

  /// Action on a desktop Home notice that hides the notice.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get homeDismiss;

  /// Subtitle of the mobile Home Zcash introduction card.
  ///
  /// In en, this message translates to:
  /// **'Privacy, address types, and what to expect'**
  String get homeEducationSubtitle;

  /// Title of the mobile Home card that opens the Zcash introduction.
  ///
  /// In en, this message translates to:
  /// **'Learn about Zcash'**
  String get homeEducationTitle;

  /// Body of the mobile Home import-progress screen asking the user to keep the app open.
  ///
  /// In en, this message translates to:
  /// **'Hang tight ... It might take some time. Keep Vizor open & running.'**
  String get homeImportingBodyMobile;

  /// Two-line detail on desktop Home while an imported wallet scans and the account has no name.
  ///
  /// In en, this message translates to:
  /// **'It might take some time.\nKeep Vizor open & running.'**
  String get homeImportingDetail;

  /// Two-line detail on desktop Home while an imported account scans. {name} is the account name entered by the user.
  ///
  /// In en, this message translates to:
  /// **'Importing {name}\nKeep Vizor open & running.'**
  String homeImportingDetailNamed(String name);

  /// Two-line title on desktop Home while an imported wallet scans the chain.
  ///
  /// In en, this message translates to:
  /// **'We\'re importing\nyour wallet...'**
  String get homeImportingTitle;

  /// Title of the mobile Home screen while an imported wallet is scanning the chain.
  ///
  /// In en, this message translates to:
  /// **'We\'re importing your wallet...'**
  String get homeImportingTitleMobile;

  /// Body of the keep-awake sheet explaining why the screen should stay on during sync.
  ///
  /// In en, this message translates to:
  /// **'Your phone pauses syncing when screen is off. This allows sync to finish faster.'**
  String get homeKeepAwakeBody;

  /// Button in the keep-awake sheet that turns on the keep-screen-awake option.
  ///
  /// In en, this message translates to:
  /// **'Keep screen awake'**
  String get homeKeepAwakeEnable;

  /// Ghost button in the keep-awake sheet that dismisses it without turning the option on.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get homeKeepAwakeLater;

  /// Bullet in the keep-awake sheet: the app still locks after one idle minute while sync continues.
  ///
  /// In en, this message translates to:
  /// **'The app locks after 1 minute of inactivity. Syncing continues behind the lock.'**
  String get homeKeepAwakeLockNote;

  /// Bullet in the keep-awake sheet saying the choice can be changed later in Settings.
  ///
  /// In en, this message translates to:
  /// **'You can change this anytime in the Settings.'**
  String get homeKeepAwakeSettingsNote;

  /// Title of the mobile Home sheet that offers to keep the screen awake while the wallet syncs.
  ///
  /// In en, this message translates to:
  /// **'Stay awake to sync?'**
  String get homeKeepAwakeTitle;

  /// Status label of the Ledger shield failure panel after an error.
  ///
  /// In en, this message translates to:
  /// **'Action needed'**
  String get homeLedgerActionNeeded;

  /// Ledger shield dialog error when the device refused a later round; earlier rounds were already broadcast.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger couldn’t accept this approval. Earlier approvals were already sent.'**
  String get homeLedgerApprovalNotAccepted;

  /// Warning on the Ledger shield dialog when the transaction was broadcast but not saved; retrying could send it twice.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction reached the network but was not stored locally. Do not try again until sync confirms it.'**
  String get homeLedgerBroadcastNotStored;

  /// Warning on the Ledger shield dialog when the broadcast outcome is unknown.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction may have reached the network. Check activity before trying again.'**
  String get homeLedgerBroadcastUnknown;

  /// Screen-reader label of the close button on the mobile Ledger shield panel while shielding can still be cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancel shielding'**
  String get homeLedgerCancelShielding;

  /// Ledger shield dialog message when the user switched account or network while shielding was in progress.
  ///
  /// In en, this message translates to:
  /// **'The selected account or network changed. Return to your wallet.'**
  String get homeLedgerContextChanged;

  /// Status label of the Ledger shield failure panel when shielding paused with funds still unshielded.
  ///
  /// In en, this message translates to:
  /// **'Inputs remaining'**
  String get homeLedgerInputsRemaining;

  /// Ledger shield dialog message when nothing was shielded because no transparent funds can be spent.
  ///
  /// In en, this message translates to:
  /// **'No spendable transparent funds remain. Return to your wallet.'**
  String get homeLedgerNoFundsRemain;

  /// Ledger shield dialog error when the transaction involves Sapling, which the Ledger preview app cannot sign.
  ///
  /// In en, this message translates to:
  /// **'This Ledger preview does not support Sapling inputs or outputs.'**
  String get homeLedgerNoSapling;

  /// Ledger shield dialog message when the remaining transparent funds are too small to shield further.
  ///
  /// In en, this message translates to:
  /// **'The remaining funds are below the shielding threshold.'**
  String get homeLedgerPausedBelowThreshold;

  /// Title of the Ledger shield failure panel when shielding stopped early without an error.
  ///
  /// In en, this message translates to:
  /// **'Shielding paused'**
  String get homeLedgerPausedTitle;

  /// Ledger shield dialog message when shielding was paused because the wallet is changing accounts or resetting.
  ///
  /// In en, this message translates to:
  /// **'Shielding paused while wallet changes finish. Return to your wallet.'**
  String get homeLedgerPausedWalletChanges;

  /// Ledger shield dialog error when the user rejected the transaction on the device.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction was rejected on your Ledger.'**
  String get homeLedgerRejected;

  /// Notice on the desktop Ledger shield dialog when shielding needs several approvals.
  ///
  /// In en, this message translates to:
  /// **'Each approval creates a separate transaction with its own network fee.'**
  String get homeLedgerRoundFeeNotice;

  /// Ledger shield dialog message after a round was sent and the rest is too small to shield. {round} is the round number.
  ///
  /// In en, this message translates to:
  /// **'Round {round} was sent. The remaining funds are below the shielding threshold.'**
  String homeLedgerRoundSentBelowThreshold(int round);

  /// Ledger shield dialog message after a round was sent but the wallet has not yet shown that inputs were spent. {round} is the round number.
  ///
  /// In en, this message translates to:
  /// **'Round {round} was sent, but no reduction in spendable inputs could be confirmed. Wait for sync before shielding again.'**
  String homeLedgerRoundSentNoReduction(int round);

  /// Ledger shield dialog message. Shielding runs in rounds, one Ledger approval each; {round} is the number of the round that was just sent.
  ///
  /// In en, this message translates to:
  /// **'Round {round} was sent, but the remaining funds could not be checked. Return to your wallet and try again after sync.'**
  String homeLedgerRoundSentUnchecked(int round);

  /// Title of the mobile Ledger shield screen while waiting for the user to approve on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Shield with Ledger'**
  String get homeLedgerShieldTitle;

  /// Generic error on the Ledger shield dialog.
  ///
  /// In en, this message translates to:
  /// **'Ledger shielding could not be completed.'**
  String get homeLedgerShieldingFailed;

  /// Title of the Ledger shield failure panel after an error.
  ///
  /// In en, this message translates to:
  /// **'Ledger signing failed'**
  String get homeLedgerSigningFailedTitle;

  /// Error text on desktop Home when the wallet failed to load. {details} is the technical error text, passed through untranslated.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again in a moment.\n\nDetails: {details}'**
  String homeLoadFailed(String details);

  /// Desktop Home button that starts the Ironwood pool migration.
  ///
  /// In en, this message translates to:
  /// **'Migrate to Ironwood'**
  String get homeMigrateToIronwood;

  /// Pill on the mobile Home balance card shown when the Ironwood migration needs the user to act.
  ///
  /// In en, this message translates to:
  /// **'Migration required'**
  String get homeMigrationRequired;

  /// Title-case heading of the desktop Home balance card when the Ironwood migration needs the user to act.
  ///
  /// In en, this message translates to:
  /// **'Migration Required'**
  String get homeMigrationRequiredTitle;

  /// Desktop Home migration button text. {amount} is the formatted amount still being moved, such as 1.5 ZEC.
  ///
  /// In en, this message translates to:
  /// **'{amount} still migrating'**
  String homeMigrationStillMigrating(String amount);

  /// Desktop Home migration button text after a network upgrade stopped the Ironwood migration.
  ///
  /// In en, this message translates to:
  /// **'Migration stopped by network upgrade'**
  String get homeMigrationStoppedByUpgrade;

  /// Desktop Home migration button text while a migration transaction waits for confirmations.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation...'**
  String get homeMigrationWaitingConfirmation;

  /// Body of the first NU7 announcement point; s means seconds.
  ///
  /// In en, this message translates to:
  /// **'Average wait for first confirmation drops from ~75s to ~25s.'**
  String get homeNu7FasterBody;

  /// Heading of the first NU7 announcement point: blocks arrive about three times as often.
  ///
  /// In en, this message translates to:
  /// **'~3× faster blocks'**
  String get homeNu7FasterTitle;

  /// Button that dismisses the NU7 announcement.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get homeNu7GotIt;

  /// Body of the second NU7 announcement point.
  ///
  /// In en, this message translates to:
  /// **'Network can handle 2.3x more shielded transactions per block.'**
  String get homeNu7ThroughputBody;

  /// Heading of the second NU7 announcement point. See the glossary entry for shielded.
  ///
  /// In en, this message translates to:
  /// **'Higher shielded throughput'**
  String get homeNu7ThroughputTitle;

  /// Two-line title of the announcement shown after the NU7 network upgrade activates.
  ///
  /// In en, this message translates to:
  /// **'NU7 Update is live.\nWhat does this mean?'**
  String get homeNu7Title;

  /// [security] Notice on desktop Home when the outcome of an earlier wallet password change could not be confirmed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify the previous password change. Try again or restart Vizor.'**
  String get homePasswordChangeUnverified;

  /// Screen-reader and tooltip label of the icon-only Pay button on desktop Home.
  ///
  /// In en, this message translates to:
  /// **'Pay in USDC'**
  String get homePayInUsdc;

  /// Home action button that opens the receive screen.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get homeReceive;

  /// Mobile Home button shown instead of Send/Receive while the wallet has no funds; opens the receive screen.
  ///
  /// In en, this message translates to:
  /// **'Receive your first ZEC'**
  String get homeReceiveFirstZec;

  /// Heading above the recent transactions list on Home.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get homeRecentActivity;

  /// Link next to the Home recent-activity heading that opens the full activity list.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get homeSeeAll;

  /// Home action button that opens the send screen.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get homeSend;

  /// [security] Card text in the desktop Home setup carousel reminding the user to back up their secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Back up your wallet. Keep your secret passphrase safe.'**
  String get homeSetupBackupMessage;

  /// Screen-reader name of the desktop Home carousel with wallet setup reminders.
  ///
  /// In en, this message translates to:
  /// **'Wallet setup'**
  String get homeSetupCarouselLabel;

  /// Lowercase name of the Home wallet-setup carousel, used in the screen-reader label of its page dots (Show wallet setup banner 1 of 2).
  ///
  /// In en, this message translates to:
  /// **'wallet setup banner'**
  String get homeSetupCarouselName;

  /// Card text in the desktop Home setup carousel that opens the Zcash introduction.
  ///
  /// In en, this message translates to:
  /// **'Learn how Zcash protects your privacy and which address to use.'**
  String get homeSetupEducationMessage;

  /// Label of the mobile Home button that shields the transparent balance.
  ///
  /// In en, this message translates to:
  /// **'Shield'**
  String get homeShield;

  /// Instruction in the desktop Keystone shield dialog; Get Signature is the name of the button next to it.
  ///
  /// In en, this message translates to:
  /// **'After you scanned, click Get Signature.'**
  String get homeShieldAfterScan;

  /// Title of the mobile Keystone shield screen while the transaction QR is shown for the Keystone to scan.
  ///
  /// In en, this message translates to:
  /// **'Approve with Keystone'**
  String get homeShieldApproveTitle;

  /// Title of the mobile Keystone shield screen when shielding failed or ended with a warning.
  ///
  /// In en, this message translates to:
  /// **'Shielding needs attention'**
  String get homeShieldAttentionTitle;

  /// Button on the shield result screens that returns to the wallet.
  ///
  /// In en, this message translates to:
  /// **'Back to wallet'**
  String get homeShieldBackToWallet;

  /// Button on the desktop Keystone shield dialog that closes it after a failure or warning.
  ///
  /// In en, this message translates to:
  /// **'Back to Wallet'**
  String get homeShieldBackToWalletTitleCase;

  /// Title of the mobile shield screens that move the transparent balance into a shielded pool.
  ///
  /// In en, this message translates to:
  /// **'Transparent Balance'**
  String get homeShieldBalanceTitle;

  /// Warning on the Keystone shield dialog when the transaction was broadcast but not saved in the wallet; retrying could send it twice.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.'**
  String get homeShieldBroadcastNotStored;

  /// Warning on the Keystone shield dialog when broadcasting timed out and the outcome is unknown.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction may have reached the network, but confirmation timed out. Check activity before trying again.'**
  String get homeShieldBroadcastUnknown;

  /// Title of the desktop Keystone shield dialog while the signed transaction is sent; tx is short for transaction.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting shield tx'**
  String get homeShieldBroadcastingTitle;

  /// Message over the mobile Keystone scanner when camera permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access in Settings to scan Keystone signatures.'**
  String get homeShieldCameraDenied;

  /// Message over the mobile Keystone scanner when the camera cannot start.
  ///
  /// In en, this message translates to:
  /// **'The camera is unavailable right now.'**
  String get homeShieldCameraUnavailable;

  /// Error on the shield screens when cancelling could not release the pending work.
  ///
  /// In en, this message translates to:
  /// **'Could not finish cancelling. Please try again.'**
  String get homeShieldCancelFailed;

  /// Message on the mobile Keystone shield screen after the user cancelled shielding.
  ///
  /// In en, this message translates to:
  /// **'Shielding was cancelled.'**
  String get homeShieldCancelled;

  /// Error on the desktop Keystone shield dialog when the user declined the proving parameter download.
  ///
  /// In en, this message translates to:
  /// **'Shielding was cancelled before proving parameters were downloaded.'**
  String get homeShieldCancelledBeforeParams;

  /// Button on the mobile shield screen that finishes the animation after shielding succeeded.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get homeShieldComplete;

  /// Label of the mobile slide-to-shield control; the user drags the handle to confirm shielding.
  ///
  /// In en, this message translates to:
  /// **'Drag to shield'**
  String get homeShieldDrag;

  /// Error on the Keystone and Ledger shield dialogs when sending the transaction to the network failed.
  ///
  /// In en, this message translates to:
  /// **'Shield transaction could not be broadcast.'**
  String get homeShieldErrorBroadcast;

  /// Generic error on the desktop Keystone shield dialog.
  ///
  /// In en, this message translates to:
  /// **'Shield balance failed. Please try again.'**
  String get homeShieldErrorGeneric;

  /// Error on the mobile Keystone shield screen when the signed transaction could not be extracted.
  ///
  /// In en, this message translates to:
  /// **'Shield transaction could not be finalized.'**
  String get homeShieldErrorNotFinalized;

  /// Error on the Keystone shield screens when the Sapling proving parameters failed to download or load.
  ///
  /// In en, this message translates to:
  /// **'Required proving parameters could not be prepared.'**
  String get homeShieldErrorProvingParams;

  /// Error on the Keystone shield screens when the scanned signature could not be added to the transaction.
  ///
  /// In en, this message translates to:
  /// **'Keystone signature could not be applied.'**
  String get homeShieldErrorSignatureNotApplied;

  /// Error on the mobile Keystone shield screen when the signing request was not ready when the user started scanning.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared.'**
  String get homeShieldErrorSigningNotPrepared;

  /// Error on the Keystone and Ledger shield dialogs when the wallet is not synced yet.
  ///
  /// In en, this message translates to:
  /// **'Sync the wallet before shielding transparent balance.'**
  String get homeShieldErrorSyncFirst;

  /// Error on the Keystone and Ledger shield dialogs when the transparent balance would not cover the network fee.
  ///
  /// In en, this message translates to:
  /// **'Transparent balance is too small to shield after fees.'**
  String get homeShieldErrorTooSmall;

  /// Title of the mobile software-account shield screen when shielding failed.
  ///
  /// In en, this message translates to:
  /// **'Shielding could not be completed'**
  String get homeShieldFailedTitle;

  /// Button in the desktop Keystone shield dialog that opens the camera to read the signature QR.
  ///
  /// In en, this message translates to:
  /// **'Get Signature'**
  String get homeShieldGetSignature;

  /// Instruction in the desktop Keystone shield dialog while the transaction is being sent.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open while the transaction is sent.'**
  String get homeShieldKeepOpen;

  /// Screen-reader label of the transaction QR code the Keystone device scans.
  ///
  /// In en, this message translates to:
  /// **'Keystone transaction QR'**
  String get homeShieldKeystoneQrSemantics;

  /// Mobile shield footer button that moves from the transaction QR to scanning the Keystone signature.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get homeShieldNextStep;

  /// Error notice on desktop Home when Shield is pressed but no account is selected.
  ///
  /// In en, this message translates to:
  /// **'No active account.'**
  String get homeShieldNoActiveAccount;

  /// Label of the desktop Home button that shields the transparent balance.
  ///
  /// In en, this message translates to:
  /// **'Shield now'**
  String get homeShieldNow;

  /// Title of the mobile software-account shield screen when the shielding transaction is queued for retry.
  ///
  /// In en, this message translates to:
  /// **'Shielding queued'**
  String get homeShieldQueuedTitle;

  /// Status text on the mobile Keystone scanner while the scanned signature QR is decoded.
  ///
  /// In en, this message translates to:
  /// **'Reading signature…'**
  String get homeShieldReadingSignature;

  /// Button in the desktop Keystone shield dialog that cancels shielding.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get homeShieldReject;

  /// Hint under the mobile Keystone scanner when the scanned QR is not a valid signature.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone signature.'**
  String get homeShieldScanDecodeFailed;

  /// Hint under the mobile Keystone scanner when a frame could not be read.
  ///
  /// In en, this message translates to:
  /// **'Keep the QR code steady and fully visible.'**
  String get homeShieldScanHold;

  /// Title of the mobile Keystone shield screen while the camera scans the signature QR.
  ///
  /// In en, this message translates to:
  /// **'Scan your Keystone signature'**
  String get homeShieldScanTitle;

  /// Subtitle of the desktop Keystone shield dialog above the transaction QR.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code to sign'**
  String get homeShieldScanToSign;

  /// Hint under the mobile Keystone scanner when the wrong kind of QR was scanned.
  ///
  /// In en, this message translates to:
  /// **'Open the signed shield QR on Keystone, then scan again.'**
  String get homeShieldScanWrongQr;

  /// Status text on the mobile Keystone scanner while an animated signature QR is read. {progress} is a whole percentage.
  ///
  /// In en, this message translates to:
  /// **'Scanning… {progress}%'**
  String homeShieldScanning(int progress);

  /// Mobile shield footer button that shows the transaction QR code for the Keystone to scan.
  ///
  /// In en, this message translates to:
  /// **'Show QR'**
  String get homeShieldShowQr;

  /// Title of the desktop Keystone shield dialog while the user signs on the device; tx is short for transaction.
  ///
  /// In en, this message translates to:
  /// **'Sign tx on your Keystone'**
  String get homeShieldSignTitle;

  /// Warning on the Keystone and Ledger shield dialogs when the outcome of the broadcast is unclear.
  ///
  /// In en, this message translates to:
  /// **'The shield transaction status is uncertain. Check activity before trying again.'**
  String get homeShieldStatusUncertain;

  /// Subtitle of the desktop Keystone shield dialog while the transaction is being sent.
  ///
  /// In en, this message translates to:
  /// **'Submitting transaction'**
  String get homeShieldSubmitting;

  /// Title of the mobile shield screens after shielding completed.
  ///
  /// In en, this message translates to:
  /// **'Shielded successfully'**
  String get homeShieldSucceededTitle;

  /// Screen-reader label of the flashlight button on the mobile Keystone scanner.
  ///
  /// In en, this message translates to:
  /// **'Toggle flashlight'**
  String get homeShieldToggleFlashlight;

  /// Button on the shield screens that retries the failed step.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get homeShieldTryAgain;

  /// Label on the Home balance card for the shielded balance. See the glossary entry for shielded.
  ///
  /// In en, this message translates to:
  /// **'Shielded balance'**
  String get homeShieldedBalance;

  /// Status text on the mobile shield screens while the transparent balance is being shielded.
  ///
  /// In en, this message translates to:
  /// **'Shielding your balance…'**
  String get homeShieldingBalance;

  /// Label of the mobile Home shield button while shielding is in progress.
  ///
  /// In en, this message translates to:
  /// **'Shielding...'**
  String get homeShieldingProgress;

  /// Row on the mobile Home card showing the transparent balance. {balance} is a formatted amount such as 0.5 ZEC.
  ///
  /// In en, this message translates to:
  /// **'Transparent: {balance}'**
  String homeTransparentBalance(String balance);

  /// Screen-reader label of the Home coinholder voting card.
  ///
  /// In en, this message translates to:
  /// **'Open coinholder voting'**
  String get homeVotingSemantics;

  /// Subtitle of the Home coinholder voting card.
  ///
  /// In en, this message translates to:
  /// **'Help to shape the network'**
  String get homeVotingSubtitle;

  /// Title of the Home card that opens coinholder voting.
  ///
  /// In en, this message translates to:
  /// **'Coinholder voting'**
  String get homeVotingTitle;

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

  /// Count of accounts found on the scanned Keystone QR, shown above the account list.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account found} other{{count} accounts found}}'**
  String keystoneAccountsFound(int count);

  /// Back-link text on the Keystone how-to-connect screen that returns to the welcome screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get keystoneBackWelcome;

  /// Placeholder of the date field before a date is picked; shows the month/day/year format.
  ///
  /// In en, this message translates to:
  /// **'mm/dd/yyyy'**
  String get keystoneBirthdayDatePlaceholder;

  /// Inline error on the Keystone wallet birthday screen when the chosen date cannot be converted to a block height.
  ///
  /// In en, this message translates to:
  /// **'Could not estimate the wallet birthday height.'**
  String get keystoneBirthdayEstimateError;

  /// Disabled primary button label while the block height for the chosen date is being estimated.
  ///
  /// In en, this message translates to:
  /// **'Estimating...'**
  String get keystoneBirthdayEstimating;

  /// Hint text of the block height input field.
  ///
  /// In en, this message translates to:
  /// **'Block height'**
  String get keystoneBirthdayHeightHint;

  /// Inline error under the block height field when the typed number is not a usable block height.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a valid block height.'**
  String get keystoneBirthdayInvalidHeight;

  /// Inline error on the Keystone wallet birthday screen when the data needed to convert dates to block heights cannot be loaded.
  ///
  /// In en, this message translates to:
  /// **'Could not load wallet birthday metadata.'**
  String get keystoneBirthdayMetadataError;

  /// Disabled primary button label while Vizor stops a running sync before importing the Keystone account.
  ///
  /// In en, this message translates to:
  /// **'Stop syncing...'**
  String get keystoneBirthdayStopSyncing;

  /// Subtitle under the wallet birthday heading explaining why the date is asked.
  ///
  /// In en, this message translates to:
  /// **'It helps us import your wallet faster.'**
  String get keystoneBirthdaySubtitle;

  /// Tab label to enter the wallet birthday block height directly.
  ///
  /// In en, this message translates to:
  /// **'Enter the block height'**
  String get keystoneBirthdayTabBlockHeight;

  /// Tab label to enter the wallet creation date.
  ///
  /// In en, this message translates to:
  /// **'Enter the date'**
  String get keystoneBirthdayTabDate;

  /// Heading of the Keystone wallet birthday screen.
  ///
  /// In en, this message translates to:
  /// **'Around when did you create your wallet?'**
  String get keystoneBirthdayTitle;

  /// Ghost button on the wallet birthday screen for users who do not know when the wallet was created; opens a confirmation.
  ///
  /// In en, this message translates to:
  /// **'I can’t remember'**
  String get keystoneBirthdayUnknown;

  /// Two-line description under the camera denied title. Keep the line break; each line is shown on its own line without wrapping, so keep both lines short.
  ///
  /// In en, this message translates to:
  /// **'Request again, or enable manually\nin the System settings.'**
  String get keystoneCameraDeniedBody;

  /// Title of the mobile Keystone scan card when the camera permission was denied.
  ///
  /// In en, this message translates to:
  /// **'You\'ve denied camera access'**
  String get keystoneCameraDeniedTitle;

  /// Two-line description under the enable camera access title. Keep the line break; each line is shown on its own line without wrapping, so keep both lines short.
  ///
  /// In en, this message translates to:
  /// **'A camera is required to connect Keystone.\nYou can revert this in settings anytime later.'**
  String get keystoneCameraEnableBody;

  /// Title of the mobile Keystone scan card while camera permission is being requested.
  ///
  /// In en, this message translates to:
  /// **'Enable camera access'**
  String get keystoneCameraEnableTitle;

  /// Button on the mobile Keystone scan card that asks for camera permission again.
  ///
  /// In en, this message translates to:
  /// **'Request again'**
  String get keystoneCameraRequestAgain;

  /// Two-line description under the camera restricted title. Keep the line break; each line is shown on its own line without wrapping, so keep both lines short.
  ///
  /// In en, this message translates to:
  /// **'Screen Time or device management\nis blocking the camera.'**
  String get keystoneCameraRestrictedBody;

  /// Title of the mobile Keystone scan card when camera access is restricted by the system.
  ///
  /// In en, this message translates to:
  /// **'Camera access is restricted'**
  String get keystoneCameraRestrictedTitle;

  /// Button on the mobile Keystone scan card that retries opening the camera.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get keystoneCameraTryAgain;

  /// Two-line description under the camera unavailable title. Keep the line break; each line is shown on its own line without wrapping, so keep both lines short.
  ///
  /// In en, this message translates to:
  /// **'Keystone import uses camera QR scanning only.\nConnect a camera and try again.'**
  String get keystoneCameraUnavailableBody;

  /// Title of the mobile Keystone scan card when no camera is available.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get keystoneCameraUnavailableTitle;

  /// Button that confirms the chosen Keystone account and continues the import.
  ///
  /// In en, this message translates to:
  /// **'Confirm selection'**
  String get keystoneConfirmSelection;

  /// Heading of the screen explaining how to connect a Keystone hardware wallet to Vizor.
  ///
  /// In en, this message translates to:
  /// **'Connect Keystone'**
  String get keystoneConnectTitle;

  /// Primary button that continues to the next step of Keystone import.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get keystoneContinue;

  /// Sentence ending in a trailing space, followed by an inline link button labelled 'link' that opens the firmware download page. Keep the trailing space.
  ///
  /// In en, this message translates to:
  /// **'Make sure your Keystone is on the latest Cypherpunk firmware. '**
  String get keystoneFirmwareBody;

  /// Screen-reader label of the inline firmware link button.
  ///
  /// In en, this message translates to:
  /// **'Download Keystone firmware'**
  String get keystoneFirmwareDownloadSemantics;

  /// Visible text of the small inline button that opens the Keystone firmware download page; appears right after the firmware sentence.
  ///
  /// In en, this message translates to:
  /// **'link'**
  String get keystoneFirmwareLinkLabel;

  /// Title of instruction step 1 on the Keystone how-to-connect screen. The step number is added by the app before this text.
  ///
  /// In en, this message translates to:
  /// **'Check Keystone firmware'**
  String get keystoneFirmwareTitle;

  /// Primary button on the Keystone how-to-connect screen; continues to the QR scan step once the user has followed the instructions.
  ///
  /// In en, this message translates to:
  /// **'I\'m ready now'**
  String get keystoneImReadyNow;

  /// Disabled primary button label while the Keystone account is being imported.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get keystoneImporting;

  /// Heading of the group of steps the user performs in the Vizor app.
  ///
  /// In en, this message translates to:
  /// **'On Vizor'**
  String get keystoneOnVizor;

  /// Heading of the group of steps the user performs on the Keystone device itself.
  ///
  /// In en, this message translates to:
  /// **'On your Keystone'**
  String get keystoneOnYourKeystone;

  /// Subtitle under the Keystone connect, scan and select-account headings, asking the user to get their Keystone device ready.
  ///
  /// In en, this message translates to:
  /// **'Prepare your Keystone wallet'**
  String get keystonePrepareSubtitle;

  /// Title of instruction step 2 on the Keystone how-to-connect screen. The step number is added by the app before this text.
  ///
  /// In en, this message translates to:
  /// **'Prepare to connect'**
  String get keystonePrepareToConnectTitle;

  /// Message shown instead of the scanner when no camera is available on this device.
  ///
  /// In en, this message translates to:
  /// **'Keystone import uses camera QR scanning only. Connect a camera and try again.'**
  String get keystoneScanCameraRequired;

  /// Caption under the camera view of the mobile Keystone QR scanner.
  ///
  /// In en, this message translates to:
  /// **'Scan the Keystone account QR'**
  String get keystoneScanCaption;

  /// Error under the Keystone QR scanner when the scanned QR cannot be decoded as a Zcash account.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone Zcash account.'**
  String get keystoneScanDecodeFailed;

  /// Scanner hint shown while a QR code cannot be read yet.
  ///
  /// In en, this message translates to:
  /// **'Keep the QR code steady and fully visible.'**
  String get keystoneScanKeepSteady;

  /// Error under the Keystone QR scanner when the scanned QR contains no Zcash accounts.
  ///
  /// In en, this message translates to:
  /// **'No Zcash accounts were found on this Keystone QR.'**
  String get keystoneScanNoAccounts;

  /// Scanner hint shown when the user scanned a QR of the wrong kind; tells them to open the Zcash account QR on the device.
  ///
  /// In en, this message translates to:
  /// **'Open the Zcash account QR on Keystone, then scan again.'**
  String get keystoneScanOpenAccountQr;

  /// Caption on the mobile Keystone scanner while an animated QR code is partially read. {progress} is a whole percentage from 1 to 99.
  ///
  /// In en, this message translates to:
  /// **'Scanning... {progress}%'**
  String keystoneScanProgress(int progress);

  /// Status text on the Keystone QR scanner while the scanned accounts are being decoded.
  ///
  /// In en, this message translates to:
  /// **'Reading accounts...'**
  String get keystoneScanReadingAccounts;

  /// Title of the Keystone QR scan screen and its sidebar step label; the user scans the account QR shown on the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get keystoneScanTitle;

  /// Heading of the screen where the user picks which Keystone account to import.
  ///
  /// In en, this message translates to:
  /// **'Select account'**
  String get keystoneSelectAccountTitle;

  /// Sidebar step label for customising the imported Keystone wallet (name and avatar).
  ///
  /// In en, this message translates to:
  /// **'Customise wallet'**
  String get keystoneStepCustomiseWallet;

  /// Sidebar step label and back-link text for the first Keystone onboarding step (how to connect the device). Title Case is intentional.
  ///
  /// In en, this message translates to:
  /// **'How to Connect'**
  String get keystoneStepHowToConnect;

  /// Device step: quotes the menu button (three dots) and the menu item 'Connect software wallet' shown on the Keystone device. Keep 'Connect software wallet' in English inside the translation because that is the label on the device screen.
  ///
  /// In en, this message translates to:
  /// **'Tap ••• (top right), then Connect software wallet.'**
  String get keystoneStepOpenSoftwareWallet;

  /// Step in the Vizor group: scan the animated QR code displayed on the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Scan the dynamic QR code on your Keystone.'**
  String get keystoneStepScanDynamicQr;

  /// Sidebar step label and back-link text for choosing which Keystone account to import. Title Case is intentional.
  ///
  /// In en, this message translates to:
  /// **'Select Account'**
  String get keystoneStepSelectAccount;

  /// Device step: pick Vizor (or ZODL) from the software wallet list shown on the Keystone device. Vizor and ZODL are wallet names and stay in Latin script.
  ///
  /// In en, this message translates to:
  /// **'Select Vizor (or ZODL)'**
  String get keystoneStepSelectVizor;

  /// Sidebar step label for setting the wallet password during Keystone import. Title Case is intentional.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get keystoneStepSetPassword;

  /// Sidebar step label and back-link text for the wallet birthday (block height) step during Keystone import. Title Case is intentional.
  ///
  /// In en, this message translates to:
  /// **'Wallet Birthday Height'**
  String get keystoneStepWalletBirthdayHeight;

  /// Language picker option that follows the device language. Shown in Settings > System > Language and the Welcome language picker.
  ///
  /// In en, this message translates to:
  /// **'System ({language})'**
  String languageSystemOption(String language);

  /// Helper text in the advanced options explaining the Ledger account index field.
  ///
  /// In en, this message translates to:
  /// **'Keep 0 unless you used a different index for this Ledger account.'**
  String get ledgerAccountIndexHint;

  /// Label of the account index input in the mobile advanced options. Keep the range 0–100.
  ///
  /// In en, this message translates to:
  /// **'Account index (0–100)'**
  String get ledgerAccountIndexLabel;

  /// [security] Note under the Add account step explaining that the Ledger account can only be viewed in Vizor; spending still requires device approval.
  ///
  /// In en, this message translates to:
  /// **'View your balance and activity in Vizor. Transactions still need approval on Ledger.'**
  String get ledgerAddAccountNote;

  /// Title of the mobile sheet that finds a Ledger device and adds its account.
  ///
  /// In en, this message translates to:
  /// **'Add Ledger account'**
  String get ledgerAddAccountTitle;

  /// Label of the collapsible advanced options section on the Connect Ledger screen.
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get ledgerAdvancedOptions;

  /// Back-link text on the desktop Connect Ledger screen that returns to the add-account screen.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get ledgerBackAddAccount;

  /// Two-line note under the Connect Ledger form explaining that Vizor shows balance and activity while transactions are approved on the device. Keep the line break.
  ///
  /// In en, this message translates to:
  /// **'See your balance and activity in Vizor.\nApprove transactions on Ledger.'**
  String get ledgerBalanceActivityNote;

  /// Error in the desktop Bluetooth dialog when the user declined opening the Zcash app on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Opening Zcash was declined on Ledger. Try again when you’re ready.'**
  String get ledgerBleDeclinedOpen;

  /// [security] Error in the desktop Bluetooth dialog when the user declined sharing the viewing key on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Sharing was declined on Ledger. Try again when you’re ready.'**
  String get ledgerBleDeclinedShare;

  /// Error in the desktop Bluetooth dialog when reading the Ledger account failed over Bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not read this Ledger account. Try again.'**
  String get ledgerBleReadFailedTryAgain;

  /// [security] Error in the desktop dialog when reading the Ledger account over USB failed for an unknown reason; lists recovery steps.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not read this Ledger account. Reconnect Ledger with a USB cable, unlock it with your PIN, and open the Zcash app. Then try again.'**
  String get ledgerBleReadFailedUsb;

  /// Subtitle identifying that the picker is for a Bluetooth connection.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth connection'**
  String get ledgerBluetoothConnection;

  /// Error in the mobile device sheet when the Bluetooth permission was not granted.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission is required to find your Ledger. Allow it in Settings, then try again.'**
  String get ledgerBluetoothPermissionRequired;

  /// Error in the mobile Add Ledger account sheet when cancelling the Ledger request failed.
  ///
  /// In en, this message translates to:
  /// **'Could not finish cancelling. Try again.'**
  String get ledgerCancelFailed;

  /// Title of the desktop dialog while a running Ledger request is being cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelling request'**
  String get ledgerCancellingRequest;

  /// Status text in the mobile sheet while the Ledger request is being cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelling the Ledger request…'**
  String get ledgerCancellingTheRequest;

  /// Status text while Vizor checks the Bluetooth permission on desktop.
  ///
  /// In en, this message translates to:
  /// **'Checking Bluetooth access…'**
  String get ledgerCheckingBluetoothAccess;

  /// Back-link text in the desktop dialog that returns to the device picker.
  ///
  /// In en, this message translates to:
  /// **'Choose another Ledger'**
  String get ledgerChooseAnother;

  /// Error in the desktop Bluetooth dialog when closing the Ledger session failed.
  ///
  /// In en, this message translates to:
  /// **'Could not finish cleanup. Try again.'**
  String get ledgerCleanupFailed;

  /// Message asking the user to confirm on the Ledger device that the Zcash app may open. 'Zcash' is the app name on the device.
  ///
  /// In en, this message translates to:
  /// **'Confirm opening Zcash on Ledger.'**
  String get ledgerConfirmOpeningZcash;

  /// Heading, sidebar step, procedure step and button label for connecting a Ledger device; it is the name of the action, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger'**
  String get ledgerConnect;

  /// Subtitle under the Connect Ledger heading, asking the user to get their Ledger ready.
  ///
  /// In en, this message translates to:
  /// **'Prepare your Ledger wallet.'**
  String get ledgerConnectSubtitle;

  /// Step 2 of the Ledger preparation list for a USB connection (the number is added by the app).
  ///
  /// In en, this message translates to:
  /// **'Connect with a USB cable.'**
  String get ledgerConnectUsbCable;

  /// Label of a device row while connecting; {device} is the device name such as a Ledger model.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {device}'**
  String ledgerConnectingTo(String device);

  /// Button in the mobile device sheet that opens help for connecting a Ledger.
  ///
  /// In en, this message translates to:
  /// **'Connection help'**
  String get ledgerConnectionHelp;

  /// Title of the desktop dialog after connecting to the Ledger failed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect Ledger'**
  String get ledgerCouldNotConnect;

  /// Message shown under the error title when no more specific error text is available.
  ///
  /// In en, this message translates to:
  /// **'Try again.'**
  String get ledgerDiscoveryErrorFallback;

  /// Title of the error block in the mobile device sheet after the Ledger search or connection failed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to your Ledger'**
  String get ledgerDiscoveryErrorTitle;

  /// Fallback error in the mobile device sheet when the Ledger search failed for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not find Ledger devices. Try again.'**
  String get ledgerDiscoveryFailed;

  /// Step 2 of the Ledger preparation list for a Bluetooth connection (the number is added by the app).
  ///
  /// In en, this message translates to:
  /// **'Enable Bluetooth and keep Ledger nearby.'**
  String get ledgerEnableBluetoothNearby;

  /// Error when the Ledger account the user is adding already exists in the wallet.
  ///
  /// In en, this message translates to:
  /// **'This Ledger account is already in Vizor.'**
  String get ledgerErrorAlreadyAdded;

  /// Generic error in the mobile Add Ledger account sheet when reading the account failed.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not read this Ledger account. Check the connection and try again.'**
  String get ledgerErrorCannotReadCheckConnection;

  /// Generic error when reading the Ledger account failed. {instruction} is a full English sentence produced elsewhere, such as 'Open the Zcash app on your Ledger.'.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not read this Ledger account. {instruction} Then try again.'**
  String ledgerErrorCannotReadWithInstruction(String instruction);

  /// Error when the Ledger connection was lost. {instruction} is a full English sentence produced elsewhere, such as 'Open the Zcash app on your Ledger.'.
  ///
  /// In en, this message translates to:
  /// **'Connect and unlock your Ledger. {instruction}'**
  String ledgerErrorConnectAndUnlock(String instruction);

  /// Error when the Ledger is locked. {instruction} is a full English sentence produced elsewhere, such as 'Open the Zcash app on your Ledger.'.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Ledger. {instruction}'**
  String ledgerErrorUnlock(String instruction);

  /// [security] Error in the mobile Add Ledger account sheet after the user declined the viewing key request on the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'The viewing key request was declined on Ledger. Try again when you’re ready.'**
  String get ledgerErrorViewingKeyDeclined;

  /// [security] Error under the desktop Connect Ledger form after the user rejected the viewing key request on the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'The viewing-key request was rejected on your Ledger.'**
  String get ledgerErrorViewingKeyRejected;

  /// Title of the desktop Bluetooth device picker and label of the button that restarts the Bluetooth search.
  ///
  /// In en, this message translates to:
  /// **'Find Ledger'**
  String get ledgerFind;

  /// Button that goes back to the device search when the old Bluetooth pairing must be replaced.
  ///
  /// In en, this message translates to:
  /// **'Find my Ledger'**
  String get ledgerFindMyLedger;

  /// Note under the Open app step: do not close the named app on the Ledger. {appName} is the app name shown on the device, normally Zcash, and stays in Latin script.
  ///
  /// In en, this message translates to:
  /// **'Keep {appName} open.'**
  String ledgerKeepAppOpen(String appName);

  /// Status text while a Ledger request is being cancelled; the user must not unplug the device yet.
  ///
  /// In en, this message translates to:
  /// **'Keep Ledger connected until the current request is cancelled.'**
  String get ledgerKeepConnectedUntilCancelled;

  /// Status text in the mobile sheet while Vizor checks whether the Zcash app is open on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Keep Ledger connected while Vizor checks the app.'**
  String get ledgerKeepConnectedWhileChecking;

  /// Message under the first connection step in the desktop dialog.
  ///
  /// In en, this message translates to:
  /// **'Keep your Ledger nearby and unlocked, with Bluetooth turned on.'**
  String get ledgerKeepNearbyUnlocked;

  /// Note under the Open Zcash step: do not close the Zcash app on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Keep Zcash open.'**
  String get ledgerKeepZcashOpen;

  /// Hint shown while checking Bluetooth access on macOS.
  ///
  /// In en, this message translates to:
  /// **'macOS may ask for Bluetooth access. If prompted, allow access for Vizor.'**
  String get ledgerMacosBluetoothPrompt;

  /// Title of the status block when the search found no Ledger device.
  ///
  /// In en, this message translates to:
  /// **'No Ledger devices found'**
  String get ledgerNoDevicesFound;

  /// Message under the no devices found title.
  ///
  /// In en, this message translates to:
  /// **'Check that your Ledger is unlocked and try again.'**
  String get ledgerNoDevicesFoundHint;

  /// Message in the desktop device picker when the Bluetooth search found no Ledger.
  ///
  /// In en, this message translates to:
  /// **'No Ledger found. Unlock Ledger, enable Bluetooth and keep it nearby. Then search again.'**
  String get ledgerNoneFoundDesktop;

  /// Heading of the list of steps the user performs on the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'On your Ledger'**
  String get ledgerOnYourLedger;

  /// Error in the mobile connection help when the Bluetooth settings could not be opened automatically.
  ///
  /// In en, this message translates to:
  /// **'Open Bluetooth settings manually to remove the old pairing.'**
  String get ledgerOpenBluetoothSettingsManually;

  /// Instruction inserted into a USB error message: the user must open the Zcash app on the Ledger and retry.
  ///
  /// In en, this message translates to:
  /// **'Open the Zcash app, then try again.'**
  String get ledgerOpenZcashThenTryAgain;

  /// Status text while the desktop dialog returns to the connection options after stopping the search.
  ///
  /// In en, this message translates to:
  /// **'Returning to connection options…'**
  String get ledgerReturningToOptions;

  /// Button that restarts the search for Ledger devices when none were found.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get ledgerSearchAgain;

  /// Message under the searching title; the search may take a moment.
  ///
  /// In en, this message translates to:
  /// **'This can take a few seconds.'**
  String get ledgerSearchTakesAWhile;

  /// Title of the status block while the mobile sheet searches for Ledger devices.
  ///
  /// In en, this message translates to:
  /// **'Searching for Ledger devices…'**
  String get ledgerSearchingDevices;

  /// Status text while the desktop dialog searches for Ledger devices over Bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Searching for nearby Ledgers…'**
  String get ledgerSearchingNearby;

  /// Instruction above the list of discovered Ledger devices.
  ///
  /// In en, this message translates to:
  /// **'Select your Ledger.'**
  String get ledgerSelectYourLedger;

  /// Title of the mobile Add Ledger account sheet after adding the account failed.
  ///
  /// In en, this message translates to:
  /// **'Could not add Ledger account'**
  String get ledgerSheetAddFailedTitle;

  /// Title of the mobile Add Ledger account sheet when cancelling the request failed.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel Ledger request'**
  String get ledgerSheetCancelFailedTitle;

  /// Title of the mobile Add Ledger account sheet after the request was declined on the device.
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get ledgerSheetDeclinedTitle;

  /// Procedure step label in the mobile sheet: the user approves adding the account on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get ledgerStepAddAccount;

  /// [security] Procedure step label: the user approves sharing the viewing key on the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'Approve viewing key'**
  String get ledgerStepApproveViewingKey;

  /// Sidebar step label for customising the imported Ledger wallet (name and avatar).
  ///
  /// In en, this message translates to:
  /// **'Customise wallet'**
  String get ledgerStepCustomiseWallet;

  /// Procedure step label: the named app must be opened on the Ledger device. {appName} is the app name shown on the device, normally Zcash, and stays in Latin script.
  ///
  /// In en, this message translates to:
  /// **'Open {appName}'**
  String ledgerStepOpenApp(String appName);

  /// Procedure step label: the Zcash app must be opened on the Ledger device. 'Zcash' is the name of the app on the device and stays in Latin script.
  ///
  /// In en, this message translates to:
  /// **'Open Zcash'**
  String get ledgerStepOpenZcash;

  /// Sidebar step label for setting the wallet password during Ledger onboarding. Title Case is intentional.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get ledgerStepSetPassword;

  /// Sidebar step label for the wallet birthday (block height) step during Ledger onboarding. Title Case is intentional.
  ///
  /// In en, this message translates to:
  /// **'Wallet Birthday Height'**
  String get ledgerStepWalletBirthdayHeight;

  /// Title of the desktop dialog while the Bluetooth device search is being stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopping search'**
  String get ledgerStoppingSearch;

  /// Small button on the Connect Ledger screen that shows a tooltip listing the supported Ledger models.
  ///
  /// In en, this message translates to:
  /// **'Supported devices'**
  String get ledgerSupportedDevices;

  /// Name of the Bluetooth connection option for a Ledger device (choice button or connection summary).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get ledgerTransportBluetooth;

  /// Name of the USB connection option for a Ledger device (choice button or connection summary).
  ///
  /// In en, this message translates to:
  /// **'USB'**
  String get ledgerTransportUsb;

  /// Button that retries the failed Ledger connection or discovery.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get ledgerTryAgain;

  /// Instruction above the mobile device list while no device has been found yet.
  ///
  /// In en, this message translates to:
  /// **'Unlock Ledger, turn on Bluetooth, and keep it nearby.'**
  String get ledgerUnlockBluetoothNearby;

  /// [security] Step 1 of the Ledger preparation list (the number is added by the app); the user unlocks the Ledger with its PIN.
  ///
  /// In en, this message translates to:
  /// **'Unlock with your PIN.'**
  String get ledgerUnlockWithPin;

  /// Status message while Vizor checks whether the Zcash app is open on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Vizor is checking the Zcash app.'**
  String get ledgerVizorCheckingZcash;

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

  /// [security] Error shown when the selected account changed while a passcode-protected secret screen was open.
  ///
  /// In en, this message translates to:
  /// **'Selected account changed. Enter your passcode again.'**
  String get settingsAccountChangedPasscode;

  /// [security] Error shown when the selected account changed while a password-protected secret screen was open.
  ///
  /// In en, this message translates to:
  /// **'Selected account changed. Enter your password again.'**
  String get settingsAccountChangedPassword;

  /// Toast shown when saving the account name or profile picture failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the account changes'**
  String get settingsAccountSaveFailed;

  /// Error shown when the account the screen was opened for no longer exists.
  ///
  /// In en, this message translates to:
  /// **'The selected account is no longer available.'**
  String get settingsAccountUnavailable;

  /// Button that returns to the accounts list when the target account no longer exists.
  ///
  /// In en, this message translates to:
  /// **'Back to accounts'**
  String get settingsBackToAccounts;

  /// Toast after turning off the biometric unlock; the placeholder is the platform's unlock feature name such as 'Face ID unlock'.
  ///
  /// In en, this message translates to:
  /// **'{feature} off'**
  String settingsBiometricOffToast(String feature);

  /// Toast after turning on the biometric unlock; the placeholder is the platform's unlock feature name such as 'Face ID unlock'.
  ///
  /// In en, this message translates to:
  /// **'{feature} on'**
  String settingsBiometricOnToast(String feature);

  /// Toast shown when the user turns on biometric unlock but the device has none set up; the placeholder is the biometric name such as 'Face ID'.
  ///
  /// In en, this message translates to:
  /// **'Set up {biometric} in your device settings first.'**
  String settingsBiometricSetupFirst(String biometric);

  /// [security] Body of the sheet that confirms turning off biometric unlock; the placeholder is the lowercase unlock feature name.
  ///
  /// In en, this message translates to:
  /// **'You will use your passcode to unlock Vizor. You can turn {feature} back on in settings anytime.'**
  String settingsBiometricTurnOffBody(String feature);

  /// Title of the sheet that confirms turning off biometric unlock; the placeholder is the lowercase unlock feature name.
  ///
  /// In en, this message translates to:
  /// **'Turn off {feature}?'**
  String settingsBiometricTurnOffTitle(String feature);

  /// Toast shown when turning biometric unlock on or off failed; the placeholder is the unlock feature name.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update {feature}.'**
  String settingsBiometricUpdateFailed(String feature);

  /// [security] Accessibility label and toast after the BIP39 passphrase was copied.
  ///
  /// In en, this message translates to:
  /// **'BIP39 passphrase copied'**
  String get settingsBip39PassphraseCopied;

  /// [security] Accessibility label of the button that copies the BIP39 passphrase.
  ///
  /// In en, this message translates to:
  /// **'Copy BIP39 passphrase'**
  String get settingsBip39PassphraseCopy;

  /// [security] Label of the row showing the optional BIP39 passphrase on mobile.
  ///
  /// In en, this message translates to:
  /// **'BIP39 Passphrase'**
  String get settingsBip39PassphraseTitle;

  /// [security] Row showing the optional BIP39 passphrase (an extra secret word added to the recovery phrase); the placeholder is the secret itself.
  ///
  /// In en, this message translates to:
  /// **'BIP39 Passphrase: {passphrase}'**
  String settingsBip39PassphraseValue(String passphrase);

  /// Label of the row showing the block height the wallet was created at (wallet birthday).
  ///
  /// In en, this message translates to:
  /// **'Birthday block height'**
  String get settingsBirthdayBlockHeight;

  /// Label of the row showing the date of the block the wallet was created at (wallet birthday).
  ///
  /// In en, this message translates to:
  /// **'Birthday date'**
  String get settingsBirthdayDate;

  /// Toast after the wallet birthday date was copied.
  ///
  /// In en, this message translates to:
  /// **'Birthday date copied'**
  String get settingsBirthdayDateCopied;

  /// Toast after the wallet birthday block height was copied.
  ///
  /// In en, this message translates to:
  /// **'Birthday height copied'**
  String get settingsBirthdayHeightCopied;

  /// [security] Error shown on the change-passcode keypad when the current passcode is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect Passcode'**
  String get settingsChangePasscodeIncorrect;

  /// Subtitle under the passcode keypad title asking the user to prove it is them.
  ///
  /// In en, this message translates to:
  /// **'Confirm your access'**
  String get settingsConfirmAccessSubtitle;

  /// Title of the card that asks the user to enter their wallet password before a sensitive Settings screen opens.
  ///
  /// In en, this message translates to:
  /// **'Confirm access'**
  String get settingsConfirmAccessTitle;

  /// Title of the keypad step where the user re-enters the new passcode.
  ///
  /// In en, this message translates to:
  /// **'Confirm Passcode'**
  String get settingsConfirmPasscodeTitle;

  /// Accessibility label of the button that submits the password, and label of the repeat-password field when changing the password.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get settingsConfirmPasswordLabel;

  /// Button that continues to the password prompt before the secret passphrase is shown.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get settingsContinue;

  /// Short button label that copies the adjacent value to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get settingsCopy;

  /// Accessibility label of a button that copies a labeled value (for example the birthday date).
  ///
  /// In en, this message translates to:
  /// **'Copy {label}'**
  String settingsCopyLabel(String label);

  /// Accessibility label after a labeled value (for example the birthday date) was copied.
  ///
  /// In en, this message translates to:
  /// **'{label} copied'**
  String settingsCopyLabelCopied(String label);

  /// Explains that with a broken endpoint the balance is stale and recent incoming funds are missing; the placeholder is the currency ticker.
  ///
  /// In en, this message translates to:
  /// **'The wallet will show the balance from the last time it was successfully connected. It won\'t show any {ticker} you recently received.'**
  String settingsEndpointBalanceNote(String ticker);

  /// Accessibility label of the button that closes the endpoint settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Close endpoint settings'**
  String get settingsEndpointCloseSettings;

  /// Error shown when the custom endpoint could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect to that endpoint. Check the host and port.'**
  String get settingsEndpointConnectFailed;

  /// Shows the host and port of the endpoint in use, optionally followed by latency and a default marker.
  ///
  /// In en, this message translates to:
  /// **'Current: {endpoint}'**
  String settingsEndpointCurrent(String endpoint);

  /// Prefix (with trailing space) before the highlighted host and port of the endpoint in use.
  ///
  /// In en, this message translates to:
  /// **'Current: '**
  String get settingsEndpointCurrentPrefix;

  /// Tab label, heading and accessibility label for entering your own server address.
  ///
  /// In en, this message translates to:
  /// **'Custom endpoint'**
  String get settingsEndpointCustom;

  /// Button on the mobile endpoint list that switches to entering a custom endpoint.
  ///
  /// In en, this message translates to:
  /// **'Customise endpoint'**
  String get settingsEndpointCustomise;

  /// Button on the desktop endpoint list that switches to entering a custom endpoint.
  ///
  /// In en, this message translates to:
  /// **'Customize endpoint'**
  String get settingsEndpointCustomize;

  /// Marker appended to the current endpoint when it is the built-in default.
  ///
  /// In en, this message translates to:
  /// **'(Default)'**
  String get settingsEndpointDefaultMarker;

  /// Heading of the network settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Network settings'**
  String get settingsEndpointNetworkSettings;

  /// Tab label for choosing an endpoint from a list of known servers.
  ///
  /// In en, this message translates to:
  /// **'Select from the list'**
  String get settingsEndpointSelectFromList;

  /// Title of the lightwalletd server (endpoint) setting, used as the Settings row label and screen heading.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get settingsEndpointTitle;

  /// Button that saves the selected endpoint.
  ///
  /// In en, this message translates to:
  /// **'Update endpoint'**
  String get settingsEndpointUpdate;

  /// Toast shown after the endpoint was saved.
  ///
  /// In en, this message translates to:
  /// **'Endpoint updated'**
  String get settingsEndpointUpdatedToast;

  /// Label of the endpoint save button while the connection is being checked.
  ///
  /// In en, this message translates to:
  /// **'Updating endpoint...'**
  String get settingsEndpointUpdating;

  /// Mobile warning shown with the custom endpoint field that a wrong endpoint stops syncing.
  ///
  /// In en, this message translates to:
  /// **'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash blockchain.'**
  String get settingsEndpointWarningBlockchain;

  /// Warning shown with the custom endpoint field that a wrong endpoint stops syncing.
  ///
  /// In en, this message translates to:
  /// **'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash network.'**
  String get settingsEndpointWarningNetwork;

  /// Top-bar title of the mobile endpoint settings screen.
  ///
  /// In en, this message translates to:
  /// **'Endpoints'**
  String get settingsEndpointsTitle;

  /// [security] Error shown when the verified current password was lost and must be entered again.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password again.'**
  String get settingsEnterCurrentPasswordAgain;

  /// Subtitle of the access confirmation card on the change-password screen; the user must confirm the current password before choosing a new one.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password first.'**
  String get settingsEnterCurrentPasswordFirst;

  /// Title of the passcode keypad screen that gates access to a secret.
  ///
  /// In en, this message translates to:
  /// **'Enter Passcode'**
  String get settingsEnterPasscodeTitle;

  /// Shows which custom block explorer is in use.
  ///
  /// In en, this message translates to:
  /// **'Current: {explorer}'**
  String settingsExplorerCurrent(String explorer);

  /// Shows which block explorer host is in use when it is the built-in default.
  ///
  /// In en, this message translates to:
  /// **'Current: {host} (default)'**
  String settingsExplorerCurrentDefault(String host);

  /// Title of the option card to enter your own block explorer URL.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsExplorerCustom;

  /// Subtitle of the custom block explorer option card.
  ///
  /// In en, this message translates to:
  /// **'Any explorer you prefer'**
  String get settingsExplorerCustomSubtitle;

  /// Error shown under the custom explorer URL field when saving it failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that explorer URL.'**
  String get settingsExplorerSaveFailed;

  /// Title of the block explorer setting, used as the Settings row label and the screen heading; the explorer is the website used to look up transactions.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get settingsExplorerTitle;

  /// Button that saves the chosen block explorer.
  ///
  /// In en, this message translates to:
  /// **'Update explorer'**
  String get settingsExplorerUpdate;

  /// Label of the text field for a custom block explorer URL.
  ///
  /// In en, this message translates to:
  /// **'Explorer URL'**
  String get settingsExplorerUrlLabel;

  /// [security] Error shown on the passcode keypad when the entered passcode is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect passcode'**
  String get settingsIncorrectPasscode;

  /// [security] Error shown under the password field when the entered wallet password is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Please try again.'**
  String get settingsIncorrectPassword;

  /// Explains the keep-screen-awake setting during sync and that the app still locks after one minute of inactivity.
  ///
  /// In en, this message translates to:
  /// **'Prevents your phone from sleeping so sync can finish faster. The app still locks after 1 minute of inactivity.'**
  String get settingsKeepAwakeDescription;

  /// Label and accessibility label of the toggle that keeps the screen on while syncing.
  ///
  /// In en, this message translates to:
  /// **'Keep screen awake'**
  String get settingsKeepAwakeLabel;

  /// Toast shown when changing the keep-screen-awake setting failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update screen awake setting.'**
  String get settingsKeepAwakeUpdateFailed;

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

  /// Small pill next to a Settings row label that flags a recently added feature (gift cards).
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get settingsNewBadge;

  /// Error shown when a secret screen opens but no account is selected.
  ///
  /// In en, this message translates to:
  /// **'No active account is selected.'**
  String get settingsNoActiveAccount;

  /// [security] Error shown when verifying the current passcode failed unexpectedly.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your passcode. Please try again.'**
  String get settingsPasscodeCheckFailed;

  /// Subtitle under the keypad title telling the user the passcode has six digits.
  ///
  /// In en, this message translates to:
  /// **'6 digits length'**
  String get settingsPasscodeLengthHint;

  /// [security] Error when the new passcode equals the current one.
  ///
  /// In en, this message translates to:
  /// **'Your new passcode must be different.'**
  String get settingsPasscodeMustDiffer;

  /// [security] Error shown when an earlier passcode change was interrupted and its result could not be verified; the secret passphrase is the recovery path.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify the previous passcode change. Keep your secret passphrase available before trying again.'**
  String get settingsPasscodeRotationRecoveryFailed;

  /// [security] Error shown when changing the passcode failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your passcode. Please try again.'**
  String get settingsPasscodeUpdateFailed;

  /// [security] Toast shown after the passcode was changed.
  ///
  /// In en, this message translates to:
  /// **'Passcode updated'**
  String get settingsPasscodeUpdatedToast;

  /// Error shown when the passcode check itself failed unexpectedly.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the passcode. Try again.'**
  String get settingsPasscodeVerifyFailed;

  /// [security] Error when the confirmation passcode differs from the new passcode.
  ///
  /// In en, this message translates to:
  /// **'Passcodes didn\'t match. Try again.'**
  String get settingsPasscodesMismatch;

  /// [security] Error shown when verifying the current password failed unexpectedly.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your password. Please try again.'**
  String get settingsPasswordCheckFailed;

  /// Placeholder inside the wallet password field on the access confirmation card.
  ///
  /// In en, this message translates to:
  /// **'Your password...'**
  String get settingsPasswordHint;

  /// Accessibility label of the wallet password text field in Settings.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get settingsPasswordLabel;

  /// [security] Hint under the new-password heading about the minimum length and how to make a stronger password.
  ///
  /// In en, this message translates to:
  /// **'Minimum 8 characters. Add numbers and symbols, or make it longer, for stronger security.'**
  String get settingsPasswordMinimumHint;

  /// [security] Error shown when an earlier password change was interrupted and its result could not be verified; the secret passphrase is the recovery path.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify the previous password change. Please keep your secret passphrase available before trying again.'**
  String get settingsPasswordRotationRecoveryFailed;

  /// [security] Error shown when changing the wallet password failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your password. Please try again.'**
  String get settingsPasswordUpdateFailed;

  /// [security] Error under the repeat-password field when the two new passwords differ.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get settingsPasswordsMismatch;

  /// Name of a built-in profile picture (a knight character).
  ///
  /// In en, this message translates to:
  /// **'Knight'**
  String get settingsPfpKnight;

  /// Name of a built-in profile picture (a samurai character).
  ///
  /// In en, this message translates to:
  /// **'Samurai'**
  String get settingsPfpSamurai;

  /// Name of a built-in profile picture (a viking character).
  ///
  /// In en, this message translates to:
  /// **'Viking'**
  String get settingsPfpViking;

  /// Name of a built-in profile picture (a wizard character).
  ///
  /// In en, this message translates to:
  /// **'Wizard'**
  String get settingsPfpWizard;

  /// Status while the server list is being refreshed.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get settingsPirCheckingUpdates;

  /// Heading above the list of private query servers.
  ///
  /// In en, this message translates to:
  /// **'Choose a server'**
  String get settingsPirChooseServer;

  /// Error shown when the public repository listing private query servers could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the config repository.'**
  String get settingsPirConfigOpenFailed;

  /// Status shown when the saved custom server URL is invalid.
  ///
  /// In en, this message translates to:
  /// **'The saved custom server is invalid. Edit it or choose another server.'**
  String get settingsPirCustomInvalid;

  /// Label of the custom private query server field and list entry.
  ///
  /// In en, this message translates to:
  /// **'Custom server'**
  String get settingsPirCustomServer;

  /// Button that opens the field to enter a custom private query server.
  ///
  /// In en, this message translates to:
  /// **'Custom server…'**
  String get settingsPirCustomServerEllipsis;

  /// Validation message under the custom server field: HTTPS URL only, no credentials, query string or fragment.
  ///
  /// In en, this message translates to:
  /// **'Enter an HTTPS base URL without credentials, a query or a fragment.'**
  String get settingsPirCustomUrlInvalid;

  /// Button that edits the saved custom private query server.
  ///
  /// In en, this message translates to:
  /// **'Edit custom server…'**
  String get settingsPirEditCustomServer;

  /// Status shown when the server list could not be loaded at all.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the server list. Try again or enter a custom server.'**
  String get settingsPirListLoadFailed;

  /// Status shown when refreshing the server list failed and the last known list is used.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the server list. Using the last list loaded.'**
  String get settingsPirListUpdateFailed;

  /// Status shown when refreshing the server list failed while a custom server is selected.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the list. Your custom server is still selected.'**
  String get settingsPirListUpdateFailedCustom;

  /// Status while the list of private query servers is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading the server list…'**
  String get settingsPirLoadingServers;

  /// Status shown when the server list is empty.
  ///
  /// In en, this message translates to:
  /// **'No servers are offered yet. You can enter a custom server.'**
  String get settingsPirNoServers;

  /// Latency placeholder in a server row while its response time is being measured.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get settingsPirPingChecking;

  /// Error shown when switching the private query server failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change server. Try again.'**
  String get settingsPirServerChangeFailed;

  /// Accessibility label of the button that closes the private query server settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Close private query server settings'**
  String get settingsPirServerCloseLabel;

  /// Status shown when the previously selected server was removed from the list; private queries pause until another is chosen.
  ///
  /// In en, this message translates to:
  /// **'The server you chose is no longer offered. Choose another to resume private queries.'**
  String get settingsPirServerRemoved;

  /// Accessibility label of the small button next to Private queries that opens the server settings.
  ///
  /// In en, this message translates to:
  /// **'Private query server settings'**
  String get settingsPirServerSettingsLabel;

  /// Title of the dialog and tooltip for choosing the server that answers private queries.
  ///
  /// In en, this message translates to:
  /// **'Private query server'**
  String get settingsPirServerTitle;

  /// Error shown when the saved private query server settings could not be read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the private query server settings.'**
  String get settingsPirSettingsReadFailed;

  /// Button that opens the public config repository so the user can add their own private query server.
  ///
  /// In en, this message translates to:
  /// **'Share your server'**
  String get settingsPirShareServer;

  /// Status shown when the current network has no private query service.
  ///
  /// In en, this message translates to:
  /// **'Private queries are unavailable on this network.'**
  String get settingsPirUnavailable;

  /// Label of the save button while the server change is in progress.
  ///
  /// In en, this message translates to:
  /// **'Updating server…'**
  String get settingsPirUpdatingServer;

  /// Button that saves the custom private query server.
  ///
  /// In en, this message translates to:
  /// **'Use custom server'**
  String get settingsPirUseCustomServer;

  /// Title of the Settings card or section that holds network privacy options such as Tor and private queries.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacyTitle;

  /// Label of the Settings toggle row and its accessibility label for the private queries feature, which sends wallet lookups to a privacy-preserving server.
  ///
  /// In en, this message translates to:
  /// **'Private queries'**
  String get settingsPrivateQueriesLabel;

  /// [security] Explains that turning off private queries makes the wallet rebuild its transparent history through public lookups, exposing addresses to the server.
  ///
  /// In en, this message translates to:
  /// **'Vizor will rebuild your transparent history publicly, allowing the server to learn all your addresses.'**
  String get settingsPrivateQueriesTurnOffBody;

  /// Destructive button that confirms turning off a setting such as private queries or a biometric unlock.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get settingsPrivateQueriesTurnOffConfirm;

  /// [security] Warning listing what the server learns once private queries are off: addresses, transaction IDs, and linkage to the IP address when Tor is not used.
  ///
  /// In en, this message translates to:
  /// **'The server receives every transparent address of every account and the IDs of transactions private recovery found. It can link them to each other and, without Tor, to your IP address.'**
  String get settingsPrivateQueriesTurnOffDisclosure;

  /// Title of the confirmation shown before private queries are turned off.
  ///
  /// In en, this message translates to:
  /// **'Turn off private queries?'**
  String get settingsPrivateQueriesTurnOffTitle;

  /// Value shown on the profile picture row when the picture is not one of the built-in options.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsProfilePictureCustom;

  /// Settings row that opens the About screen.
  ///
  /// In en, this message translates to:
  /// **'About Vizor'**
  String get settingsRowAboutVizor;

  /// Settings row that opens the account rename dialog.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get settingsRowAccountName;

  /// Mobile Settings row that opens the account rename sheet (title case).
  ///
  /// In en, this message translates to:
  /// **'Account Name'**
  String get settingsRowAccountNameMobile;

  /// Settings row that opens the address book.
  ///
  /// In en, this message translates to:
  /// **'Address book'**
  String get settingsRowAddressBook;

  /// [security] Mobile Settings row that opens the change passcode screen.
  ///
  /// In en, this message translates to:
  /// **'Change passcode'**
  String get settingsRowChangePasscode;

  /// [security] Settings row that opens the change wallet password screen.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsRowChangePassword;

  /// Mobile Settings row that opens coinholder governance voting.
  ///
  /// In en, this message translates to:
  /// **'Coinholder voting'**
  String get settingsRowCoinholderVoting;

  /// Settings row that links the desktop wallet with the Vizor mobile app.
  ///
  /// In en, this message translates to:
  /// **'Link Vizor mobile'**
  String get settingsRowLinkMobile;

  /// Settings row that opens the user's gift cards.
  ///
  /// In en, this message translates to:
  /// **'My gift cards'**
  String get settingsRowMyGiftCards;

  /// Settings row that opens the profile picture picker.
  ///
  /// In en, this message translates to:
  /// **'Profile picture'**
  String get settingsRowProfilePicture;

  /// Mobile Settings row that opens the profile picture sheet (title case).
  ///
  /// In en, this message translates to:
  /// **'Profile Picture'**
  String get settingsRowProfilePictureMobile;

  /// [security] Settings row that opens the secret recovery phrase screen (desktop, sentence case).
  ///
  /// In en, this message translates to:
  /// **'Secret passphrase'**
  String get settingsRowSecretPassphrase;

  /// Settings row that opens the donation screen.
  ///
  /// In en, this message translates to:
  /// **'Support Vizor'**
  String get settingsRowSupportVizor;

  /// Settings row and dialog title for checking and installing app updates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsRowUpdates;

  /// [security] Mobile Settings row that opens the viewing key screen (title case).
  ///
  /// In en, this message translates to:
  /// **'Viewing Key'**
  String get settingsRowViewingKeyMobile;

  /// [security] Title of the screen and card that show the wallet's secret recovery phrase.
  ///
  /// In en, this message translates to:
  /// **'Secret Passphrase'**
  String get settingsSecretPassphraseTitle;

  /// Heading of the Settings group with account items such as secret passphrase and password.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// Heading of the Settings group that holds destructive actions such as uninstalling.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get settingsSectionDangerZone;

  /// Heading of the Settings group with miscellaneous items such as About and Support.
  ///
  /// In en, this message translates to:
  /// **'Misc'**
  String get settingsSectionMisc;

  /// Heading of the Settings group with personal items such as gift cards and address book.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get settingsSectionPersonal;

  /// Heading of the Settings card that holds the keep-screen-awake option.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get settingsSectionSyncing;

  /// Heading of the Settings group with endpoint, explorer, theme and language.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSectionSystem;

  /// Error shown when saving the 'written down' or 'remind me later' choice for the passphrase backup failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save that. Try again.'**
  String get settingsSeedBackupSaveFailed;

  /// [security] Reason text shown in the system biometric prompt before revealing the secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Confirm access to your secret passphrase'**
  String get settingsSeedBiometricReason;

  /// [security] Toast after the secret passphrase was copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Secret passphrase copied'**
  String get settingsSeedCopiedToast;

  /// [security] Accessibility label of the button that copies the secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Copy secret passphrase'**
  String get settingsSeedCopyLabel;

  /// [security] Warning under the Secret Passphrase heading; two lines separated by a line break.
  ///
  /// In en, this message translates to:
  /// **'This is the master key to your wallet.\nDon’t share it with anyone.'**
  String get settingsSeedHeadingSubtitle;

  /// [security] Error shown when the secret passphrase could not be read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your secret passphrase. Please try again.'**
  String get settingsSeedLoadFailed;

  /// Subtitle of the access confirmation card; completes the sentence 'Confirm access ... to view the secret passphrase'.
  ///
  /// In en, this message translates to:
  /// **'To view the secret passphrase.'**
  String get settingsSeedPasswordSubtitle;

  /// [security] Button that postpones backing up the secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Remind me later'**
  String get settingsSeedRemindLater;

  /// Button that dismisses the screenshot warning sheet.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get settingsSeedScreenshotAck;

  /// [security] Bold first words of the screenshot warning body; the next string continues the same sentence.
  ///
  /// In en, this message translates to:
  /// **'Screenshots are not reliable'**
  String get settingsSeedScreenshotBodyLead;

  /// [security] Rest of the screenshot warning body; it directly follows the bold lead and so starts with a period.
  ///
  /// In en, this message translates to:
  /// **'. Anyone who has access to your phone or your photo library will be able to see your Secret Passphrase. Write down your Phrase on a piece of paper instead.'**
  String get settingsSeedScreenshotBodyRest;

  /// [security] Heading of the warning sheet shown when a screenshot is taken while the secret passphrase is visible.
  ///
  /// In en, this message translates to:
  /// **'Don’t take screenshots of your Secret Passphrase'**
  String get settingsSeedScreenshotTitle;

  /// Error shown when the account has no stored secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Secret passphrase is not available for this account.'**
  String get settingsSeedUnavailableAccount;

  /// Error shown for hardware wallet accounts, whose secret never leaves the device.
  ///
  /// In en, this message translates to:
  /// **'Secret passphrase is not available for hardware accounts.'**
  String get settingsSeedUnavailableHardware;

  /// [security] Button confirming the user has written down the secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'I’ve written it down'**
  String get settingsSeedWrittenDown;

  /// Title of the keypad step where the user chooses a new 6-digit passcode.
  ///
  /// In en, this message translates to:
  /// **'Set New Passcode'**
  String get settingsSetNewPasscodeTitle;

  /// Status text shown under a Settings row when the feature is turned off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsStatusOff;

  /// Status text shown under a Settings row when the feature is turned on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsStatusOn;

  /// Dark color theme option and row value.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Light color theme option and row value.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Short value of the theme row when the theme follows the operating system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// Theme option that follows the operating system's light or dark setting.
  ///
  /// In en, this message translates to:
  /// **'System (Auto)'**
  String get settingsThemeSystemAuto;

  /// Settings row label and dialog title for choosing the color theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeTitle;

  /// Error shown in the theme dialog when saving the theme failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update theme.'**
  String get settingsThemeUpdateFailed;

  /// [security] Tor status description on mobile when connecting failed; requests fail closed.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not connect to Tor. Requests stay blocked until it connects or you turn Tor off.'**
  String get settingsTorDescBootstrapFailed;

  /// Tor status description when connected.
  ///
  /// In en, this message translates to:
  /// **'Vizor’s network requests go through Tor. Links opened in other apps use those apps’ network settings.'**
  String get settingsTorDescConnected;

  /// [security] Tor status description on iOS: the background Ironwood migration is direct while the app is closed.
  ///
  /// In en, this message translates to:
  /// **'Vizor’s network requests go through Tor. Ironwood private migration uses a direct connection while Vizor is closed. Links opened in other apps use those apps’ network settings.'**
  String get settingsTorDescConnectedIos;

  /// Tor status description when connected but software updates cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Vizor’s network requests go through Tor, but software updates are unavailable.'**
  String get settingsTorDescConnectedNoUpdates;

  /// Tor status description while connecting; it names the way out for networks that block Tor.
  ///
  /// In en, this message translates to:
  /// **'New requests wait until the Tor connection is ready. Turn Tor off to stop connecting and use a direct connection.'**
  String get settingsTorDescConnecting;

  /// Tor status description while connecting on Linux.
  ///
  /// In en, this message translates to:
  /// **'New requests wait until the Tor connection is ready. Turn Tor off to stop connecting and use a direct connection. Update pages and downloads opened in another app use that app’s connection.'**
  String get settingsTorDescConnectingLinux;

  /// Tor status description when connecting to Tor failed (desktop); direct requests stay blocked.
  ///
  /// In en, this message translates to:
  /// **'Direct requests remain blocked. Try again or turn off Tor.'**
  String get settingsTorDescConnectionFailed;

  /// Tor status description when requests are direct and software updates cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Network requests connect directly. Software updates are unavailable.'**
  String get settingsTorDescDirectNoUpdates;

  /// [security] Tor status description on mobile when requests are direct but the setting could not be saved; Tor returns at the next launch.
  ///
  /// In en, this message translates to:
  /// **'Requests now use a direct connection, but Vizor could not save the change. Tor turns back on the next time you open the app.'**
  String get settingsTorDescDisableNotSaved;

  /// Tor status description on mobile when the enable toggle could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not save the change, so Tor was not turned on. Requests keep using a direct connection.'**
  String get settingsTorDescEnableNotSaved;

  /// Tor status description when Tor is off (desktop).
  ///
  /// In en, this message translates to:
  /// **'Tor is off. Requests to the Zcash network, in-app services, and software updates connect directly.'**
  String get settingsTorDescOff;

  /// Tor status description when Tor is off on Linux; update pages and downloads open in another app.
  ///
  /// In en, this message translates to:
  /// **'Tor is off. Vizor requests, including software update checks, connect directly. Update pages and downloads open in another app.'**
  String get settingsTorDescOffLinux;

  /// Tor status description on mobile when Tor is off.
  ///
  /// In en, this message translates to:
  /// **'Wallet sync and in-app requests connect directly. Turn Tor on to hide your IP address from the servers Vizor talks to.'**
  String get settingsTorDescOffMobile;

  /// Tor status description when switching to direct failed (desktop).
  ///
  /// In en, this message translates to:
  /// **'Vizor could not switch to a direct connection. Try again.'**
  String get settingsTorDescSwitchFailed;

  /// Tor status description on mobile when switching to direct failed and Tor is still carrying traffic.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not switch to a direct connection. Tor is still on and requests keep going through it.'**
  String get settingsTorDescSwitchFailedStillOn;

  /// Tor status description while switching to direct (desktop).
  ///
  /// In en, this message translates to:
  /// **'Vizor is switching network requests and software updates to a direct connection.'**
  String get settingsTorDescSwitching;

  /// Tor status description while switching to direct on Linux.
  ///
  /// In en, this message translates to:
  /// **'Vizor is switching its requests, including software update checks, to a direct connection.'**
  String get settingsTorDescSwitchingLinux;

  /// Tor status description while switching to direct (mobile).
  ///
  /// In en, this message translates to:
  /// **'Vizor is switching network requests to a direct connection.'**
  String get settingsTorDescSwitchingMobile;

  /// Short general description of the Tor setting on mobile.
  ///
  /// In en, this message translates to:
  /// **'Use Tor to hide your IP address from servers. Other apps use their own network settings.'**
  String get settingsTorGeneralDescription;

  /// [security] Sentence appended (with a leading space) to the general Tor description on iOS.
  ///
  /// In en, this message translates to:
  /// **' Ironwood private migration connects directly while Vizor is closed.'**
  String get settingsTorGeneralIosSuffix;

  /// Button that retries making software updates available after they were blocked.
  ///
  /// In en, this message translates to:
  /// **'Retry updates'**
  String get settingsTorRetryUpdates;

  /// Tor status label when requests go through Tor.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get settingsTorStatusConnected;

  /// Tor status label while the Tor connection is being established.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get settingsTorStatusConnecting;

  /// Tor status label when connecting to Tor failed (desktop).
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get settingsTorStatusConnectionFailed;

  /// Tor status label when requests connect directly without Tor.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get settingsTorStatusDirect;

  /// Tor status label when connecting to Tor failed (mobile).
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settingsTorStatusFailed;

  /// Tor status label when the Tor preference could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Setting not saved'**
  String get settingsTorStatusNotSaved;

  /// Tor status label when switching to a direct connection failed.
  ///
  /// In en, this message translates to:
  /// **'Switch failed'**
  String get settingsTorStatusSwitchFailed;

  /// Tor status label while switching from Tor to a direct connection (mobile).
  ///
  /// In en, this message translates to:
  /// **'Switching…'**
  String get settingsTorStatusSwitching;

  /// Tor status label while switching from Tor to a direct connection (desktop).
  ///
  /// In en, this message translates to:
  /// **'Switching to direct…'**
  String get settingsTorStatusSwitchingDirect;

  /// Accessibility label of the Tor toggle while Tor is still connecting; turning it off cancels the attempt.
  ///
  /// In en, this message translates to:
  /// **'Stop connecting to Tor'**
  String get settingsTorStopConnecting;

  /// Button that retries switching to a direct (non-Tor) connection after a failure.
  ///
  /// In en, this message translates to:
  /// **'Try direct connection'**
  String get settingsTorTryDirect;

  /// Label of the toggle that routes Vizor's network requests through Tor.
  ///
  /// In en, this message translates to:
  /// **'Use Tor'**
  String get settingsTorUse;

  /// Button that retries a failed action in Settings.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get settingsTryAgain;

  /// [security] Blocks uninstalling while swaps are still in progress, because funds could arrive after the wipe and be lost.
  ///
  /// In en, this message translates to:
  /// **'This wallet has {count, plural, =1{1 active swap} other{{count} active swaps}}. Wait for them to complete before uninstalling.'**
  String settingsUninstallActiveSwaps(int count);

  /// [security] Short warning under the uninstall subtitle: deletion is irreversible.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get settingsUninstallCannotUndo;

  /// Label of the uninstall button while swaps and gift card claims are being checked.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get settingsUninstallChecking;

  /// Error shown when checking for gift cards that are still being claimed failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for incoming gift cards. Try again before uninstalling.'**
  String get settingsUninstallClaimCheckFailed;

  /// Button that quits the app after wallet data was removed.
  ///
  /// In en, this message translates to:
  /// **'Close Vizor'**
  String get settingsUninstallCloseApp;

  /// Phrase naming the current computer on other platforms, inserted into the uninstall warning.
  ///
  /// In en, this message translates to:
  /// **'this device'**
  String get settingsUninstallDeviceGeneric;

  /// Phrase naming the current computer on macOS, inserted into the uninstall warning.
  ///
  /// In en, this message translates to:
  /// **'this Mac'**
  String get settingsUninstallDeviceMac;

  /// Phrase naming the current computer on Windows, inserted into the uninstall warning.
  ///
  /// In en, this message translates to:
  /// **'this PC'**
  String get settingsUninstallDevicePc;

  /// Title shown after wallet data was deleted.
  ///
  /// In en, this message translates to:
  /// **'Your data has been removed'**
  String get settingsUninstallDoneTitle;

  /// Final instruction on other platforms after wallet data was removed.
  ///
  /// In en, this message translates to:
  /// **'To finish uninstallation, remove the Vizor app from this device.'**
  String get settingsUninstallFinishGeneric;

  /// Final instruction on macOS after wallet data was removed.
  ///
  /// In en, this message translates to:
  /// **'To finish uninstallation, remove the Vizor app from Applications.'**
  String get settingsUninstallFinishMac;

  /// Final instruction on Windows after wallet data was removed.
  ///
  /// In en, this message translates to:
  /// **'To finish uninstallation, uninstall Vizor from Windows settings.'**
  String get settingsUninstallFinishWindows;

  /// Subtitle of the access confirmation card on the uninstall screen.
  ///
  /// In en, this message translates to:
  /// **'To uninstall Vizor.'**
  String get settingsUninstallPasswordSubtitle;

  /// Title shown while wallet data is being deleted.
  ///
  /// In en, this message translates to:
  /// **'Removing data...'**
  String get settingsUninstallRemovingTitle;

  /// Error shown when checking for in-progress swaps failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for active swaps. Try again before uninstalling.'**
  String get settingsUninstallSwapCheckFailed;

  /// [security] Title and destructive button label of the screen that wipes all wallet data from this device.
  ///
  /// In en, this message translates to:
  /// **'Uninstall Vizor'**
  String get settingsUninstallTitle;

  /// Error shown when wiping wallet data failed part way.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish removing data. Please try again.'**
  String get settingsUninstallWipeFailed;

  /// [security] Irreversible-deletion warning on the uninstall screen. {device} is one of the phrases 'this Mac', 'this PC' or 'this device'.
  ///
  /// In en, this message translates to:
  /// **'Vizor will delete wallet data and secure storage from {device}. Unshared gift card links will be permanently lost.'**
  String settingsUninstallWipeSubtitle(String device);

  /// Short value on the Updates row while an update is being applied.
  ///
  /// In en, this message translates to:
  /// **'Applying'**
  String get settingsUpdateApplying;

  /// Short value on the Updates row, and label of the available-version line, when a new version exists.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get settingsUpdateAvailable;

  /// Short value on the Updates row prompting the user to check for updates.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get settingsUpdateCheck;

  /// Button in the Updates dialog that checks for a new version.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsUpdateCheckForUpdates;

  /// Short value on the Updates row while checking for an update.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get settingsUpdateChecking;

  /// Disabled button label in the Updates dialog while checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get settingsUpdateCheckingButton;

  /// Label before the currently installed version number in the Updates dialog.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get settingsUpdateCurrentLabel;

  /// Button in the Updates dialog that downloads the new version.
  ///
  /// In en, this message translates to:
  /// **'Download update'**
  String get settingsUpdateDownloadButton;

  /// Disabled button label in the Updates dialog while downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get settingsUpdateDownloadingButton;

  /// Short value on the Updates row when the update failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settingsUpdateFailed;

  /// [security] Heading and button label for setting a new wallet password.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get settingsUpdatePasswordTitle;

  /// Short value on the Updates row when an update is downloaded and needs a restart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get settingsUpdateRestart;

  /// Button in the Updates dialog that restarts the app to install the downloaded update.
  ///
  /// In en, this message translates to:
  /// **'Restart to update'**
  String get settingsUpdateRestartButton;

  /// Disabled button label in the Updates dialog while the app restarts to apply the update.
  ///
  /// In en, this message translates to:
  /// **'Restarting…'**
  String get settingsUpdateRestartingButton;

  /// Status line in the Updates dialog when a newer version exists.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available.'**
  String settingsUpdateStatusAvailable(String version);

  /// Status line in the Updates dialog while checking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates.'**
  String get settingsUpdateStatusChecking;

  /// Status line in the Updates dialog during the download; the placeholder is a whole-number percentage.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%.'**
  String settingsUpdateStatusDownloading(String percent);

  /// Status line in the Updates dialog when the update failed without a specific message.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the update. Try again.'**
  String get settingsUpdateStatusFailed;

  /// Status line in the Updates dialog before any check has run.
  ///
  /// In en, this message translates to:
  /// **'Ready to check for updates.'**
  String get settingsUpdateStatusIdle;

  /// Status line in the Updates dialog when the download finished.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is ready.'**
  String settingsUpdateStatusReady(String version);

  /// Status line in the Updates dialog while the app restarts.
  ///
  /// In en, this message translates to:
  /// **'Restarting Vizor.'**
  String get settingsUpdateStatusRestarting;

  /// Status line in the Updates dialog for builds that cannot update themselves.
  ///
  /// In en, this message translates to:
  /// **'Updates are available in the installed Windows app.'**
  String get settingsUpdateStatusUnsupported;

  /// Status line in the Updates dialog when no newer version exists.
  ///
  /// In en, this message translates to:
  /// **'Vizor is up to date.'**
  String get settingsUpdateStatusUpToDate;

  /// Short value on the Updates row when updates are not supported in this build.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get settingsUpdateUnavailable;

  /// Short value on the Updates row when there is no newer version.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get settingsUpdateUpToDate;

  /// Label of the update-password button while the password change is in progress.
  ///
  /// In en, this message translates to:
  /// **'Updating password...'**
  String get settingsUpdatingPassword;

  /// Accessibility label of the version footer at the bottom of mobile Settings.
  ///
  /// In en, this message translates to:
  /// **'Vizor, version {version}'**
  String settingsVersionFooterLabel(String version);

  /// [security] Reason text shown in the system biometric prompt before revealing the viewing key.
  ///
  /// In en, this message translates to:
  /// **'Confirm access to your viewing key'**
  String get settingsViewingKeyBiometricReason;

  /// [security] Warning under the viewing key choice: share only with trusted parties.
  ///
  /// In en, this message translates to:
  /// **'Share only with trusted parties. Both keys may reveal transparent balances and spending.'**
  String get settingsViewingKeyChoiceSharingWarning;

  /// Heading above the choice between sharing an incoming-only or a full viewing key.
  ///
  /// In en, this message translates to:
  /// **'Choose what others can view'**
  String get settingsViewingKeyChooseTitle;

  /// Error text asking the user to re-enter their password or passcode and retry loading the viewing key.
  ///
  /// In en, this message translates to:
  /// **'Confirm access again to try loading this key.'**
  String get settingsViewingKeyConfirmAgain;

  /// [security] Button that copies the viewing key to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy viewing key'**
  String get settingsViewingKeyCopy;

  /// [security] Explains what the full viewing key reveals and that it cannot spend funds.
  ///
  /// In en, this message translates to:
  /// **'Reveals your balance and all past and future transactions. It cannot spend ZEC.'**
  String get settingsViewingKeyExplanation;

  /// Segmented control option that shows the viewing key as a QR code.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get settingsViewingKeyFormatQr;

  /// Segmented control option that shows the viewing key as text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get settingsViewingKeyFormatText;

  /// Description of the full viewing key choice.
  ///
  /// In en, this message translates to:
  /// **'Balance, incoming and outgoing transactions.'**
  String get settingsViewingKeyFullDescription;

  /// [security] Explains what the incoming viewing key reveals and that it cannot spend funds.
  ///
  /// In en, this message translates to:
  /// **'Reveals past and future incoming payments. It cannot spend ZEC.'**
  String get settingsViewingKeyIncomingExplanation;

  /// Title of the choice card for the viewing key that reveals only incoming transactions.
  ///
  /// In en, this message translates to:
  /// **'Incoming only'**
  String get settingsViewingKeyIncomingOnly;

  /// Description of the incoming-only viewing key choice.
  ///
  /// In en, this message translates to:
  /// **'Incoming transactions only.'**
  String get settingsViewingKeyIncomingOnlyDescription;

  /// [security] Warning heading above the incoming-only viewing key.
  ///
  /// In en, this message translates to:
  /// **'This key reveals incoming payments'**
  String get settingsViewingKeyIncomingWarningTitle;

  /// Heading of the error card shown when the viewing key could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the viewing key'**
  String get settingsViewingKeyLoadFailedTitle;

  /// Subtitle of the access confirmation card; completes the sentence 'Confirm access ... to view the viewing key'.
  ///
  /// In en, this message translates to:
  /// **'To view the viewing key.'**
  String get settingsViewingKeyPasswordSubtitle;

  /// Accessibility label of the QR code that encodes the full viewing key.
  ///
  /// In en, this message translates to:
  /// **'Full viewing key QR code'**
  String get settingsViewingKeyQrFull;

  /// Accessibility label of the QR code that encodes the incoming-only viewing key.
  ///
  /// In en, this message translates to:
  /// **'Incoming viewing key QR code'**
  String get settingsViewingKeyQrIncoming;

  /// [security] Title and back-link label of the viewing key screen, which shows a key that lets others see wallet activity.
  ///
  /// In en, this message translates to:
  /// **'Viewing key'**
  String get settingsViewingKeyTitle;

  /// Label of the copy button after copying the viewing key to the clipboard failed.
  ///
  /// In en, this message translates to:
  /// **'Try copying again'**
  String get settingsViewingKeyTryCopyAgain;

  /// [security] Name of the viewing key that reveals balance plus incoming and outgoing transactions; used as a choice title and screen title.
  ///
  /// In en, this message translates to:
  /// **'Full viewing key'**
  String get settingsViewingKeyTypeFull;

  /// [security] Screen title for the viewing key that reveals only incoming payments.
  ///
  /// In en, this message translates to:
  /// **'Incoming key'**
  String get settingsViewingKeyTypeIncoming;

  /// [security] Warning heading above the full viewing key.
  ///
  /// In en, this message translates to:
  /// **'This key reveals your transactions'**
  String get settingsViewingKeyWarningTitle;

  /// [security] Error shown when the secure storage session changed while the secret passphrase screen was open.
  ///
  /// In en, this message translates to:
  /// **'The wallet session changed. Enter your password again.'**
  String get settingsWalletSessionChanged;

  /// Button that downloads the update over Tor.
  ///
  /// In en, this message translates to:
  /// **'Continue with Tor'**
  String get settingsWinUpdateContinueTor;

  /// Title of the error dialog when the update download could not start; the message below comes from the updater.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the update'**
  String get settingsWinUpdateStartFailedTitle;

  /// Body of the error dialog when updates are unavailable over Tor; direct requests were deliberately not used.
  ///
  /// In en, this message translates to:
  /// **'Vizor kept direct requests blocked. Retry updates in Settings, or turn off Tor and try the download again.'**
  String get settingsWinUpdateTorBlockedBody;

  /// Title of the error dialog shown when the user picked Tor for a Windows update but updates cannot go through Tor.
  ///
  /// In en, this message translates to:
  /// **'Software updates unavailable over Tor'**
  String get settingsWinUpdateTorBlockedTitle;

  /// [security] Explains that updating over Tor is slower and that turning Tor off makes every Vizor request direct.
  ///
  /// In en, this message translates to:
  /// **'Updating over Tor may take longer. Turning Tor off switches all Vizor network requests to a direct connection.'**
  String get settingsWinUpdateTorChoiceBody;

  /// Title of the dialog that asks whether to download the Windows update over Tor.
  ///
  /// In en, this message translates to:
  /// **'Use Tor for this update?'**
  String get settingsWinUpdateTorChoiceTitle;

  /// Body of the error dialog when turning off Tor failed and the update stayed blocked.
  ///
  /// In en, this message translates to:
  /// **'Tor remains on, so Vizor kept the update blocked. Try again, or turn off Tor in Settings before downloading.'**
  String get settingsWinUpdateTorOffFailedBody;

  /// Title of the error dialog when turning off Tor for the update failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t turn off Tor'**
  String get settingsWinUpdateTorOffFailedTitle;

  /// Button that turns Tor off and downloads the update over a direct connection.
  ///
  /// In en, this message translates to:
  /// **'Turn off Tor and update'**
  String get settingsWinUpdateTurnOffTorAndUpdate;

  /// Body of the error dialog when updates are still unavailable after Tor was turned off.
  ///
  /// In en, this message translates to:
  /// **'Tor is off, but software updates are still unavailable. Retry updates in Settings before downloading.'**
  String get settingsWinUpdateUnavailableBody;

  /// Title of the error dialog when updates are still unavailable after Tor was turned off.
  ///
  /// In en, this message translates to:
  /// **'Software updates unavailable'**
  String get settingsWinUpdateUnavailableTitle;

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

  /// Section title above the list of importable accounts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account} other{{count} accounts}} found'**
  String walletLinkAccountsFound(int count);

  /// Subtitle of the account selection screen with counts of accounts that can still be imported and accounts already on the phone.
  ///
  /// In en, this message translates to:
  /// **'{ready, plural, =1{1 account} other{{ready} accounts}} ready to import, {imported} already imported.'**
  String walletLinkAccountsReadySubtitle(int ready, int imported);

  /// Section title above the list of accounts or contacts that are already on the phone.
  ///
  /// In en, this message translates to:
  /// **'{count} already imported'**
  String walletLinkAlreadyImported(int count);

  /// Message shown instead of the scanner when the device has no camera.
  ///
  /// In en, this message translates to:
  /// **'Desktop link scanning needs a camera on this device.'**
  String get walletLinkCameraRequired;

  /// Section title above the list of importable contacts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 contact} other{{count} contacts}} found'**
  String walletLinkContactsFound(int count);

  /// Subtitle of the contact selection screen with counts of contacts found and contacts already on the phone.
  ///
  /// In en, this message translates to:
  /// **'{found, plural, =1{1 contact} other{{found} contacts}} found, {imported} already imported.'**
  String walletLinkContactsReadySubtitle(int found, int imported);

  /// Button on the account selection screen when no account is selected but contacts can still be imported.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get walletLinkContinue;

  /// Action in a list section header that clears the selection.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get walletLinkDeselectAll;

  /// Body of the expired link error; 'Generate new code' is the name of a button in the desktop app.
  ///
  /// In en, this message translates to:
  /// **'The code on your computer timed out. On desktop, choose Generate new code and scan it again.'**
  String get walletLinkErrorExpiredBody;

  /// Title of the scan error card when the desktop link code timed out.
  ///
  /// In en, this message translates to:
  /// **'Link expired'**
  String get walletLinkErrorExpiredTitle;

  /// Body of the generic link error.
  ///
  /// In en, this message translates to:
  /// **'Check that the desktop code is still visible, then scan it again.'**
  String get walletLinkErrorFailedBody;

  /// Title of the scan error card when the link could not be opened for another reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this link'**
  String get walletLinkErrorFailedTitle;

  /// Body of the invalid QR error; 'Settings' and 'Link Vizor Mobile' are menu names in the desktop app.
  ///
  /// In en, this message translates to:
  /// **'The code you scanned isn\'t a Vizor desktop link. On your computer, open Settings → Link Vizor Mobile.'**
  String get walletLinkErrorInvalidBody;

  /// Title of the scan error card when the scanned QR is not a Vizor desktop link.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR code'**
  String get walletLinkErrorInvalidTitle;

  /// Button on the account selection screen when there is nothing to import; leaves the flow.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get walletLinkGoBack;

  /// Button on the contact selection screen that imports the selected contacts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Import 1 contact} other{Import {count} contacts}}'**
  String walletLinkImportContacts(int count);

  /// Heading of the mobile screen where the user chooses which desktop contacts to import.
  ///
  /// In en, this message translates to:
  /// **'Import contacts'**
  String get walletLinkImportContactsTitle;

  /// Button label while the selected accounts or contacts are being imported.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get walletLinkImporting;

  /// Reassurance card on the intro screen: linking copies the wallet and contacts and leaves the desktop unchanged.
  ///
  /// In en, this message translates to:
  /// **'This copies the wallet and contacts to the phone. Nothing on the computer changes, and you can use both.'**
  String get walletLinkIntroNotice;

  /// Primary button on the intro screen that opens the QR scanner.
  ///
  /// In en, this message translates to:
  /// **'I\'m ready to scan'**
  String get walletLinkIntroReady;

  /// Subtitle under the Link with Desktop and Scan QR Code headings.
  ///
  /// In en, this message translates to:
  /// **'Copy your desktop wallet to this phone'**
  String get walletLinkIntroSubtitle;

  /// Heading of the mobile screen that explains how to copy a wallet from the Vizor desktop app to this phone.
  ///
  /// In en, this message translates to:
  /// **'Link with Desktop'**
  String get walletLinkIntroTitle;

  /// Button on the account selection screen that links the selected accounts to this phone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Link 1 account} other{Link {count} accounts}}'**
  String walletLinkLinkAccounts(int count);

  /// Subtitle of the account selection screen when everything in the link already exists on the phone.
  ///
  /// In en, this message translates to:
  /// **'There is nothing new to import from this desktop link.'**
  String get walletLinkNothingNewSubtitle;

  /// Body of the nothing to import card.
  ///
  /// In en, this message translates to:
  /// **'Everything in this desktop link is already on this phone.'**
  String get walletLinkNothingToImportBody;

  /// Title of the card shown when everything in the desktop link is already on the phone.
  ///
  /// In en, this message translates to:
  /// **'Nothing to import'**
  String get walletLinkNothingToImportTitle;

  /// Caption under the camera view while the scanned link is being read.
  ///
  /// In en, this message translates to:
  /// **'Reading link...'**
  String get walletLinkReadingLink;

  /// Button on the scan error card that returns to the scanner.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get walletLinkScanAgain;

  /// Caption under the camera view and title of the camera permission card while scanning the desktop link QR code.
  ///
  /// In en, this message translates to:
  /// **'Scan the Vizor desktop QR'**
  String get walletLinkScanCaption;

  /// Subtitle of the scan screen when the scan error card is shown.
  ///
  /// In en, this message translates to:
  /// **'Scan the code on your desktop'**
  String get walletLinkScanSubtitleDesktop;

  /// Heading of the mobile screen that scans the desktop link QR code.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get walletLinkScanTitle;

  /// Heading of the mobile screen where the user chooses which desktop accounts to link.
  ///
  /// In en, this message translates to:
  /// **'Select account'**
  String get walletLinkSelectAccountTitle;

  /// Action in a list section header that selects every importable item.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get walletLinkSelectAll;

  /// Step 2 of the desktop link instructions; 'Settings' and 'Link Vizor Mobile' are menu names in the desktop app (the arrow separates the menu path).
  ///
  /// In en, this message translates to:
  /// **'Go to Settings → Link Vizor Mobile'**
  String get walletLinkStepOpenSettings;

  /// Step 3 of the desktop link instructions.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your desktop from the next screen.'**
  String get walletLinkStepScanQr;

  /// Step 1 of the desktop link instructions (the number is added by the app).
  ///
  /// In en, this message translates to:
  /// **'Open & unlock your Vizor desktop app'**
  String get walletLinkStepUnlockDesktop;
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
