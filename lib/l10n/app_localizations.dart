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
