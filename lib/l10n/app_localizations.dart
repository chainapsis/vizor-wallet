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

  /// Body of the first paragraph of the About screen.
  ///
  /// In en, this message translates to:
  /// **'We built Keplr, the wallet used by millions across Cosmos, Ethereum, and Bitcoin. Vizor is our take on what a Zcash wallet should feel like.'**
  String get aboutBuiltByBody;

  /// Heading of the first paragraph of the About screen.
  ///
  /// In en, this message translates to:
  /// **'Built by the Keplr team'**
  String get aboutBuiltByHeading;

  /// Body of the placeholder paragraphs on the Terms and Privacy Policy screens.
  ///
  /// In en, this message translates to:
  /// **'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount.'**
  String get aboutLegalPlaceholderBody;

  /// Heading of the placeholder paragraphs on the Terms and Privacy Policy screens.
  ///
  /// In en, this message translates to:
  /// **'From the team that brought you Keplr Wallet.'**
  String get aboutLegalPlaceholderHeading;

  /// Accessibility label of a link button on mobile About; {label} is the visible button label.
  ///
  /// In en, this message translates to:
  /// **'{label} link'**
  String aboutLinkSemantics(String label);

  /// Accessibility label of the button that opens the Vizor GitHub page.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor GitHub'**
  String get aboutOpenGithub;

  /// Body of the third paragraph of the About screen; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Vizor is Apache licensed. Your keys stay on your device.\nWe don\'t see your balances or your transactions.'**
  String get aboutOpenSourceBody;

  /// Heading of the third paragraph of the About screen.
  ///
  /// In en, this message translates to:
  /// **'Open source, self-custodied'**
  String get aboutOpenSourceHeading;

  /// Accessibility label of the button that opens the Vizor website.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor website'**
  String get aboutOpenWebsite;

  /// Body of the second paragraph of the About screen.
  ///
  /// In en, this message translates to:
  /// **'Vizor is built around shielded transactions, where the sender, recipient, and amount stay private. Transparent Zcash works too, but private is the default.'**
  String get aboutShieldedBody;

  /// Heading of the second paragraph of the About screen.
  ///
  /// In en, this message translates to:
  /// **'Designed for shielded Zcash'**
  String get aboutShieldedHeading;

  /// Title of the Terms of Usage legal screen on desktop.
  ///
  /// In en, this message translates to:
  /// **'Terms of Usage'**
  String get aboutTermsTitle;

  /// Title of the About screen, also its top-bar title on mobile.
  ///
  /// In en, this message translates to:
  /// **'About Vizor Wallet'**
  String get aboutTitle;

  /// Version line under the title of the About and legal screens; {version} is the app release number such as 1.2.3.
  ///
  /// In en, this message translates to:
  /// **'Version: {version} Public Beta'**
  String aboutVersionLabel(String version);

  /// Label of the link button that opens the Vizor website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// Label of the account name field or row.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountNameLabel;

  /// Validation message when an account name is longer than 20 characters.
  ///
  /// In en, this message translates to:
  /// **'Name can be up to 20 characters.'**
  String get accountNameTooLong;

  /// Screen-reader label of the button that opens an account's action menu on desktop.
  ///
  /// In en, this message translates to:
  /// **'Account actions'**
  String get accountsActionsLabel;

  /// Toast on the mobile Accounts screen when an account's address could not be loaded for sending.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the account address'**
  String get accountsAddressLoadFailed;

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

  /// Error in the remove-account dialog when more gift card links were funded while the removal was pending.
  ///
  /// In en, this message translates to:
  /// **'More gift card links were funded. Review the warning and confirm again.'**
  String get accountsRemoveGiftCardsMoreFunded;

  /// Error in the remove-account dialog when the gift card links could not be rechecked before removal.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t recheck gift card links. Review the warning and confirm again.'**
  String get accountsRemoveGiftCardsRecheckFailed;

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

  /// [security] Placeholder of the wallet password field in the desktop remove-account dialog.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get accountsRemovePasswordHint;

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

  /// [security] Toast when an account cannot be deleted because gift cards are still being received into it.
  ///
  /// In en, this message translates to:
  /// **'Wait for incoming gift cards to finish before deleting this account.'**
  String get accountsRemoveWaitForGiftCards;

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

  /// Error when saving account name or picture changes failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the account changes'**
  String get accountsSaveFailed;

  /// Toast on the Accounts screen when sending to an account's address could not be started.
  ///
  /// In en, this message translates to:
  /// **'Send couldn\'t be started'**
  String get accountsSendFailed;

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

  /// Title of the sheet that shows a full unified address.
  ///
  /// In en, this message translates to:
  /// **'Unified address'**
  String get activityAddressUnified;

  /// Sub-line under the amount of an Ironwood migration receipt: the funds came from the Orchard balance.
  ///
  /// In en, this message translates to:
  /// **'From Orchard balance'**
  String get activityBalanceFromOrchard;

  /// Sub-line under the amount of a shielding receipt: the funds came from the transparent balance.
  ///
  /// In en, this message translates to:
  /// **'From transparent balance'**
  String get activityBalanceFromTransparent;

  /// Value of the To row of a migration receipt.
  ///
  /// In en, this message translates to:
  /// **'Ironwood balance'**
  String get activityBalanceIronwood;

  /// Value of the From row of a migration receipt.
  ///
  /// In en, this message translates to:
  /// **'Orchard balance'**
  String get activityBalanceOrchard;

  /// Row value shown after a public load of the transaction details failed; the row stays tappable.
  ///
  /// In en, this message translates to:
  /// **'Failed — try again'**
  String get activityDetailsLoadFailed;

  /// Row value and dialog button that loads one transaction's full details from the server.
  ///
  /// In en, this message translates to:
  /// **'Load publicly'**
  String get activityDetailsLoadPublicly;

  /// Label of the row that offers to load one transaction's full details from the server.
  ///
  /// In en, this message translates to:
  /// **'Full details'**
  String get activityDetailsLoadPubliclyLabel;

  /// Row value shown while a public load of the transaction details runs.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get activityDetailsLoading;

  /// Value of the Details row when Private queries cannot look up the transaction's outputs.
  ///
  /// In en, this message translates to:
  /// **'Not available in private mode'**
  String get activityDetailsNotCovered;

  /// Label of the row that lists what the private details of a transaction leave out.
  ///
  /// In en, this message translates to:
  /// **'Not shown'**
  String get activityDetailsOmittedLabel;

  /// Label of the list of a transaction's other transparent outputs when no recipient was recorded.
  ///
  /// In en, this message translates to:
  /// **'Transaction outputs'**
  String get activityDetailsOutputsLabel;

  /// Value telling that the listed outputs are the transaction's, not payments the account is known to have made.
  ///
  /// In en, this message translates to:
  /// **'Recipient not confirmed'**
  String get activityDetailsOutputsUnattributed;

  /// Value of the Details row when transparent outputs could not be looked up yet; a later sync fills them in.
  ///
  /// In en, this message translates to:
  /// **'Details unavailable — will update when the service is reachable'**
  String get activityDetailsUnavailable;

  /// Value of the To row of a send whose recipient the account did not record.
  ///
  /// In en, this message translates to:
  /// **'Unknown recipient'**
  String get activityDetailsUnknownRecipient;

  /// Estimated time for a pending TEX transfer that first waits for its funding transaction.
  ///
  /// In en, this message translates to:
  /// **'Est. 2–6 min'**
  String get activityEtaFunding;

  /// Estimated confirmation time after NU7, when blocks come faster.
  ///
  /// In en, this message translates to:
  /// **'Est. under 1 min'**
  String get activityEtaNu7;

  /// Estimated time for a pending TEX transfer after NU7.
  ///
  /// In en, this message translates to:
  /// **'Est. 1–2 min'**
  String get activityEtaNu7Funding;

  /// Estimated confirmation time beside a pending transaction (about 1 to 3 minutes).
  ///
  /// In en, this message translates to:
  /// **'Est. 1–3 min'**
  String get activityEtaStandard;

  /// Shown beside a pending transaction that is taking longer than estimated.
  ///
  /// In en, this message translates to:
  /// **'Taking longer'**
  String get activityEtaTakingLonger;

  /// Message shown when the activity list is empty.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get activityFeedEmpty;

  /// Button that reloads the activity list after it failed.
  ///
  /// In en, this message translates to:
  /// **'Retry loading activity'**
  String get activityFeedRetry;

  /// Cost breakdown of a gift card batch: card value, reserved redeem fees, and the network fee.
  ///
  /// In en, this message translates to:
  /// **'Cards {cards} ZEC · Redeem fees {fees} ZEC · {feeLabel} {fee}'**
  String activityGiftBatchBreakdown(
    String cards,
    String fees,
    String feeLabel,
    String fee,
  );

  /// Title of a completed gift card creation.
  ///
  /// In en, this message translates to:
  /// **'Created a gift card'**
  String get activityGiftCreated;

  /// Title of a completed batch of gift cards.
  ///
  /// In en, this message translates to:
  /// **'Created {count} gift cards'**
  String activityGiftCreatedMany(int count);

  /// Title of a pending gift card creation; the app appends an ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Creating a card'**
  String get activityGiftCreating;

  /// Title of a pending batch of gift cards; the app appends an ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Creating {count} cards'**
  String activityGiftCreatingMany(int count);

  /// Title of a gift card that could not be created.
  ///
  /// In en, this message translates to:
  /// **'Gift card creation failed'**
  String get activityGiftCreationFailed;

  /// Title of a failed batch of gift cards.
  ///
  /// In en, this message translates to:
  /// **'Gift card group failed'**
  String get activityGiftGroupFailed;

  /// Title of a completed gift card redemption.
  ///
  /// In en, this message translates to:
  /// **'Redeemed a gift card'**
  String get activityGiftRedeemed;

  /// Title of a pending gift card redemption; the app appends an ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Redeeming a card'**
  String get activityGiftRedeeming;

  /// Title of a gift card that could not be redeemed.
  ///
  /// In en, this message translates to:
  /// **'Gift card redemption failed'**
  String get activityGiftRedemptionFailed;

  /// Status of a gift card receipt after the card was redeemed.
  ///
  /// In en, this message translates to:
  /// **'Redeemed'**
  String get activityGiftStatusRedeemed;

  /// Status of a gift card receipt while the card is being redeemed.
  ///
  /// In en, this message translates to:
  /// **'Redeeming…'**
  String get activityGiftStatusRedeeming;

  /// Label of the total cost of a gift card batch that failed.
  ///
  /// In en, this message translates to:
  /// **'Planned total'**
  String get activityGiftTotalPlanned;

  /// Label of the total cost of a completed gift card batch.
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get activityGiftTotalSpent;

  /// Label of the total cost of a gift card batch that is pending.
  ///
  /// In en, this message translates to:
  /// **'Submitted total'**
  String get activityGiftTotalSubmitted;

  /// Error shown on the desktop activity screen when loading failed.
  ///
  /// In en, this message translates to:
  /// **'Activity could not be loaded.'**
  String get activityLoadFailedDesktop;

  /// Error shown on the mobile activity screen when loading failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load activity. Try again in a moment.'**
  String get activityLoadFailedMobile;

  /// Item in the list of what private details leave out: outputs beyond the second.
  ///
  /// In en, this message translates to:
  /// **'outputs after the second'**
  String get activityOmissionLaterOutputs;

  /// Item in the list of what private details leave out: how many outputs are not listed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more output} other{{count} more outputs}}'**
  String activityOmissionMoreOutputs(int count);

  /// Item in the list of what private details leave out: further sender addresses.
  ///
  /// In en, this message translates to:
  /// **'other sending addresses'**
  String get activityOmissionOtherSenders;

  /// Item in the list of what private details leave out: an output address.
  ///
  /// In en, this message translates to:
  /// **'an output address'**
  String get activityOmissionOutputAddress;

  /// Item in the list of what private details leave out: the sender address.
  ///
  /// In en, this message translates to:
  /// **'the sending address'**
  String get activityOmissionSender;

  /// Item in the list of what private details leave out: inputs owned by other wallets.
  ///
  /// In en, this message translates to:
  /// **'inputs from other wallets'**
  String get activityOmissionSharedFunding;

  /// Item in the list of what private details leave out: the shielded part of the funds.
  ///
  /// In en, this message translates to:
  /// **'the shielded part of the funding'**
  String get activityOmissionShieldedFunding;

  /// Subtitle of a Pay activity row: the payment was made from shielded ZEC.
  ///
  /// In en, this message translates to:
  /// **'from shielded ZEC'**
  String get activityPayFromShielded;

  /// Subtitle of a Pay activity row: shielded ZEC paid out to a network.
  ///
  /// In en, this message translates to:
  /// **'from shielded ZEC · {network}'**
  String activityPayFromShieldedOnChain(String network);

  /// Title of the Pay detail screen when the deposit was incomplete.
  ///
  /// In en, this message translates to:
  /// **'Payment incomplete'**
  String get activityPayIncomplete;

  /// Title of a completed Pay activity row or detail screen.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get activityPayPaid;

  /// Title of the Pay detail screen while the payment is pending.
  ///
  /// In en, this message translates to:
  /// **'Paying ...'**
  String get activityPayPaying;

  /// Badge on an activity row for a transaction that involves more than one pool.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get activityPoolMixed;

  /// Body of the dialog that confirms loading one transaction's details from the server.
  ///
  /// In en, this message translates to:
  /// **'Vizor will ask the server for this one transaction to show what private lookups leave out.'**
  String get activityPublicLookupBody;

  /// Title of the dialog that confirms loading one transaction's details from the server.
  ///
  /// In en, this message translates to:
  /// **'Load details publicly?'**
  String get activityPublicLookupTitle;

  /// [security] Warning in the dialog that confirms loading one transaction's details from the server: what the server learns.
  ///
  /// In en, this message translates to:
  /// **'The server learns that this wallet is interested in this transaction, and without Tor, your IP address.'**
  String get activityPublicLookupWarning;

  /// Label of a row on a transaction receipt: the amount moved to Ironwood.
  ///
  /// In en, this message translates to:
  /// **'Amount migrated'**
  String get activityReceiptAmountMigrated;

  /// Label of a row on a transaction receipt: the fee for creating a gift card.
  ///
  /// In en, this message translates to:
  /// **'Card fee'**
  String get activityReceiptCardFee;

  /// Label of a row on a transaction receipt: a notice about transaction details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get activityReceiptDetails;

  /// Short notice, also a sheet title, that some details of an entry are not known yet.
  ///
  /// In en, this message translates to:
  /// **'Details incomplete'**
  String get activityReceiptDetailsIncomplete;

  /// Explains why a receipt is marked as having incomplete details.
  ///
  /// In en, this message translates to:
  /// **'Some details of this transaction, such as its recipients, memos, or fee, are not known yet. The amount shown may change.'**
  String get activityReceiptDetailsIncompleteHelp;

  /// Part of the gift card batch cost breakdown: the network fee while the batch is pending or failed.
  ///
  /// In en, this message translates to:
  /// **'Estimated network fee'**
  String get activityReceiptEstimatedNetworkFee;

  /// Label of a row on a transaction receipt: the sender or the source of funds.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get activityReceiptFrom;

  /// Value of the Details row on a receipt whose details are not all known yet.
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get activityReceiptIncomplete;

  /// Message shown when a transaction receipt could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Transaction could not be loaded.'**
  String get activityReceiptLoadFailed;

  /// Message shown while a transaction receipt is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading transaction…'**
  String get activityReceiptLoading;

  /// Label of a row on a transaction receipt: the balance change of a transaction that is not shown as an external payment.
  ///
  /// In en, this message translates to:
  /// **'Net change'**
  String get activityReceiptNetChange;

  /// Label of a row on a transaction receipt: one transparent output of the transaction, followed by its address and amount.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get activityReceiptOutput;

  /// Message shown when the latest status of a transaction could not be refreshed.
  ///
  /// In en, this message translates to:
  /// **'Latest transaction status could not be refreshed.'**
  String get activityReceiptRefreshFailed;

  /// Label of a row on a transaction receipt: the transaction status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get activityReceiptStatus;

  /// Tooltip explaining a network fee when the account's share of it is not known.
  ///
  /// In en, this message translates to:
  /// **'Total fee for this transaction. Your account\'s share of this fee is unknown.'**
  String get activityReceiptUnattributedFeeHelp;

  /// Timestamp of an activity row from today on desktop.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String activityRowToday(String time);

  /// Subtitle of a pending activity row while the app has no connection.
  ///
  /// In en, this message translates to:
  /// **'Waiting for connection'**
  String get activityRowWaitingForConnection;

  /// Timestamp of an activity row from yesterday on desktop.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String activityRowYesterday(String time);

  /// Heading of the activity section for entries without a date.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get activitySectionEarlier;

  /// Heading of the activity section for the current week.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get activitySectionThisWeek;

  /// Value of the From row when the sender is in a shielded pool, so no address is known.
  ///
  /// In en, this message translates to:
  /// **'Shielded sender'**
  String get activitySenderShielded;

  /// Value of the From row when the sender cannot be determined.
  ///
  /// In en, this message translates to:
  /// **'Unknown sender'**
  String get activitySenderUnknown;

  /// Status value of a mobile receipt for a transaction that expired before mining; no funds were spent.
  ///
  /// In en, this message translates to:
  /// **'Failed, funds returned'**
  String get activityStatusFailedFundsReturned;

  /// Status value of a swap whose deposit was smaller than the quote requires.
  ///
  /// In en, this message translates to:
  /// **'Incomplete deposit'**
  String get activityStatusIncompleteDeposit;

  /// Subtitle of a swap activity row: an asset and the chain it lives on.
  ///
  /// In en, this message translates to:
  /// **'{symbol} on {chain}'**
  String activitySwapAssetOnChain(String symbol, String chain);

  /// Title of the sub-row of a completed swap that shows the deposited asset.
  ///
  /// In en, this message translates to:
  /// **'Deposited {symbol}'**
  String activitySwapDepositedAsset(String symbol);

  /// Timestamp of a swap sub-row that settled some minutes ago.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String activitySwapMinutesAgo(int minutes);

  /// Title of the sub-row of a completed swap that shows the received asset.
  ///
  /// In en, this message translates to:
  /// **'Received {symbol}'**
  String activitySwapReceivedAsset(String symbol);

  /// Status of a swap activity row that shows which step of the swap it is on.
  ///
  /// In en, this message translates to:
  /// **'{current}/{total} In progress'**
  String activitySwapStep(int current, int total);

  /// Title of a completed swap activity row.
  ///
  /// In en, this message translates to:
  /// **'Swapped'**
  String get activitySwapSwapped;

  /// Title of a pending swap activity row.
  ///
  /// In en, this message translates to:
  /// **'Swapping...'**
  String get activitySwapSwapping;

  /// Subtitle of the amount of a swap that expired.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get activitySwapTimeout;

  /// Title of the mobile swap detail screen when the swap is not loaded.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get activitySwapTitle;

  /// Title of an activity row or receipt for funds moved from Orchard to Ironwood.
  ///
  /// In en, this message translates to:
  /// **'Migrated to Ironwood'**
  String get activityTitleMigrated;

  /// Title of the mobile receipt of a pending Ironwood migration.
  ///
  /// In en, this message translates to:
  /// **'Migrating to Ironwood...'**
  String get activityTitleMigrating;

  /// Title of a pending Ironwood migration activity row; the app appends an ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Migrating to Ironwood'**
  String get activityTitleMigratingVerb;

  /// Title of an activity row or receipt for a failed move to Ironwood.
  ///
  /// In en, this message translates to:
  /// **'Migration failed'**
  String get activityTitleMigrationFailed;

  /// Title of a receipt for an incoming transaction that failed.
  ///
  /// In en, this message translates to:
  /// **'Receive failed'**
  String get activityTitleReceiveFailed;

  /// Title of the desktop receipt of an incoming transaction that is pending.
  ///
  /// In en, this message translates to:
  /// **'Receive in progress...'**
  String get activityTitleReceiveInProgress;

  /// Title of the desktop receipt of an incoming transaction that completed.
  ///
  /// In en, this message translates to:
  /// **'Received successfully'**
  String get activityTitleReceivedSuccessfully;

  /// Title of the mobile receipt of an incoming transaction that is pending.
  ///
  /// In en, this message translates to:
  /// **'Receiving...'**
  String get activityTitleReceiving;

  /// Title of a pending incoming activity row; the app appends an ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get activityTitleReceivingVerb;

  /// Title of a pending outgoing activity row; the app appends an ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get activityTitleSendingVerb;

  /// Title of an activity row for an outgoing transaction.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get activityTitleSent;

  /// Title of an activity row or receipt for funds moved into a shielded pool.
  ///
  /// In en, this message translates to:
  /// **'Shielded'**
  String get activityTitleShielded;

  /// Title of a receipt for a failed move into a shielded pool.
  ///
  /// In en, this message translates to:
  /// **'Shielding failed'**
  String get activityTitleShieldingFailed;

  /// Title of the desktop receipt of a pending shielding transaction.
  ///
  /// In en, this message translates to:
  /// **'Shielding in progress...'**
  String get activityTitleShieldingInProgress;

  /// Title of a pending shielding activity row; the app appends an ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Shielding'**
  String get activityTitleShieldingVerb;

  /// Title of a receipt or activity row for a transaction of unknown kind.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get activityTitleTransaction;

  /// Toast on the mobile receipt after the transaction hash was copied.
  ///
  /// In en, this message translates to:
  /// **'Transaction Hash Copied'**
  String get activityToastHashCopiedMobile;

  /// Button and dialog title that adds a new contact.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get addressBookAddContact;

  /// Placeholder of the contact address field in the desktop dialog.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get addressBookAddressHintDesktop;

  /// Placeholder of the contact address field on mobile.
  ///
  /// In en, this message translates to:
  /// **'Add an address'**
  String get addressBookAddressHintMobile;

  /// Label of the contact address field.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressBookAddressLabel;

  /// Validation message when the contact address field is empty.
  ///
  /// In en, this message translates to:
  /// **'Add an address'**
  String get addressBookAddressMissing;

  /// Accessibility label of the button that clears the contact address on mobile.
  ///
  /// In en, this message translates to:
  /// **'Clear address'**
  String get addressBookClearAddress;

  /// Accessibility label of the button that clears the contact name on mobile.
  ///
  /// In en, this message translates to:
  /// **'Clear name'**
  String get addressBookClearName;

  /// Accessibility label of the button that clears the search text.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get addressBookClearSearch;

  /// Accessibility label of the menu button on a contact row. {label} is the contact's name.
  ///
  /// In en, this message translates to:
  /// **'{label} actions'**
  String addressBookContactActions(String label);

  /// Contact menu item and title of the dialog that edits a contact.
  ///
  /// In en, this message translates to:
  /// **'Edit contact'**
  String get addressBookEditContact;

  /// Body text of the empty address book.
  ///
  /// In en, this message translates to:
  /// **'Add your first contact to get started.'**
  String get addressBookEmptyBody;

  /// Headline of the address book when it has no contacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get addressBookEmptyTitle;

  /// Error under an address field when the text is not a valid Bitcoin address.
  ///
  /// In en, this message translates to:
  /// **'Invalid Bitcoin address'**
  String get addressBookInvalidBitcoin;

  /// Error under an address field when the text is not a valid address for EVM chains such as Ethereum or Base.
  ///
  /// In en, this message translates to:
  /// **'Invalid EVM address'**
  String get addressBookInvalidEvm;

  /// Error under an address field when the text is not a valid NEAR account.
  ///
  /// In en, this message translates to:
  /// **'Invalid NEAR address'**
  String get addressBookInvalidNear;

  /// Error under an address field when the text is not a valid Solana address.
  ///
  /// In en, this message translates to:
  /// **'Invalid Solana address'**
  String get addressBookInvalidSolana;

  /// Error under an address field when the text is not a valid Zcash address for the current network.
  ///
  /// In en, this message translates to:
  /// **'Invalid Zcash address'**
  String get addressBookInvalidZcash;

  /// Validation message when the contact label is longer than 20 characters.
  ///
  /// In en, this message translates to:
  /// **'Use 1-20 characters'**
  String get addressBookLabelLength;

  /// Validation message when the contact label field is empty.
  ///
  /// In en, this message translates to:
  /// **'Add a label'**
  String get addressBookLabelMissing;

  /// Error shown in place of the address book when loading fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your contacts. Try again, or contact support if this keeps happening.'**
  String get addressBookLoadFailed;

  /// Placeholder of the contact name field on mobile.
  ///
  /// In en, this message translates to:
  /// **'Add a name'**
  String get addressBookNameHint;

  /// Label of the contact name field on mobile.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get addressBookNameLabel;

  /// Warning under an address field when a NEAR account name has no .near suffix. The address can still be saved.
  ///
  /// In en, this message translates to:
  /// **'NEAR accounts usually end in .near — double-check this address'**
  String get addressBookNearSuffixWarning;

  /// Label of the network selector in the mobile contact sheet.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get addressBookNetworkLabel;

  /// Message when the network picker search matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No networks found'**
  String get addressBookNoNetworks;

  /// Body text when an address book search matches nothing.
  ///
  /// In en, this message translates to:
  /// **'Try to modify your search'**
  String get addressBookNoResultsBody;

  /// Headline when an address book search matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No contacts were found'**
  String get addressBookNoResultsTitle;

  /// Accessibility label of the button that closes the contact picker.
  ///
  /// In en, this message translates to:
  /// **'Close contacts'**
  String get addressBookPickerClose;

  /// Message in the contact picker when no contact matches.
  ///
  /// In en, this message translates to:
  /// **'No contacts found'**
  String get addressBookPickerEmptyTitle;

  /// Error in the contact picker when loading contacts fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load contacts. Try again.'**
  String get addressBookPickerLoadFailed;

  /// Placeholder of the contact picker search field.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get addressBookPickerSearchHint;

  /// Body of the desktop remove dialog. {label} is the contact's name.
  ///
  /// In en, this message translates to:
  /// **'{label} will be removed from your contacts.'**
  String addressBookRemoveBody(String label);

  /// Body of the desktop remove dialog when the contact is unknown.
  ///
  /// In en, this message translates to:
  /// **'This contact will be removed.'**
  String get addressBookRemoveBodyUnknown;

  /// Body of the mobile remove confirmation. {label} is the contact's name.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" will be removed from your contacts. This does not affect any past transactions.'**
  String addressBookRemoveConfirmBody(String label);

  /// Title of the mobile confirmation sheet that removes a contact.
  ///
  /// In en, this message translates to:
  /// **'Remove contact?'**
  String get addressBookRemoveConfirmTitle;

  /// Contact menu item and title of the dialog that removes a contact.
  ///
  /// In en, this message translates to:
  /// **'Remove contact'**
  String get addressBookRemoveContact;

  /// Error in the desktop remove dialog when deleting a contact fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove contact. Try again.'**
  String get addressBookRemoveFailed;

  /// Toast on mobile when deleting a contact fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove the contact. Please try again.'**
  String get addressBookRemoveFailedMobile;

  /// Error in the desktop contact dialog when saving fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save contact. Try again.'**
  String get addressBookSaveFailed;

  /// Toast on mobile when saving a contact fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the contact. Please try again.'**
  String get addressBookSaveFailedMobile;

  /// Accessibility label of the button that scans an address QR code.
  ///
  /// In en, this message translates to:
  /// **'Scan address QR'**
  String get addressBookScanAddressQr;

  /// Title of the camera scanner that reads a contact address. {network} is the chain name such as Ethereum.
  ///
  /// In en, this message translates to:
  /// **'Scan {network} QR code'**
  String addressBookScanQrTitle(String network);

  /// Accessibility label of the search field in the address book and network picker.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get addressBookSearch;

  /// Placeholder of the address book search field.
  ///
  /// In en, this message translates to:
  /// **'Search for label or network'**
  String get addressBookSearchHint;

  /// Placeholder of the network picker search field.
  ///
  /// In en, this message translates to:
  /// **'Search network'**
  String get addressBookSearchNetwork;

  /// Title and accessibility label of the network picker.
  ///
  /// In en, this message translates to:
  /// **'Select network'**
  String get addressBookSelectNetwork;

  /// Description in the mobile address scanner when the device has no camera.
  ///
  /// In en, this message translates to:
  /// **'Address QR scanning needs a camera on this device.'**
  String get addressScanAddressCameraNeeded;

  /// Camera name with a marker that it is the system default. {name} is the device-reported camera name.
  ///
  /// In en, this message translates to:
  /// **'{name} (Default)'**
  String addressScanCameraDefaultSuffix(String name);

  /// Description in the mobile QR scanner when the device has no camera.
  ///
  /// In en, this message translates to:
  /// **'QR scanning needs a camera on this device.'**
  String get addressScanCameraNeeded;

  /// Message over the full-screen scanner when camera permission is off.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. Allow it in Settings to scan addresses.'**
  String get addressScanCameraOff;

  /// Description in the desktop QR scanner when the device has no camera.
  ///
  /// In en, this message translates to:
  /// **'Address QR scanning requires a camera on this device.'**
  String get addressScanCameraRequired;

  /// Message over the full-screen scanner when the system restricts the camera.
  ///
  /// In en, this message translates to:
  /// **'Screen Time or device management is blocking the camera on this device.'**
  String get addressScanCameraRestricted;

  /// Accessibility label of the close button of the QR scanner.
  ///
  /// In en, this message translates to:
  /// **'Close scanner'**
  String get addressScanCloseScanner;

  /// Title in the desktop QR scanner when the camera permission was denied.
  ///
  /// In en, this message translates to:
  /// **'You\'ve denied Camera access'**
  String get addressScanDeniedTitle;

  /// Title of the desktop QR scanner while waiting for the camera permission.
  ///
  /// In en, this message translates to:
  /// **'Grant access to your camera'**
  String get addressScanGrantAccess;

  /// Title of the QR scanner that reads an address.
  ///
  /// In en, this message translates to:
  /// **'Scan the address QR code'**
  String get addressScanTitle;

  /// Caption under the viewfinder of the mobile QR scanner.
  ///
  /// In en, this message translates to:
  /// **'Scan a Zcash QR code to continue'**
  String get addressScanZcashPrompt;

  /// Back-link name of the donation screen.
  ///
  /// In en, this message translates to:
  /// **'Donation'**
  String get appBackDonation;

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

  /// Back-link name of the Receive screen.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get appBackReceive;

  /// Back-link name of a review step (send, swap, vote).
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get appBackReview;

  /// Back-link name of the Send screen.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get appBackSend;

  /// Back-link name of a status screen (send, vote).
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get appBackStatus;

  /// Back-link name of the vote submitted screen.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get appBackSubmitted;

  /// Back-link name of a transaction detail screen.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get appBackTransaction;

  /// Hint shown on Android after the first Back press at the root, telling the user to press Back again to exit the app.
  ///
  /// In en, this message translates to:
  /// **'Go back again to exit'**
  String get appExitBackHint;

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

  /// Title when Vizor cannot start because storage is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to open Vizor'**
  String get appOpenFailedTitle;

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

  /// [security] Message on the unlock screen after the device's biometrics changed, so the passcode is required. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Face ID changed. Enter your passcode.} touchId{Touch ID changed. Enter your passcode.} fingerprint{Fingerprint changed. Enter your passcode.} other{Biometric unlock changed. Enter your passcode.}}'**
  String biometricChangedMessage(String kind);

  /// Button label that turns on biometric unlock. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Enable Face ID} touchId{Enable Touch ID} fingerprint{Enable fingerprint} other{Enable biometrics}}'**
  String biometricEnableLabel(String kind);

  /// Biometric method name used inside a sentence. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Face ID} touchId{Touch ID} fingerprint{fingerprint} other{biometrics}}'**
  String biometricNameInline(String kind);

  /// Biometric method name as the object of the heading 'Unlock your wallet with ...'. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Face ID} touchId{Touch ID} fingerprint{your fingerprint} other{biometrics}}'**
  String biometricNameOnboardingTitle(String kind);

  /// Biometric method name used as a standalone label or row title. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Face ID} touchId{Touch ID} fingerprint{Fingerprint} other{Biometrics}}'**
  String biometricNameStandalone(String kind);

  /// Button label that unlocks the wallet with biometrics. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Sign in with Face ID} touchId{Sign in with Touch ID} fingerprint{Sign in with fingerprint} other{Sign in with biometrics}}'**
  String biometricSignInLabel(String kind);

  /// Name of the biometric unlock feature used inside a sentence. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Face ID unlock} touchId{Touch ID unlock} fingerprint{fingerprint unlock} other{biometric unlock}}'**
  String biometricUnlockFeatureInline(String kind);

  /// Name of the biometric unlock feature as a capitalized label. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Face ID unlock} touchId{Touch ID unlock} fingerprint{Fingerprint unlock} other{Biometric unlock}}'**
  String biometricUnlockFeatureLabel(String kind);

  /// Checkbox label on the unlock screen that remembers biometrics for the next unlock. {kind} is the device's biometric type: face, touchId, fingerprint or none. Face ID and Touch ID are Apple product names and stay in English.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, face{Use Face ID next time} touchId{Use Touch ID next time} fingerprint{Use fingerprint next time} other{Use biometrics next time}}'**
  String biometricUseNextTimeLabel(String kind);

  /// [security] Name of the optional BIP39 passphrase (25th word), not the seed phrase.
  ///
  /// In en, this message translates to:
  /// **'BIP39 Passphrase'**
  String get bip39PassphraseTitle;

  /// [security] Shows the optional BIP39 passphrase value.
  ///
  /// In en, this message translates to:
  /// **'BIP39 Passphrase: {passphrase}'**
  String bip39PassphraseValue(String passphrase);

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. A software send stopped part way: {sent} of {total} transactions went out ({txids} lists their IDs). {detail} is the error from the network, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Broadcast failed after {sent}/{total} txs sent ({txids}). Error: {detail}'**
  String broadcastNoticeBroadcastFailed(
    String sent,
    String total,
    String txids,
    String detail,
  );

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. The network accepted the transaction but the wallet could not record it. {detail} is the storage error, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Broadcast succeeded (txid={txid}) but local storage failed. {detail}. The transaction is on the network; check an explorer to confirm, and do not attempt to send again until the next sync reconciles your balance.'**
  String broadcastNoticeBroadcastStorageFailed(String txid, String detail);

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. The wallet created the transaction but could not open its database to send it. {detail} is the database error, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Failed to open DB for broadcast after local transaction creation: {detail}'**
  String broadcastNoticeDatabaseUnavailable(String detail);

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. The device approval took so long that the transaction would expire; nothing was sent. {expiryHeight} and {chainHeight} are block heights.
  ///
  /// In en, this message translates to:
  /// **'Hardware signing request expired before broadcast: txid={txid}, expiry height {expiryHeight}, current chain height {chainHeight}. Start the signing flow again so Vizor can build a fresh transaction.'**
  String broadcastNoticeExpired(
    String txid,
    String expiryHeight,
    String chainHeight,
  );

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. The wallet created the transaction but could not read it back to send it. {detail} is the database error, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Failed to get raw tx for {txid} after local transaction creation: {detail}'**
  String broadcastNoticeRawTransactionUnavailable(String txid, String detail);

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. The connection ended before the server answered. {detail} is the connection status, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Broadcast response was unavailable for txid={txid} ({detail}). The transaction may already be on the network. Do not send again until sync or an explorer confirms whether this transaction was accepted.'**
  String broadcastNoticeResponseUnavailable(String txid, String detail);

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. Follows the storage failure sentence: the wallet also could not keep the spent funds reserved. {detail} is the error, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Proposal input-lock retention also failed: {detail}.'**
  String broadcastNoticeRetentionFailed(String detail);

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. Follows the sentence about the unavailable response.
  ///
  /// In en, this message translates to:
  /// **'It was stored locally and will retry automatically during sync until it is confirmed or expires.'**
  String get broadcastNoticeRetryingLocally;

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. Earlier transactions of the batch went out; transaction {index} of {total} could not be sent. {detail} is the network error, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the broadcast route for transaction {index} of {total}; it was not stored: {detail}'**
  String broadcastNoticeRouteUnavailable(
    String index,
    String total,
    String detail,
  );

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. May follow another sentence of the result. {detail} is the storage error, shown in English.
  ///
  /// In en, this message translates to:
  /// **'A transaction may already be on the network, but local storage failed: {detail}. Do not send again until sync or an explorer confirms the result.'**
  String broadcastNoticeStorageFailed(String detail);

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. Follows a sentence about a transaction that failed or has an unknown result: the transactions that went out, or may have, were saved so sync can recover them.
  ///
  /// In en, this message translates to:
  /// **'The accepted-or-ambiguous transaction prefix was stored locally for recovery.'**
  String get broadcastNoticeStoredLocally;

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. Follows the sentence about the unavailable response. {detail} is the storage error, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Local tracking also failed: {detail}. Check an explorer before retrying this send.'**
  String broadcastNoticeTrackingFailed(String detail);

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. Earlier transactions of the batch went out; the server rejected transaction {index} of {total}. {detail} is the rejection, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Transaction {index} of {total} was rejected and was not stored: {detail}'**
  String broadcastNoticeTransactionRejected(
    String index,
    String total,
    String detail,
  );

  /// [security] Part of a hardware-wallet broadcast result shown on the send, shield, swap and Gift Card screens; it tells the user whether the transaction may already be on the network. The connection ended while transaction {index} of {total} was being sent, so it may be on the network. {detail} is the connection error, shown in English.
  ///
  /// In en, this message translates to:
  /// **'Transaction {index} of {total} has an unknown broadcast result: {detail}'**
  String broadcastNoticeTransactionUnknown(
    String index,
    String total,
    String detail,
  );

  /// Tooltip on a password field warning that Caps Lock is on.
  ///
  /// In en, this message translates to:
  /// **'Caps Lock is on'**
  String get capsLockWarning;

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

  /// Status label of the Ledger shield failure panel after an error. Shared by: home, send.
  ///
  /// In en, this message translates to:
  /// **'Action needed'**
  String get commonActionNeeded;

  /// Label of the collapsed prompt that adds an optional message to a payment request. Shared by: receive, send.
  ///
  /// In en, this message translates to:
  /// **'Add a message'**
  String get commonAddAMessage;

  /// Button, screen name and step label for adding another account.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get commonAddAccount;

  /// Toast after an address is copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get commonAddressCopied;

  /// Placeholder of the Pay recipient field on mobile; names the chain the address must belong to. Shared by: pay, swap.
  ///
  /// In en, this message translates to:
  /// **'{chain} address'**
  String commonAddressForChain(String chain);

  /// Label of the contact name field in the desktop contact dialog. Shared by: address, pay.
  ///
  /// In en, this message translates to:
  /// **'Address label'**
  String get commonAddressLabel;

  /// Label of a row on a transaction receipt: the transferred amount. Shared by: activity, app, pay, receive, send, swap. Shared by: common, migration.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get commonAmount;

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

  /// Button on the shield result screens that returns to the wallet. Shared by: home, send.
  ///
  /// In en, this message translates to:
  /// **'Back to wallet'**
  String get commonBackToWallet;

  /// Placeholder shown for the amount, fee or button while the Immediate migration plan is being calculated.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get commonCalculatingEllipsis;

  /// Shown instead of the overall progress while the total number of migration transactions is not known yet. Shared by: migration, payment.
  ///
  /// In en, this message translates to:
  /// **'Calculating total'**
  String get commonCalculatingTotal;

  /// Label of the camera row on the Keystone scanner and the camera picker. Shared by: keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get commonCamera;

  /// Title in the mobile QR scanner when the camera permission was denied. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'You\'ve denied camera access'**
  String get commonCameraDeniedTitle;

  /// Description when camera access is requested or denied. The line break splits the text for the narrow dialog. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Request again, or enable manually\nin the System settings.'**
  String get commonCameraRequestAgainHint;

  /// Description in the mobile QR scanner when Screen Time or device management restricts the camera. The line break splits the text. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Screen Time or device management\nis blocking the camera.'**
  String get commonCameraRestrictedBody;

  /// Title in the mobile QR scanner when the camera is restricted by the system. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Camera access is restricted'**
  String get commonCameraRestrictedTitle;

  /// Title shown when the camera cannot be used. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get commonCameraUnavailable;

  /// Message over the full-screen scanner when the camera cannot start. Shared by: address, home.
  ///
  /// In en, this message translates to:
  /// **'The camera is unavailable right now.'**
  String get commonCameraUnavailableNow;

  /// Button that closes a modal or sheet without applying a change.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Error on the shield screens when cancelling could not release the pending work. Shared by: home, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Could not finish cancelling. Please try again.'**
  String get commonCancelFailedRetry;

  /// Screen-reader label of the close button on the mobile Ledger shield panel while shielding can still be cancelled. Shared by: home, ledger.
  ///
  /// In en, this message translates to:
  /// **'Cancel shielding'**
  String get commonCancelShielding;

  /// Toast when leaving a flow could not cancel its pending work.
  ///
  /// In en, this message translates to:
  /// **'Could not finish cancellation. Try again.'**
  String get commonCancellationFailed;

  /// Label shown on a button or title while a signing request is being cancelled. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get commonCancelling;

  /// [security] Warning that a destructive action is permanent.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get commonCannotBeUndone;

  /// Label of a row on a transaction receipt: the number of gift cards in a batch. Shared by: activity, payment.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get commonCards;

  /// Section label above the network selector and address field in the contact dialog. Shared by: address, pay.
  ///
  /// In en, this message translates to:
  /// **'Chain & address'**
  String get commonChainAndAddress;

  /// Accessibility label of the avatar button in the contact dialog. Shared by: address, pay.
  ///
  /// In en, this message translates to:
  /// **'Change contact picture'**
  String get commonChangeContactPicture;

  /// Button label to re-check Bluetooth access. Shared by: ledger, payment, send, voting.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get commonCheckAgain;

  /// Status while Vizor checks something.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get commonChecking;

  /// Label of the primary button on the payment request card while the request is being checked. Shared by: send, settings. Shared by: common, payment.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get commonCheckingEllipsis;

  /// Subtitle of a pending activity row while the app checks the transaction status. Shared by: activity, swap.
  ///
  /// In en, this message translates to:
  /// **'Checking status'**
  String get commonCheckingStatus;

  /// Title while Vizor checks that the Zcash app is ready on the Ledger. Shared by: ledger, voting.
  ///
  /// In en, this message translates to:
  /// **'Checking your Ledger'**
  String get commonCheckingYourLedger;

  /// Button that clears the secret passphrase words entered so far. Shared by: onboarding, send.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// Accessibility label of the button that clears the contact label. Shared by: address, pay.
  ///
  /// In en, this message translates to:
  /// **'Clear contact label'**
  String get commonClearContactLabel;

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

  /// Accessibility label of the button that removes the optional message field. Shared by: receive, send.
  ///
  /// In en, this message translates to:
  /// **'Close message'**
  String get commonCloseMessage;

  /// Name of the coinholder voting feature.
  ///
  /// In en, this message translates to:
  /// **'Coinholder voting'**
  String get commonCoinholderVoting;

  /// Status value of a transaction or swap that finished. Shared by: activity, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get commonCompleted;

  /// Title asking the user to confirm on the Ledger that the Zcash app may open. Shared by: ledger, voting.
  ///
  /// In en, this message translates to:
  /// **'Confirm opening Zcash'**
  String get commonConfirmOpeningZcash;

  /// [security] Subtitle of the second step: the user confirms on the Keystone and scans its signature QR code. Shared by: keystone, send.
  ///
  /// In en, this message translates to:
  /// **'Confirm with Keystone'**
  String get commonConfirmWithKeystone;

  /// Status label while migration transfers wait for network confirmations. Shared by: migration, payment.
  ///
  /// In en, this message translates to:
  /// **'Confirming'**
  String get commonConfirming;

  /// Title of the Ledger connection dialog. Shared by: ledger, onboarding.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger'**
  String get commonConnectLedger;

  /// Status while connecting to the saved Ledger. Shared by: ledger, settings.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get commonConnecting;

  /// Placeholder of the contact name field in the desktop dialog. Shared by: address, pay.
  ///
  /// In en, this message translates to:
  /// **'Add label 1-20 characters'**
  String get commonContactLabelHint;

  /// Title of the address book screen. Shared by: address, app, pay, send.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get commonContacts;

  /// Button that moves to the next step.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// [security] Destructive button on the Immediate migration review that broadcasts the less private migration after the privacy warning. Shared by: migration, onboarding.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get commonContinueAnyway;

  /// Primary button label on the mobile swap screen that opens the review. Shared by: swap, voting.
  ///
  /// In en, this message translates to:
  /// **'Continue to review'**
  String get commonContinueToReview;

  /// Toast after a value is copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// Button that copies a value to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// Button that copies an address to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get commonCopyAddress;

  /// Button that copies the Gift Card link to the clipboard. Shared by: payment, receive.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get commonCopyLink;

  /// Button label and accessibility label that copies the shielded address. Shared by: receive, sidebar.
  ///
  /// In en, this message translates to:
  /// **'Copy shielded address'**
  String get commonCopyShieldedAddress;

  /// Toast shown when cancelling a gift card claim during wallet setup fails. Shared by: app, payment.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t close the card. Try again.'**
  String get commonCouldnTCloseTheCardTry;

  /// Status of a gift card receipt after the card was created. Shared by: activity, payment.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get commonCreated;

  /// Status of a gift card receipt while the card is being created. Shared by: activity, payment.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get commonCreating;

  /// Heading of the step where the user names the account and picks a profile picture; also the back label pointing to it. Shared by: onboarding, payment.
  ///
  /// In en, this message translates to:
  /// **'Customise Account'**
  String get commonCustomiseAccount;

  /// Onboarding step for naming the wallet and picking a picture. Shared by: onboarding, payment.
  ///
  /// In en, this message translates to:
  /// **'Customise wallet'**
  String get commonCustomiseWallet;

  /// Detail tag in the camera picker for the default camera. Shared by: keystone, voting.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get commonDefault;

  /// Fallback name of the camera in the desktop QR scanner footer. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Default camera'**
  String get commonDefaultCamera;

  /// Screen-reader label of the close button on a toast.
  ///
  /// In en, this message translates to:
  /// **'Dismiss notification'**
  String get commonDismissNotification;

  /// Primary button of the mobile Pay submitted screen; goes to Home. Shared by: pay, send.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Button on the in-app update prompt that starts downloading the update. Shared by: app, send.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get commonDownload;

  /// Compact countdown until the deposit deadline when exactly one hour remains; 'hr' abbreviates hour.
  ///
  /// In en, this message translates to:
  /// **'1hr'**
  String get commonDurationOneHour;

  /// Compact countdown until the deposit deadline when exactly one minute remains; 'min' abbreviates minute.
  ///
  /// In en, this message translates to:
  /// **'1min'**
  String get commonDurationOneMinute;

  /// Button that edits the value shown next to it. Shared by: onboarding, send.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// Title in the desktop QR scanner when Windows blocks the camera. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Enable Windows camera access'**
  String get commonEnableWindowsCameraAccess;

  /// Placeholder of the Gift Card amount field. Shared by: payment, send.
  ///
  /// In en, this message translates to:
  /// **'Enter amount'**
  String get commonEnterAmount;

  /// Screen reader label of a currency toggle on the Gift Card amount field; {currency} is ZEC or USD. Shared by: payment, send.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in {currency}'**
  String commonEnterAmountIn(String currency);

  /// Accessibility label of the toggle that switches the mobile Pay amount input to US dollars. Shared by: pay, receive.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in USD'**
  String get commonEnterAmountInUsd;

  /// An error summary line, then a technical details line. {details} is raw error text and is not translated. Shared by: receive, migration, voting.
  ///
  /// In en, this message translates to:
  /// **'{message}\nDetails: {details}'**
  String commonErrorWithDetails(String message, String details);

  /// Status value of a transaction or swap that failed. Shared by: activity, send, settings, swap.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get commonFailed;

  /// Body of the sheet for a feature that is not available on this platform yet.
  ///
  /// In en, this message translates to:
  /// **'This feature is still in progress.'**
  String get commonFeatureInProgress;

  /// Link on the mobile Pay review recipient row that shows the whole address. Shared by: pay, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Full address'**
  String get commonFullAddress;

  /// [security] Primary button in the desktop Keystone modal that opens the scanner to read the signature QR code from the device. Shared by: send, swap. Shared by: common, migration.
  ///
  /// In en, this message translates to:
  /// **'Get signature'**
  String get commonGetSignature;

  /// Button that returns to the previous screen.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get commonGoBack;

  /// Button that leaves the migration screen and returns to the home screen. Shared by: migration, payment, voting.
  ///
  /// In en, this message translates to:
  /// **'Go home'**
  String get commonGoHome;

  /// Label of a status detail row with the minimum amount the swap is guaranteed to deliver.
  ///
  /// In en, this message translates to:
  /// **'Guaranteed minimum'**
  String get commonGuaranteedMinimum;

  /// Status or button label while an account is being imported.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get commonImporting;

  /// Status value of a transaction or swap that has not finished. Shared by: activity, send, swap.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get commonInProgress;

  /// Default screen-reader name of a carousel of information cards.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get commonInformation;

  /// Timestamp of a swap sub-row that settled less than a minute ago. Shared by: activity, pay.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get commonJustNow;

  /// Hint while scanning a QR code from a device screen. Shared by: common, pay. Shared by: common, migration, voting.
  ///
  /// In en, this message translates to:
  /// **'Keep the QR code steady and fully visible.'**
  String get commonKeepQrSteady;

  /// Setting and button that keep the screen on while Vizor syncs.
  ///
  /// In en, this message translates to:
  /// **'Keep screen awake'**
  String get commonKeepScreenAwake;

  /// Instruction in the desktop Keystone shield dialog while the transaction is being sent. Shared by: home, payment.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open while the transaction is sent.'**
  String get commonKeepVizorOpenWhileTheTransaction;

  /// [security] Instruction in the desktop Keystone modal after proofs are ready. Shared by: send, swap. Shared by: common, migration.
  ///
  /// In en, this message translates to:
  /// **'After you scanned, click Get signature.'**
  String get commonKeystoneAfterScan;

  /// Two-line instruction under a QR code. {icon} is replaced by the small button icon the user taps on the Keystone device, so move it wherever the grammar needs it. The line break between the two halves is intentional. Shared by: keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Tap {icon} on your Keystone,\nthen scan this QR code'**
  String commonKeystoneScanPrompt(String icon);

  /// Hint when the scanned QR code is of the wrong type; asks to open the signature result QR code on the Keystone device. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'Open the signature result QR on Keystone, then scan again.'**
  String get commonKeystoneScanSignatureResult;

  /// [security] Instruction on the mobile Keystone screen to scan the transaction QR code with the Keystone device and follow its prompts. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'Use your Keystone wallet to scan this transaction QR code. Follow the steps on your device.'**
  String get commonKeystoneScanTransaction;

  /// Error on the Keystone shield screens when the scanned signature could not be added to the transaction. Shared by: home, migration, payment.
  ///
  /// In en, this message translates to:
  /// **'Keystone signature could not be applied.'**
  String get commonKeystoneSignatureCouldNotBeApplied;

  /// Error on the mobile Keystone shield screen when the signing request was not ready when the user started scanning. Shared by: home, keystone.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared.'**
  String get commonKeystoneSigningCouldNotBePrepared;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers. Shared by: payment, settings.
  ///
  /// In en, this message translates to:
  /// **'Knight'**
  String get commonKnight;

  /// Title of the failure panel when the Ledger device needs the user to act (unlock, open the app, reconnect). Shared by: send, voting.
  ///
  /// In en, this message translates to:
  /// **'Ledger needs attention'**
  String get commonLedgerNeedsAttention;

  /// Message on the Ledger signing screen when signing failed for another reason. Shared by: payment, send.
  ///
  /// In en, this message translates to:
  /// **'Ledger signing could not be completed. Check your device and try again.'**
  String get commonLedgerSigningCouldNotBeCompleted;

  /// Title of the Ledger shield failure panel after an error. Shared by: home, send.
  ///
  /// In en, this message translates to:
  /// **'Ledger signing failed'**
  String get commonLedgerSigningFailed;

  /// Label next to a spinner in the desktop QR scanner while the camera starts. Shared by: address, onboarding.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get commonLoading;

  /// Screen-reader label of the activity list loading placeholder. Shared by: activity, home.
  ///
  /// In en, this message translates to:
  /// **'Loading activity'**
  String get commonLoadingActivity;

  /// Footer label of the desktop QR scanner while cameras are being listed. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Loading camera...'**
  String get commonLoadingCamera;

  /// Label next to a spinner in the mobile QR scanner while the camera starts. Shared by: address, migration.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoadingDots;

  /// Status while the transaction QR code is prepared. Shared by: keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Loading QR code ...'**
  String get commonLoadingQRCode;

  /// Scanning tip on QR scanners. Shared by: keystone, send.
  ///
  /// In en, this message translates to:
  /// **'Make sure the room is well-lit and the QR code isn\'t reflecting glare.'**
  String get commonMakeSureTheRoomIsWell;

  /// Button on the migration schedule that opens the Manage Migration dialog. Shared by: migration, sidebar.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get commonManage;

  /// Label of a status detail row holding the deposit memo the user must include.
  ///
  /// In en, this message translates to:
  /// **'Memo'**
  String get commonMemo;

  /// Label of a row on a transaction receipt: the memo attached to the transaction. Shared by: activity, receipt, receive, send.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get commonMessage;

  /// Error shown when the payment request message exceeds the size limit. Shared by: receive, send.
  ///
  /// In en, this message translates to:
  /// **'Message is too long'**
  String get commonMessageIsTooLong;

  /// Desktop Home button that starts the Ironwood pool migration. Shared by: home, migration.
  ///
  /// In en, this message translates to:
  /// **'Migrate to Ironwood'**
  String get commonMigrateToIronwood;

  /// Heading of the migration status screen while the migration transaction is sent or confirming. Shared by: migration, sidebar.
  ///
  /// In en, this message translates to:
  /// **'Migrating...'**
  String get commonMigrating;

  /// Text of the Home migration banner when the migration was stopped by a network upgrade. Shared by: migration, sidebar.
  ///
  /// In en, this message translates to:
  /// **'Migration stopped'**
  String get commonMigrationStopped;

  /// Desktop Home migration button text after a network upgrade stopped the Ironwood migration. Shared by: home, migration.
  ///
  /// In en, this message translates to:
  /// **'Migration stopped by network upgrade'**
  String get commonMigrationStoppedByNetworkUpgrade;

  /// Scanning tip on the gift card QR scanner. Shared by: keystone, send.
  ///
  /// In en, this message translates to:
  /// **'Move the QR code a few inches further from the camera so it can focus.'**
  String get commonMoveTheQRCodeAFew;

  /// Label of a status detail row with the network and conversion fees of a payment in progress.
  ///
  /// In en, this message translates to:
  /// **'Network + conversion fees'**
  String get commonNetworkConversionFees;

  /// Label of a row on a transaction receipt: the total network fee of the transaction. Shared by: activity, payment.
  ///
  /// In en, this message translates to:
  /// **'Network fee'**
  String get commonNetworkFee;

  /// Mobile shield footer button that moves from the transaction QR to scanning the Keystone signature. Shared by: home, keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get commonNextStep;

  /// Error shown on the Receive screen when no wallet account is selected. Shared by: receive, send.
  ///
  /// In en, this message translates to:
  /// **'No active account'**
  String get commonNoActiveAccount;

  /// Error shown when a receipt is opened with no active account. Shared by: activity, home.
  ///
  /// In en, this message translates to:
  /// **'No active account.'**
  String get commonNoActiveAccountSentence;

  /// Description in the desktop QR scanner when the camera cannot be opened. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'No camera could be opened. Check that a camera is connected and not in use by another app.'**
  String get commonNoCameraCouldBeOpenedCheck;

  /// Footer label of the desktop QR scanner when the device has no camera. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'No camera found'**
  String get commonNoCameraFound;

  /// Title of the sheet for a feature that is not available on this platform yet.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get commonNotAvailableYet;

  /// Error or disabled button label on Pay steps when the spendable ZEC balance is too low. Shared by: pay, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Not enough ZEC'**
  String get commonNotEnoughZec;

  /// Button that acknowledges a message and closes it.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Scanning tip on QR scanners. 'Continuity Camera' is an Apple feature name. Shared by: keystone, send.
  ///
  /// In en, this message translates to:
  /// **'On a Mac, you can use Continuity Camera to scan with your iPhone instead.'**
  String get commonOnAMacYouCanUse;

  /// Button that opens the system settings page for the camera permission. Shared by: address, keystone, ledger.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get commonOpenSettings;

  /// Hint when the scanned QR code is not the signed transaction. Shared by: keystone, send.
  ///
  /// In en, this message translates to:
  /// **'Open the signed transaction QR on Keystone, then scan again.'**
  String get commonOpenTheSignedTransactionQROn;

  /// Label of the disabled action while an operation is held until the Zcash network upgrade activates.
  ///
  /// In en, this message translates to:
  /// **'Paused for network upgrade'**
  String get commonPausedForNetworkUpgrade;

  /// Error on the Pay recipient step when the quote costs more ZEC than is spendable. Shared by: pay, swap.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have enough ZEC for this payment. Try a smaller amount.'**
  String get commonPayInsufficientZec;

  /// Disabled primary button label on the Pay review while the payment is being started. Shared by: pay, swap.
  ///
  /// In en, this message translates to:
  /// **'Paying'**
  String get commonPayingButton;

  /// Title of a failed Pay activity row or detail screen. Shared by: activity, pay, swap.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get commonPaymentFailed;

  /// Title of a pending Pay activity row. Shared by: activity, swap.
  ///
  /// In en, this message translates to:
  /// **'Payment in progress'**
  String get commonPaymentInProgress;

  /// Label of the progress tab on a payment status screen.
  ///
  /// In en, this message translates to:
  /// **'Payment progress'**
  String get commonPaymentProgress;

  /// Title of a refunded Pay activity row or detail screen. Shared by: activity, swap.
  ///
  /// In en, this message translates to:
  /// **'Payment refunded'**
  String get commonPaymentRefunded;

  /// Title of the payment request card that opens when the user follows a zcash: link or scans a payment request QR code.
  ///
  /// In en, this message translates to:
  /// **'Payment request'**
  String get commonPaymentRequest;

  /// Status of a migration transfer that has not been sent yet. Shared by: migration, payment.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get commonPending;

  /// Short status chip while waiting. Shared by: ledger, swap.
  ///
  /// In en, this message translates to:
  /// **'Please wait'**
  String get commonPleaseWait;

  /// Subtitle under the Keystone connect, scan and select-account headings, asking the user to get their Keystone device ready. Shared by: keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Prepare your Keystone wallet'**
  String get commonPrepareYourKeystoneWallet;

  /// Disabled button label while the Keystone request is being prepared. Shared by: migration, send, wallet.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get commonPreparing;

  /// Heading of the migration status screen while the balance is being split. Shared by: migration, send, voting.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get commonPreparingDots;

  /// Button label while a Gift Card claim is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get commonPreparingEllipsis;

  /// Line under the paid amount on a payment status screen, saying the payment is spent privately from the shielded balance.
  ///
  /// In en, this message translates to:
  /// **'Privately, from shielded balance'**
  String get commonPrivatelyFromShieldedBalance;

  /// Error on the Keystone shield screens when the Sapling proving parameters failed to download or load. Shared by: home, send.
  ///
  /// In en, this message translates to:
  /// **'Required proving parameters could not be prepared.'**
  String get commonProvingParamsFailed;

  /// Error shown after scanning a QR code that contains no address. Shared by: address, pay, swap.
  ///
  /// In en, this message translates to:
  /// **'QR code did not include an address.'**
  String get commonQrNoAddress;

  /// Button that quits Vizor.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get commonQuit;

  /// Label of a status detail row with the exchange rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get commonRate;

  /// Status while the signature QR code from the Keystone is decoded. Shared by: keystone, migration, send, voting.
  ///
  /// In en, this message translates to:
  /// **'Reading signature...'**
  String get commonReadingSignature;

  /// Status text on the mobile Keystone scanner while the scanned signature QR is decoded. Shared by: home, payment.
  ///
  /// In en, this message translates to:
  /// **'Reading signature…'**
  String get commonReadingSignatureEllipsis;

  /// Title of an activity row or receipt for an incoming transaction. Shared by: activity, payment.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get commonReceived;

  /// Label of the amount the payment recipient will receive, on an in-progress payment status screen.
  ///
  /// In en, this message translates to:
  /// **'Recipient gets'**
  String get commonRecipientGets;

  /// Label of a status detail row with the fee charged for the refund.
  ///
  /// In en, this message translates to:
  /// **'Refund fee'**
  String get commonRefundFee;

  /// Label of a status detail row holding the address a refund goes to.
  ///
  /// In en, this message translates to:
  /// **'Refund to'**
  String get commonRefundTo;

  /// Line under the paid amount of a swap status screen: the address a refund goes to.
  ///
  /// In en, this message translates to:
  /// **'Refund to: {address}'**
  String commonRefundToAddress(String address);

  /// Status value of a swap, or subtitle of a failed row, whose funds were returned. Shared by: activity, swap.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get commonRefunded;

  /// Label of a status detail row with the amount refunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded amount'**
  String get commonRefundedAmount;

  /// [security] Destructive button that confirms removing one account and its local data. Shared by: accounts, address.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// Button that asks for the camera permission again. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Request again'**
  String get commonRequestAgain;

  /// [security] Button that erases every account and wallet data on this device.
  ///
  /// In en, this message translates to:
  /// **'Reset Vizor'**
  String get commonResetVizor;

  /// Back-link name of the voting results screen. Shared by: app, voting.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get commonResults;

  /// Button on the migration progress screen that resumes a paused migration. Shared by: migration, voting.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get commonResume;

  /// Button that retries a failed step.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Button that retries saving a Ledger-signed transaction. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'Retry saving'**
  String get commonRetrySaving;

  /// Primary button of the mobile Pay submitted screen after a failure; goes to Home. Shared by: pay, send.
  ///
  /// In en, this message translates to:
  /// **'Return home'**
  String get commonReturnHome;

  /// Button on the manual import step shown after the last word that moves to the review step. Shared by: onboarding, send.
  ///
  /// In en, this message translates to:
  /// **'Review & finish'**
  String get commonReviewAndFinish;

  /// Title of the Pay review step. Shared by: pay, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Review Payment'**
  String get commonReviewPayment;

  /// Title of the mobile swap detail screen while the user has to review the quote. Shared by: activity, swap.
  ///
  /// In en, this message translates to:
  /// **'Review quote'**
  String get commonReviewQuote;

  /// Primary button label on the swap screen that opens the swap review.
  ///
  /// In en, this message translates to:
  /// **'Review swap'**
  String get commonReviewSwap;

  /// Dialog button that saves the edited value. Shared by: onboarding, pay.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Button that saves an edited contact on mobile. Shared by: address, pay.
  ///
  /// In en, this message translates to:
  /// **'Save contact'**
  String get commonSaveContact;

  /// Disabled button label while saving. Shared by: ledger, pay.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get commonSaving;

  /// Button that reopens the QR scanner after a failed scan. Shared by: payment, wallet.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get commonScanAgain;

  /// Button that opens the camera to scan the requester's original payment request QR code.
  ///
  /// In en, this message translates to:
  /// **'Scan original QR'**
  String get commonScanOriginalQr;

  /// Title of a QR code scanning screen. Shared by: common, migration.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get commonScanQrCode;

  /// Accessibility label of the button that opens the QR scanner on the Pay recipient step. Shared by: pay, payment.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get commonScanQrCodeSentenceCase;

  /// Subtitle of the Keystone signing screen that shows the QR code to scan. Shared by: payment, swap.
  ///
  /// In en, this message translates to:
  /// **'Scan to sign'**
  String get commonScanToSign;

  /// Subtitle of the first step: the Keystone scans the QR code shown by Vizor. Shared by: keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Scan with Keystone'**
  String get commonScanWithKeystone;

  /// [security] Subtitle of the Keystone signing modal asking the user to scan the QR with Keystone. Shared by: migration, send.
  ///
  /// In en, this message translates to:
  /// **'Scan with your Keystone'**
  String get commonScanWithYourKeystone;

  /// Title of a screen that picks one account to import.
  ///
  /// In en, this message translates to:
  /// **'Select account'**
  String get commonSelectAccount;

  /// Title of the picker that chooses a contact avatar. Shared by: address, pay.
  ///
  /// In en, this message translates to:
  /// **'Select contact picture'**
  String get commonSelectContactPicture;

  /// Title of the Pay recipient step. Shared by: pay, send.
  ///
  /// In en, this message translates to:
  /// **'Select Recipient'**
  String get commonSelectRecipient;

  /// Accessibility label of the check mark on the chosen contact. Shared by: address, pay.
  ///
  /// In en, this message translates to:
  /// **'Selected contact'**
  String get commonSelectedContact;

  /// Title of an activity row or receipt for an outgoing transaction that failed. Shared by: activity, send.
  ///
  /// In en, this message translates to:
  /// **'Send failed'**
  String get commonSendFailed;

  /// Account menu item that starts a send to that account's address. Shared by: accounts, address.
  ///
  /// In en, this message translates to:
  /// **'Send ZEC'**
  String get commonSendZec;

  /// Title of the mobile receipt of an outgoing transaction that is pending. Shared by: activity, send.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get commonSending;

  /// Screen-reader label of the lock icon covering secret content while the app is in the background.
  ///
  /// In en, this message translates to:
  /// **'Sensitive content hidden'**
  String get commonSensitiveContentHidden;

  /// Title of the mobile receipt of an outgoing transaction that completed. Shared by: activity, send.
  ///
  /// In en, this message translates to:
  /// **'Sent successfully'**
  String get commonSentSuccessfully;

  /// Title of the sheet that shows a full shielded address. Shared by: activity, onboarding, receive, send.
  ///
  /// In en, this message translates to:
  /// **'Shielded address'**
  String get commonShieldedAddress;

  /// Value of the To row of a shielding receipt. Shared by: activity, home, pay.
  ///
  /// In en, this message translates to:
  /// **'Shielded balance'**
  String get commonShieldedBalance;

  /// Title of the desktop receipt of a shielding transaction that completed. Shared by: activity, home.
  ///
  /// In en, this message translates to:
  /// **'Shielded successfully'**
  String get commonShieldedSuccessfully;

  /// Title of the mobile receipt of a pending shielding transaction. Shared by: activity, home.
  ///
  /// In en, this message translates to:
  /// **'Shielding...'**
  String get commonShielding;

  /// Ghost button on a receipt row that opens the full address of the sender or recipient. Shared by: activity, pay, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Show full address'**
  String get commonShowFullAddress;

  /// Screen-reader label of the button that returns to the transaction QR code. Shared by: keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Show transaction QR'**
  String get commonShowTransactionQR;

  /// Error shown when the user declined the proving-parameter download during Keystone signing. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'Signing was cancelled before proving parameters were downloaded.'**
  String get commonSigningCancelledBeforeParams;

  /// [security] Error shown when the transaction expired before the Keystone could sign it. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'Transaction expired before it could be signed.'**
  String get commonSigningExpired;

  /// Label of a status detail row with the slippage tolerance of the quote.
  ///
  /// In en, this message translates to:
  /// **'Slippage tolerance'**
  String get commonSlippageTolerance;

  /// Step indicator in the mobile Keystone signing flow (first of two steps). Shared by: keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Step 1/2'**
  String get commonStepOneOfTwo;

  /// Step indicator in the mobile Keystone signing flow (second of two steps). Shared by: keystone, migration.
  ///
  /// In en, this message translates to:
  /// **'Step 2/2'**
  String get commonStepTwoOfTwo;

  /// Subtitle of the desktop Keystone shield dialog while the transaction is being sent. Shared by: home, payment.
  ///
  /// In en, this message translates to:
  /// **'Submitting transaction'**
  String get commonSubmittingTransaction;

  /// Back link label on the donation review screen. Shared by: send, settings.
  ///
  /// In en, this message translates to:
  /// **'Support Vizor'**
  String get commonSupportVizor;

  /// Title of a failed swap activity row. Shared by: activity, swap.
  ///
  /// In en, this message translates to:
  /// **'Swap failed'**
  String get commonSwapFailed;

  /// Label of a status detail row with the swap fee.
  ///
  /// In en, this message translates to:
  /// **'Swap fee'**
  String get commonSwapFee;

  /// Label of the progress tab on a swap status screen.
  ///
  /// In en, this message translates to:
  /// **'Swap progress'**
  String get commonSwapProgress;

  /// Title of a refunded swap activity row. Shared by: activity, swap.
  ///
  /// In en, this message translates to:
  /// **'Swap refunded'**
  String get commonSwapRefunded;

  /// Default contact label suggestion when saving a swap recipient to the address book.
  ///
  /// In en, this message translates to:
  /// **'{symbol} recipient'**
  String commonSymbolRecipient(String symbol);

  /// Label of a status detail row holding the address a refund of the asset goes to.
  ///
  /// In en, this message translates to:
  /// **'{symbol} refund address'**
  String commonSymbolRefundAddress(String symbol);

  /// Value of the estimated completion row while the migration progress is syncing. Shared by: migration, settings.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get commonSyncing;

  /// Hint under the mobile Keystone scanner when the scanned QR is not a valid signature. Shared by: home, keystone.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone signature.'**
  String get commonThisQRCodeCouldNotBe;

  /// Error on the Keystone signing screen when the scanned QR code belongs to a different request. Shared by: payment, swap.
  ///
  /// In en, this message translates to:
  /// **'This QR code does not match the current Keystone request.'**
  String get commonThisQRCodeDoesNotMatch;

  /// Heading on the swap timeout screen shown when the quote deposit window has expired. Shared by: swap, wallet.
  ///
  /// In en, this message translates to:
  /// **'Time’s up'**
  String get commonTimeSUp;

  /// Label of a row on a transaction receipt: the date and time of the transaction. Shared by: activity, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get commonTimestamp;

  /// Label of a row on a transaction receipt: the recipient or the destination of funds. Shared by: activity, pay, send, swap.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get commonTo;

  /// Line under the received amount of a swap or payment status screen: the recipient address followed by the blockchain it is on.
  ///
  /// In en, this message translates to:
  /// **'To: {address} on {chain}'**
  String commonToAddressOnChain(String address, String chain);

  /// Accessibility label of the flashlight button of the QR scanner. Shared by: address, home.
  ///
  /// In en, this message translates to:
  /// **'Toggle flashlight'**
  String get commonToggleFlashlight;

  /// Label of the last row on the mobile donation summary showing amount plus fee. Shared by: donation, voting.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get commonTotal;

  /// Title of the Ledger failure panel when the transaction proposal expired before it could be signed. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'Transaction expired'**
  String get commonTransactionExpired;

  /// Toast on the desktop receipt after the transaction hash was copied. Shared by: activity, send.
  ///
  /// In en, this message translates to:
  /// **'Transaction hash copied'**
  String get commonTransactionHashCopied;

  /// Title of the sheet that shows a full transparent address. Shared by: activity, onboarding, receive, send.
  ///
  /// In en, this message translates to:
  /// **'Transparent address'**
  String get commonTransparentAddress;

  /// Button that repeats an action that failed.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Description telling the user which two switches to turn on in Windows Settings. Use the Windows setting names. Shared by: address, keystone.
  ///
  /// In en, this message translates to:
  /// **'Turn on Camera access and Let desktop apps access your camera in Windows Settings.'**
  String get commonTurnOnCameraAccessAndLet;

  /// Label of a row on a transaction receipt: the transaction ID, tapping it opens a block explorer. Shared by: activity, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Tx ID'**
  String get commonTxId;

  /// Shown as the fee of a transaction whose fee the wallet has not recorded. An unknown fee is never zero. Shared by: activity, voting.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// [security] Button and system biometric prompt reason for unlocking the wallet.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor'**
  String get commonUnlockVizor;

  /// Button that applies a setting chosen in a picker modal or sheet (theme, language).
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// Title of the in-app update prompt when the update failed. Shared by: app, payment.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get commonUpdateFailed;

  /// The Update button label while the change is being saved.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get commonUpdating;

  /// Link on the legacy migration card that opens the batch schedule. Shared by: migration, voting.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get commonView;

  /// Message while Vizor checks that the Zcash app on the Ledger is ready. Shared by: ledger, voting.
  ///
  /// In en, this message translates to:
  /// **'Vizor is checking whether the Zcash app is ready.'**
  String get commonVizorIsCheckingWhetherTheZcash;

  /// Back-link name of a coinholder voting round screen. Shared by: app, voting.
  ///
  /// In en, this message translates to:
  /// **'Voting round'**
  String get commonVotingRound;

  /// Desktop Home migration button text while a migration transaction waits for confirmations. Shared by: home, migration.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation...'**
  String get commonWaitingForConfirmation;

  /// Ring sub-caption: migration cannot continue until the wallet finishes syncing. Shared by: migration, voting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for wallet sync'**
  String get commonWaitingForWalletSync;

  /// Title of the unlock screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get commonWelcomeBack;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers. Shared by: payment, settings.
  ///
  /// In en, this message translates to:
  /// **'Wizard'**
  String get commonWizard;

  /// Label of the amount the user pays, on a payment status screen before the payment completes.
  ///
  /// In en, this message translates to:
  /// **'You pay'**
  String get commonYouPay;

  /// Label of the amount being paid while a swap or payment is still in progress.
  ///
  /// In en, this message translates to:
  /// **'You\'re paying'**
  String get commonYourePaying;

  /// Label of the amount being received while a swap is in progress.
  ///
  /// In en, this message translates to:
  /// **'You\'re receiving'**
  String get commonYoureReceiving;

  /// Title of the sheet that shows a full address of unrecognized type. Shared by: activity, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Zcash address'**
  String get commonZcashAddress;

  /// Label of the review row that names the donation recipient.
  ///
  /// In en, this message translates to:
  /// **'Donating to'**
  String get donationDonatingTo;

  /// Placeholder prompt next to the unit selector on the donation amount screen.
  ///
  /// In en, this message translates to:
  /// **'Enter your amount'**
  String get donationEnterAmount;

  /// Shown under the donation amount field on mobile when the live ZEC price is unavailable, so the USD conversion cannot be shown.
  ///
  /// In en, this message translates to:
  /// **'Price unavailable'**
  String get donationPriceUnavailable;

  /// Title of the desktop donation review step.
  ///
  /// In en, this message translates to:
  /// **'Review Amount'**
  String get donationReviewAmountTitle;

  /// Label of the review row on the mobile donation summary that names the balance used for the donation.
  ///
  /// In en, this message translates to:
  /// **'Sending from'**
  String get donationSendingFrom;

  /// Lead-in of a line on the desktop donation screen, followed by a shield icon and the words 'Shielded balance'.
  ///
  /// In en, this message translates to:
  /// **'Sending from your'**
  String get donationSendingFromYour;

  /// Accessibility label of the button that toggles the donation amount between ZEC and USD.
  ///
  /// In en, this message translates to:
  /// **'Switch between ZEC and USD'**
  String get donationSwitchCurrency;

  /// Headline of the desktop screen shown after a donation succeeded.
  ///
  /// In en, this message translates to:
  /// **'Thank you for supporting Vizor'**
  String get donationThanksTitle;

  /// Name of the automatic endpoint selection option, and the Settings value while it is on.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get endpointAutomatic;

  /// Current endpoint while automatic selection is still choosing a server.
  ///
  /// In en, this message translates to:
  /// **'Automatic · Selecting...'**
  String get endpointAutomaticSelecting;

  /// Current endpoint once automatic selection has picked a server.
  ///
  /// In en, this message translates to:
  /// **'Automatic · {endpoint}'**
  String endpointAutomaticWithHost(String endpoint);

  /// Shows the lightwalletd endpoint in use.
  ///
  /// In en, this message translates to:
  /// **'Current: {endpoint}'**
  String endpointCurrent(String endpoint);

  /// Option to enter a custom lightwalletd endpoint.
  ///
  /// In en, this message translates to:
  /// **'Custom endpoint'**
  String get endpointCustom;

  /// Endpoint settings error when automatic endpoint selection cannot run.
  ///
  /// In en, this message translates to:
  /// **'Automatic selection is unavailable.'**
  String get endpointErrorAutomaticUnavailable;

  /// Endpoint field error when the field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter an endpoint.'**
  String get endpointErrorEmpty;

  /// Endpoint field error when the text is not a host name with a port.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid hostname and port.'**
  String get endpointErrorHost;

  /// Endpoint field error when the endpoint is not https. Keep https:// as is.
  ///
  /// In en, this message translates to:
  /// **'Use an https:// endpoint.'**
  String get endpointErrorHttps;

  /// Endpoint settings error when Update is pressed with no endpoint chosen in the list.
  ///
  /// In en, this message translates to:
  /// **'Select an endpoint.'**
  String get endpointErrorNoSelection;

  /// Endpoint field error when the port is missing or out of range. Keep the example host and port as is.
  ///
  /// In en, this message translates to:
  /// **'Include a valid port, for example us.zec.stardust.rest:443.'**
  String get endpointErrorPort;

  /// Endpoint field error when the text contains a space.
  ///
  /// In en, this message translates to:
  /// **'Endpoint cannot contain spaces.'**
  String get endpointErrorSpaces;

  /// Endpoint error when the server serves another Zcash network. {endpointNetwork} and {walletNetwork} are network names the server reports, such as main or test; keep them as is.
  ///
  /// In en, this message translates to:
  /// **'Endpoint is for {endpointNetwork}, but this wallet uses {walletNetwork}.'**
  String endpointErrorWrongNetwork(
    String endpointNetwork,
    String walletNetwork,
  );

  /// Toast when the wallet switched back to the selected server endpoint after it recovered.
  ///
  /// In en, this message translates to:
  /// **'Selected endpoint recovered. Switched back.'**
  String get endpointFailoverSwitchedBack;

  /// Toast when the wallet switched from an unstable server endpoint to a fallback endpoint.
  ///
  /// In en, this message translates to:
  /// **'Selected endpoint is unstable. Switched to fallback endpoint.'**
  String get endpointFailoverSwitchedToFallback;

  /// Latency label of a server endpoint that could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get endpointLatencyUnavailable;

  /// Latency label of a server endpoint that serves a different Zcash network than the wallet.
  ///
  /// In en, this message translates to:
  /// **'Wrong network'**
  String get endpointLatencyWrongNetwork;

  /// Group heading in the server endpoint list. Regtest is a developer network name and stays in English.
  ///
  /// In en, this message translates to:
  /// **'{region, select, standard{Default} europe{Europe} global{Global} americas{Americas} asiaPacific{Asia Pacific} community{Community} testnet{Testnet} regtest{Regtest} other{Other}}'**
  String endpointRegionName(String region);

  /// Error when saving an endpoint failed. Shared by: the onboarding network settings sheet and the endpoint settings panel.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the endpoint. Try again.'**
  String get endpointSaveFailed;

  /// Detail under the Automatic option while no server has been chosen yet.
  ///
  /// In en, this message translates to:
  /// **'Selecting an endpoint…'**
  String get endpointSelecting;

  /// Button that saves a new lightwalletd endpoint.
  ///
  /// In en, this message translates to:
  /// **'Update endpoint'**
  String get endpointUpdate;

  /// Toast after the lightwalletd endpoint changed.
  ///
  /// In en, this message translates to:
  /// **'Endpoint updated'**
  String get endpointUpdated;

  /// Button that switches the endpoint back to automatic selection.
  ///
  /// In en, this message translates to:
  /// **'Use automatic selection'**
  String get endpointUseAutomatic;

  /// Status line under the Private queries switch while the setting is being changed.
  ///
  /// In en, this message translates to:
  /// **'Changing setting…'**
  String get enhancePirChanging;

  /// Status line under the Private queries switch: turning it off did not finish, so it is still on.
  ///
  /// In en, this message translates to:
  /// **'Private queries are still on. Try turning them off again.'**
  String get enhancePirOptOutPending;

  /// Status line under the Private queries switch: the setting is on but private recovery of transparent funds could not start yet and will be retried.
  ///
  /// In en, this message translates to:
  /// **'Private queries are on. Private transparent recovery could not start yet and will be retried.'**
  String get enhancePirRaisePending;

  /// Status line under the Private queries switch when the setting could not be changed at all.
  ///
  /// In en, this message translates to:
  /// **'Setting unchanged. Try again.'**
  String get enhancePirUnchanged;

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

  /// Error text on desktop Home when the wallet failed to load. {details} is the technical error text, passed through untranslated.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again in a moment.\n\nDetails: {details}'**
  String homeLoadFailed(String details);

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

  /// Shield error when sending the shield transaction to the network failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t broadcast your shielding transaction. Try again.'**
  String get homeShieldErrorBroadcastFailed;

  /// Shield error when the cause is not known.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t shield your balance. Try again.'**
  String get homeShieldErrorCouldNotShield;

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

  /// [security] Shield error when the account's seed phrase cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Secret Passphrase isn\'t available for this account.'**
  String get homeShieldErrorSeedUnavailable;

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

  /// Shield error while the wallet is still syncing.
  ///
  /// In en, this message translates to:
  /// **'Wait for sync to finish, then shield.'**
  String get homeShieldErrorWaitForSync;

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

  /// Screen-reader label of the transaction QR code the Keystone device scans.
  ///
  /// In en, this message translates to:
  /// **'Keystone transaction QR'**
  String get homeShieldKeystoneQrSemantics;

  /// Label of the desktop Home button that shields the transparent balance.
  ///
  /// In en, this message translates to:
  /// **'Shield now'**
  String get homeShieldNow;

  /// Message after a shield transaction was saved but not yet broadcast; Vizor retries it.
  ///
  /// In en, this message translates to:
  /// **'Shielding queued for retry. Check Activity.'**
  String get homeShieldQueuedForRetry;

  /// Title of the mobile software-account shield screen when the shielding transaction is queued for retry.
  ///
  /// In en, this message translates to:
  /// **'Shielding queued'**
  String get homeShieldQueuedTitle;

  /// Button in the desktop Keystone shield dialog that cancels shielding.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get homeShieldReject;

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

  /// Message when a Keystone shield must wait for private recovery; the signature is kept for the retry.
  ///
  /// In en, this message translates to:
  /// **'Private recovery is catching up with the latest block. Try again in a moment; your Keystone signature is kept.'**
  String get homeShieldWaitingForPrivateRecovery;

  /// Status text on the mobile shield screens while the transparent balance is being shielded.
  ///
  /// In en, this message translates to:
  /// **'Shielding your balance…'**
  String get homeShieldingBalance;

  /// Row on the mobile Home card showing the transparent balance. {balance} is a formatted amount such as 0.5 ZEC.
  ///
  /// In en, this message translates to:
  /// **'Transparent: {balance}'**
  String homeTransparentBalance(String balance);

  /// Transparent balance row showing the last amount Vizor knew. {amount} is a formatted ZEC amount.
  ///
  /// In en, this message translates to:
  /// **'{amount} (last known)'**
  String homeTransparentLastKnown(String amount);

  /// Transparent balance row when private recovery stopped; shows the last known amount.
  ///
  /// In en, this message translates to:
  /// **'{amount} (last known, recovery stopped)'**
  String homeTransparentLastKnownStopped(String amount);

  /// Transparent balance row when private recovery stopped and no amount is known.
  ///
  /// In en, this message translates to:
  /// **'Recovery stopped'**
  String get homeTransparentRecoveryStopped;

  /// [security] Why private transparent recovery stopped: earlier public records disagree.
  ///
  /// In en, this message translates to:
  /// **'Earlier public records don\'t match private recovery. Turning off Private queries discards privately recovered records and looks up transparent funds publicly.'**
  String get homeTransparentStopLegacyDiscrepancy;

  /// [security] Why private transparent recovery stopped: turning off Private queries did not complete.
  ///
  /// In en, this message translates to:
  /// **'Turning off Private queries didn\'t finish. Turn it off again in Settings to look up transparent funds publicly.'**
  String get homeTransparentStopOptOutUnfinished;

  /// [security] Why private transparent recovery stopped: conflicting records. Turning off Private queries reveals lookups publicly.
  ///
  /// In en, this message translates to:
  /// **'Private recovery found conflicting records for this account. Turning off Private queries discards privately recovered records and looks up transparent funds publicly.'**
  String get homeTransparentStopQuarantined;

  /// Why private transparent recovery stopped: no progress.
  ///
  /// In en, this message translates to:
  /// **'Private recovery can\'t make progress for this account. Vizor will try again later.'**
  String get homeTransparentStopStalled;

  /// Why private transparent recovery stopped: the service withdrew data.
  ///
  /// In en, this message translates to:
  /// **'The private recovery service withdrew data for this account. Vizor will try again later.'**
  String get homeTransparentStopWithdrawn;

  /// Transparent balance row when the amount is unknown.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get homeTransparentUnavailable;

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

  /// Toast shown when a gift card link is opened while the user is in the middle of a task.
  ///
  /// In en, this message translates to:
  /// **'Finish or cancel your current task to open this gift card.'**
  String get incomingLinkGiftBusy;

  /// Toast shown when a gift card link is opened during account setup.
  ///
  /// In en, this message translates to:
  /// **'Finish account setup to open this gift card.'**
  String get incomingLinkGiftSetup;

  /// Toast shown when a Vizor home link is opened while the user is in the middle of a task; asks them to finish or cancel and reopen it.
  ///
  /// In en, this message translates to:
  /// **'Finish or cancel your task, then reopen the link.'**
  String get incomingLinkHomeBusy;

  /// Toast shown when a Vizor home link is opened during account setup; asks them to finish setup and reopen it.
  ///
  /// In en, this message translates to:
  /// **'Finish account setup, then reopen the link.'**
  String get incomingLinkHomeSetup;

  /// Toast shown when a payment request link is opened while the user is in the middle of a task.
  ///
  /// In en, this message translates to:
  /// **'Finish or cancel your current task to open this payment request.'**
  String get incomingLinkPaymentBusy;

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

  /// Body of the startup failure screen on Linux.
  ///
  /// In en, this message translates to:
  /// **'Quit and restart Vizor to try again.'**
  String get keyringRestartHint;

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

  /// Title asking the user to unlock the system keyring (Linux).
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

  /// Button that asks for camera permission again.
  ///
  /// In en, this message translates to:
  /// **'Allow camera'**
  String get keystoneAllowCamera;

  /// Error shown when a swap deposit has inputs Keystone batch signing does not support.
  ///
  /// In en, this message translates to:
  /// **'This deposit uses inputs that Keystone batch signing cannot sign.'**
  String get keystoneBatchCannotSignDeposit;

  /// Error shown when a transaction has inputs Keystone batch signing does not support.
  ///
  /// In en, this message translates to:
  /// **'This transaction uses inputs that Keystone batch signing cannot sign.'**
  String get keystoneBatchCannotSignTx;

  /// Error shown when a swap deposit needs more signatures than one Keystone batch can hold.
  ///
  /// In en, this message translates to:
  /// **'This deposit uses too many inputs for Keystone batch signing. Try a smaller amount.'**
  String get keystoneBatchTooManyInputsDeposit;

  /// Error shown when a transaction needs more signatures than one Keystone batch can hold.
  ///
  /// In en, this message translates to:
  /// **'This transaction uses too many inputs for Keystone batch signing. Try a smaller amount.'**
  String get keystoneBatchTooManyInputsTx;

  /// Inline error under the block height field when the typed number is not a usable block height.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a valid block height.'**
  String get keystoneBirthdayInvalidHeight;

  /// Subtitle under the wallet birthday heading explaining why the date is asked.
  ///
  /// In en, this message translates to:
  /// **'It helps us import your wallet faster.'**
  String get keystoneBirthdaySubtitle;

  /// Title when camera access was denied.
  ///
  /// In en, this message translates to:
  /// **'You\'ve denied the Camera access'**
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

  /// Detail tag in the camera picker for an external camera.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get keystoneCameraExternal;

  /// Detail tag in the camera picker for a front camera.
  ///
  /// In en, this message translates to:
  /// **'Front'**
  String get keystoneCameraFront;

  /// Permission explanation on the gift card QR scanner; the two lines are separated by a line break.
  ///
  /// In en, this message translates to:
  /// **'A camera is required to scan the gift card QR code.\nYou can revert this in settings anytime later.'**
  String get keystoneCameraGiftBody;

  /// Camera name followed by a marker that it is the default camera. {name} is the camera's own name.
  ///
  /// In en, this message translates to:
  /// **'{name} (Default)'**
  String keystoneCameraNameDefault(String name);

  /// Detail tag in the camera picker for a normal lens.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get keystoneCameraNormal;

  /// Shown on the mobile signature scanner when camera permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. Allow it in Settings to scan Keystone signatures.'**
  String get keystoneCameraOffAllow;

  /// Two-line description under the camera unavailable title. Keep the line break; each line is shown on its own line without wrapping, so keep both lines short.
  ///
  /// In en, this message translates to:
  /// **'Keystone import uses camera QR scanning only.\nConnect a camera and try again.'**
  String get keystoneCameraUnavailableBody;

  /// Detail tag in the camera picker for a wide-angle lens.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get keystoneCameraWide;

  /// Detail tag in the camera picker for a zoom lens.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get keystoneCameraZoom;

  /// Button that confirms the chosen Keystone account and continues the import.
  ///
  /// In en, this message translates to:
  /// **'Confirm selection'**
  String get keystoneConfirmSelection;

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

  /// Screen-reader label of the keyst.one/firmware link.
  ///
  /// In en, this message translates to:
  /// **'Open Keystone firmware page'**
  String get keystoneFirmwareOpenPage;

  /// Title of instruction step 1 on the Keystone how-to-connect screen. The step number is added by the app before this text.
  ///
  /// In en, this message translates to:
  /// **'Check Keystone firmware'**
  String get keystoneFirmwareTitle;

  /// Line in the Keystone scanning help. {link} is the keyst.one/firmware link, which is a URL and is not translated; place it where the grammar needs it.
  ///
  /// In en, this message translates to:
  /// **'Update to the latest Keystone firmware at {link}'**
  String keystoneFirmwareUpdate(String link);

  /// Primary button on the Keystone how-to-connect screen; continues to the QR scan step once the user has followed the instructions.
  ///
  /// In en, this message translates to:
  /// **'I\'m ready now'**
  String get keystoneImReadyNow;

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

  /// Title of instruction step 2 on the Keystone how-to-connect screen. The step number is added by the app before this text.
  ///
  /// In en, this message translates to:
  /// **'Prepare to connect'**
  String get keystonePrepareToConnectTitle;

  /// Screen-reader label of the loading spinner while the signing QR code is prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing QR'**
  String get keystonePreparingQr;

  /// Status while a scanned Keystone QR code is decoded.
  ///
  /// In en, this message translates to:
  /// **'Reading QR...'**
  String get keystoneReadingQr;

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

  /// [security] Caption on the mobile signing scanner asking the user to scan the signed-transaction QR code on the Keystone.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to confirm'**
  String get keystoneScanCaptionConfirm;

  /// Error under the Keystone QR scanner when the scanned QR cannot be decoded as a Zcash account.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone Zcash account.'**
  String get keystoneScanDecodeFailed;

  /// Screen-reader label of the close button of the scanning help tooltip.
  ///
  /// In en, this message translates to:
  /// **'Close scan help'**
  String get keystoneScanHelpClose;

  /// Title of the tooltip with Keystone scanning help.
  ///
  /// In en, this message translates to:
  /// **'Scanning issues?'**
  String get keystoneScanIssuesTitle;

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

  /// Title of the camera picker.
  ///
  /// In en, this message translates to:
  /// **'Select Camera'**
  String get keystoneSelectCamera;

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

  /// Label next to a spinner while a signed transaction is submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitting the transaction'**
  String get keystoneSubmittingTransaction;

  /// Scanning tip on the gift card QR scanner.
  ///
  /// In en, this message translates to:
  /// **'Open the gift card QR code full screen on another device.'**
  String get keystoneTipGiftFullScreen;

  /// Scanning tip on the Keystone QR scanner.
  ///
  /// In en, this message translates to:
  /// **'Move your Keystone a few inches further from the camera so it can focus.'**
  String get keystoneTipMoveKeystoneFurther;

  /// Scanning tip on the Keystone QR scanner.
  ///
  /// In en, this message translates to:
  /// **'Tap the QR code on your Keystone to show it full screen. This is the easiest fix.'**
  String get keystoneTipTapFullScreen;

  /// Title of the scanning tips popover.
  ///
  /// In en, this message translates to:
  /// **'Trouble scanning?'**
  String get keystoneTroubleScanning;

  /// Subtitle of the signing flow after a failure.
  ///
  /// In en, this message translates to:
  /// **'Try again with Keystone'**
  String get keystoneTryAgainWithKeystone;

  /// Label of the account index field in Ledger onboarding.
  ///
  /// In en, this message translates to:
  /// **'Ledger account index (0–100)'**
  String get ledgerAccountIndexFieldLabel;

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

  /// Validation error under the Ledger account index field.
  ///
  /// In en, this message translates to:
  /// **'Account index must be between 0 and 100.'**
  String get ledgerAccountIndexOutOfRange;

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

  /// Screen-reader label of the app icon in the Ledger prompt. {appName} is the device app name, normally Zcash.
  ///
  /// In en, this message translates to:
  /// **'{appName} app'**
  String ledgerAppSemanticsLabel(String appName);

  /// Title shown when the Zcash app on the Ledger must be updated before signing.
  ///
  /// In en, this message translates to:
  /// **'Ledger app update required'**
  String get ledgerAppUpdateRequiredTitle;

  /// [security] Instruction to approve on the Ledger sharing the viewing key with Vizor.
  ///
  /// In en, this message translates to:
  /// **'Approve sharing your viewing key with Vizor.'**
  String get ledgerApproveShareViewingKey;

  /// [security] Instruction to approve on the Ledger sharing the viewing key. {number} is the account number shown on the device.
  ///
  /// In en, this message translates to:
  /// **'Approve sharing the viewing key for Account #{number}.'**
  String ledgerApproveShareViewingKeyForAccount(String number);

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

  /// List of Ledger models that support Bluetooth. Product model names stay in Latin script.
  ///
  /// In en, this message translates to:
  /// **'Nano X, Flex, Stax, and Nano Gen5'**
  String get ledgerBluetoothModelsList;

  /// Error in the mobile device sheet when the Bluetooth permission was not granted.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission is required to find your Ledger. Allow it in Settings, then try again.'**
  String get ledgerBluetoothPermissionRequired;

  /// Shown in the Bluetooth access checker when permission is granted.
  ///
  /// In en, this message translates to:
  /// **'Permission is allowed. Try again when ready.'**
  String get ledgerBtAccessAllowed;

  /// Shown before the Bluetooth permission is requested. 'Allow permission' is a button label.
  ///
  /// In en, this message translates to:
  /// **'Choose Allow permission to connect to your Ledger. If no prompt appears, open Settings.'**
  String get ledgerBtAccessBluetoothRequestable;

  /// Shown when Bluetooth access is denied on mobile.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth access for Vizor in your device settings.'**
  String get ledgerBtAccessBluetoothSettings;

  /// Permission name 'Location' inserted into the restricted-access sentence.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get ledgerBtAccessKindLocation;

  /// Shown on Android before the location permission is requested. 'Allow permission' is a button label.
  ///
  /// In en, this message translates to:
  /// **'This Android version needs location permission to find your Ledger. Choose Allow permission, or open Settings if no prompt appears.'**
  String get ledgerBtAccessLocationRequestable;

  /// Shown on Android when location permission is denied and must be changed in Settings.
  ///
  /// In en, this message translates to:
  /// **'This Android version needs location permission to find your Ledger. Allow location access for Vizor in Settings.'**
  String get ledgerBtAccessLocationSettings;

  /// Shown on macOS when Bluetooth access is denied. 'System Settings', 'Privacy & Security' and 'Bluetooth' are macOS menu names; use the localized macOS names.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings > Privacy & Security > Bluetooth and allow access for Vizor.'**
  String get ledgerBtAccessMacosSettings;

  /// Shown in the access checker when the permission is restricted. {kind} is the permission name, Location or Bluetooth.
  ///
  /// In en, this message translates to:
  /// **'{kind} access is restricted by your device settings or administrator.'**
  String ledgerBtAccessRestricted(String kind);

  /// Shown in the Bluetooth access checker when Bluetooth is off.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bluetooth, then check access again.'**
  String get ledgerBtAccessTurnOnBluetooth;

  /// Shown in the Bluetooth access checker when location services are off.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services, then check access again.'**
  String get ledgerBtAccessTurnOnLocation;

  /// Error when checking Bluetooth access failed.
  ///
  /// In en, this message translates to:
  /// **'Could not check access. Open Settings manually, then check again.'**
  String get ledgerBtCouldNotCheckAccess;

  /// Error when the system settings could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open Settings. Open your device settings manually and allow access for Vizor.'**
  String get ledgerBtCouldNotOpenSettingsAllow;

  /// Error when the system settings could not be opened while Bluetooth access is restricted.
  ///
  /// In en, this message translates to:
  /// **'Could not open Settings. Open your device settings manually to review access for Vizor.'**
  String get ledgerBtCouldNotOpenSettingsRestricted;

  /// Button label that asks the system to show the permission prompt.
  ///
  /// In en, this message translates to:
  /// **'Allow access'**
  String get ledgerBtLabelAllowAccess;

  /// Button label while access is being checked.
  ///
  /// In en, this message translates to:
  /// **'Checking access'**
  String get ledgerBtLabelChecking;

  /// Button label to reconnect to the Ledger once access is granted.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get ledgerBtLabelReconnect;

  /// Message explaining why Bluetooth access is needed.
  ///
  /// In en, this message translates to:
  /// **'Vizor needs Bluetooth access to connect to your Ledger.'**
  String get ledgerBtMsgBluetoothNeeded;

  /// Message while Vizor checks if it can connect to the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Checking whether Vizor can connect to your Ledger.'**
  String get ledgerBtMsgChecking;

  /// Message explaining why Android asks for location access.
  ///
  /// In en, this message translates to:
  /// **'This Android version needs location access to find your Ledger.'**
  String get ledgerBtMsgLocationNeeded;

  /// Message when Bluetooth access is fine; the user must turn on and unlock the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Turn on your Ledger and unlock it to continue.'**
  String get ledgerBtMsgReady;

  /// Help when Bluetooth access is restricted.
  ///
  /// In en, this message translates to:
  /// **'Check Vizor’s Bluetooth access in Settings. Device restrictions or your administrator may prevent changes.'**
  String get ledgerBtRestrictedGeneric;

  /// Help on Android when location access is restricted.
  ///
  /// In en, this message translates to:
  /// **'Check location access for Vizor in Settings. Device restrictions or your administrator may prevent changes.'**
  String get ledgerBtRestrictedLocation;

  /// Help on macOS when Bluetooth access is restricted. Use the localized macOS menu names.
  ///
  /// In en, this message translates to:
  /// **'Check Privacy & Security > Bluetooth in System Settings. This restriction may need to be changed by your administrator.'**
  String get ledgerBtRestrictedMacos;

  /// Help on Android when Nearby devices access is restricted.
  ///
  /// In en, this message translates to:
  /// **'Check Nearby devices access for Vizor in Settings. Device restrictions or your administrator may prevent changes.'**
  String get ledgerBtRestrictedNearby;

  /// Message in the mobile Bluetooth sheet when permission is denied during account import.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth access for Vizor in your phone settings to add your account.'**
  String get ledgerBtSheetAllowAddAccount;

  /// Generic message in the mobile Bluetooth sheet when permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth access for Vizor in your phone settings to continue.'**
  String get ledgerBtSheetAllowContinue;

  /// Message in the mobile Bluetooth sheet when permission is denied and signing was interrupted.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth access for Vizor in your phone settings to continue signing.'**
  String get ledgerBtSheetAllowSigning;

  /// Message in the mobile Bluetooth sheet during account import.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is available. Unlock your Ledger to add your account.'**
  String get ledgerBtSheetReadyAddAccount;

  /// Generic message in the mobile Bluetooth sheet.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is available. Unlock your Ledger to continue.'**
  String get ledgerBtSheetReadyContinue;

  /// Message in the mobile Bluetooth sheet when signing was interrupted.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is available. Unlock your Ledger to continue signing.'**
  String get ledgerBtSheetReadySigning;

  /// Message in the mobile Bluetooth sheet when Bluetooth is off during account import.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bluetooth on your phone to add your account.'**
  String get ledgerBtSheetTurnOnAddAccount;

  /// Generic message in the mobile Bluetooth sheet when Bluetooth is off.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bluetooth on your phone to continue.'**
  String get ledgerBtSheetTurnOnContinue;

  /// Message in the mobile Bluetooth sheet when Bluetooth is off and signing was interrupted.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bluetooth on your phone to continue signing.'**
  String get ledgerBtSheetTurnOnSigning;

  /// Title asking the user to allow Bluetooth access.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth access'**
  String get ledgerBtTitleAllowBluetooth;

  /// Title asking the user to allow Bluetooth in system Settings.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth in Settings'**
  String get ledgerBtTitleAllowBluetoothSettings;

  /// Title asking the user to allow location access (Android).
  ///
  /// In en, this message translates to:
  /// **'Allow location access'**
  String get ledgerBtTitleAllowLocation;

  /// Title asking the user to allow location in system Settings.
  ///
  /// In en, this message translates to:
  /// **'Allow location in Settings'**
  String get ledgerBtTitleAllowLocationSettings;

  /// Title while Vizor checks Bluetooth permission for the Ledger connection.
  ///
  /// In en, this message translates to:
  /// **'Checking Bluetooth access'**
  String get ledgerBtTitleChecking;

  /// Title when Bluetooth access is fine and the user can reconnect the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Ready to reconnect'**
  String get ledgerBtTitleReady;

  /// Title when Bluetooth or location access is restricted by the device or an administrator.
  ///
  /// In en, this message translates to:
  /// **'Access is restricted'**
  String get ledgerBtTitleRestricted;

  /// Title asking the user to turn on Bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bluetooth'**
  String get ledgerBtTitleTurnOnBluetooth;

  /// Title asking the user to turn on location services (needed on Android to find Bluetooth devices).
  ///
  /// In en, this message translates to:
  /// **'Turn on location services'**
  String get ledgerBtTitleTurnOnLocation;

  /// Disabled button label while verifying the account.
  ///
  /// In en, this message translates to:
  /// **'Checking account'**
  String get ledgerButtonCheckingAccount;

  /// Disabled button label while connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get ledgerButtonConnecting;

  /// Disabled button label while searching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get ledgerButtonSearching;

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

  /// Shown when Ledger is not available on the selected network.
  ///
  /// In en, this message translates to:
  /// **'Ledger is currently supported only for Zcash mainnet.'**
  String get ledgerCapabilityMainnetOnly;

  /// Shown when Ledger is not available on this operating system.
  ///
  /// In en, this message translates to:
  /// **'Ledger is supported on Vizor for macOS, Windows, Linux, iOS, and Android.'**
  String get ledgerCapabilityUnsupportedPlatform;

  /// Message when a different Ledger or app was found than the one verified earlier.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger changed. Keep one Ledger connected and try again.'**
  String get ledgerChangedKeepOne;

  /// Status text while Vizor checks the Bluetooth permission on desktop.
  ///
  /// In en, this message translates to:
  /// **'Checking Bluetooth access…'**
  String get ledgerCheckingBluetoothAccess;

  /// Status while Vizor checks the USB connection.
  ///
  /// In en, this message translates to:
  /// **'Checking USB connection…'**
  String get ledgerCheckingUsb;

  /// Back-link text in the desktop dialog that returns to the device picker.
  ///
  /// In en, this message translates to:
  /// **'Choose another Ledger'**
  String get ledgerChooseAnother;

  /// Back button label in Ledger dialogs that returns to the connection choice.
  ///
  /// In en, this message translates to:
  /// **'Choose connection'**
  String get ledgerChooseConnection;

  /// Message above the list of found Ledger devices.
  ///
  /// In en, this message translates to:
  /// **'Choose a device to continue.'**
  String get ledgerChooseDevice;

  /// Message above the list of found Ledger devices.
  ///
  /// In en, this message translates to:
  /// **'Choose the Ledger you want to use for this account.'**
  String get ledgerChooseLedgerForAccount;

  /// Error in the desktop Bluetooth dialog when closing the Ledger session failed.
  ///
  /// In en, this message translates to:
  /// **'Could not finish cleanup. Try again.'**
  String get ledgerCleanupFailed;

  /// Body of recovery step 2 in the desktop dialog. 'Find Ledger' is the button label below.
  ///
  /// In en, this message translates to:
  /// **'Keep your Ledger unlocked, then select Find Ledger below.'**
  String get ledgerComeBackFindLedger;

  /// Body of recovery step 2. 'Find my Ledger' is the button label below.
  ///
  /// In en, this message translates to:
  /// **'Keep your Ledger unlocked, then select “Find my Ledger” below.'**
  String get ledgerComeBackFindMyLedger;

  /// Title of recovery step 2.
  ///
  /// In en, this message translates to:
  /// **'Come back and reconnect'**
  String get ledgerComeBackReconnect;

  /// [security] Message while verifying a new Ledger: the user approves sharing the viewing key on the device.
  ///
  /// In en, this message translates to:
  /// **'Complete pairing if prompted, then open the Zcash app and approve sharing the viewing key.'**
  String get ledgerCompletePairingOpenZcash;

  /// Message asking the user to confirm on the Ledger device that the Zcash app may open. 'Zcash' is the app name on the device.
  ///
  /// In en, this message translates to:
  /// **'Confirm opening Zcash on Ledger.'**
  String get ledgerConfirmOpeningZcash;

  /// Instruction to choose how to connect the Ledger for this account.
  ///
  /// In en, this message translates to:
  /// **'Connect the Ledger for this account.'**
  String get ledgerConnectForAccount;

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

  /// Guidance shown when the Ledger could not be reached over Bluetooth and the user has to reconnect it.
  ///
  /// In en, this message translates to:
  /// **'Turn on and unlock your Ledger, then reconnect with Bluetooth.'**
  String get ledgerConnectionRequiredBluetooth;

  /// Guidance shown when the Ledger could not be reached over USB and the user has to reconnect it.
  ///
  /// In en, this message translates to:
  /// **'Connect and unlock your Ledger with USB, then try again.'**
  String get ledgerConnectionRequiredUsb;

  /// Button label to continue signing after the Ledger is connected.
  ///
  /// In en, this message translates to:
  /// **'Continue signing'**
  String get ledgerContinueSigning;

  /// Title of the desktop dialog after connecting to the Ledger failed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect Ledger'**
  String get ledgerCouldNotConnect;

  /// Error in the desktop Ledger recovery dialog when stopping the search failed.
  ///
  /// In en, this message translates to:
  /// **'Could not stop the search. Try again.'**
  String get ledgerCouldNotStopSearchTryAgain;

  /// Hint under a found Ledger that differs from the saved one.
  ///
  /// In en, this message translates to:
  /// **'Different from saved connection'**
  String get ledgerDifferentFromSaved;

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

  /// Shown when the Ledger firmware and Zcash app are too old for this transaction. {version} is a version number such as 3.10.0. 'Ledger Wallet' is a product name.
  ///
  /// In en, this message translates to:
  /// **'Update your Ledger and its Zcash app to {version} or newer in Ledger Wallet.'**
  String ledgerFailureMsgAppUpdateRequired(String version);

  /// Message when the Ledger is busy with another request.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger is busy. Try again in a moment.'**
  String get ledgerFailureMsgBusy;

  /// Message after a Ledger request was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled. Try again when ready.'**
  String get ledgerFailureMsgCancelledTryAgain;

  /// Generic message asking the user to check the Ledger and open the Zcash app.
  ///
  /// In en, this message translates to:
  /// **'Check your Ledger and open the Zcash app, then try again.'**
  String get ledgerFailureMsgCheckOpenZcash;

  /// Message under a Ledger failure card after the user declined the request on the device.
  ///
  /// In en, this message translates to:
  /// **'Declined on your Ledger. Try again when ready.'**
  String get ledgerFailureMsgDeclined;

  /// Message when the Ledger could not accept a gift card request; nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger couldn’t accept this request. Create a new gift card. Nothing was sent.'**
  String get ledgerFailureMsgGiftCardRejected;

  /// Message when a gift card is too large for the Ledger to sign.
  ///
  /// In en, this message translates to:
  /// **'Too large for your Ledger. Create a gift card with a smaller amount.'**
  String get ledgerFailureMsgGiftCardTooLarge;

  /// Message asking the user to install the Zcash app using the Ledger Wallet desktop app. 'Ledger Wallet' is a product name.
  ///
  /// In en, this message translates to:
  /// **'Install the Zcash app with Ledger Wallet.'**
  String get ledgerFailureMsgInstallZcash;

  /// Shown when the Zcash app on the Ledger is too old to sign a memo with non-English characters.
  ///
  /// In en, this message translates to:
  /// **'Update the Ledger Zcash app to sign non-English memos'**
  String get ledgerFailureMsgMemoHashUnsupported;

  /// Message when a migration step is too large for the Ledger to sign.
  ///
  /// In en, this message translates to:
  /// **'This migration step is too large for your Ledger to sign. Vizor can’t split it yet.'**
  String get ledgerFailureMsgMigrationTooLarge;

  /// Message asking the user to open the Zcash app on the Ledger. 'Zcash' is the app name shown on the device.
  ///
  /// In en, this message translates to:
  /// **'Open the Zcash app on your Ledger.'**
  String get ledgerFailureMsgOpenZcash;

  /// Shown when a transaction would keep change in the Orchard pool, which the Ledger cannot sign. 'Orchard' and 'Ironwood' are Zcash pool names.
  ///
  /// In en, this message translates to:
  /// **'Ledger can\'t sign a transaction that keeps change in Orchard. Migrate your Orchard balance to Ironwood first.'**
  String get ledgerFailureMsgOrchardChange;

  /// Message when a payment is too large for the Ledger to sign.
  ///
  /// In en, this message translates to:
  /// **'Start a new payment. Don’t send a smaller amount to this address.'**
  String get ledgerFailureMsgPaymentTooLarge;

  /// Message asking the user to reconnect and unlock the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Reconnect and unlock your Ledger.'**
  String get ledgerFailureMsgReconnectUnlock;

  /// Message when the Ledger could not accept a request Vizor built; nothing was broadcast.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger couldn’t accept this request. Create a new one. Nothing was sent.'**
  String get ledgerFailureMsgRejectedNewRequest;

  /// Message asking the user to close and reopen the Zcash app on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Close and reopen the Zcash app.'**
  String get ledgerFailureMsgReopenZcash;

  /// Message when a Ledger cannot send to a Sapling address. 'Sapling' is a Zcash pool name.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger can’t send to a Sapling address. Create a new request.'**
  String get ledgerFailureMsgSaplingRecipient;

  /// [security] Message asking the user to set a PIN on the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'Set up a PIN on your Ledger, then try again.'**
  String get ledgerFailureMsgSetPin;

  /// Message when shielding has too many inputs for the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Too many inputs for your Ledger. Try again. Nothing was shielded.'**
  String get ledgerFailureMsgShieldTooLarge;

  /// Message when a swap is too large for the Ledger to sign; the swap is discarded.
  ///
  /// In en, this message translates to:
  /// **'Start a new swap with a smaller amount. This one is discarded.'**
  String get ledgerFailureMsgSwapTooLarge;

  /// Message when a send has more inputs than the Ledger can sign.
  ///
  /// In en, this message translates to:
  /// **'Too many inputs for your Ledger. Try a smaller amount.'**
  String get ledgerFailureMsgTooManyInputs;

  /// Message for an unexpected Ledger device error.
  ///
  /// In en, this message translates to:
  /// **'Unexpected Ledger error. Reopen the Zcash app and try again.'**
  String get ledgerFailureMsgUnexpected;

  /// Message for an unexpected Ledger device error. {code} is empty or a status code in parentheses with a leading space, such as ' (0x6e00)'.
  ///
  /// In en, this message translates to:
  /// **'Unexpected Ledger error{code}. Reopen the Zcash app and try again.'**
  String ledgerFailureMsgUnexpectedWithCode(String code);

  /// Message asking the user to unlock the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Ledger, then try again.'**
  String get ledgerFailureMsgUnlock;

  /// Message when the Ledger cannot sign this kind of transaction.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger can’t sign this transaction type. Create a new request.'**
  String get ledgerFailureMsgUnsupportedTxType;

  /// Message asking the user to update the Zcash app on the Ledger. {version} is a version number such as 3.9.3.
  ///
  /// In en, this message translates to:
  /// **'Update the Zcash app to {version} or newer.'**
  String ledgerFailureMsgUpdateZcash(String version);

  /// [security] Message when the Ledger could not accept a viewing-key request.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger couldn’t accept this viewing-key request. Check the account number.'**
  String get ledgerFailureMsgViewingKeyRejected;

  /// Message when the Ledger could not accept a vote request.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger couldn’t accept this vote request. Your vote was not signed.'**
  String get ledgerFailureMsgVoteRejected;

  /// Message when a vote is too large for the Ledger to sign.
  ///
  /// In en, this message translates to:
  /// **'This vote is too large for your Ledger to sign.'**
  String get ledgerFailureMsgVoteTooLarge;

  /// [security] Message when the connected Ledger signed with a different key than this account's, asking for the right device.
  ///
  /// In en, this message translates to:
  /// **'Connect the Ledger that holds this account.'**
  String get ledgerFailureMsgWrongLedger;

  /// Title of a Ledger failure card when the device is busy with another request.
  ///
  /// In en, this message translates to:
  /// **'Ledger is busy'**
  String get ledgerFailureTitleBusy;

  /// Title of a Ledger failure card when the request was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get ledgerFailureTitleCancelled;

  /// Title of a Ledger failure card for an unexpected device error.
  ///
  /// In en, this message translates to:
  /// **'Ledger error'**
  String get ledgerFailureTitleError;

  /// Generic title of a Ledger failure card.
  ///
  /// In en, this message translates to:
  /// **'Request failed'**
  String get ledgerFailureTitleFailed;

  /// Title of a Ledger failure card when the device is locked.
  ///
  /// In en, this message translates to:
  /// **'Ledger locked'**
  String get ledgerFailureTitleLocked;

  /// Title of a Ledger failure card when the device cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Ledger not reachable'**
  String get ledgerFailureTitleNotReachable;

  /// Title of a Ledger failure card asking the user to open the Zcash app on the device.
  ///
  /// In en, this message translates to:
  /// **'Open the Zcash app'**
  String get ledgerFailureTitleOpenZcash;

  /// Title of a Ledger failure card when no PIN is set on the device.
  ///
  /// In en, this message translates to:
  /// **'PIN required'**
  String get ledgerFailureTitlePinRequired;

  /// Title of a Ledger failure card when the Zcash app refused a request Vizor built.
  ///
  /// In en, this message translates to:
  /// **'Request not accepted'**
  String get ledgerFailureTitleRejected;

  /// Title of a Ledger failure card when the Zcash app is in an unexpected state.
  ///
  /// In en, this message translates to:
  /// **'Reopen the Zcash app'**
  String get ledgerFailureTitleReopenZcash;

  /// Title of a Ledger failure card when the request exceeds what the device can sign.
  ///
  /// In en, this message translates to:
  /// **'Request too large'**
  String get ledgerFailureTitleTooLarge;

  /// Title of a Ledger failure card when the Zcash app on the device is too old.
  ///
  /// In en, this message translates to:
  /// **'Update the Zcash app'**
  String get ledgerFailureTitleUpdateZcash;

  /// Title of a Ledger failure card when the connected device does not hold the account.
  ///
  /// In en, this message translates to:
  /// **'Wrong Ledger'**
  String get ledgerFailureTitleWrongLedger;

  /// Title of a Ledger failure card when the Zcash app is not installed on the device.
  ///
  /// In en, this message translates to:
  /// **'Zcash app missing'**
  String get ledgerFailureTitleZcashMissing;

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

  /// Status while the user must act on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Follow the prompts on Ledger.'**
  String get ledgerFollowPromptsOnLedger;

  /// Third check in the Ledger connection help.
  ///
  /// In en, this message translates to:
  /// **'Close other wallet apps and disconnect Ledger from other phones or computers.'**
  String get ledgerHelpChecksCloseOtherApps;

  /// Second check in the Ledger connection help.
  ///
  /// In en, this message translates to:
  /// **'Leave Ledger on its home screen. Open the Zcash app when Vizor asks.'**
  String get ledgerHelpChecksHomeScreen;

  /// First check in the Ledger connection help.
  ///
  /// In en, this message translates to:
  /// **'Unlock Ledger, turn on Bluetooth, and keep it close to your phone.'**
  String get ledgerHelpChecksUnlockClose;

  /// Placeholder of the Ledger model dropdown.
  ///
  /// In en, this message translates to:
  /// **'Choose your model'**
  String get ledgerHelpChooseModel;

  /// Intro of step 2 in the Ledger pairing reset help.
  ///
  /// In en, this message translates to:
  /// **'Find your Ledger in your phone’s Bluetooth settings.'**
  String get ledgerHelpFindInPhoneBluetooth;

  /// Android menu path to forget the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth settings > the settings button next to your Ledger > Forget or Unpair'**
  String get ledgerHelpForgetAndroid;

  /// iOS menu path to forget the Ledger. Use the localized iOS names.
  ///
  /// In en, this message translates to:
  /// **'Settings > Bluetooth > the info button next to your Ledger > Forget This Device'**
  String get ledgerHelpForgetIos;

  /// First instruction of the last step in the Ledger help.
  ///
  /// In en, this message translates to:
  /// **'Keep Ledger unlocked with Bluetooth on, and leave it on its home screen.'**
  String get ledgerHelpKeepUnlockedHome;

  /// Label above the Ledger model dropdown.
  ///
  /// In en, this message translates to:
  /// **'Ledger model'**
  String get ledgerHelpModelLabel;

  /// [security] Instruction to confirm on the Ledger and enter the PIN on the device.
  ///
  /// In en, this message translates to:
  /// **'Confirm on Ledger and enter your PIN on the device.'**
  String get ledgerHelpNanoXConfirm;

  /// Instruction for Ledger Nano X; the menu path follows on the next line.
  ///
  /// In en, this message translates to:
  /// **'Unlock Ledger. Hold both buttons to open its controls, then choose:'**
  String get ledgerHelpNanoXControls;

  /// Menu path shown on the Ledger Nano X. Keep it in English, exactly as the device shows it.
  ///
  /// In en, this message translates to:
  /// **'Settings > Security > Reset pairings'**
  String get ledgerHelpNanoXMenuPath;

  /// Help text explaining how to find the Ledger Nano X name. 'Device Name' is the menu item shown on the device and stays in English.
  ///
  /// In en, this message translates to:
  /// **'On your Nano X, hold both buttons for 2 seconds, then find Device Name.'**
  String get ledgerHelpNanoXName;

  /// Button label that moves to the phone step of the Ledger help.
  ///
  /// In en, this message translates to:
  /// **'Next: phone settings'**
  String get ledgerHelpNextPhoneSettings;

  /// Button label that moves to the last step of the Ledger help.
  ///
  /// In en, this message translates to:
  /// **'Next: search in Vizor'**
  String get ledgerHelpNextSearchInVizor;

  /// Title of the first and last step of the Ledger help.
  ///
  /// In en, this message translates to:
  /// **'Find your Ledger'**
  String get ledgerHelpNextSearchTitle;

  /// [security] Warning not to choose Reset device on the Ledger. 'Reset device' is the menu item shown on the device and stays in English.
  ///
  /// In en, this message translates to:
  /// **'Use the Bluetooth pairing option, not Reset device. Your wallet and accounts stay unchanged.'**
  String get ledgerHelpNotResetDevice;

  /// Button label that opens the phone's Bluetooth settings.
  ///
  /// In en, this message translates to:
  /// **'Open Bluetooth settings'**
  String get ledgerHelpOpenBluetoothSettings;

  /// Help text explaining how to find the Ledger name. {model} is a product model such as Flex or Stax and stays in Latin script. 'Settings > Name' is the menu path shown on the device and stays in English.
  ///
  /// In en, this message translates to:
  /// **'On your {model}, check Settings > Name.'**
  String ledgerHelpOtherModelName(String model);

  /// Intro of step 1 in the Ledger pairing reset help.
  ///
  /// In en, this message translates to:
  /// **'Remove the saved pairing on Ledger, then remove it on your phone.'**
  String get ledgerHelpRemovePairingOnLedger;

  /// Last-resort advice in the Ledger help.
  ///
  /// In en, this message translates to:
  /// **'If it still does not appear, restart both devices and check Ledger’s official Bluetooth troubleshooting guide.'**
  String get ledgerHelpRestartBothGuide;

  /// Second instruction of the last step in the Ledger help.
  ///
  /// In en, this message translates to:
  /// **'Search in Vizor and select your Ledger. Open the Zcash app when Vizor asks.'**
  String get ledgerHelpSearchSelectOpenZcash;

  /// Hint shown until a Ledger model is selected.
  ///
  /// In en, this message translates to:
  /// **'Select your model to see its pairing removal instructions.'**
  String get ledgerHelpSelectModelHint;

  /// Hint about how the Ledger appears in the phone's Bluetooth list.
  ///
  /// In en, this message translates to:
  /// **'If you haven’t named your Ledger, it may appear as a short ID, such as 01AB. Otherwise, look for the name you set.'**
  String get ledgerHelpShortIdName;

  /// Hint to skip the step when the Ledger is not in the phone's Bluetooth list.
  ///
  /// In en, this message translates to:
  /// **'If Ledger is not listed, skip this step and continue.'**
  String get ledgerHelpSkipIfNotListed;

  /// Step indicator in the Ledger connection help; this step is done back in the app.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 3 · Back in Vizor'**
  String ledgerHelpStepBackInVizor(String step);

  /// Step indicator in the Ledger connection help; this step is done on the device.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 3 · On your Ledger'**
  String ledgerHelpStepOnLedger(String step);

  /// Step indicator in the Ledger connection help; this step is done on the phone.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 3 · On your phone'**
  String ledgerHelpStepOnPhone(String step);

  /// Heading above extra troubleshooting advice.
  ///
  /// In en, this message translates to:
  /// **'Still not showing?'**
  String get ledgerHelpStillNotShowing;

  /// Instruction for touchscreen Ledger models; the menu path follows on the next line.
  ///
  /// In en, this message translates to:
  /// **'Unlock Ledger. From its home screen, tap the settings icon, then choose:'**
  String get ledgerHelpTouchControls;

  /// Menu path shown on touchscreen Ledger models. Keep it in English, exactly as the device shows it.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth > Remove pairing'**
  String get ledgerHelpTouchMenuPath;

  /// Troubleshooting advice when the Ledger is not found.
  ///
  /// In en, this message translates to:
  /// **'Try restarting Ledger. If it stays missing, removing the saved Bluetooth pairing on both devices may help.'**
  String get ledgerHelpTryRestart;

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

  /// Hint under the open-the-app instruction.
  ///
  /// In en, this message translates to:
  /// **'Keep it open on your Ledger.'**
  String get ledgerKeepItOpen;

  /// Message under the first connection step in the desktop dialog.
  ///
  /// In en, this message translates to:
  /// **'Keep your Ledger nearby and unlocked, with Bluetooth turned on.'**
  String get ledgerKeepNearbyUnlocked;

  /// Message while searching for the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Keep your Ledger nearby and unlocked.'**
  String get ledgerKeepNearbyUnlockedShort;

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

  /// [security] Message when the connected Ledger is not the one that holds this account.
  ///
  /// In en, this message translates to:
  /// **'Choose the Ledger that holds this account. Your saved connection has not changed.'**
  String get ledgerMismatchChooseHolder;

  /// [security] Mobile message when the connected Ledger is not the one that holds this account.
  ///
  /// In en, this message translates to:
  /// **'Choose the Ledger that holds this account. Your saved connection hasn’t changed.'**
  String get ledgerMismatchChooseHolderMobile;

  /// [security] Message when the connected Ledger is not the one that holds this account.
  ///
  /// In en, this message translates to:
  /// **'Connect the Ledger that holds this account. Your saved connection hasn’t changed.'**
  String get ledgerMismatchConnectHolder;

  /// Guidance when the device still shows a previous request.
  ///
  /// In en, this message translates to:
  /// **'Another Ledger request is still active. Complete or reject it on your Ledger, then try again.'**
  String get ledgerMobileAnotherRequestActive;

  /// Guidance when Bluetooth permission was denied; a Bluetooth access checker is shown below.
  ///
  /// In en, this message translates to:
  /// **'Check Bluetooth access below, then try connecting to your Ledger again.'**
  String get ledgerMobileCheckBluetoothBelow;

  /// Error on the Ledger sheet when the Bluetooth connection failed without a reason.
  ///
  /// In en, this message translates to:
  /// **'Ledger mobile connection failed.'**
  String get ledgerMobileConnectionFailed;

  /// Guidance when the Bluetooth connection failed or dropped.
  ///
  /// In en, this message translates to:
  /// **'The Bluetooth connection to your Ledger was lost or could not be established. Turn on and unlock your Ledger, keep it nearby, then try again.'**
  String get ledgerMobileConnectionLost;

  /// Error on the Ledger connection sheet when the Bluetooth device search failed without a reason.
  ///
  /// In en, this message translates to:
  /// **'Ledger discovery failed.'**
  String get ledgerMobileDiscoveryFailed;

  /// Error on the Ledger signing sheet when the Bluetooth connection answered with nothing.
  ///
  /// In en, this message translates to:
  /// **'Ledger returned an empty response.'**
  String get ledgerMobileEmptyResponse;

  /// Guidance when the stored Bluetooth pairing with the Ledger is stale and must be removed in system settings.
  ///
  /// In en, this message translates to:
  /// **'Your Bluetooth pairing is no longer valid. Forget this Ledger in your device’s Bluetooth settings, then reconnect.'**
  String get ledgerMobilePairingInvalid;

  /// Guidance when the user did not complete the Bluetooth pairing prompt.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth pairing was not completed. Reconnect your Ledger and approve the pairing request, then try again.'**
  String get ledgerMobilePairingNotCompleted;

  /// Guidance when the Ledger request was cancelled.
  ///
  /// In en, this message translates to:
  /// **'The Ledger request was cancelled. Try again when ready.'**
  String get ledgerMobileRequestCancelled;

  /// Guidance when the user rejected the request on the device.
  ///
  /// In en, this message translates to:
  /// **'The request was rejected on your Ledger. Try again when ready.'**
  String get ledgerMobileRequestRejected;

  /// Guidance when Bluetooth is turned off.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bluetooth, then try again.'**
  String get ledgerMobileTurnOnBluetooth;

  /// Guidance on Android when location services are off, which this Android version needs to find Bluetooth devices.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services to find your Ledger on this Android version, then try again.'**
  String get ledgerMobileTurnOnLocation;

  /// Fallback guidance when the Bluetooth connection to the Ledger failed for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not reach your Ledger. Make sure it is on, unlocked and nearby, then try again.'**
  String get ledgerMobileUnavailable;

  /// Error on the Ledger connection sheet when the Bluetooth device search reported something Vizor does not recognize.
  ///
  /// In en, this message translates to:
  /// **'Ledger discovery returned an unknown event.'**
  String get ledgerMobileUnknownDiscoveryEvent;

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

  /// Instruction to open an app on the Ledger. {appName} is the device app name, normally Zcash, and stays in Latin script.
  ///
  /// In en, this message translates to:
  /// **'Open the {appName} app'**
  String ledgerOpenAppInstruction(String appName);

  /// Instruction to open an app on the Ledger. {appName} is the device app name, normally Zcash.
  ///
  /// In en, this message translates to:
  /// **'Open the {appName} app on your Ledger.'**
  String ledgerOpenAppOnLedger(String appName);

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

  /// Status while the mobile Ledger connection help is prepared.
  ///
  /// In en, this message translates to:
  /// **'Opening connection help…'**
  String get ledgerOpeningConnectionHelp;

  /// Message when the Ledger forgot the stored Bluetooth pairing.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger no longer recognizes this Bluetooth pairing.'**
  String get ledgerPairingNoLongerRecognized;

  /// Message when the Ledger forgot the stored Bluetooth pairing and the old pairing must be removed.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger no longer recognizes this Bluetooth pairing. Remove the old pairing, then reconnect.'**
  String get ledgerPairingNoLongerRecognizedRemove;

  /// Screen-reader label of a step in the Ledger procedure list.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String ledgerProcedureStep(String step, String total);

  /// Screen-reader label of a finished step in the Ledger procedure list.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}, complete'**
  String ledgerProcedureStepComplete(String step, String total);

  /// Ledger error when the Zcash app version could not be read. 'Zcash' is the device app name.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not verify the Ledger Zcash app. Try again.'**
  String get ledgerReadinessAppNotVerified;

  /// Fallback message when preparing the Zcash app on the Ledger failed.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not prepare the Ledger Zcash app. Try again.'**
  String get ledgerReadinessCouldNotPrepare;

  /// Ledger error when another app or the dashboard is open on the device. 'Zcash' is the device app name.
  ///
  /// In en, this message translates to:
  /// **'Open the Zcash app on your Ledger, then try again.'**
  String get ledgerReadinessOpenZcashApp;

  /// Message when a Ledger operation was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Ledger operation was cancelled.'**
  String get ledgerReadinessOperationCancelled;

  /// Message asking the user to reconnect and unlock the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Reconnect and unlock your Ledger, then try again.'**
  String get ledgerReadinessReconnectUnlockTryAgain;

  /// [security] Ledger error when the Zcash device app is too old. {version} is a version number such as 3.10.0.
  ///
  /// In en, this message translates to:
  /// **'Update the Ledger Zcash app to version {version} or newer.'**
  String ledgerReadinessUpdateApp(String version);

  /// Message when Vizor has no USB permission to reach the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Connect and unlock your Ledger over USB. If it is connected, install the Ledger udev rules on Linux, then unplug and reconnect it.'**
  String get ledgerReadinessUsbPermission;

  /// Message when the Ledger is connected and signing can continue.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger is ready. Continue signing when you’re ready.'**
  String get ledgerReadyContinueSigning;

  /// [security] Message when the Ledger is connected; the user will review the transaction on the device next.
  ///
  /// In en, this message translates to:
  /// **'Continue when you’re ready to review the transaction on your Ledger.'**
  String get ledgerReadyReviewOnLedger;

  /// Title of the mobile Bluetooth sheet when access is fine and the user can reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect Ledger'**
  String get ledgerReconnectTitle;

  /// Title of recovery step 1.
  ///
  /// In en, this message translates to:
  /// **'Remove the old pairing'**
  String get ledgerRemoveOldPairing;

  /// Recovery step on iOS. Use the localized iOS names for Settings and Bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Open Settings > Bluetooth. If your Ledger is listed, tap its info button and forget the device.'**
  String get ledgerRemovePairingIos;

  /// Recovery step on macOS. Use the localized macOS names.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings > Bluetooth. If your Ledger is listed, remove its saved pairing.'**
  String get ledgerRemovePairingMacos;

  /// Recovery step on other platforms.
  ///
  /// In en, this message translates to:
  /// **'Open Bluetooth settings. If your Ledger is listed, remove its saved pairing.'**
  String get ledgerRemovePairingOther;

  /// Button and title in the mobile Ledger help that guides the user to remove the saved Bluetooth pairing.
  ///
  /// In en, this message translates to:
  /// **'Reset Bluetooth pairing'**
  String get ledgerResetBluetoothPairing;

  /// Status text while the desktop dialog returns to the connection options after stopping the search.
  ///
  /// In en, this message translates to:
  /// **'Returning to connection options…'**
  String get ledgerReturningToOptions;

  /// Message after the Ledger was verified; the user must search again to continue.
  ///
  /// In en, this message translates to:
  /// **'This Ledger matches your account. Find it again to continue.'**
  String get ledgerSavedFindAgain;

  /// Message after the Ledger was verified and stored.
  ///
  /// In en, this message translates to:
  /// **'This Ledger matches your account and is now saved. Find it again to continue.'**
  String get ledgerSavedMatchesFindAgain;

  /// Message while the verified Ledger connection is stored.
  ///
  /// In en, this message translates to:
  /// **'Your account matches. Saving the verified connection.'**
  String get ledgerSavingVerified;

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

  /// Note under the review step when several transactions are signed in a row.
  ///
  /// In en, this message translates to:
  /// **'You will approve the next transaction separately.'**
  String get ledgerSigningApproveNextSeparately;

  /// [security] Note under the review step on mobile asking the user to approve or reject on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Approve to sign, or reject to cancel.'**
  String get ledgerSigningApproveOrReject;

  /// [security] Note under the review step asking the user to approve signing on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Approve to sign.'**
  String get ledgerSigningApproveToSign;

  /// [security] Note under the review step when several transactions are signed in a row; the two paragraphs are separated by a blank line.
  ///
  /// In en, this message translates to:
  /// **'Approve to sign.\n\nYou will approve the next transaction separately.'**
  String get ledgerSigningApproveToSignNext;

  /// Step message after the user approved on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Approved on Ledger. Vizor is finishing the transaction.'**
  String get ledgerSigningApprovedFinishing;

  /// Back button label in the Ledger signing dialog that returns to the connection options.
  ///
  /// In en, this message translates to:
  /// **'Change connection'**
  String get ledgerSigningChangeConnection;

  /// [security] Step message asking the user to verify the amount and recipient on the Ledger screen before approving.
  ///
  /// In en, this message translates to:
  /// **'When prompted, check the amount and recipient on Ledger.'**
  String get ledgerSigningCheckAmountRecipient;

  /// Screen-reader label of the close button on the mobile Ledger signing surface.
  ///
  /// In en, this message translates to:
  /// **'Close Ledger'**
  String get ledgerSigningCloseSemantics;

  /// [security] Message asking the user to confirm on the Ledger; Vizor reconnects by itself afterwards.
  ///
  /// In en, this message translates to:
  /// **'Confirm the request on your Ledger. Vizor will reconnect automatically.'**
  String get ledgerSigningConfirmRequestReconnect;

  /// [security] Step message in the Ledger signing dialog after the user declined signing on the device.
  ///
  /// In en, this message translates to:
  /// **'Signing was declined on Ledger. Try again when you’re ready.'**
  String get ledgerSigningDeclined;

  /// Step message while the Ledger request is being finished.
  ///
  /// In en, this message translates to:
  /// **'Finishing the Ledger request.'**
  String get ledgerSigningFinishingRequest;

  /// Reminder in the Ledger signing dialog to leave the device connected.
  ///
  /// In en, this message translates to:
  /// **'Keep Ledger connected.'**
  String get ledgerSigningKeepLedgerConnected;

  /// Message while the Ledger request is being cancelled.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open while the Ledger request is cancelled.'**
  String get ledgerSigningKeepOpenWhileCancelling;

  /// Reminder not to close Vizor while a Ledger operation finishes.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open.'**
  String get ledgerSigningKeepVizorOpen;

  /// Status chip reminding the user not to close Vizor while the transaction finishes.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open'**
  String get ledgerSigningKeepVizorOpenShort;

  /// Body while Vizor prepares a transaction.
  ///
  /// In en, this message translates to:
  /// **'Please wait while Vizor prepares your transaction.'**
  String get ledgerSigningMsgPreparing;

  /// [security] Body asking the user to review and approve on the Ledger when prompted.
  ///
  /// In en, this message translates to:
  /// **'Review and approve when prompted on your Ledger.'**
  String get ledgerSigningMsgReviewing;

  /// Body during Ledger signing. {wait} is the sentence 'Ledger is preparing to sign. It may seem unresponsive for a few seconds.' translated separately.
  ///
  /// In en, this message translates to:
  /// **'{wait} Keep your Ledger connected.'**
  String ledgerSigningMsgSending(String wait);

  /// Step message in the Ledger signing dialog while the signed transaction is stored.
  ///
  /// In en, this message translates to:
  /// **'Saving the signed transaction.'**
  String get ledgerSigningSaving;

  /// Status chip while Vizor checks the device.
  ///
  /// In en, this message translates to:
  /// **'Checking device'**
  String get ledgerSigningStatusCheckingDevice;

  /// Status chip while the Zcash app opens on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Opening Zcash'**
  String get ledgerSigningStatusOpeningZcash;

  /// Short status chip while the Ledger prepares to sign.
  ///
  /// In en, this message translates to:
  /// **'Preparing to sign'**
  String get ledgerSigningStatusPreparing;

  /// [security] Short status chip asking the user to review on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Review on device'**
  String get ledgerSigningStatusReview;

  /// [security] Mobile status chip while waiting for the user to approve on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your approval'**
  String get ledgerSigningStatusWaitingApproval;

  /// Third step label of the Ledger signing procedure.
  ///
  /// In en, this message translates to:
  /// **'Finish transaction'**
  String get ledgerSigningStepFinish;

  /// First step label of the Ledger signing procedure.
  ///
  /// In en, this message translates to:
  /// **'Prepare transaction'**
  String get ledgerSigningStepPrepare;

  /// [security] Second step label of the Ledger signing procedure: review and approve on the device.
  ///
  /// In en, this message translates to:
  /// **'Review on Ledger'**
  String get ledgerSigningStepReview;

  /// [security] Mobile title asking the user to confirm the transaction on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Confirm on your Ledger'**
  String get ledgerSigningTitleConfirmOnLedger;

  /// Title while Vizor finishes a signed transaction.
  ///
  /// In en, this message translates to:
  /// **'Finishing transaction'**
  String get ledgerSigningTitleFinishing;

  /// Title while Vizor prepares a transaction for Ledger signing.
  ///
  /// In en, this message translates to:
  /// **'Preparing transaction'**
  String get ledgerSigningTitlePreparing;

  /// [security] Title asking the user to review and approve the transaction on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Check your Ledger'**
  String get ledgerSigningTitleReviewing;

  /// Title while the Ledger processes the signing request.
  ///
  /// In en, this message translates to:
  /// **'Processing with Ledger'**
  String get ledgerSigningTitleSending;

  /// Title of the Ledger dialog while the signed transaction is broadcast.
  ///
  /// In en, this message translates to:
  /// **'Sending transaction'**
  String get ledgerSigningTitleSendingTx;

  /// Title of the Ledger signing dialog.
  ///
  /// In en, this message translates to:
  /// **'Sign transaction'**
  String get ledgerSigningTitleSign;

  /// Shows which transaction of a batch is being signed on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Transaction {current} of {total}'**
  String ledgerSigningTransactionProgress(String current, String total);

  /// Explains that the Ledger may look frozen for a few seconds while preparing to sign.
  ///
  /// In en, this message translates to:
  /// **'Ledger is preparing to sign. It may seem unresponsive for a few seconds.'**
  String get ledgerSigningWaitInstruction;

  /// Status while the user must act on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Follow the prompts on your Ledger'**
  String get ledgerStatusFollowPrompts;

  /// Status while opening the system Bluetooth settings.
  ///
  /// In en, this message translates to:
  /// **'Opening Bluetooth settings…'**
  String get ledgerStatusOpeningBluetoothSettings;

  /// Status while the Ledger connection is stored.
  ///
  /// In en, this message translates to:
  /// **'Saving connection…'**
  String get ledgerStatusSavingConnection;

  /// Status while searching for Ledger devices.
  ///
  /// In en, this message translates to:
  /// **'Searching nearby…'**
  String get ledgerStatusSearchingNearby;

  /// Status while the search continues.
  ///
  /// In en, this message translates to:
  /// **'Still searching nearby…'**
  String get ledgerStatusStillSearching;

  /// [security] Procedure step label: the user approves sharing the viewing key on the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'Approve viewing key'**
  String get ledgerStepApproveViewingKey;

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

  /// Error shown in the mobile Ledger connection help when stopping the Bluetooth search failed.
  ///
  /// In en, this message translates to:
  /// **'Could not stop the search. Try opening connection help again.'**
  String get ledgerStopSearchFailedHelp;

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

  /// Title while connecting to the saved Ledger.
  ///
  /// In en, this message translates to:
  /// **'Connecting to your Ledger'**
  String get ledgerTitleConnectingToLedger;

  /// Title while Vizor searches for the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Finding your Ledger'**
  String get ledgerTitleFindingLedger;

  /// Title when the Ledger is connected.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger is connected'**
  String get ledgerTitleLedgerConnected;

  /// Title after the Ledger connection was stored.
  ///
  /// In en, this message translates to:
  /// **'Ledger saved'**
  String get ledgerTitleLedgerSaved;

  /// [security] Title when the connected Ledger does not hold the account.
  ///
  /// In en, this message translates to:
  /// **'This Ledger doesn’t match'**
  String get ledgerTitleMismatch;

  /// Title asking the user to pair the Ledger again.
  ///
  /// In en, this message translates to:
  /// **'Pair your Ledger again'**
  String get ledgerTitlePairAgain;

  /// Title while the Ledger connection is stored.
  ///
  /// In en, this message translates to:
  /// **'Saving your connection'**
  String get ledgerTitleSavingConnection;

  /// Title above the list of found Ledger devices.
  ///
  /// In en, this message translates to:
  /// **'Select your Ledger'**
  String get ledgerTitleSelectYourLedger;

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

  /// Instruction above the mobile device list while no device has been found yet.
  ///
  /// In en, this message translates to:
  /// **'Unlock Ledger, turn on Bluetooth, and keep it nearby.'**
  String get ledgerUnlockBluetoothNearby;

  /// Message while searching for Ledger devices over Bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Unlock Ledger, enable Bluetooth and keep it nearby.'**
  String get ledgerUnlockEnableBluetoothNearby;

  /// [security] Message while verifying the saved Ledger.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Ledger and open the Zcash app. Approve opening it if prompted.'**
  String get ledgerUnlockOpenZcashApprove;

  /// [security] Step 1 of the Ledger preparation list (the number is added by the app); the user unlocks the Ledger with its PIN.
  ///
  /// In en, this message translates to:
  /// **'Unlock with your PIN.'**
  String get ledgerUnlockWithPin;

  /// [security] Message asking the user to approve opening the Zcash app on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Approve opening the Zcash app on your Ledger.'**
  String get ledgerUsbApproveOpening;

  /// Fallback message for a USB connection problem.
  ///
  /// In en, this message translates to:
  /// **'Check the USB cable, unlock your Ledger, and open the Zcash app.'**
  String get ledgerUsbCheckCableOpenApp;

  /// Instruction for connecting over USB.
  ///
  /// In en, this message translates to:
  /// **'Connect your Ledger with a USB cable, unlock it, and open the Zcash app.'**
  String get ledgerUsbConnectUnlockOpen;

  /// Identity chip showing the Ledger is connected over USB.
  ///
  /// In en, this message translates to:
  /// **'USB connection'**
  String get ledgerUsbConnection;

  /// USB error when another app may be holding the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Vizor found your Ledger but could not open it. Close other wallet apps that use the Ledger, reconnect it, then try again.'**
  String get ledgerUsbCouldNotOpen;

  /// USB error when the USB stack failed to start.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not start USB access for your Ledger. Reconnect the device, then try again.'**
  String get ledgerUsbCouldNotStart;

  /// USB error after the connection dropped. {instruction} is a full sentence produced elsewhere, such as 'Open the Zcash app on your Ledger.'.
  ///
  /// In en, this message translates to:
  /// **'The USB connection to your Ledger was interrupted. Reconnect and unlock your Ledger. {instruction}'**
  String ledgerUsbInterrupted(String instruction);

  /// Linux USB permission error. Keep the URL github.com/LedgerHQ/udev-rules unchanged.
  ///
  /// In en, this message translates to:
  /// **'Vizor cannot access your Ledger over USB. Install Ledger\'s udev rules for Linux (github.com/LedgerHQ/udev-rules), then reconnect your Ledger and try again.'**
  String get ledgerUsbPermissionLinux;

  /// USB permission error on macOS and Windows.
  ///
  /// In en, this message translates to:
  /// **'Vizor cannot access your Ledger over USB. Check USB device permissions, then reconnect and try again.'**
  String get ledgerUsbPermissionOther;

  /// [security] Message while verifying a new Ledger: the user approves sharing the viewing key on the device.
  ///
  /// In en, this message translates to:
  /// **'Complete pairing if prompted, then approve sharing your viewing key.'**
  String get ledgerVerifyingNewDevice;

  /// [security] Message while verifying the saved Ledger.
  ///
  /// In en, this message translates to:
  /// **'Unlock Ledger and confirm opening Zcash if prompted.'**
  String get ledgerVerifyingSavedDevice;

  /// Status message while Vizor checks whether the Zcash app is open on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Vizor is checking the Zcash app.'**
  String get ledgerVizorCheckingZcash;

  /// [security] Status while waiting for the user to approve on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval…'**
  String get ledgerWaitingForApproval;

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

  /// Top bar title of the passcode entry screen while sync runs, with the percentage complete.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Syncing...'**
  String lockNavSyncing(int percent);

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

  /// Approximate time left before the next migration step, without 'in' (shown as a value, e.g. in a status row).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{~1 minute} other{~{count} minutes}}'**
  String migrationAboutMinutes(int count);

  /// Rotating status message while the private migration plan is being computed.
  ///
  /// In en, this message translates to:
  /// **'Analyzing your balance...'**
  String get migrationAnalyzingBalance;

  /// Caption under the analysis animation, split over two lines.
  ///
  /// In en, this message translates to:
  /// **'Vizor is working hard to find a perfect balance\nof safety, privacy, and speed for your migration'**
  String get migrationAnalyzingCaption;

  /// Rotating status message while the private migration plan is being computed.
  ///
  /// In en, this message translates to:
  /// **'Finding private batches...'**
  String get migrationAnalyzingFindingBatches;

  /// Rotating status message while the private migration plan is being computed.
  ///
  /// In en, this message translates to:
  /// **'Preparing your migration plan...'**
  String get migrationAnalyzingPreparingPlan;

  /// Screen-reader label of the progress ring shown while the private migration plan is computed.
  ///
  /// In en, this message translates to:
  /// **'Preparing private migration plan'**
  String get migrationAnalyzingSemanticsLabel;

  /// Body of the announcement modal about the new Ironwood pool, split over three lines.
  ///
  /// In en, this message translates to:
  /// **'Ironwood is the latest Zcash shielded pool.\nIt\'s the first formally verified pool with\ncutting edge cryptography.'**
  String get migrationAnnouncementBody;

  /// Button in the announcement modal that opens the official release note.
  ///
  /// In en, this message translates to:
  /// **'Official Release Note'**
  String get migrationAnnouncementReleaseNote;

  /// Button in the announcement modal that starts the migration.
  ///
  /// In en, this message translates to:
  /// **'Start Migration'**
  String get migrationAnnouncementStart;

  /// Back-link label that returns to the migration introduction.
  ///
  /// In en, this message translates to:
  /// **'About Migration'**
  String get migrationBackAbout;

  /// Button that returns to the home screen from a migration screen.
  ///
  /// In en, this message translates to:
  /// **'Back home'**
  String get migrationBackHome;

  /// Back-link label that returns to the "How the Migration Works" screen.
  ///
  /// In en, this message translates to:
  /// **'How Migration Works'**
  String get migrationBackHowItWorks;

  /// Back-link label that returns to the list of migration options.
  ///
  /// In en, this message translates to:
  /// **'Migration Options'**
  String get migrationBackOptions;

  /// Status of the current migration batch while it is being sent to the network.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting...'**
  String get migrationBatchBroadcasting;

  /// Title of the card above the sign button: batch number and how many notes it contains.
  ///
  /// In en, this message translates to:
  /// **'Batch #{number} ({count} notes)'**
  String migrationBatchCardTitle(String number, String count);

  /// Status of the current migration batch while it waits for confirmations.
  ///
  /// In en, this message translates to:
  /// **'Confirming...'**
  String get migrationBatchConfirming;

  /// Estimated arrival of a migration batch, given as the block height at which it is sent.
  ///
  /// In en, this message translates to:
  /// **'Block {height}'**
  String migrationBlockHeight(String height);

  /// Approximate wait expressed as a number of blocks.
  ///
  /// In en, this message translates to:
  /// **'~{blocks} blocks'**
  String migrationBlocksEstimate(String blocks);

  /// Approximate time until a scheduled migration transfer is sent, in hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{~in 1 hr} other{~in {count} hrs}}'**
  String migrationBroadcastApproxInHours(int count);

  /// Approximate time until a scheduled migration transfer is sent, in minutes.
  ///
  /// In en, this message translates to:
  /// **'~in {count} min'**
  String migrationBroadcastApproxInMinutes(int count);

  /// Status of a scheduled migration transfer that the network confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get migrationBroadcastConfirmed;

  /// Status of a scheduled migration transfer whose send time has arrived.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get migrationBroadcastDueNow;

  /// When a scheduled migration transfer will be sent, in hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{in 1 hr} other{in {count} hrs}}'**
  String migrationBroadcastInHours(int count);

  /// When a scheduled migration transfer will be sent, in minutes.
  ///
  /// In en, this message translates to:
  /// **'in {count} min'**
  String migrationBroadcastInMinutes(int count);

  /// Status of a migration transfer that was sent to the network.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get migrationBroadcastSubmitted;

  /// Screen-reader label for the carousel of tips shown during migration preparation.
  ///
  /// In en, this message translates to:
  /// **'Migration preparation information'**
  String get migrationCarouselPreparationLabel;

  /// Screen-reader label for the carousel of tips shown during migration.
  ///
  /// In en, this message translates to:
  /// **'Migration information'**
  String get migrationCarouselProgressLabel;

  /// Body text of the migration-complete screen, split over two lines.
  ///
  /// In en, this message translates to:
  /// **'Migration completed successfully and you can\nspend your funds as usual.'**
  String get migrationCompleteBody;

  /// Headline of the migration-complete screen, split over three lines; {amount} is the migrated ZEC amount.
  ///
  /// In en, this message translates to:
  /// **'Your\n{amount} ZEC\nare on Ironwood!'**
  String migrationCompleteTitle(String amount);

  /// Button that continues the migration with its next step.
  ///
  /// In en, this message translates to:
  /// **'Continue migration'**
  String get migrationContinueMigration;

  /// Label of the action button while the migration is continuing.
  ///
  /// In en, this message translates to:
  /// **'Continuing...'**
  String get migrationContinuing;

  /// Label of the home call-to-action that starts the Ironwood migration.
  ///
  /// In en, this message translates to:
  /// **'Migrate to Ironwood Pool'**
  String get migrationCtaStart;

  /// Label on the legacy migration card for the batch currently being processed.
  ///
  /// In en, this message translates to:
  /// **'Current Batch'**
  String get migrationCurrentBatch;

  /// Approximate duration in days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{~1 day} other{~{count} days}}'**
  String migrationDurationDays(int count);

  /// Approximate duration of a whole number of hours plus a half hour, for example "~2.5 hrs".
  ///
  /// In en, this message translates to:
  /// **'~{hours}.5 hrs'**
  String migrationDurationHalfHours(String hours);

  /// Approximate duration in hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{~1 hr} other{~{count} hrs}}'**
  String migrationDurationHours(int count);

  /// Approximate duration in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{~1 min} other{~{count} mins}}'**
  String migrationDurationMinutes(int count);

  /// Error shown when sending a migration transaction to the network failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t broadcast the migration transaction. Try again.'**
  String get migrationErrorBroadcast;

  /// Error shown when continuing the migration failed for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t continue migration. Try again.'**
  String get migrationErrorContinue;

  /// [security] Error shown when the transaction could not be prepared for signing on Keystone.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t prepare Keystone signing.'**
  String get migrationErrorKeystonePrepare;

  /// Error shown when a Ledger account tries the private migration, which needs batched signing the Ledger flow does not support.
  ///
  /// In en, this message translates to:
  /// **'Ledger private migration is excluded because the current flow requires batched signing.'**
  String get migrationErrorLedgerExcluded;

  /// Error shown when the migration amount or fee changed after the user reviewed the plan.
  ///
  /// In en, this message translates to:
  /// **'The amount or fee changed. Review the updated details.'**
  String get migrationErrorPlanChanged;

  /// Error shown when starting the migration failed for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start migration. Try again.'**
  String get migrationErrorStart;

  /// [security] Error shown when migration cannot continue because the wallet is locked.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor before continuing migration.'**
  String get migrationErrorUnlockBeforeContinue;

  /// [security] Error shown when migration cannot start because the wallet is locked.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor before starting migration.'**
  String get migrationErrorUnlockBeforeStart;

  /// Error shown when a migration action needs the wallet to finish syncing first.
  ///
  /// In en, this message translates to:
  /// **'Wait for sync to finish, then try again.'**
  String get migrationErrorWaitForSync;

  /// Estimated completion shown while migration is waiting for the user to sign.
  ///
  /// In en, this message translates to:
  /// **'After signing'**
  String get migrationEstimateAfterSigning;

  /// Estimated completion shown when no preparation transactions remain.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get migrationEstimateComplete;

  /// Estimated completion phrased as a sentence; {estimate} is an approximate duration such as "~5 mins".
  ///
  /// In en, this message translates to:
  /// **'in {estimate}'**
  String migrationEstimateIn(String estimate);

  /// Estimated time until the migration completes, in days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{in ~1 day} other{in ~{count} days}}'**
  String migrationEstimateInDays(int count);

  /// Estimated time until the migration completes; {hours} is a number such as "2" or "2.5".
  ///
  /// In en, this message translates to:
  /// **'in ~{hours} hours'**
  String migrationEstimateInHours(String hours);

  /// Estimated time until the migration completes, in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{in ~1 minute} other{in ~{count} minutes}}'**
  String migrationEstimateInMinutes(int count);

  /// Estimated time until the migration completes: about one hour.
  ///
  /// In en, this message translates to:
  /// **'in ~1 hour'**
  String get migrationEstimateInOneHour;

  /// Label on the legacy migration card for when the batch is expected to arrive.
  ///
  /// In en, this message translates to:
  /// **'Estimated arrival time'**
  String get migrationEstimatedArrivalTime;

  /// [security] Explains that the computer must stay unlocked with Vizor running so the next migration transaction can be sent.
  ///
  /// In en, this message translates to:
  /// **'Your computer needs to be unlocked with Vizor running so we can send the next migration transaction'**
  String get migrationExpectKeepRunningBody;

  /// Explains that the duration depends on the migrated amount.
  ///
  /// In en, this message translates to:
  /// **'Ironwood migrations can take anywhere from several hours up to a couple days depending on your migration amount.'**
  String get migrationExpectLongBody;

  /// Heading of a "what to expect" item about the migration duration.
  ///
  /// In en, this message translates to:
  /// **'Migrations can take a long time'**
  String get migrationExpectLongTitle;

  /// Explains that confirmed Ironwood amounts are spendable while the migration continues.
  ///
  /// In en, this message translates to:
  /// **'Each confirmed Ironwood amount is available to spend while the rest of the migration continues.'**
  String get migrationExpectSpendBody;

  /// Heading of a "what to expect" item about spending migrated funds early.
  ///
  /// In en, this message translates to:
  /// **'You can spend as funds arrive'**
  String get migrationExpectSpendTitle;

  /// Title of the screen that lists what to expect during the migration.
  ///
  /// In en, this message translates to:
  /// **'What to expect'**
  String get migrationExpectTitle;

  /// Recommends running the migration behind a trustworthy VPN or network privacy layer.
  ///
  /// In en, this message translates to:
  /// **'It’s recommended to run the migration behind a trustable VPN/network privacy layer'**
  String get migrationExpectVpnBody;

  /// Heading of a "what to expect" item recommending a VPN.
  ///
  /// In en, this message translates to:
  /// **'Use VPN for an extra privacy'**
  String get migrationExpectVpnTitle;

  /// Title of the Ironwood migration screens.
  ///
  /// In en, this message translates to:
  /// **'Ironwood Migration'**
  String get migrationFlowTitle;

  /// Explains that parts are sent slowly at staggered times to make tracing harder.
  ///
  /// In en, this message translates to:
  /// **'Vizor slowly sends parts at staggered intervals across multiple batches to reduce traceability.'**
  String get migrationHowDelayedBody;

  /// Heading of the third step of "How the Migration Works".
  ///
  /// In en, this message translates to:
  /// **'Delayed and randomized migrations'**
  String get migrationHowDelayedTitle;

  /// Explains that a one-time migration is needed to spend the Orchard balance.
  ///
  /// In en, this message translates to:
  /// **'A one-time migration to Ironwood is required to spend your existing shielded balance.'**
  String get migrationHowFrozenBody;

  /// Heading of the first step of "How the Migration Works".
  ///
  /// In en, this message translates to:
  /// **'Orchard (legacy shielded) balance is frozen'**
  String get migrationHowFrozenTitle;

  /// Explains that the balance is split into smaller standard notes before migrating.
  ///
  /// In en, this message translates to:
  /// **'Vizor splits your total balance into many smaller notes (e.g. 0.1 ZEC / 1 ZEC / 5 ZEC) before migrating.'**
  String get migrationHowPreparationBody;

  /// Heading of the second step of "How the Migration Works".
  ///
  /// In en, this message translates to:
  /// **'Pre-migration preparations'**
  String get migrationHowPreparationTitle;

  /// Small label on a card of the "How the Migration Works" carousel.
  ///
  /// In en, this message translates to:
  /// **'Step {number}'**
  String migrationHowStepLabel(String number);

  /// Screen-reader label of the current card of the migration steps carousel.
  ///
  /// In en, this message translates to:
  /// **'Migration step {number} of {total}. {title}. {body}'**
  String migrationHowStepSemanticsCurrent(
    String number,
    String total,
    String title,
    String body,
  );

  /// Screen-reader label of a button that shows another card of the migration steps carousel.
  ///
  /// In en, this message translates to:
  /// **'Show migration step {number} of {total}'**
  String migrationHowStepSemanticsShow(String number, String total);

  /// Title of the "How the Migration Works" screen.
  ///
  /// In en, this message translates to:
  /// **'How the Migration Works'**
  String get migrationHowTitle;

  /// [security] Button that authorises the one-step migration despite its privacy trade-off.
  ///
  /// In en, this message translates to:
  /// **'Authorise anyway'**
  String get migrationImmediateAuthoriseAnyway;

  /// [security] Label of the confirm button while the one-step migration is being authorised.
  ///
  /// In en, this message translates to:
  /// **'Authorising…'**
  String get migrationImmediateAuthorising;

  /// [security] Screen-reader label of the spinner shown while the one-step migration is being authorised.
  ///
  /// In en, this message translates to:
  /// **'Authorising migration'**
  String get migrationImmediateAuthorisingSemantics;

  /// Button on the one-step migration review that goes back to the list of migration options.
  ///
  /// In en, this message translates to:
  /// **'Consider another option'**
  String get migrationImmediateConsiderOther;

  /// Row label for the estimated network fee of the one-step migration.
  ///
  /// In en, this message translates to:
  /// **'Fees (estimate)'**
  String get migrationImmediateFees;

  /// Message shown when there is no spendable Orchard balance to move with the one-step migration.
  ///
  /// In en, this message translates to:
  /// **'No spendable Orchard balance is available for Immediate migration.'**
  String get migrationImmediateNoBalance;

  /// Error shown when the plan for the one-step ("Immediate") migration could not be calculated.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t calculate the Immediate migration plan. Sync and try again.'**
  String get migrationImmediatePlanFailed;

  /// Button that recalculates the one-step migration plan after a failure.
  ///
  /// In en, this message translates to:
  /// **'Retry calculation'**
  String get migrationImmediateRetryCalculation;

  /// Title of the review screen for the one-step ("Immediate") migration.
  ///
  /// In en, this message translates to:
  /// **'Review Migration Plan'**
  String get migrationImmediateReviewTitle;

  /// [security] Sentence of the privacy notice for the one-step migration. {amount} is the ZEC amount; {highlight} is the emphasized phrase 'easier to associate with your wallet' and can be moved anywhere in the sentence.
  ///
  /// In en, this message translates to:
  /// **'Crosses in one visible step — your {amount} and timing are {highlight}.'**
  String migrationImmediateTradeoffBody(String amount, String highlight);

  /// [security] Emphasized phrase inserted into the privacy notice sentence as its highlight; it completes 'your amount and timing are …'.
  ///
  /// In en, this message translates to:
  /// **'easier to associate with your wallet'**
  String get migrationImmediateTradeoffHighlight;

  /// [security] Last line of the privacy notice for Ledger accounts; starts with a line break.
  ///
  /// In en, this message translates to:
  /// **'\nPrivate migration is not available for Ledger accounts.'**
  String get migrationImmediateTradeoffLedger;

  /// [security] Last line of the privacy notice suggesting the private migration; starts with a line break.
  ///
  /// In en, this message translates to:
  /// **'\nConsider choosing a Private Migration option.'**
  String get migrationImmediateTradeoffPrivate;

  /// [security] Heading of the notice that the one-step migration is less private.
  ///
  /// In en, this message translates to:
  /// **'Privacy trade-off'**
  String get migrationImmediateTradeoffTitle;

  /// Placeholder shown for the amount, fee or button when the Immediate migration plan is not available.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get migrationImmediateUnavailable;

  /// Approximate time until the next migration step, in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{~in 1 minute} other{~in {count} minutes}}'**
  String migrationInMinutes(int count);

  /// Button on the migration introduction screen that opens the official announcement.
  ///
  /// In en, this message translates to:
  /// **'Official Announcement'**
  String get migrationIntroAnnouncement;

  /// Badge on the migration introduction screen naming the network upgrade.
  ///
  /// In en, this message translates to:
  /// **'Zcash Network Upgrade'**
  String get migrationIntroBadge;

  /// Body of the migration introduction screen; {amount} is the ZEC amount still in the Orchard pool. The first sentence ends with a line break.
  ///
  /// In en, this message translates to:
  /// **'Your {amount} ZEC is currently in Orchard.\nTo keep using these funds for shielded payments, you will need to move them to Ironwood. You will review the migration plan before any funds move.'**
  String migrationIntroBody(String amount);

  /// Tagline on the migration introduction screen.
  ///
  /// In en, this message translates to:
  /// **'A new shielded pool for Zcash.'**
  String get migrationIntroTagline;

  /// [security] Status while the Keystone signature is being applied.
  ///
  /// In en, this message translates to:
  /// **'Applying the Keystone signature.'**
  String get migrationKeystoneApplyingSignature;

  /// [security] Status while the signature is being applied to the migration plan.
  ///
  /// In en, this message translates to:
  /// **'Applying the Keystone signature to your migration plan.'**
  String get migrationKeystoneApplyingToPlan;

  /// Button that leaves Keystone signing and returns to the migration review.
  ///
  /// In en, this message translates to:
  /// **'Back to review'**
  String get migrationKeystoneBackToReview;

  /// Button that leaves Keystone signing and returns to the migration status.
  ///
  /// In en, this message translates to:
  /// **'Back to status'**
  String get migrationKeystoneBackToStatus;

  /// [security] Button that starts the Keystone signing rounds.
  ///
  /// In en, this message translates to:
  /// **'Begin signing'**
  String get migrationKeystoneBeginSigning;

  /// Shown when the camera is unavailable; asks for camera access to scan the signed QR.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access to scan the signed Keystone QR.'**
  String get migrationKeystoneCameraAccess;

  /// Shown when no camera is available; Keystone migration signing needs a camera to scan QR codes.
  ///
  /// In en, this message translates to:
  /// **'Keystone migration signing uses camera QR scanning only. Connect a camera and try again.'**
  String get migrationKeystoneCameraOnly;

  /// [security] Error shown when cancelling the Keystone signing request failed.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel the signing request. Try again.'**
  String get migrationKeystoneCancelFailed;

  /// Hint under the request QR.
  ///
  /// In en, this message translates to:
  /// **'Click QR to enlarge'**
  String get migrationKeystoneClickToEnlarge;

  /// [security] Title of the Keystone signing step that confirms the one-step migration.
  ///
  /// In en, this message translates to:
  /// **'Confirm Migration with Keystone'**
  String get migrationKeystoneConfirmTitle;

  /// Screen-reader label of the button that enlarges the request QR.
  ///
  /// In en, this message translates to:
  /// **'Enlarge Keystone request QR'**
  String get migrationKeystoneEnlargeQr;

  /// Screen-reader label of the enlarged Keystone request QR dialog.
  ///
  /// In en, this message translates to:
  /// **'Enlarged Keystone request QR'**
  String get migrationKeystoneEnlargedQr;

  /// [security] Error shown when the Keystone firmware is too old to sign Ironwood migrations.
  ///
  /// In en, this message translates to:
  /// **'Update Keystone firmware to sign Ironwood migrations, then try again.'**
  String get migrationKeystoneFirmwareUpdate;

  /// Title of the mobile Keystone migration screen.
  ///
  /// In en, this message translates to:
  /// **'Keystone migration'**
  String get migrationKeystoneMobileTitle;

  /// [security] Error shown when the active account is not a Keystone account.
  ///
  /// In en, this message translates to:
  /// **'Use a Keystone account to sign this migration.'**
  String get migrationKeystoneNotKeystone;

  /// [security] Error shown when the scanned QR is not the signed migration QR.
  ///
  /// In en, this message translates to:
  /// **'Open the signed migration QR on Keystone, then scan again.'**
  String get migrationKeystoneOpenSignedQr;

  /// [security] Explains that each signing round shows one animated request QR and reads one signed response QR.
  ///
  /// In en, this message translates to:
  /// **'Each round uses one animated request QR and one signed response QR.'**
  String get migrationKeystonePlanBody;

  /// [security] Heading of the screen that previews how many QR rounds Keystone signing needs.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing plan'**
  String get migrationKeystonePlanTitle;

  /// [security] Error shown when the Keystone signing request could not be prepared.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared. Try again.'**
  String get migrationKeystonePrepareFailed;

  /// Disabled button label while QR codes are prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing QR codes...'**
  String get migrationKeystonePreparingQr;

  /// [security] Error shown when local proof preparation failed.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not prepare local proofs. Go back and prepare this request again.'**
  String get migrationKeystoneProofFailed;

  /// [security] Message after the signature was captured while proofs are being prepared; asks the user to keep the screen open.
  ///
  /// In en, this message translates to:
  /// **'Signature captured. Vizor is still preparing local proofs. Keep this screen open.'**
  String get migrationKeystoneProofWaiting;

  /// [security] Message after the signature was captured while proofs are being prepared; asks the user to keep the screen open.
  ///
  /// In en, this message translates to:
  /// **'Signature captured. Vizor is still preparing local proofs ({ready}/{total}). Keep this screen open.'**
  String migrationKeystoneProofWaitingProgress(String ready, String total);

  /// Status while the wallet prepares zero-knowledge proofs on this device.
  ///
  /// In en, this message translates to:
  /// **'Preparing local proofs'**
  String get migrationKeystoneProofsPreparing;

  /// Label shown while the signed QR is decoded and local proofs are being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing local proofs...'**
  String get migrationKeystoneProofsPreparingEllipsis;

  /// Progress while the wallet prepares proofs on this device; {ready} of {total} are done.
  ///
  /// In en, this message translates to:
  /// **'Preparing local proofs {ready}/{total}'**
  String migrationKeystoneProofsProgress(String ready, String total);

  /// [security] Instruction under the request QR: Keystone signs the preparation transactions and migration batches together.
  ///
  /// In en, this message translates to:
  /// **'Scan this request with Keystone to sign the preparation transactions and migration batches together.'**
  String get migrationKeystoneQrBodyCombined;

  /// [security] Instruction under the request QR: scan it with Keystone to confirm the migration.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code with your Keystone wallet to confirm migration.'**
  String get migrationKeystoneQrBodyImmediate;

  /// [security] Instruction under the request QR: after signing, Keystone shows a new signed QR code.
  ///
  /// In en, this message translates to:
  /// **'Scan this request QR with Keystone. Keystone will show a new signed QR when it finishes.'**
  String get migrationKeystoneQrBodyRound;

  /// [security] Error shown after the Keystone signing request was cancelled.
  ///
  /// In en, this message translates to:
  /// **'This signing request was cancelled. Prepare it again.'**
  String get migrationKeystoneRequestCancelled;

  /// [security] Error shown when the Keystone signing request expired.
  ///
  /// In en, this message translates to:
  /// **'This Keystone signing request expired. Prepare it again.'**
  String get migrationKeystoneRequestExpired;

  /// Toolbar label while the request QR code for Keystone is shown.
  ///
  /// In en, this message translates to:
  /// **'Request QR'**
  String get migrationKeystoneRequestQr;

  /// [security] Error: the Keystone signing request is no longer valid and must be prepared again.
  ///
  /// In en, this message translates to:
  /// **'This Keystone signing request can no longer be used. Prepare it again.'**
  String get migrationKeystoneRequestUnusable;

  /// Label showing which signing round (QR) is on screen, for example "Round 1 of 3".
  ///
  /// In en, this message translates to:
  /// **'Round {current} of {total}'**
  String migrationKeystoneRound(String current, String total);

  /// Summary of how many QR signing rounds Keystone needs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 QR signing round} other{{count} QR signing rounds}}'**
  String migrationKeystoneRoundCount(int count);

  /// [security] Help dialog text suggesting the user update the Keystone Cypherpunk firmware.
  ///
  /// In en, this message translates to:
  /// **'There may be a newer version of Keystone Cypherpunk firmware available. Check if you have the latest version.'**
  String get migrationKeystoneScanIssuesBody;

  /// Button that closes the Keystone scan help dialog.
  ///
  /// In en, this message translates to:
  /// **'Ok, I will check'**
  String get migrationKeystoneScanIssuesConfirm;

  /// [security] Heading of the help dialog shown when scanning the signed Keystone QR code keeps failing.
  ///
  /// In en, this message translates to:
  /// **'Having issues with scanning the QR code?'**
  String get migrationKeystoneScanIssuesTitle;

  /// [security] Instruction to scan the new signed QR code displayed by Keystone.
  ///
  /// In en, this message translates to:
  /// **'Scan the new signed QR shown on Keystone.'**
  String get migrationKeystoneScanNewQr;

  /// [security] Heading above the request QR asking the user to scan it with Keystone.
  ///
  /// In en, this message translates to:
  /// **'Scan request with Keystone'**
  String get migrationKeystoneScanRequest;

  /// [security] Heading and button for scanning the signed QR shown on Keystone.
  ///
  /// In en, this message translates to:
  /// **'Scan Keystone signature'**
  String get migrationKeystoneScanSignature;

  /// [security] Title of the Keystone signing step that signs one batch of Ironwood migration transfers.
  ///
  /// In en, this message translates to:
  /// **'Sign Ironwood batch'**
  String get migrationKeystoneSignBatch;

  /// [security] Title of the Keystone signing step that signs the whole migration.
  ///
  /// In en, this message translates to:
  /// **'Sign migration'**
  String get migrationKeystoneSignMigration;

  /// [security] Title of the Keystone signing step that signs the note-splitting transactions.
  ///
  /// In en, this message translates to:
  /// **'Sign private split'**
  String get migrationKeystoneSignPrivateSplit;

  /// Label under the request QR: it signs all the listed transactions; {transactions} is a count such as "3 transactions".
  ///
  /// In en, this message translates to:
  /// **'Signs {transactions}'**
  String migrationKeystoneSignsAll(String transactions);

  /// Label under the request QR: it signs {count} of the total transactions; {transactions} is the total such as "7 transactions".
  ///
  /// In en, this message translates to:
  /// **'Signs {count} of {transactions}'**
  String migrationKeystoneSignsSome(String count, String transactions);

  /// Back-link label that returns to the migration review screen from Keystone signing.
  ///
  /// In en, this message translates to:
  /// **'Review migration'**
  String get migrationKeystoneToolbarReview;

  /// Back-link label that returns to the migration status screen from Keystone signing.
  ///
  /// In en, this message translates to:
  /// **'Migration status'**
  String get migrationKeystoneToolbarStatus;

  /// Summary of how many transactions Keystone signs in total.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction total} other{{count} transactions total}}'**
  String migrationKeystoneTransactionTotal(int count);

  /// Number of transactions, used inside the signing summary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction} other{{count} transactions}}'**
  String migrationKeystoneTransactions(int count);

  /// Message shown when Keystone signing is unavailable until sync finishes.
  ///
  /// In en, this message translates to:
  /// **'Try again after sync finishes.'**
  String get migrationKeystoneTryAfterSync;

  /// Heading shown when Keystone signing cannot be started.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing unavailable'**
  String get migrationKeystoneUnavailableTitle;

  /// [security] Error shown when the wallet is locked while signing the migration.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor before signing migration.'**
  String get migrationKeystoneUnlockFirst;

  /// [security] Status after the signature was captured; Vizor continues once local proofs are ready.
  ///
  /// In en, this message translates to:
  /// **'Signature captured. Vizor will continue when local proofs are ready.'**
  String get migrationKeystoneWaitingForProofsLong;

  /// [security] Status after the Keystone signature was captured while proofs are still being prepared.
  ///
  /// In en, this message translates to:
  /// **'Signature captured. Waiting for local proofs.'**
  String get migrationKeystoneWaitingForProofsShort;

  /// [security] Error shown when the scanned signed QR belongs to a different signing round.
  ///
  /// In en, this message translates to:
  /// **'This signed QR is from another round. Go back, scan the current request with Keystone, then scan its new signed QR.'**
  String get migrationKeystoneWrongRound;

  /// Error shown when the signed migration transaction could not be sent to the network.
  ///
  /// In en, this message translates to:
  /// **'The migration transaction could not be broadcast.'**
  String get migrationLedgerBroadcast;

  /// [security] Error shown when the Ledger is not reachable; asks the user to connect, unlock and open the Zcash app.
  ///
  /// In en, this message translates to:
  /// **'Connect and unlock your Ledger, then open the Zcash app.'**
  String get migrationLedgerConnect;

  /// Error shown when the migration with a Ledger failed for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Ledger migration could not be completed.'**
  String get migrationLedgerFailed;

  /// Title of the Ledger signing dialog after the migration failed.
  ///
  /// In en, this message translates to:
  /// **'Ledger migration failed'**
  String get migrationLedgerFailedTitle;

  /// Error shown when the migration amount or fee changed while the Ledger was signing.
  ///
  /// In en, this message translates to:
  /// **'The amount or fee changed. Return and review the updated plan.'**
  String get migrationLedgerPlanChanged;

  /// Error shown when the local proofs for the Ledger migration could not be prepared.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not finish preparing migration proofs.'**
  String get migrationLedgerProofs;

  /// [security] Error shown when the user rejected the migration transaction on the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'The migration transaction was rejected on your Ledger.'**
  String get migrationLedgerRejected;

  /// Title of the mobile screen where the migration is signed with a Ledger.
  ///
  /// In en, this message translates to:
  /// **'Migrate with Ledger'**
  String get migrationLedgerTitle;

  /// Line on the legacy migration screen; {amount} is a ZEC amount, possibly starting with "~".
  ///
  /// In en, this message translates to:
  /// **'Left to transfer: {amount}'**
  String migrationLeftToTransfer(String amount);

  /// Label of the confirm button while the migration is being cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelling...'**
  String get migrationManageCancelling;

  /// Error in the Manage Migration dialog when the migration is past the point where it can be stopped.
  ///
  /// In en, this message translates to:
  /// **'This migration can no longer be cancelled.'**
  String get migrationManageCannotCancel;

  /// Confirm button of the Manage Migration dialogs.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get migrationManageConfirm;

  /// [security] Warning bullet: switching to Immediate slightly reduces privacy.
  ///
  /// In en, this message translates to:
  /// **'Remaining split notes will be processed as an immediate migration, slightly increasing traceability'**
  String get migrationManageImmediateBullet1;

  /// [security] Warning bullet: transactions that were already sent stay as they are.
  ///
  /// In en, this message translates to:
  /// **'Transactions already broadcast will not be reverted'**
  String get migrationManageImmediateBullet2;

  /// [security] Warning bullet: an Immediate migration is irreversible.
  ///
  /// In en, this message translates to:
  /// **'There’s no way to revert an immediate migration'**
  String get migrationManageImmediateBullet3;

  /// [security] Intro line of the dialog that switches the remaining migration to Immediate.
  ///
  /// In en, this message translates to:
  /// **'Process the remaining migration immediately.'**
  String get migrationManageImmediateIntro;

  /// Error in the Manage Migration dialog when nothing is left to migrate.
  ///
  /// In en, this message translates to:
  /// **'There is no remaining Orchard balance to migrate.'**
  String get migrationManageNoBalance;

  /// Option for cancelling the remaining scheduled migration transactions.
  ///
  /// In en, this message translates to:
  /// **'Stop Migration'**
  String get migrationManageStop;

  /// [security] Explains that stopping cancels the remaining scheduled transactions and that migration can be restarted from the home screen.
  ///
  /// In en, this message translates to:
  /// **'This cancels the remaining scheduled migration transactions. You can re-start the migration from the home page.'**
  String get migrationManageStopBody;

  /// [security] Title of the dialog that confirms stopping the migration.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to stop?'**
  String get migrationManageStopTitle;

  /// Label of the confirm button while the switch to Immediate migration is being processed.
  ///
  /// In en, this message translates to:
  /// **'Stopping...'**
  String get migrationManageStopping;

  /// Option and title for finishing the remaining private migration as an Immediate (one-step) migration.
  ///
  /// In en, this message translates to:
  /// **'Switch to Immediate'**
  String get migrationManageSwitchImmediate;

  /// Title of the dialog for switching to Immediate migration or stopping the migration.
  ///
  /// In en, this message translates to:
  /// **'Manage Migration'**
  String get migrationManageTitle;

  /// Error in the Manage Migration dialog when changing the migration failed.
  ///
  /// In en, this message translates to:
  /// **'The migration could not be updated. Please try again.'**
  String get migrationManageUpdateFailed;

  /// Label of the signing summary row when every migration transaction is signed in one Keystone step.
  ///
  /// In en, this message translates to:
  /// **'All transactions'**
  String get migrationMobileActionAllTransactions;

  /// Label of the signing summary row naming the migration batch. {number} starts at 1.
  ///
  /// In en, this message translates to:
  /// **'Batch #{number}'**
  String migrationMobileActionBatch(int number);

  /// Screen reader label of the spinner on the migration action button.
  ///
  /// In en, this message translates to:
  /// **'Migration action in progress'**
  String get migrationMobileActionInProgress;

  /// Label of the signing summary row listing the migration transactions that need to be signed again.
  ///
  /// In en, this message translates to:
  /// **'Transactions needing signature'**
  String get migrationMobileActionNeedSignature;

  /// Action button that prepares the next migration batch. {number} starts at 1.
  ///
  /// In en, this message translates to:
  /// **'Prepare batch #{number}'**
  String migrationMobileActionPrepareBatch(int number);

  /// Label of the action button while the next migration batch is being prepared. {number} starts at 1.
  ///
  /// In en, this message translates to:
  /// **'Preparing batch #{number}...'**
  String migrationMobileActionPreparingBatch(int number);

  /// [security] Button label on the migration progress screen asking the user to sign the rebuilt migration transactions again on the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Re-sign migration transactions'**
  String get migrationMobileActionResign;

  /// [security] Button label on the migration progress screen asking the user to sign the migration transactions on the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Sign migration transactions'**
  String get migrationMobileActionSign;

  /// [security] Default label of the button that signs a migration batch. {number} starts at 1.
  ///
  /// In en, this message translates to:
  /// **'Sign batch #{number}'**
  String migrationMobileActionSignBatch(int number);

  /// Action button that submits a scheduled migration transaction whose time has passed.
  ///
  /// In en, this message translates to:
  /// **'Submit scheduled transaction'**
  String get migrationMobileActionSubmitScheduled;

  /// Label of the action button while the late scheduled transaction is being submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitting scheduled transaction...'**
  String get migrationMobileActionSubmittingScheduled;

  /// Body of the bottom sheet announcing the Ironwood pool; two paragraphs separated by a blank line. The apostrophe is a curly one.
  ///
  /// In en, this message translates to:
  /// **'Zcash’s latest shielded pool, bringing cutting-edge cryptography and formal verification.\n\nYour shielded balance needs a one-time migration to Ironwood.'**
  String get migrationMobileAnnouncementBody;

  /// Ghost button of the Ironwood announcement sheet that opens the official announcement in the browser.
  ///
  /// In en, this message translates to:
  /// **'Official announcement'**
  String get migrationMobileAnnouncementOfficial;

  /// Primary button of the Ironwood announcement sheet that starts the migration flow.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Ironwood'**
  String get migrationMobileAnnouncementUpgrade;

  /// Title of the Home sheet asking the user to continue the Ironwood migration.
  ///
  /// In en, this message translates to:
  /// **'Continue your migration'**
  String get migrationMobileAttentionContinueTitle;

  /// Title of the Home sheet saying a scheduled migration transaction is late and needs the user.
  ///
  /// In en, this message translates to:
  /// **'A migration transaction needs attention'**
  String get migrationMobileAttentionLateTitle;

  /// Ghost button of the Home sheet that dismisses it until later. The apostrophe is a curly one.
  ///
  /// In en, this message translates to:
  /// **'I’ll visit later'**
  String get migrationMobileAttentionLater;

  /// Primary button of the Home sheet that opens the migration screen.
  ///
  /// In en, this message translates to:
  /// **'Go to migration page'**
  String get migrationMobileAttentionOpen;

  /// Title of the Home sheet saying the next migration batch can be prepared.
  ///
  /// In en, this message translates to:
  /// **'Your next migration batch is ready'**
  String get migrationMobileAttentionProofTitle;

  /// Title of the Home sheet telling the user that migration notes wait for their signature. {count} is the number of notes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note is ready for your signature} other{{count} notes are ready for your signature}}'**
  String migrationMobileAttentionSignatureSheet(int count);

  /// Button on the migration progress screen that returns to Home.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get migrationMobileBackToHome;

  /// Text of the Home migration banner when a migration transaction is late.
  ///
  /// In en, this message translates to:
  /// **'Migration needs attention'**
  String get migrationMobileBannerLate;

  /// Text of the Home migration banner when the next batch is ready.
  ///
  /// In en, this message translates to:
  /// **'Next migration batch is ready'**
  String get migrationMobileBannerProof;

  /// Text of the Home migration banner showing the amount that is still migrating. {amount} is the formatted amount without the ZEC unit.
  ///
  /// In en, this message translates to:
  /// **'{amount} ZEC still migrating'**
  String migrationMobileBannerRemaining(String amount);

  /// Text of the Home migration banner when notes wait for a signature. {count} is the number of notes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note is ready for signing} other{{count} notes are ready for signing}}'**
  String migrationMobileBannerSignature(int count);

  /// Label inside the progress ring showing completed batches out of the total.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} Batch'**
  String migrationMobileBatchProgress(int completed, int total);

  /// First line on the mobile migration progress screens saying the user may leave the screen.
  ///
  /// In en, this message translates to:
  /// **'You can leave this screen.'**
  String get migrationMobileCanLeave;

  /// Body of the migration complete screen.
  ///
  /// In en, this message translates to:
  /// **'Migration went successfully and you can spend your funds as usual.'**
  String get migrationMobileCompleteBody;

  /// Large heading of the migration complete screen; line breaks are intentional. {amount} is the migrated amount with the ZEC unit.
  ///
  /// In en, this message translates to:
  /// **'Your\n{amount}\nare on Ironwood!'**
  String migrationMobileCompleteHeading(String amount);

  /// Top bar title of the screen shown when the migration completed. The apostrophe is curly.
  ///
  /// In en, this message translates to:
  /// **'You’re all set!'**
  String get migrationMobileCompleteTitle;

  /// Message on the migration progress screen when continuing the migration failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t continue this migration. Try again.'**
  String get migrationMobileContinueThisError;

  /// [security] Message on the migration progress screen when the saved migration credentials must be restored first.
  ///
  /// In en, this message translates to:
  /// **'Your migration credentials need to be restored before continuing.'**
  String get migrationMobileCredentialsRestore;

  /// Error under the Immediate migration review when the plan or fee could not be calculated.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t calculate the Immediate migration fee. Sync and try again.'**
  String get migrationMobileFastPlanError;

  /// Placeholder value of the amount and fee rows on the Immediate migration review when no plan could be made.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get migrationMobileFastPlanUnavailable;

  /// Last sentence of the privacy warning card suggesting the Private migration option.
  ///
  /// In en, this message translates to:
  /// **'Consider choosing a Private Migration option.'**
  String get migrationMobileFastPrivacyConsiderPrivate;

  /// Last sentence of the privacy warning card for Ledger accounts.
  ///
  /// In en, this message translates to:
  /// **'Private migration is not available for Ledger accounts.'**
  String get migrationMobileFastPrivacyLedger;

  /// Body of the success screen after the Immediate migration was broadcast. {amount} is the migrated amount with the ZEC unit, such as 1.50 ZEC.
  ///
  /// In en, this message translates to:
  /// **'{amount} is on its way to Ironwood.'**
  String migrationMobileFastSubmittedBody(String amount);

  /// Heading of the success screen after the Immediate migration was broadcast.
  ///
  /// In en, this message translates to:
  /// **'Migration submitted'**
  String get migrationMobileFastSubmittedTitle;

  /// Title-case top bar title of the mobile Immediate (fast) migration success screen.
  ///
  /// In en, this message translates to:
  /// **'Fast Migration'**
  String get migrationMobileFastTitle;

  /// Top bar title of the mobile screen that explains the migration steps.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get migrationMobileHowItWorksNavTitle;

  /// Body on the first mobile migration screen explaining that the user's funds must move from the Orchard pool to the Ironwood pool. {amount} is the formatted Orchard balance without the ZEC unit.
  ///
  /// In en, this message translates to:
  /// **'Your {amount} ZEC is currently in Orchard. To keep using these funds for shielded payments, you\'ll need to move them to Ironwood. You\'ll review the migration plan before any funds move.'**
  String migrationMobileIntroBody(String amount);

  /// Ghost button on the first mobile migration screen that opens the official Ironwood release note in the browser.
  ///
  /// In en, this message translates to:
  /// **'Official release note'**
  String get migrationMobileIntroReleaseNote;

  /// Title-case top bar title of the first mobile Ironwood migration screen, which announces the network update.
  ///
  /// In en, this message translates to:
  /// **'Zcash Network Update'**
  String get migrationMobileIntroTitle;

  /// [security] First line on the mobile migration progress screen telling the user to keep the app open and unlocked so a step needing input can proceed.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open & unlocked.'**
  String get migrationMobileKeepOpenUnlocked;

  /// [security] Second line on the mobile migration progress screens telling the user to keep the app open and running so the migration continues.
  ///
  /// In en, this message translates to:
  /// **'But keep Vizor open & running.'**
  String get migrationMobileKeepRunning;

  /// [security] Screen reader label of the Keystone request screen for the preparation (note split) signing round.
  ///
  /// In en, this message translates to:
  /// **'Confirm migration preparation with Keystone'**
  String get migrationMobileKeystoneConfirmPrepSemantics;

  /// [security] Screen reader label of the Keystone request screen for the migration transfer signing round.
  ///
  /// In en, this message translates to:
  /// **'Confirm migration transfer with Keystone'**
  String get migrationMobileKeystoneConfirmTransferSemantics;

  /// Instruction text of the Keystone scanning help preview; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Tap QR on your Keystone,\nthen scan this QR code.'**
  String get migrationMobileKeystoneHelpPrompt;

  /// Screen reader label of the help button on the Keystone request screen.
  ///
  /// In en, this message translates to:
  /// **'Keystone QR scanning help'**
  String get migrationMobileKeystoneHelpSemantics;

  /// Screen reader label of the placeholder shown while the Keystone request QR code loads.
  ///
  /// In en, this message translates to:
  /// **'Loading QR code'**
  String get migrationMobileKeystoneLoadingQrSemantics;

  /// [security] Message on the migration progress screen telling the user to reconnect or re-import the Keystone account to continue.
  ///
  /// In en, this message translates to:
  /// **'Reconnect or re-import your Keystone account to continue this migration.'**
  String get migrationMobileKeystoneReconnect;

  /// [security] Screen reader label of the QR code that the Keystone device scans to sign the migration.
  ///
  /// In en, this message translates to:
  /// **'Keystone request QR code'**
  String get migrationMobileKeystoneRequestQrSemantics;

  /// Status value on the migration progress screen when the Keystone account is missing from the wallet.
  ///
  /// In en, this message translates to:
  /// **'Keystone account required'**
  String get migrationMobileKeystoneRequiredStatus;

  /// [security] Message on the migration progress screen telling the user to sign the rebuilt migration transactions with the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Sign the rebuilt migration transactions with Keystone to continue.'**
  String get migrationMobileKeystoneResignMessage;

  /// [security] Default caption on the scanner screen; the line break after 'your' is intentional.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your\nKeystone to confirm'**
  String get migrationMobileKeystoneScanCaption;

  /// [security] Screen reader label of the scanner screen for the signed preparation round.
  ///
  /// In en, this message translates to:
  /// **'Scan the signed migration preparation from Keystone'**
  String get migrationMobileKeystoneScanPrepSemantics;

  /// Screen reader label of the progress bar for the animated QR code the user scans from the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Scan progress'**
  String get migrationMobileKeystoneScanProgress;

  /// [security] Screen reader label of the scanner screen for the signed migration transfer round.
  ///
  /// In en, this message translates to:
  /// **'Scan the signed migration transfer from Keystone'**
  String get migrationMobileKeystoneScanTransferSemantics;

  /// Message in the mobile manage-migration dialog when the migration status could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check the migration status. Please try again.'**
  String get migrationMobileManageCheckError;

  /// Message in the mobile manage-migration dialog while the migration status is loading.
  ///
  /// In en, this message translates to:
  /// **'Checking migration status...'**
  String get migrationMobileManageChecking;

  /// [security] Note in the manage-migration dialog that transactions already sent to the network are not undone.
  ///
  /// In en, this message translates to:
  /// **'Transactions already broadcast will not be reverted.'**
  String get migrationMobileManageNoRevert;

  /// Button in the manage-migration dialog that reloads the migration status after a failure.
  ///
  /// In en, this message translates to:
  /// **'Retry status check'**
  String get migrationMobileManageRetryStatus;

  /// [security] Button in the manage-migration dialog that starts stopping the remaining migration.
  ///
  /// In en, this message translates to:
  /// **'Stop migration'**
  String get migrationMobileManageStopAction;

  /// [security] Explanation in the manage-migration dialog before stopping the migration: funds already moved stay in Ironwood.
  ///
  /// In en, this message translates to:
  /// **'Stop the remaining migration. Funds already migrated will stay in Ironwood.'**
  String get migrationMobileManageStopBody;

  /// [security] Title of the manage-migration dialog confirmation step for stopping the migration.
  ///
  /// In en, this message translates to:
  /// **'Stop migration?'**
  String get migrationMobileManageStopTitle;

  /// Button in the manage-migration dialog that starts switching to the Fast migration.
  ///
  /// In en, this message translates to:
  /// **'Switch to Fast'**
  String get migrationMobileManageSwitchAction;

  /// [security] Warning in the manage-migration dialog before switching to Fast migration: it lowers privacy and cannot be undone after it is submitted.
  ///
  /// In en, this message translates to:
  /// **'Stop the private schedule and review a Fast migration for your remaining balance. Fast migration increases traceability and cannot be reversed once submitted.'**
  String get migrationMobileManageSwitchBody;

  /// Title of the manage-migration dialog confirmation step for switching to the Fast migration.
  ///
  /// In en, this message translates to:
  /// **'Switch to Fast?'**
  String get migrationMobileManageSwitchTitle;

  /// Title of the mobile dialog that lets the user switch to Fast migration or stop the migration.
  ///
  /// In en, this message translates to:
  /// **'Manage migration'**
  String get migrationMobileManageTitle;

  /// Message in the mobile manage-migration dialog when the migration can no longer be stopped or changed.
  ///
  /// In en, this message translates to:
  /// **'This migration is no longer available to manage.'**
  String get migrationMobileManageUnavailable;

  /// Note in the manage-migration dialog while it waits for a transaction being broadcast to finish before stopping.
  ///
  /// In en, this message translates to:
  /// **'Waiting for any active broadcast to finish before stopping the remaining migration.'**
  String get migrationMobileManageWaitingBroadcast;

  /// Migration status text while transactions wait for confirmations; the second sentence is on its own line.
  ///
  /// In en, this message translates to:
  /// **'Confirmations are still arriving.\nYou can leave Vizor and check again later.'**
  String get migrationMobileNextConfirmationsArriving;

  /// First lines of the migration status text; the timing is on its own line. {timing} is an estimated duration such as ~in 5 minutes.
  ///
  /// In en, this message translates to:
  /// **'Next migration step expected in\n{timing}.'**
  String migrationMobileNextExpectedIn(String timing);

  /// [security] Status text when notifications are off: the user must open the app after the given block and approve the next batch. {height} is a block height; {timing} is an estimated time such as ~in 5 minutes.
  ///
  /// In en, this message translates to:
  /// **'Notifications are disabled. Open Vizor after block {height} ({timing}) and approve the next migration batch.'**
  String migrationMobileNextNotificationsOffBlock(int height, String timing);

  /// [security] Status text when notifications are off and the next step's timing is not known: the user must open the app again and approve the next batch.
  ///
  /// In en, this message translates to:
  /// **'Notifications are disabled. Open Vizor again when the timing is available and approve the next migration batch.'**
  String get migrationMobileNextNotificationsOffNoTiming;

  /// [security] Line of the migration status text saying notifications are off, so the user must reopen the app to continue.
  ///
  /// In en, this message translates to:
  /// **'Notifications are disabled. Open Vizor again to continue.'**
  String get migrationMobileNextNotificationsOffOpen;

  /// Line of the migration status text saying notifications are on, so the user may leave the app.
  ///
  /// In en, this message translates to:
  /// **'Notifications are on. You can leave Vizor and check back later.'**
  String get migrationMobileNextNotificationsOnLeave;

  /// First line of the migration status text while a step is being sent.
  ///
  /// In en, this message translates to:
  /// **'Next migration step is on the way.'**
  String get migrationMobileNextOnTheWay;

  /// [security] Migration status text when the scheduled transaction is ready to be sent automatically; the app must stay open.
  ///
  /// In en, this message translates to:
  /// **'The scheduled transaction is ready for automatic submission. Keep Vizor open.'**
  String get migrationMobileNextReadyAuto;

  /// [security] Migration status text when the next step is ready now; the app must stay open.
  ///
  /// In en, this message translates to:
  /// **'The next migration step is ready. Keep Vizor open to continue.'**
  String get migrationMobileNextStepReady;

  /// Migration status text with the wait until the next step; the notification sentence is on its own line. {timing} is an estimate such as ~in 5 minutes.
  ///
  /// In en, this message translates to:
  /// **'{timing} until the next migration step.\nNotifications are on; you can leave Vizor and check back later.'**
  String migrationMobileNextTimingUntil(String timing);

  /// [security] Sentence for iOS users with Tor on, appended on a new line to the migration status text: the background migration uses a direct connection, not Tor, while the app is closed.
  ///
  /// In en, this message translates to:
  /// **'While Vizor is closed, migration continues over a direct connection.'**
  String get migrationMobileNextTorDisclosure;

  /// Button that asks the system permission for notifications, or opens Settings.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications'**
  String get migrationMobileNotifyAllow;

  /// Body of the notification permission screen explaining why notifications help. The apostrophes are curly.
  ///
  /// In en, this message translates to:
  /// **'Some migration steps require approval. We’ll notify you when it’s time, so you can respond quickly and avoid unnecessary delays.'**
  String get migrationMobileNotifyBody;

  /// [security] Body of the confirmation shown when the user declines notifications: they must open the app regularly to approve steps. The apostrophes are curly.
  ///
  /// In en, this message translates to:
  /// **'Without notifications, you’ll need to remember to open Vizor regularly and approve the next migration step when it’s ready.'**
  String get migrationMobileNotifyConfirmBody;

  /// Second paragraph of the confirmation shown when the user declines notifications.
  ///
  /// In en, this message translates to:
  /// **'Otherwise, your migration may take longer.'**
  String get migrationMobileNotifyConfirmNote;

  /// Heading of the confirmation shown when the user declines notifications for the private migration.
  ///
  /// In en, this message translates to:
  /// **'Continue without notifications?'**
  String get migrationMobileNotifyConfirmTitle;

  /// Ghost button of the confirmation that continues the private migration without notifications.
  ///
  /// In en, this message translates to:
  /// **'Continue without notifications'**
  String get migrationMobileNotifyContinueWithout;

  /// Heading of the notification permission screen of the private migration.
  ///
  /// In en, this message translates to:
  /// **'Keep your migration on schedule'**
  String get migrationMobileNotifyHeading;

  /// Error shown on the notification permission screen after the system dialog was dismissed and notifications are still off.
  ///
  /// In en, this message translates to:
  /// **'Notifications are still off. Allow them from Settings, or continue without notifications.'**
  String get migrationMobileNotifyStillOff;

  /// Top bar title of the mobile screen that asks the user to allow notifications for the private migration.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get migrationMobileNotifyTitle;

  /// Body of the Immediate migration option card. {estimate} is a short completion time estimate such as ~2 hours.
  ///
  /// In en, this message translates to:
  /// **'Migrates your entire balance in one batch. Fast ({estimate}) but less private.'**
  String migrationMobileOptionImmediateBody(String estimate);

  /// Body of the Private migration option card.
  ///
  /// In en, this message translates to:
  /// **'Splits transactions into multiple parts to minimize traceability but will take several hours to days.'**
  String get migrationMobileOptionPrivateBody;

  /// Body of the disabled Private migration option card on Android.
  ///
  /// In en, this message translates to:
  /// **'Not available on Android.'**
  String get migrationMobileOptionPrivateUnavailableAndroid;

  /// Title-case top bar title of the mobile screen where the user chooses between Private and Immediate migration.
  ///
  /// In en, this message translates to:
  /// **'How to Migrate'**
  String get migrationMobileOptionsNavTitle;

  /// Error under the Continue button of the migration options screen when the private migration preparation screen could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open migration preparation. Try again.'**
  String get migrationMobileOptionsOpenError;

  /// Subtitle of the migration options screen on Android, where private migration is temporarily unavailable.
  ///
  /// In en, this message translates to:
  /// **'Private migration is temporarily unavailable on Android. Choose immediate to continue.'**
  String get migrationMobileOptionsSubtitleAndroid;

  /// Subtitle of the migration options screen on Android when part of the balance is already migrated. {amount} is the remaining Orchard balance without the ZEC unit.
  ///
  /// In en, this message translates to:
  /// **'{amount} ZEC is still in Orchard. Private migration is temporarily unavailable on Android. Choose immediate to continue.'**
  String migrationMobileOptionsSubtitleAndroidRest(String amount);

  /// Subtitle of the migration options screen for a Ledger account. Immediate is the name of the fast option.
  ///
  /// In en, this message translates to:
  /// **'Private migration is not available for Ledger accounts. Choose Immediate to continue.'**
  String get migrationMobileOptionsSubtitleLedger;

  /// Subtitle of the migration options screen for a Ledger account when part of the balance is already migrated. Immediate is the name of the fast option. {amount} is the remaining Orchard balance without the ZEC unit.
  ///
  /// In en, this message translates to:
  /// **'{amount} ZEC is still in Orchard. Private migration is not available for Ledger accounts. Choose Immediate to continue.'**
  String migrationMobileOptionsSubtitleLedgerRest(String amount);

  /// Title-case heading of the migration options screen where the user picks Private or Immediate migration.
  ///
  /// In en, this message translates to:
  /// **'Choose How to Migrate'**
  String get migrationMobileOptionsTitle;

  /// Title-case heading of the migration options screen when part of the balance has already been migrated and the rest remains.
  ///
  /// In en, this message translates to:
  /// **'How to Move the Rest'**
  String get migrationMobileOptionsTitleRest;

  /// Status of a migration part waiting for network confirmations. {count} is the confirmations so far and {target} the number needed.
  ///
  /// In en, this message translates to:
  /// **'Confirming · {count}/{target}'**
  String migrationMobilePartConfirming(int count, int target);

  /// Label of one migration part (one transaction of the split migration) in the progress list. {number} starts at 1.
  ///
  /// In en, this message translates to:
  /// **'Part {number}'**
  String migrationMobilePartLabel(int number);

  /// Screen reader label of a migration part's progress bar. {part} is the part label such as Part 2; {percent} is a whole number.
  ///
  /// In en, this message translates to:
  /// **'{part} progress {percent}%'**
  String migrationMobilePartProgress(String part, int percent);

  /// Status of a migration part that is waiting for its turn and has no time estimate yet.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get migrationMobilePartQueued;

  /// Placeholder on the mobile migration progress screen while the list of migration parts is empty.
  ///
  /// In en, this message translates to:
  /// **'Migration parts will appear as transactions are prepared.'**
  String get migrationMobilePartsPlaceholder;

  /// [security] Text inside the preparation ring while the next preparation transactions are being made; the app must stay open.
  ///
  /// In en, this message translates to:
  /// **'Preparing the next transactions. Keep Vizor open.'**
  String get migrationMobilePrepAdvancing;

  /// Text inside the preparation ring while confirmations are tracked in the background; keep it two short sentences.
  ///
  /// In en, this message translates to:
  /// **'Confirming in the background. You can close Vizor.'**
  String get migrationMobilePrepBackgroundTracking;

  /// [security] Text inside the preparation ring on a device that cannot track preparation while the app is closed; the app must stay open. The apostrophe is curly.
  ///
  /// In en, this message translates to:
  /// **'This device can’t confirm in the background. Keep Vizor open.'**
  String get migrationMobilePrepBackgroundUnsupported;

  /// Button that resumes a paused preparation.
  ///
  /// In en, this message translates to:
  /// **'Continue preparation'**
  String get migrationMobilePrepContinue;

  /// [security] Button that continues the preparation by signing again on the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Continue with Keystone'**
  String get migrationMobilePrepContinueKeystone;

  /// Body of the modal shown when the balance preparation finished.
  ///
  /// In en, this message translates to:
  /// **'Preparation is complete. Check your migration status for progress and any action needed.'**
  String get migrationMobilePrepDoneBody;

  /// Heading of the modal shown when the balance preparation finished.
  ///
  /// In en, this message translates to:
  /// **'Preparation is done'**
  String get migrationMobilePrepDoneTitle;

  /// Text inside the preparation ring giving the typical preparation time; the line break is intentional and the dash is an en dash.
  ///
  /// In en, this message translates to:
  /// **'Preparation will\ntake 10–20 min'**
  String get migrationMobilePrepDuration;

  /// Second line of the info card under the preparation ring.
  ///
  /// In en, this message translates to:
  /// **'Once preparation finishes, your migration can begin.'**
  String get migrationMobilePrepInfoThenBegin;

  /// [security] Text inside the preparation ring when the preparation needs another signature from the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Preparation needs another Keystone signature.'**
  String get migrationMobilePrepKeystoneSignature;

  /// [security] Text inside the preparation ring when notifications are off and the preparation cannot continue in the background.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications to continue in the background, or keep Vizor open.'**
  String get migrationMobilePrepNotificationsDisabled;

  /// Text inside the preparation ring when the preparation paused because the user left the app.
  ///
  /// In en, this message translates to:
  /// **'Preparation was paused because you left.'**
  String get migrationMobilePrepPausedLeft;

  /// Text inside the preparation ring while the wallet syncs before preparation continues.
  ///
  /// In en, this message translates to:
  /// **'Syncing your wallet…'**
  String get migrationMobilePrepSyncingWallet;

  /// Subtitle on the mobile migration preparation status screen while the balance is split into parts.
  ///
  /// In en, this message translates to:
  /// **'Preparing your balance for migration. This step usually takes 10-20 mins.'**
  String get migrationMobilePreparingBody;

  /// Top bar title of the mobile private migration preparation screen.
  ///
  /// In en, this message translates to:
  /// **'Preparing your migration'**
  String get migrationMobilePreparingTitle;

  /// Body of step 1 on the how migration works screen.
  ///
  /// In en, this message translates to:
  /// **'Compare a privacy-optimized schedule with a faster migration.'**
  String get migrationMobileProcessChooseBody;

  /// Title of step 1 on the how migration works screen.
  ///
  /// In en, this message translates to:
  /// **'Choose how you migrate'**
  String get migrationMobileProcessChooseTitle;

  /// Body of step 3 on the how migration works screen.
  ///
  /// In en, this message translates to:
  /// **'Privacy-optimized migrations send parts at staggered times to reduce linkability.'**
  String get migrationMobileProcessMoveBody;

  /// Title of step 3 on the how migration works screen.
  ///
  /// In en, this message translates to:
  /// **'Move to Ironwood'**
  String get migrationMobileProcessMoveTitle;

  /// Body of step 2 on the how migration works screen.
  ///
  /// In en, this message translates to:
  /// **'Vizor reorganizes your balance into common-sized parts before migration begins.'**
  String get migrationMobileProcessPrepareBody;

  /// Title of step 2 on the how migration works screen.
  ///
  /// In en, this message translates to:
  /// **'Prepare your balance'**
  String get migrationMobileProcessPrepareTitle;

  /// Body of the note below the steps explaining confirmed Ironwood funds can be spent while the migration continues.
  ///
  /// In en, this message translates to:
  /// **'Each confirmed Ironwood amount is available to spend while the rest continues.'**
  String get migrationMobileProcessSpendBody;

  /// Title of the note below the steps explaining funds can be spent as they arrive.
  ///
  /// In en, this message translates to:
  /// **'Spend as funds arrive'**
  String get migrationMobileProcessSpendTitle;

  /// Title of the status card for a software account while the migration is processed.
  ///
  /// In en, this message translates to:
  /// **'All clear. Migration is in progress'**
  String get migrationMobileProgressAllClear;

  /// Title of the status card for a Keystone account while the migration batch is processed. {number} starts at 1.
  ///
  /// In en, this message translates to:
  /// **'All clear. Processing batch #{number}'**
  String migrationMobileProgressAllClearBatch(int number);

  /// Body of the status card when a migration batch waits for the user's confirmation. {number} starts at 1.
  ///
  /// In en, this message translates to:
  /// **'Batch #{number} is ready.'**
  String migrationMobileProgressBatchReady(int number);

  /// Title and value text shown while the migration waits for its next step.
  ///
  /// In en, this message translates to:
  /// **'Waiting for next migration step'**
  String get migrationMobileProgressNextStep;

  /// Title of the status card when the scheduled transaction is ready now.
  ///
  /// In en, this message translates to:
  /// **'Ready now'**
  String get migrationMobileProgressReadyNow;

  /// Value of the estimated completion row when a scheduled transaction is ready to submit.
  ///
  /// In en, this message translates to:
  /// **'Scheduled transaction ready'**
  String get migrationMobileProgressScheduledReady;

  /// Body of the status card while the migration progress is syncing.
  ///
  /// In en, this message translates to:
  /// **'Checking the latest confirmations and migration status.'**
  String get migrationMobileProgressSyncingBody;

  /// Title of the status card while the migration progress is syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing migration progress'**
  String get migrationMobileProgressSyncingTitle;

  /// Body of the status card when preparation is complete and notifications are on; the line breaks are intentional.
  ///
  /// In en, this message translates to:
  /// **'Preparation is complete, but we are waiting\nfor the next available signing window.\nWe’ll let you know when it’s time to take action.'**
  String get migrationMobileProgressWaitingWindowBody;

  /// [security] Title and value text shown while the migration waits for the user to confirm a step.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your confirmation'**
  String get migrationMobileProgressYourConfirmation;

  /// Confirm button of the rebuild migration dialog.
  ///
  /// In en, this message translates to:
  /// **'Rebuild'**
  String get migrationMobileRebuildAction;

  /// Body of the rebuild migration confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Vizor will first check that the pending transactions were not sent. It will then rebuild the migration for only your remaining balance. Any confirmed transfers will stay unchanged.'**
  String get migrationMobileRebuildBody;

  /// Title of the confirmation dialog for rebuilding the migration.
  ///
  /// In en, this message translates to:
  /// **'Rebuild migration?'**
  String get migrationMobileRebuildTitle;

  /// Button on the mobile migration progress screen that starts rebuilding the migration from saved transactions.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get migrationMobileRecover;

  /// Label of the Recover button while the migration is being rebuilt.
  ///
  /// In en, this message translates to:
  /// **'Recovering...'**
  String get migrationMobileRecovering;

  /// First line on the mobile migration progress screen when saved transactions must be rebuilt.
  ///
  /// In en, this message translates to:
  /// **'Migration recovery required.'**
  String get migrationMobileRecoveryRequired;

  /// Label of the action button on the migration progress screen while a paused migration resumes.
  ///
  /// In en, this message translates to:
  /// **'Resuming...'**
  String get migrationMobileResuming;

  /// Second line on the mobile migration progress screen saying the app retries on its own.
  ///
  /// In en, this message translates to:
  /// **'Vizor will retry automatically.'**
  String get migrationMobileRetryAutomatically;

  /// Second line on the mobile migration progress screen explaining why recovery is required.
  ///
  /// In en, this message translates to:
  /// **'Two saved transactions couldn\'t be reopened.'**
  String get migrationMobileSavedTxError;

  /// Label of a split output that is change returned to the wallet, in the preparation schedule.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get migrationMobileScheduleChange;

  /// Status of a transaction waiting for network confirmations. {count} is confirmations so far and {target} the number needed.
  ///
  /// In en, this message translates to:
  /// **'Confirming {count}/{target}'**
  String migrationMobileScheduleConfirming(int count, int target);

  /// Footer label on the migration schedule screen for the time left until the migration completes.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get migrationMobileScheduleDuration;

  /// Screen reader label of the loading indicator on the mobile migration schedule screen.
  ///
  /// In en, this message translates to:
  /// **'Loading migration schedule'**
  String get migrationMobileScheduleLoading;

  /// Status of a migration part that is being sent, in the migration schedule list (with a single ellipsis character).
  ///
  /// In en, this message translates to:
  /// **'Migrating…'**
  String get migrationMobileScheduleMigrating;

  /// Label of a split output that will be migrated, in the preparation schedule.
  ///
  /// In en, this message translates to:
  /// **'Migration note'**
  String get migrationMobileScheduleMigrationNote;

  /// Status of a preparation transaction that waits for the previous round, and label of an output that feeds the next round.
  ///
  /// In en, this message translates to:
  /// **'Next round'**
  String get migrationMobileScheduleNextRound;

  /// Progress of split rounds. {current} is the current round or completed count and {total} the total.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String migrationMobileScheduleOf(int current, int total);

  /// Status of a scheduled migration part whose block has passed beyond the grace period.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get migrationMobileScheduleOverdue;

  /// Footer label on the preparation schedule screen for how many split transactions are done.
  ///
  /// In en, this message translates to:
  /// **'Preparation progress'**
  String get migrationMobileSchedulePreparationProgress;

  /// Footer label on the preparation schedule screen for the time left until preparation is ready.
  ///
  /// In en, this message translates to:
  /// **'Ready in'**
  String get migrationMobileScheduleReadyIn;

  /// Button on the migration schedule screens that goes back to the migration status.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get migrationMobileScheduleReturn;

  /// Label of a split output that feeds a later round. {round} is the round number.
  ///
  /// In en, this message translates to:
  /// **'Round {round}'**
  String migrationMobileScheduleRound(int round);

  /// Label of the summary row on the preparation schedule showing the current round out of the total.
  ///
  /// In en, this message translates to:
  /// **'Rounds remaining'**
  String get migrationMobileScheduleRoundsRemaining;

  /// Footer label on the migration schedule screen for the already migrated, spendable Ironwood amount.
  ///
  /// In en, this message translates to:
  /// **'Ironwood spendable'**
  String get migrationMobileScheduleSpendable;

  /// Heading of one round of note-splitting transactions on the preparation schedule screen.
  ///
  /// In en, this message translates to:
  /// **'Split round {round}'**
  String migrationMobileScheduleSplitRound(int round);

  /// Body of the error state of the migration schedule screen.
  ///
  /// In en, this message translates to:
  /// **'Vizor couldn\'t load the latest schedule. Your saved migration state is unchanged.'**
  String get migrationMobileScheduleUnavailableBody;

  /// Label of the row showing the balance that can be spent right now while a migration is running.
  ///
  /// In en, this message translates to:
  /// **'Currently spendable balance'**
  String get migrationMobileSpendableBalance;

  /// Body of the error state of the private migration preparation screen when there is no specific error message.
  ///
  /// In en, this message translates to:
  /// **'Try again when you are ready.'**
  String get migrationMobileStartErrorFallback;

  /// Heading of the error state of the private migration preparation screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t prepare your migration'**
  String get migrationMobileStartErrorTitle;

  /// Body under the loading indicator while Vizor prepares the private migration.
  ///
  /// In en, this message translates to:
  /// **'Vizor is preparing your migration. This may take a moment.'**
  String get migrationMobileStartLoadingBody;

  /// Second rotating loading message on the mobile private migration preparation screen.
  ///
  /// In en, this message translates to:
  /// **'Organizing migration batches...'**
  String get migrationMobileStartMessageOrganizing;

  /// First rotating loading message on the mobile private migration preparation screen.
  ///
  /// In en, this message translates to:
  /// **'Preparing your migration...'**
  String get migrationMobileStartMessagePreparing;

  /// [security] Body explaining that the user will sign the preparation transactions and all migration batches in one Keystone signing step.
  ///
  /// In en, this message translates to:
  /// **'Continue to sign the preparation transactions and migration batches together with Keystone.'**
  String get migrationMobileStartReadyBody;

  /// Muted number of notes (migration parts) after the word Migration in the heading row of the progress screens.
  ///
  /// In en, this message translates to:
  /// **'{count} notes'**
  String migrationMobileStatusNotesCount(int count);

  /// Heading row above the migration parts. {notes} is the muted note count such as '3 notes' and can be moved anywhere.
  ///
  /// In en, this message translates to:
  /// **'Migration {notes}'**
  String migrationMobileStatusNotesTitle(String notes);

  /// Message under the loading indicator while the migration progress is syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing the migration progress.'**
  String get migrationMobileSyncingProgress;

  /// Placeholder used as the timing of the next migration step while the estimate is not available.
  ///
  /// In en, this message translates to:
  /// **'Timing is updating'**
  String get migrationMobileTimingUpdating;

  /// Small button and its screen reader label that opens the migration schedule.
  ///
  /// In en, this message translates to:
  /// **'View schedule'**
  String get migrationMobileViewSchedule;

  /// Note under the note split card for software accounts: the migration starts by itself.
  ///
  /// In en, this message translates to:
  /// **'Migration will start automatically once note split is complete.'**
  String get migrationMobileWaitAutoStart;

  /// Progress of the confirmation wait. {count} is confirmed blocks and {target} the number needed.
  ///
  /// In en, this message translates to:
  /// **'{count}/{target} blocks'**
  String migrationMobileWaitBlocks(int count, int target);

  /// Second step of the note split card: wait for blocks to confirm the split.
  ///
  /// In en, this message translates to:
  /// **'Wait for confirmation'**
  String get migrationMobileWaitConfirmation;

  /// Note under the note split card for Keystone accounts: another signing on the device is required afterwards.
  ///
  /// In en, this message translates to:
  /// **'Another Keystone approval will be needed after these confirmations.'**
  String get migrationMobileWaitKeystoneAgain;

  /// Caption in the middle of the animated loop that explains the sign-and-wait cycle; the line breaks are intentional and the dash is an en dash.
  ///
  /// In en, this message translates to:
  /// **'Repeat several times,\nwaiting could take 2–10\nhours'**
  String get migrationMobileWaitLoopCaption;

  /// Highlighted verb inserted into the bottom text of the animated loop, which reads 'Sign the batch of transactions'.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get migrationMobileWaitLoopSign;

  /// Text along the bottom of the animated loop on the migration screen: the user signs the next batch. {highlight} is the highlighted verb 'Sign' and can be moved anywhere.
  ///
  /// In en, this message translates to:
  /// **'{highlight} the batch of transactions'**
  String migrationMobileWaitLoopSignLine(String highlight);

  /// Highlighted verb inserted into the top text of the animated loop, which reads 'Wait for the window'.
  ///
  /// In en, this message translates to:
  /// **'Wait'**
  String get migrationMobileWaitLoopWait;

  /// Text along the top of the animated loop on the migration screen: the user waits for the next signing window. {highlight} is the highlighted verb 'Wait' and can be moved anywhere.
  ///
  /// In en, this message translates to:
  /// **'{highlight} for the window'**
  String migrationMobileWaitLoopWaitLine(String highlight);

  /// Title-case heading of the card on the preparation screen that shows the note split steps.
  ///
  /// In en, this message translates to:
  /// **'Note Split'**
  String get migrationMobileWaitNoteSplit;

  /// First line on the mobile migration progress screen while the next step waits for a block that is safe to use.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a safe block to continue.'**
  String get migrationMobileWaitSafeBlock;

  /// Title-case first step of the note split card. {count} is the number of migration parts.
  ///
  /// In en, this message translates to:
  /// **'Split Notes into {count} Migration Parts'**
  String migrationMobileWaitSplitInto(int count);

  /// Ring sub-caption: every note has been migrated.
  ///
  /// In en, this message translates to:
  /// **'All notes completed'**
  String get migrationNextActionDetailAllNotesCompleted;

  /// Ring sub-caption shown just before a block height, as in "at 3,428,143".
  ///
  /// In en, this message translates to:
  /// **'at'**
  String get migrationNextActionDetailAt;

  /// Ring sub-caption shown just before the block height at which the next window is expected.
  ///
  /// In en, this message translates to:
  /// **'Expected at'**
  String get migrationNextActionDetailExpectedAt;

  /// Ring sub-caption while the migration transfer is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing migration'**
  String get migrationNextActionDetailPreparing;

  /// Ring sub-caption: the next migration transfer is waiting for the user to sign.
  ///
  /// In en, this message translates to:
  /// **'Ready to sign'**
  String get migrationNextActionDetailReadyToSign;

  /// Ring sub-caption: the migration transfer is being sent right now.
  ///
  /// In en, this message translates to:
  /// **'Sending now'**
  String get migrationNextActionDetailSendingNow;

  /// Ring sub-caption: all transfers are sent and waiting for network confirmations.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmations'**
  String get migrationNextActionDetailWaitingForConfirmations;

  /// Ring caption while broadcast migration transfers wait to be mined into a block.
  ///
  /// In en, this message translates to:
  /// **'Awaiting mining'**
  String get migrationNextActionLabelAwaitingMining;

  /// Ring caption when every migration transfer has completed.
  ///
  /// In en, this message translates to:
  /// **'Migration complete'**
  String get migrationNextActionLabelComplete;

  /// Ring caption while the last migration transfers finish confirming.
  ///
  /// In en, this message translates to:
  /// **'Finalizing migration'**
  String get migrationNextActionLabelFinalizing;

  /// Ironwood migration ring caption naming the next transfer to be sent.
  ///
  /// In en, this message translates to:
  /// **'Next migration'**
  String get migrationNextActionLabelNext;

  /// Ring caption naming the upcoming migration time window.
  ///
  /// In en, this message translates to:
  /// **'Next migration window'**
  String get migrationNextActionLabelNextWindow;

  /// Ring caption while the wallet waits for the migration time window to open.
  ///
  /// In en, this message translates to:
  /// **'Opening migration window'**
  String get migrationNextActionLabelOpeningWindow;

  /// Ring caption while a due migration transfer is being sent.
  ///
  /// In en, this message translates to:
  /// **'Sending migration'**
  String get migrationNextActionLabelSending;

  /// Ring caption when the migration time window is open.
  ///
  /// In en, this message translates to:
  /// **'Migration window ready'**
  String get migrationNextActionLabelWindowReady;

  /// Shown in place of a completion duration when no migration transfers are scheduled.
  ///
  /// In en, this message translates to:
  /// **'Not scheduled'**
  String get migrationNotScheduled;

  /// Count of migration notes waiting for network confirmations.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note awaiting confirmation} other{{count} notes awaiting confirmation}}'**
  String migrationNotesAwaitingConfirmation(int count);

  /// Count of migration notes that were broadcast and are waiting to be mined.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note broadcast} other{{count} notes broadcast}}'**
  String migrationNotesBroadcast(int count);

  /// Count of migration notes that still need to finish.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note remaining} other{{count} notes remaining}}'**
  String migrationNotesRemaining(int count);

  /// Name of the immediate (one-step, faster) migration option.
  ///
  /// In en, this message translates to:
  /// **'Immediate'**
  String get migrationOptionImmediate;

  /// Describes the immediate migration option.
  ///
  /// In en, this message translates to:
  /// **'Migrates your entire balance in one batch. Fast but less private.'**
  String get migrationOptionImmediateBody;

  /// Name of the private (slower, split) migration option.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get migrationOptionPrivate;

  /// Describes the private migration option.
  ///
  /// In en, this message translates to:
  /// **'Splits transactions into multiple parts to minimize traceability, but will take longer.'**
  String get migrationOptionPrivateBody;

  /// Shown instead of the private option description for Ledger accounts.
  ///
  /// In en, this message translates to:
  /// **'Not available for Ledger accounts.'**
  String get migrationOptionPrivateLedger;

  /// Badge on the recommended migration option.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get migrationOptionRecommended;

  /// Body of the migration options screen.
  ///
  /// In en, this message translates to:
  /// **'Choose between more privacy over time or a faster migration. You can review the details before anything moves.'**
  String get migrationOptionsBody;

  /// Body of the options screen when part of the balance is already migrated; {amount} is the remaining ZEC amount.
  ///
  /// In en, this message translates to:
  /// **'{amount} ZEC is still in Orchard. Choose between more privacy over time or a faster migration.'**
  String migrationOptionsBodyMoveRest(String amount);

  /// Button on the migration options screen that opens the review of the selected option.
  ///
  /// In en, this message translates to:
  /// **'Select & review'**
  String get migrationOptionsSelectReview;

  /// Title of the migration options screen.
  ///
  /// In en, this message translates to:
  /// **'Choose how to migrate'**
  String get migrationOptionsTitle;

  /// Title of the options screen when part of the balance was already migrated.
  ///
  /// In en, this message translates to:
  /// **'How to move the rest'**
  String get migrationOptionsTitleMoveRest;

  /// Overall migration progress, for example "3 of 9 complete".
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} complete'**
  String migrationOverallProgress(String completed, String total);

  /// Heading of the legacy migration card; {count} is the number of planned batches.
  ///
  /// In en, this message translates to:
  /// **'{count} Planned batches'**
  String migrationPlannedBatches(String count);

  /// Name of the Ironwood pool in the migration illustration.
  ///
  /// In en, this message translates to:
  /// **'Ironwood Pool'**
  String get migrationPoolIronwood;

  /// Small caption above the Orchard pool name in the migration illustration.
  ///
  /// In en, this message translates to:
  /// **'(Legacy)'**
  String get migrationPoolLegacy;

  /// Name of the Orchard pool in the migration illustration.
  ///
  /// In en, this message translates to:
  /// **'Orchard Pool'**
  String get migrationPoolOrchard;

  /// Progress label for confirmations received by the split transactions.
  ///
  /// In en, this message translates to:
  /// **'{confirmed} of {target} confirmations'**
  String migrationPreparationConfirmations(String confirmed, String target);

  /// Progress label naming which split transaction is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing split {current} of {total}'**
  String migrationPreparationSplitProgress(String current, String total);

  /// Progress label naming which split transaction is in progress.
  ///
  /// In en, this message translates to:
  /// **'Split {current} of {total}'**
  String migrationPreparationSplitStep(String current, String total);

  /// Progress label while the balance is split into standard-sized notes before migrating.
  ///
  /// In en, this message translates to:
  /// **'Preparing split transactions'**
  String get migrationPreparationSplitTransactions;

  /// Carousel tip on the Ironwood migration preparation screen about the deliberate wait before transfers start.
  ///
  /// In en, this message translates to:
  /// **'Once preparation finishes, your migration will begin automatically after a long intentional delay.'**
  String get migrationPreparationTipDelay;

  /// Carousel tip explaining that the balance is split into common-sized notes so the migration is harder to link.
  ///
  /// In en, this message translates to:
  /// **'We’re organizing your balance into common-sized parts. This makes your migration harder to link.'**
  String get migrationPreparationTipOrganizing;

  /// Carousel tip saying the note splitting can take several rounds.
  ///
  /// In en, this message translates to:
  /// **'We may have to do multiple rounds of note splitting depending on your balance.'**
  String get migrationPreparationTipRounds;

  /// [security] Button label while a migration batch is being prepared for signing.
  ///
  /// In en, this message translates to:
  /// **'Preparing batch...'**
  String get migrationPreparingBatch;

  /// [security] Text on the lock screen shown during a running migration, explaining that the wallet auto-locked after inactivity.
  ///
  /// In en, this message translates to:
  /// **'We auto-locked Vizor after 10 minutes of inactivity.'**
  String get migrationPrivacyLockDescription;

  /// Carousel tip about block time; {seconds} is the average number of seconds per block.
  ///
  /// In en, this message translates to:
  /// **'Each Zcash block takes about {seconds} seconds to create, but timing can vary with network conditions.'**
  String migrationProgressTipBlockTime(String seconds);

  /// [security] Carousel tip on the migration progress screen: closing the app pauses the migration and it can be resumed later.
  ///
  /// In en, this message translates to:
  /// **'You can close Vizor anytime. Migration will pause, and you can restart it when you return.'**
  String get migrationProgressTipClose;

  /// [security] Carousel tip: leaving Vizor open lets the migration continue automatically in the background.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor running and the migration will automatically run in the background.'**
  String get migrationProgressTipKeepRunning;

  /// Lowercase status: the migration step can start now.
  ///
  /// In en, this message translates to:
  /// **'ready now'**
  String get migrationReadyNow;

  /// Button that retries a migration that hit a recoverable error.
  ///
  /// In en, this message translates to:
  /// **'Retry migration'**
  String get migrationRetryMigration;

  /// Label of the retry button while the retry is running.
  ///
  /// In en, this message translates to:
  /// **'Retrying...'**
  String get migrationRetrying;

  /// Label above the ZEC amount that the private migration will move.
  ///
  /// In en, this message translates to:
  /// **'Amount to migrate'**
  String get migrationReviewAmountToMigrate;

  /// Title of the error shown when the private migration plan could not be computed for the balance.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t analyze this balance'**
  String get migrationReviewAnalyzeErrorTitle;

  /// Label of the estimated time until the private migration is complete.
  ///
  /// In en, this message translates to:
  /// **'Migration complete in'**
  String get migrationReviewCompleteIn;

  /// [security] Notice body: preparation keeps going while the app is minimized, then the migration starts on its own.
  ///
  /// In en, this message translates to:
  /// **'Preparation continues while the app is minimized, then migration starts automatically.'**
  String get migrationReviewKeepRunningBody;

  /// [security] Heading of a notice asking the user to keep Vizor open while the migration runs.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor running'**
  String get migrationReviewKeepRunningTitle;

  /// Button that starts the private migration.
  ///
  /// In en, this message translates to:
  /// **'Start migration'**
  String get migrationReviewStart;

  /// Label of the start button while the migration is being started.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get migrationReviewStarting;

  /// Ring detail when all note-splitting transactions have completed.
  ///
  /// In en, this message translates to:
  /// **'All splits completed'**
  String get migrationRingAllSplitsCompleted;

  /// Ring caption while a split transaction collects confirmations.
  ///
  /// In en, this message translates to:
  /// **'Confirming split'**
  String get migrationRingConfirmingSplit;

  /// Ring caption naming the next note-splitting transaction.
  ///
  /// In en, this message translates to:
  /// **'Next split'**
  String get migrationRingNextSplit;

  /// Ring caption when every note-splitting transaction has completed.
  ///
  /// In en, this message translates to:
  /// **'Preparation complete'**
  String get migrationRingPreparationComplete;

  /// Ring sub-caption while the split schedule is being computed.
  ///
  /// In en, this message translates to:
  /// **'Preparing schedule'**
  String get migrationRingPreparingSchedule;

  /// Ring detail for a split transaction that is scheduled for a future block.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get migrationRingScheduled;

  /// Ring caption while a split transaction has been sent and is not yet mined.
  ///
  /// In en, this message translates to:
  /// **'Split in progress'**
  String get migrationRingSplitInProgress;

  /// Lowercase screen-reader state of a migration note that is done.
  ///
  /// In en, this message translates to:
  /// **'completed'**
  String get migrationRingStatusCompleted;

  /// Lowercase screen-reader state of a migration note waiting for confirmations.
  ///
  /// In en, this message translates to:
  /// **'confirming'**
  String get migrationRingStatusConfirming;

  /// Lowercase screen-reader state of a migration note being sent.
  ///
  /// In en, this message translates to:
  /// **'migrating'**
  String get migrationRingStatusMigrating;

  /// Lowercase screen-reader state of a migration note that needs the user to sign.
  ///
  /// In en, this message translates to:
  /// **'needs input'**
  String get migrationRingStatusNeedsInput;

  /// Lowercase screen-reader state of a migration note that has not started.
  ///
  /// In en, this message translates to:
  /// **'not started'**
  String get migrationRingStatusNotStarted;

  /// Lowercase screen-reader state of a migration note being prepared.
  ///
  /// In en, this message translates to:
  /// **'preparing'**
  String get migrationRingStatusPreparing;

  /// Lowercase screen-reader state of a migration note that is scheduled.
  ///
  /// In en, this message translates to:
  /// **'scheduled'**
  String get migrationRingStatusScheduled;

  /// Ring detail: the split transaction is waiting to be included in a block.
  ///
  /// In en, this message translates to:
  /// **'Waiting for block'**
  String get migrationRingWaitingForBlock;

  /// Ring detail: this split cannot start until the previous split is confirmed.
  ///
  /// In en, this message translates to:
  /// **'Waiting for previous split'**
  String get migrationRingWaitingForPreviousSplit;

  /// Toast shown when the user opens the migration but the account cannot migrate.
  ///
  /// In en, this message translates to:
  /// **'Migration is not available for this account.'**
  String get migrationRouteNotAvailable;

  /// Toast shown when the account has nothing to migrate.
  ///
  /// In en, this message translates to:
  /// **'Migration is not needed for this account.'**
  String get migrationRouteNotNeeded;

  /// Toast shown when the migration state could not be read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify migration status.'**
  String get migrationRouteStatusFailed;

  /// Toast shown when the migration cannot start because the wallet sync failed.
  ///
  /// In en, this message translates to:
  /// **'Sync could not finish. Try again once Vizor is synced.'**
  String get migrationRouteSyncFailed;

  /// Status of a split transaction that is being sent to the network.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting'**
  String get migrationScheduleBroadcasting;

  /// Value shown while the preparation completion block is being computed.
  ///
  /// In en, this message translates to:
  /// **'Calculating'**
  String get migrationScheduleCalculating;

  /// Status of a migration transfer that was mined; {height} is the block height.
  ///
  /// In en, this message translates to:
  /// **'Completed at block {height}'**
  String migrationScheduleCompletedAtBlock(String height);

  /// Status of a migration transfer collecting confirmations.
  ///
  /// In en, this message translates to:
  /// **'Confirming {count}/{target}'**
  String migrationScheduleConfirmingProgress(String count, String target);

  /// Summary row label for the note-splitting round currently running.
  ///
  /// In en, this message translates to:
  /// **'Current round'**
  String get migrationScheduleCurrentRound;

  /// Expected block height of a split transaction that waits for the previous split.
  ///
  /// In en, this message translates to:
  /// **'Expected #{height}'**
  String migrationScheduleExpected(String height);

  /// Destination of a split output: it stays in the Orchard pool.
  ///
  /// In en, this message translates to:
  /// **'Stays in Orchard'**
  String get migrationScheduleOutputChange;

  /// Destination of a split output: it is split again in the given round.
  ///
  /// In en, this message translates to:
  /// **'Used in round {round}'**
  String migrationScheduleOutputContinuation(String round);

  /// Destination of a split output: it will be migrated.
  ///
  /// In en, this message translates to:
  /// **'For migration'**
  String get migrationScheduleOutputMigration;

  /// Placeholder shown where a migration time or duration is not yet scheduled.
  ///
  /// In en, this message translates to:
  /// **'Schedule pending'**
  String get migrationSchedulePending;

  /// Summary row label for the block height at which preparation is expected to finish.
  ///
  /// In en, this message translates to:
  /// **'Ready to migrate'**
  String get migrationScheduleReadyToMigrate;

  /// Status of a split transaction whose expected time is being recalculated.
  ///
  /// In en, this message translates to:
  /// **'Recalculating'**
  String get migrationScheduleRecalculating;

  /// Status of a migration transfer that moved to a later block height.
  ///
  /// In en, this message translates to:
  /// **'Rescheduled #{height}'**
  String migrationScheduleRescheduled(String height);

  /// Current split round out of all rounds, for example "2 of 3".
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String migrationScheduleRoundProgress(String current, String total);

  /// Status of a migration transfer scheduled for a block height.
  ///
  /// In en, this message translates to:
  /// **'Scheduled #{height}'**
  String migrationScheduleScheduledAt(String height);

  /// Lowercase screen-reader state of a split transaction waiting for the previous split.
  ///
  /// In en, this message translates to:
  /// **'waiting for previous split, expected at block {height}'**
  String migrationScheduleSemanticsAwaiting(String height);

  /// Lowercase screen-reader state of a split transaction that was sent and awaits mining.
  ///
  /// In en, this message translates to:
  /// **'broadcast, waiting to be mined, projected completion at block {height}'**
  String migrationScheduleSemanticsBroadcast(String height);

  /// Lowercase screen-reader state of a transaction completed at a block height.
  ///
  /// In en, this message translates to:
  /// **'completed at block {height}'**
  String migrationScheduleSemanticsCompletedAt(String height);

  /// Lowercase screen-reader state of a note that is due.
  ///
  /// In en, this message translates to:
  /// **'due now'**
  String get migrationScheduleSemanticsDue;

  /// Lowercase screen-reader state of a note that was sent and awaits mining.
  ///
  /// In en, this message translates to:
  /// **'broadcast, waiting to be mined'**
  String get migrationScheduleSemanticsMigrating;

  /// Screen-reader description of one migration note row.
  ///
  /// In en, this message translates to:
  /// **'Note {number}, {amount} ZEC, {state}.'**
  String migrationScheduleSemanticsNote(
    String number,
    String amount,
    String state,
  );

  /// Lowercase screen-reader state of a note collecting confirmations.
  ///
  /// In en, this message translates to:
  /// **'confirming, {count} of {target} confirmations'**
  String migrationScheduleSemanticsNoteConfirming(String count, String target);

  /// Lowercase screen-reader state of a mined note collecting confirmations.
  ///
  /// In en, this message translates to:
  /// **'confirming, {count} of {target} confirmations, mined at block {height}'**
  String migrationScheduleSemanticsNoteConfirmingMined(
    String count,
    String target,
    String height,
  );

  /// Screen-reader description of one split output: its ZEC amount and where it goes.
  ///
  /// In en, this message translates to:
  /// **'{amount} ZEC, {destination}'**
  String migrationScheduleSemanticsOutput(String amount, String destination);

  /// Lowercase screen-reader destination of a split output: it stays in Orchard.
  ///
  /// In en, this message translates to:
  /// **'stays in Orchard'**
  String get migrationScheduleSemanticsOutputChange;

  /// Lowercase screen-reader destination of a split output that is split again.
  ///
  /// In en, this message translates to:
  /// **'used in round {round}'**
  String migrationScheduleSemanticsOutputContinuation(String round);

  /// Lowercase screen-reader destination of a split output: it will be migrated.
  ///
  /// In en, this message translates to:
  /// **'for migration'**
  String get migrationScheduleSemanticsOutputMigration;

  /// Screen-reader description of the outputs of a split transaction; {outputs} is a semicolon-separated list.
  ///
  /// In en, this message translates to:
  /// **'Outputs: {outputs}.'**
  String migrationScheduleSemanticsOutputs(String outputs);

  /// Lowercase screen-reader state of a note whose schedule is not set yet.
  ///
  /// In en, this message translates to:
  /// **'schedule pending'**
  String get migrationScheduleSemanticsPending;

  /// Lowercase screen-reader state of a note waiting for the user to sign.
  ///
  /// In en, this message translates to:
  /// **'ready to sign'**
  String get migrationScheduleSemanticsReadyToSign;

  /// Lowercase screen-reader state of a note that moved to a later block.
  ///
  /// In en, this message translates to:
  /// **'rescheduled from block {from} to block {to}'**
  String migrationScheduleSemanticsRescheduled(String from, String to);

  /// Lowercase screen-reader state of a transaction scheduled for a block height.
  ///
  /// In en, this message translates to:
  /// **'scheduled at block {height}'**
  String migrationScheduleSemanticsScheduled(String height);

  /// Screen-reader description of one split transaction row.
  ///
  /// In en, this message translates to:
  /// **'Split {number}, {amount} ZEC, {state}.'**
  String migrationScheduleSemanticsSplit(
    String number,
    String amount,
    String state,
  );

  /// Lowercase screen-reader state of a split transaction collecting confirmations.
  ///
  /// In en, this message translates to:
  /// **'confirming, {count} of {target} confirmations, projected completion at block {height}'**
  String migrationScheduleSemanticsSplitConfirming(
    String count,
    String target,
    String height,
  );

  /// Lowercase screen-reader state of a note waiting for its migration window.
  ///
  /// In en, this message translates to:
  /// **'waiting for window at block {height}'**
  String migrationScheduleSemanticsWaitingWindow(String height);

  /// Heading above the split transactions of one round.
  ///
  /// In en, this message translates to:
  /// **'Split round {number}'**
  String migrationScheduleSplitRound(String number);

  /// Title of the migration schedule screen.
  ///
  /// In en, this message translates to:
  /// **'Migration Schedule'**
  String get migrationScheduleTitle;

  /// Title of the screen listing the note-splitting transactions.
  ///
  /// In en, this message translates to:
  /// **'Preparation Schedule'**
  String get migrationScheduleTitlePreparation;

  /// [security] Explains that the schedule could not be loaded and the saved migration state is unchanged.
  ///
  /// In en, this message translates to:
  /// **'Vizor couldn\'t load the latest migration schedule. Your saved migration state is unchanged.'**
  String get migrationScheduleUnavailableBody;

  /// Heading shown when the migration schedule cannot be loaded.
  ///
  /// In en, this message translates to:
  /// **'Migration schedule unavailable'**
  String get migrationScheduleUnavailableTitle;

  /// Status of a migration transfer that was sent and awaits mining.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be mined'**
  String get migrationScheduleWaitingToBeMined;

  /// Status of a migration transfer waiting for its time window at a block height.
  ///
  /// In en, this message translates to:
  /// **'Window #{height}'**
  String migrationScheduleWindow(String height);

  /// Screen-reader description of one note in the migration ring; {status} is a short state such as "completed".
  ///
  /// In en, this message translates to:
  /// **'Note {number}: {amount} ZEC, {status}.'**
  String migrationSemanticsNote(String number, String amount, String status);

  /// Screen-reader description of the migration ring: notes are listed in processing order.
  ///
  /// In en, this message translates to:
  /// **'Migration notes in expected processing order.'**
  String get migrationSemanticsNotesOrder;

  /// Screen-reader description of the migration ring while notes are being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing migration notes.'**
  String get migrationSemanticsPreparingNotes;

  /// [security] Button that starts signing one batch of migration transfers; {number} is the batch number.
  ///
  /// In en, this message translates to:
  /// **'Sign Batch #{number}'**
  String migrationSignBatch(String number);

  /// [security] Button that starts signing the next migration batch on the Keystone hardware wallet.
  ///
  /// In en, this message translates to:
  /// **'Sign with Keystone'**
  String get migrationSignWithKeystone;

  /// Step label in the migration progress header: the final stage.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get migrationStageFinish;

  /// Step label in the migration progress header: the migration stage.
  ///
  /// In en, this message translates to:
  /// **'Migration'**
  String get migrationStageMigration;

  /// Step label in the migration progress header: the preparation stage.
  ///
  /// In en, this message translates to:
  /// **'Preparation'**
  String get migrationStagePreparation;

  /// Explains that a recoverable error interrupted the migration.
  ///
  /// In en, this message translates to:
  /// **'Vizor hit a recoverable migration error before completing the Ironwood transition.'**
  String get migrationStatusAttentionBody;

  /// [security] Reassures that no funds are lost and tells the user to retry once Vizor is synced and online.
  ///
  /// In en, this message translates to:
  /// **'No funds are lost. Retry migration after checking that Vizor is synced and online.'**
  String get migrationStatusAttentionFooter;

  /// Heading of the migration status screen after a recoverable error.
  ///
  /// In en, this message translates to:
  /// **'Migration Needs Attention'**
  String get migrationStatusAttentionTitle;

  /// Row label showing how many migration transactions were sent to the network.
  ///
  /// In en, this message translates to:
  /// **'Broadcasted'**
  String get migrationStatusBroadcasted;

  /// Explains that Vizor is sending the prepared migration transaction.
  ///
  /// In en, this message translates to:
  /// **'Vizor is broadcasting the prepared Ironwood migration transaction.'**
  String get migrationStatusBroadcastingBody;

  /// Confirms the funds were moved into the Ironwood pool.
  ///
  /// In en, this message translates to:
  /// **'Your funds have moved into the Ironwood pool.'**
  String get migrationStatusCompleteBody;

  /// Footer note after migration completes.
  ///
  /// In en, this message translates to:
  /// **'You can return home and continue using Vizor.'**
  String get migrationStatusCompleteFooter;

  /// Heading of the migration status screen when migration is finished.
  ///
  /// In en, this message translates to:
  /// **'Migration Complete'**
  String get migrationStatusCompleteTitle;

  /// Explains that the migration transaction was sent and is waiting for confirmations.
  ///
  /// In en, this message translates to:
  /// **'The migration transaction was broadcast. Vizor is waiting for network confirmations.'**
  String get migrationStatusConfirmingBody;

  /// Explains that Vizor is tracking the migration state.
  ///
  /// In en, this message translates to:
  /// **'Vizor is tracking the current Ironwood migration state.'**
  String get migrationStatusDefaultBody;

  /// Disabled button label in an unrecognized migration state.
  ///
  /// In en, this message translates to:
  /// **'Migration in progress'**
  String get migrationStatusDefaultButton;

  /// Footer note: this fallback state is shown only for diagnostics.
  ///
  /// In en, this message translates to:
  /// **'This state is visible for diagnostics while the migration flow is being connected.'**
  String get migrationStatusDefaultFooter;

  /// Heading of the migration status screen in an unrecognized state.
  ///
  /// In en, this message translates to:
  /// **'Migration Status'**
  String get migrationStatusDefaultTitle;

  /// [security] Footer note: the user may leave the screen but must keep the app open so the migration continues.
  ///
  /// In en, this message translates to:
  /// **'You can leave this screen.\nBut keep Vizor open & running.'**
  String get migrationStatusLeaveFooter;

  /// Footer note on the migration status screen for Ledger accounts, whose device flow cannot do batched signing.
  ///
  /// In en, this message translates to:
  /// **'Ledger private migration is not supported because this flow requires batched signing.'**
  String get migrationStatusLedgerUnsupported;

  /// Explains that the private migration is paused before its next step.
  ///
  /// In en, this message translates to:
  /// **'The private migration is paused before the next action.'**
  String get migrationStatusPausedBody;

  /// Disabled button label while the migration is paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get migrationStatusPausedButton;

  /// Footer note: nothing new happens until the migration is resumed.
  ///
  /// In en, this message translates to:
  /// **'No new transaction will be prepared until migration execution is resumed.'**
  String get migrationStatusPausedFooter;

  /// Heading of the migration status screen when the migration is paused.
  ///
  /// In en, this message translates to:
  /// **'Migration Paused'**
  String get migrationStatusPausedTitle;

  /// Row label showing how many migration transactions still have to be sent.
  ///
  /// In en, this message translates to:
  /// **'Pending broadcasts'**
  String get migrationStatusPendingBroadcasts;

  /// Explains how long each note-splitting step usually takes.
  ///
  /// In en, this message translates to:
  /// **'This usually takes around 30 minutes per split.'**
  String get migrationStatusPreparingBody;

  /// Explains that the next step prepares the Ironwood migration batch.
  ///
  /// In en, this message translates to:
  /// **'The private split is ready. The next step will prepare the Ironwood migration batch.'**
  String get migrationStatusReadyBody;

  /// Footer note telling the user to continue so the Ironwood transaction is prepared and sent when due.
  ///
  /// In en, this message translates to:
  /// **'Continue migration to prepare and broadcast the Ironwood transaction when it is due.'**
  String get migrationStatusReadyFooter;

  /// Heading of the migration status screen when the split is done and migration can start.
  ///
  /// In en, this message translates to:
  /// **'Ready to Migrate'**
  String get migrationStatusReadyTitle;

  /// Explains that the migration transaction is ready and waits for its send time.
  ///
  /// In en, this message translates to:
  /// **'Your migration transaction is prepared and waiting for its scheduled broadcast window.'**
  String get migrationStatusScheduledBody;

  /// [security] Footer note: scheduled sends only progress while Vizor is open.
  ///
  /// In en, this message translates to:
  /// **'When Vizor is open, scheduled broadcasts will be advanced by the migration worker.'**
  String get migrationStatusScheduledFooter;

  /// Heading of the migration status screen when the transaction waits for its send time.
  ///
  /// In en, this message translates to:
  /// **'Broadcast Scheduled'**
  String get migrationStatusScheduledTitle;

  /// Row label showing how many note-splitting transactions are done.
  ///
  /// In en, this message translates to:
  /// **'Split progress'**
  String get migrationStatusSplitProgress;

  /// Explains that the migration state could not be verified and no new migration will start meanwhile.
  ///
  /// In en, this message translates to:
  /// **'Vizor couldn\'t verify the current Ironwood migration state. No new migration will start until the status can be checked.'**
  String get migrationStatusUnavailableBody;

  /// Advice on the migration-status-unavailable screen.
  ///
  /// In en, this message translates to:
  /// **'Return home and try again after sync refreshes. If a migration is already in progress, Vizor will continue from the saved state after it can be read.'**
  String get migrationStatusUnavailableHint;

  /// Heading of the screen shown when the migration state cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Migration status unavailable'**
  String get migrationStatusUnavailableTitle;

  /// Label of the summary row showing the current block height.
  ///
  /// In en, this message translates to:
  /// **'Current block'**
  String get migrationSummaryCurrentBlock;

  /// Label of the summary row showing the estimated completion time of the migration.
  ///
  /// In en, this message translates to:
  /// **'Est. completion'**
  String get migrationSummaryEstCompletion;

  /// Label of the summary row showing the ZEC amount that is not migrated yet.
  ///
  /// In en, this message translates to:
  /// **'Left to migrate'**
  String get migrationSummaryLeftToMigrate;

  /// Label of the summary row showing how many migration transactions are complete.
  ///
  /// In en, this message translates to:
  /// **'Overall progress'**
  String get migrationSummaryOverallProgress;

  /// Ring caption naming which transaction of the migration is shown, when the total is not known yet.
  ///
  /// In en, this message translates to:
  /// **'Transaction {ordinal}'**
  String migrationTransactionOrdinal(String ordinal);

  /// Ring caption naming which transaction of the migration is shown, for example "Transaction 2 of 7".
  ///
  /// In en, this message translates to:
  /// **'Transaction {ordinal} of {total}'**
  String migrationTransactionOrdinalOfTotal(String ordinal, String total);

  /// Explains that migration transfers signed before the network upgrade can no longer be sent, and that no funds were lost.
  ///
  /// In en, this message translates to:
  /// **'Transfers signed before the upgrade can’t be sent after it. Your funds are safe.'**
  String get migrationUpgradeStopBody;

  /// Button that starts a new migration of the balance left after the network upgrade stopped the previous one.
  ///
  /// In en, this message translates to:
  /// **'Move remaining balance'**
  String get migrationUpgradeStopMoveRemainingLabel;

  /// Label for the amount already migrated when a network upgrade stopped the migration.
  ///
  /// In en, this message translates to:
  /// **'Moved to Ironwood'**
  String get migrationUpgradeStopMovedLabel;

  /// Label for the amount that remains in the Orchard pool after a network upgrade stopped the migration.
  ///
  /// In en, this message translates to:
  /// **'Still in Orchard'**
  String get migrationUpgradeStopRemainingLabel;

  /// Ironwood migration ring message, split over two lines, shown when the network upgrade stopped a migration partway.
  ///
  /// In en, this message translates to:
  /// **'Stopped by the\nnetwork upgrade'**
  String get migrationUpgradeStopRingMessage;

  /// Button that opens the schedule of migration transfers.
  ///
  /// In en, this message translates to:
  /// **'View Schedule'**
  String get migrationViewSchedule;

  /// Title of the Android system fingerprint prompt shown by the OS when the user turns on fingerprint unlock for the app passcode.
  ///
  /// In en, this message translates to:
  /// **'Enable fingerprint unlock'**
  String get nativeBiometricEnableTitle;

  /// Button in the Android system fingerprint prompt that dismisses it so the user can type the 6-digit app passcode instead.
  ///
  /// In en, this message translates to:
  /// **'Use passcode'**
  String get nativeBiometricUsePasscode;

  /// Body of the iOS notification posted by background work when the next Ironwood migration transfer can be prepared in the app.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to prepare the next migration transfer.'**
  String get nativeIronwoodContinueBody;

  /// Title of the iOS notification posted by background work when the next Ironwood migration transfer can be prepared in the app.
  ///
  /// In en, this message translates to:
  /// **'Continue your Ironwood migration'**
  String get nativeIronwoodContinueTitle;

  /// Body of the iOS notification posted by background work when the Ironwood migration stopped and needs the user in the app.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to review and continue your migration.'**
  String get nativeIronwoodNeedsAttentionBody;

  /// Title of the iOS notification posted by background work when the Ironwood migration stopped and needs the user in the app.
  ///
  /// In en, this message translates to:
  /// **'Ironwood migration needs attention'**
  String get nativeIronwoodNeedsAttentionTitle;

  /// Error the iOS and Android Ledger Bluetooth layer returns when the app sent the Ledger a malformed command; shown in the Ledger error message.
  ///
  /// In en, this message translates to:
  /// **'Ledger APDU arguments are invalid.'**
  String get nativeLedgerApduArgumentsInvalid;

  /// Error the iOS and Android Ledger Bluetooth layer returns when the signing command list the app built is empty or malformed; shown in the Ledger error message.
  ///
  /// In en, this message translates to:
  /// **'Ledger signing APDU list is empty or invalid.'**
  String get nativeLedgerApduListInvalid;

  /// Error the iOS Ledger Bluetooth layer returns when the app timed out waiting for the Ledger to finish opening its Zcash app.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not resume after opening the Zcash app. Try again.'**
  String get nativeLedgerAppSwitchTimedOut;

  /// Error the iOS Ledger Bluetooth layer returns when the phone has no Bluetooth Low Energy support, so it cannot reach a Ledger.
  ///
  /// In en, this message translates to:
  /// **'This device does not support Bluetooth LE.'**
  String get nativeLedgerBleUnsupported;

  /// Error the Android Ledger Bluetooth layer returns when the phone has no Bluetooth Low Energy support, so it cannot reach a Ledger.
  ///
  /// In en, this message translates to:
  /// **'This Android device does not support Bluetooth LE.'**
  String get nativeLedgerBleUnsupportedAndroid;

  /// Error the iOS Ledger Bluetooth layer returns when iOS reports an unknown Bluetooth state.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is unavailable.'**
  String get nativeLedgerBluetoothUnavailable;

  /// Error the Android Ledger Bluetooth layer returns when a command to the Ledger failed for an unexpected reason.
  ///
  /// In en, this message translates to:
  /// **'Could not communicate with Ledger. Try again.'**
  String get nativeLedgerCommunicationFailed;

  /// Error the Android Ledger Bluetooth layer returns when searching for nearby Ledger devices failed.
  ///
  /// In en, this message translates to:
  /// **'Could not discover Ledger devices. Try again.'**
  String get nativeLedgerDiscoveryFailed;

  /// Error the iOS Ledger Bluetooth layer returns when the Ledger answered with data the app could not read.
  ///
  /// In en, this message translates to:
  /// **'Ledger returned an invalid response.'**
  String get nativeLedgerInvalidResponse;

  /// Error the Android Ledger Bluetooth layer returns for an unexpected Ledger failure; {reason} is an untranslated technical code from the Ledger SDK.
  ///
  /// In en, this message translates to:
  /// **'Ledger operation failed: {reason}'**
  String nativeLedgerOperationFailed(String reason);

  /// Error the Android Ledger Bluetooth layer returns when the app asked for Bluetooth permission while an earlier request is still on screen.
  ///
  /// In en, this message translates to:
  /// **'A Ledger permission request is already active.'**
  String get nativeLedgerPermissionRequestActive;

  /// Error the iOS Ledger Bluetooth layer returns when the connected Ledger has no Zcash app installed.
  ///
  /// In en, this message translates to:
  /// **'The Zcash app is not installed on this Ledger.'**
  String get nativeLedgerZcashAppNotInstalled;

  /// Body of the iOS notification shown by the OS when the migration of several accounts stopped; {count} is always 2 or more.
  ///
  /// In en, this message translates to:
  /// **'{count} accounts need attention. Open Vizor to continue.'**
  String nativeMigrationAccountsNeedAttentionBody(String count);

  /// Title of the iOS notification shown by the OS when the migration preparation of one account stopped and needs the user in the app.
  ///
  /// In en, this message translates to:
  /// **'Migration needs attention'**
  String get nativeMigrationNeedsAttentionTitle;

  /// Body of the iOS notification posted by background work when a network upgrade stopped the migration before the whole balance moved.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to move the rest of your balance.'**
  String get nativeMigrationStoppedByUpgradeBody;

  /// Title of the iOS notification posted by background work when a network upgrade stopped the migration before the whole balance moved.
  ///
  /// In en, this message translates to:
  /// **'Migration stopped by network upgrade'**
  String get nativeMigrationStoppedByUpgradeTitle;

  /// Body of the iOS notification posted by background work after it broadcast every scheduled migration transfer.
  ///
  /// In en, this message translates to:
  /// **'All scheduled transfers were submitted. Open Vizor to check the status.'**
  String get nativeMigrationTransfersSentBody;

  /// Title of the iOS notification posted by background work after it broadcast every scheduled migration transfer.
  ///
  /// In en, this message translates to:
  /// **'Migration transfers sent'**
  String get nativeMigrationTransfersSentTitle;

  /// Title of the iOS notification shown by the OS when the migration of several accounts stopped and needs the user in the app.
  ///
  /// In en, this message translates to:
  /// **'Migration updates'**
  String get nativeMigrationUpdatesTitle;

  /// Body of the iOS notification shown by the OS when the migration preparation of one account stopped and needs the user in the app.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to continue.'**
  String get nativeOpenToContinue;

  /// Subtitle of the iOS system background-task progress item when tracking stopped because the user added or removed an account; no trailing period.
  ///
  /// In en, this message translates to:
  /// **'Your wallet accounts changed'**
  String get nativePrepAccountsChanged;

  /// Body of the iOS notification shown by the OS when the preparation transactions of several accounts confirmed; {count} is always 2 or more.
  ///
  /// In en, this message translates to:
  /// **'{count} accounts are ready for the next step. Open Vizor to continue.'**
  String nativePrepAccountsReadyBody(String count);

  /// Subtitle of the iOS system background-task progress item while it waits for migration preparation transactions to confirm; no trailing period.
  ///
  /// In en, this message translates to:
  /// **'Checking transaction confirmations'**
  String get nativePrepCheckingConfirmations;

  /// Title of the iOS system background-task progress item when every migration preparation transaction confirmed.
  ///
  /// In en, this message translates to:
  /// **'Migration preparation complete'**
  String get nativePrepCompleteTitle;

  /// Title of the iOS notification and system background-task item when the current wave of migration preparation transactions confirmed.
  ///
  /// In en, this message translates to:
  /// **'Preparation transactions confirmed'**
  String get nativePrepConfirmedTitle;

  /// Subtitle of the iOS system background-task progress item when every migration preparation transaction confirmed; no trailing period.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to continue your migration'**
  String get nativePrepOpenToContinueMigration;

  /// Subtitle of the iOS system background-task progress item when iOS paused confirmation tracking; no trailing period.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to resume'**
  String get nativePrepOpenToResume;

  /// Subtitle of the iOS system background-task progress item when the current wave of migration preparation transactions confirmed; no trailing period.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to start the next step'**
  String get nativePrepOpenToStartNextStep;

  /// Body of the iOS notification shown by the OS when the migration preparation transactions of one account confirmed.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to start the next step.'**
  String get nativePrepOpenToStartNextStepBody;

  /// Progress line of the iOS system background-task item while migration preparation transactions confirm, used as title or subtitle; no trailing period.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} preparation transactions confirmed'**
  String nativePrepProgress(String completed, String total);

  /// Title of the iOS system background-task progress item when tracking stopped because the user added or removed an account.
  ///
  /// In en, this message translates to:
  /// **'Preparation stopped'**
  String get nativePrepStoppedTitle;

  /// Title of the iOS system background-task progress item while it waits for migration preparation transactions to confirm.
  ///
  /// In en, this message translates to:
  /// **'Preparing your migration'**
  String get nativePrepTaskTitle;

  /// Body of the iOS notification shown by the OS when iOS stopped confirmation tracking for migration preparation before it finished.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor to resume migration preparation.'**
  String get nativePrepTrackingPausedBody;

  /// Title of the iOS notification and system background-task item when iOS stopped confirmation tracking for migration preparation before it finished.
  ///
  /// In en, this message translates to:
  /// **'Preparation tracking paused'**
  String get nativePrepTrackingPausedTitle;

  /// Title of the iOS notification shown by the OS when the preparation transactions of several accounts confirmed.
  ///
  /// In en, this message translates to:
  /// **'Migration preparation updates'**
  String get nativePrepUpdatesTitle;

  /// Body of the macOS alert shown before downloading an app update while Tor is on.
  ///
  /// In en, this message translates to:
  /// **'Updating over Tor may take longer. Turning Tor off switches all Vizor network requests to a direct connection.'**
  String get nativeTorUpdateBody;

  /// Button in the macOS update alert: skip this update.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get nativeTorUpdateCancel;

  /// Button that dismisses the macOS update failure alerts.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get nativeTorUpdateClose;

  /// Button in the macOS update alert: download the update over Tor.
  ///
  /// In en, this message translates to:
  /// **'Continue with Tor'**
  String get nativeTorUpdateContinue;

  /// Body of the macOS alert when turning Tor off for an update failed.
  ///
  /// In en, this message translates to:
  /// **'Tor remains on. Turn it off in Settings, then check for updates again.'**
  String get nativeTorUpdateDisableFailedBody;

  /// Title of the macOS alert when turning Tor off for an update failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t turn off Tor'**
  String get nativeTorUpdateDisableFailedTitle;

  /// Body of the macOS alert when Tor was turned off but the direct update check could not start.
  ///
  /// In en, this message translates to:
  /// **'Tor is off. Check for updates again to continue with a direct connection.'**
  String get nativeTorUpdateRestartFailedBody;

  /// Title of the macOS alert when Tor was turned off but the direct update check could not start.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t restart the update'**
  String get nativeTorUpdateRestartFailedTitle;

  /// Title of the macOS alert shown before downloading an app update while Tor is on.
  ///
  /// In en, this message translates to:
  /// **'Use Tor for this update?'**
  String get nativeTorUpdateTitle;

  /// Button in the macOS update alert: turn Tor off for every request, then download the update directly.
  ///
  /// In en, this message translates to:
  /// **'Turn off Tor and update'**
  String get nativeTorUpdateTurnOff;

  /// Sidebar and tab bar destination: transaction history. Shared by: activity, nav.
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

  /// Toast when the user turns off Tor while a software update is in progress.
  ///
  /// In en, this message translates to:
  /// **'Finish the current software update before turning off Tor.'**
  String get networkPrivacyFinishUpdateBeforeTorOff;

  /// Toast when the user turns on Tor while a software update is in progress.
  ///
  /// In en, this message translates to:
  /// **'Finish the current software update before turning on Tor.'**
  String get networkPrivacyFinishUpdateBeforeTorOn;

  /// Toast at launch when Tor is on but could not connect, so network requests are paused.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect to Tor. Network requests are paused.'**
  String get networkPrivacyTorStartupFailed;

  /// Toast when Tor is connected but the software updater cannot use it.
  ///
  /// In en, this message translates to:
  /// **'Tor is connected, but software updates are unavailable. Turn off Tor to update directly.'**
  String get networkPrivacyTorUpdatesUnavailable;

  /// Toast when software updates are unavailable while other network requests use a direct connection.
  ///
  /// In en, this message translates to:
  /// **'Software updates are unavailable. Other network requests still use a direct connection.'**
  String get networkPrivacyUpdatesUnavailable;

  /// Title of the network settings (endpoint) screen or sheet.
  ///
  /// In en, this message translates to:
  /// **'Network settings'**
  String get networkSettingsTitle;

  /// Dialog button that adds the entered value.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get onboardingAdd;

  /// [security] Visible label of the button that opens the optional BIP39 passphrase (25th word) dialog.
  ///
  /// In en, this message translates to:
  /// **'Add BIP39 Passphrase (Optional)'**
  String get onboardingAddBip39PassphraseOptional;

  /// [security] Accessibility label of the button that opens the optional BIP39 passphrase (25th word) dialog.
  ///
  /// In en, this message translates to:
  /// **'Add BIP39 passphrase'**
  String get onboardingAddBip39PassphraseSemantics;

  /// Body of the shielded address card on the mobile address types step. u1 and zs are literal address prefixes shown in bold; keep them unchanged.
  ///
  /// In en, this message translates to:
  /// **'Address starts with u1 (or zs for legacy).\nOnly you can see your account balance and transaction history.'**
  String get onboardingAddressShieldedBodyMobile;

  /// Explains shielded addresses on the desktop address types step. {unifiedPrefix} and {legacyPrefix} are the literal address prefixes and are shown in bold; keep them unchanged.
  ///
  /// In en, this message translates to:
  /// **'Address starts with {unifiedPrefix} (or {legacyPrefix} for legacy). Only you can see your account balance and transaction history.'**
  String onboardingAddressShieldedDescription(
    String unifiedPrefix,
    String legacyPrefix,
  );

  /// Heading of the shielded address card on the mobile address types step.
  ///
  /// In en, this message translates to:
  /// **'Shielded Address'**
  String get onboardingAddressShieldedTitleMobile;

  /// Explains transparent addresses on the address types step, desktop and mobile.
  ///
  /// In en, this message translates to:
  /// **'Address starts with t, similar to Bitcoin, your address\' balance and transaction history are publicly visible.'**
  String get onboardingAddressTransparentDescription;

  /// Heading of the transparent address card on the mobile address types step.
  ///
  /// In en, this message translates to:
  /// **'Transparent Address'**
  String get onboardingAddressTransparentTitleMobile;

  /// Subtitle of the address types step on desktop and mobile, and of the desktop things-to-know step; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'Zcash has two address types.\nOne for privacy, one for transparency.'**
  String get onboardingAddressTypesSubtitle;

  /// Title of the screen explaining shielded and transparent addresses.
  ///
  /// In en, this message translates to:
  /// **'Zcash Address Types'**
  String get onboardingAddressTypesTitle;

  /// Toast when enabling biometric unlock failed; {method} is the biometric name such as Face ID.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t enable {method}. You can try again in settings.'**
  String onboardingBiometricEnableFailed(String method);

  /// Toast when the user taps enable biometric unlock but the device has none set up; {method} is the biometric name such as Face ID.
  ///
  /// In en, this message translates to:
  /// **'Set up {method} in your device settings first.'**
  String onboardingBiometricSetUpFirst(String method);

  /// Subtitle of the biometric opt-in step; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'This is an easy and fast way to sign in.\nYou can switch back to passcode anytime.'**
  String get onboardingBiometricSubtitle;

  /// Heading of the biometric opt-in step; {method} is the biometric name such as Face ID. The line break matches the design.
  ///
  /// In en, this message translates to:
  /// **'Unlock your wallet\nwith {method}'**
  String onboardingBiometricTitle(String method);

  /// [security] Accessibility label of the clear button inside the BIP39 passphrase field.
  ///
  /// In en, this message translates to:
  /// **'Clear BIP39 passphrase'**
  String get onboardingBip39PassphraseClear;

  /// [security] Explains the BIP39 passphrase (25th word) in the dialog; a different passphrase yields a separate wallet from the same secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Add an optional passphrase (“25th word”) to create/import a separate wallet from the same recovery phrase.'**
  String get onboardingBip39PassphraseExplanation;

  /// [security] Accessibility label of the text field in the BIP39 passphrase dialog.
  ///
  /// In en, this message translates to:
  /// **'BIP39 passphrase'**
  String get onboardingBip39PassphraseFieldLabel;

  /// Placeholder of the BIP39 passphrase field describing the allowed length.
  ///
  /// In en, this message translates to:
  /// **'1–100 characters'**
  String get onboardingBip39PassphraseHint;

  /// [security] Title of the BIP39 passphrase dialog when adding a passphrase.
  ///
  /// In en, this message translates to:
  /// **'BIP39 Passphrase (Optional)'**
  String get onboardingBip39PassphraseTitleOptional;

  /// Button when the user does not know when the wallet was created.
  ///
  /// In en, this message translates to:
  /// **'I can’t remember'**
  String get onboardingBirthdayCantRemember;

  /// Placeholder of the birthday date field. The picked date replaces it, written in your language's numeric order with two-digit month and day (Korean 2026. 05. 25., Chinese 2026/05/25), so write the same order and separators with letter placeholders.
  ///
  /// In en, this message translates to:
  /// **'mm/dd/yyyy'**
  String get onboardingBirthdayDateHint;

  /// Ghost button on the mobile birthday step for users who do not know when the wallet was created.
  ///
  /// In en, this message translates to:
  /// **'I don’t remember'**
  String get onboardingBirthdayDontRemember;

  /// Tab for entering the wallet birthday as a block height.
  ///
  /// In en, this message translates to:
  /// **'Enter the block height'**
  String get onboardingBirthdayEnterBlockHeight;

  /// Tab for entering the wallet birthday as a date.
  ///
  /// In en, this message translates to:
  /// **'Enter the date'**
  String get onboardingBirthdayEnterDate;

  /// Tab label on the iOS birthday step for entering a month.
  ///
  /// In en, this message translates to:
  /// **'Enter the month'**
  String get onboardingBirthdayEnterMonth;

  /// Error when the birthday height could not be estimated.
  ///
  /// In en, this message translates to:
  /// **'Could not estimate the wallet birthday height.'**
  String get onboardingBirthdayEstimateFailed;

  /// Hint under the block height field before the chain tip is known; {height} is the lowest allowed block height.
  ///
  /// In en, this message translates to:
  /// **'At least {height}.'**
  String onboardingBirthdayHeightAtLeast(String height);

  /// Hint under the block height field; {min} and {max} are the lowest and highest allowed block heights.
  ///
  /// In en, this message translates to:
  /// **'Between {min} and {max}.'**
  String onboardingBirthdayHeightBetween(String min, String max);

  /// Inline error under the block height field when the number is outside the valid range.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t seem like a legit block height'**
  String get onboardingBirthdayInvalidHeight;

  /// Error when the data for the birthday step could not load.
  ///
  /// In en, this message translates to:
  /// **'Could not load wallet birthday metadata.'**
  String get onboardingBirthdayMetadataFailed;

  /// Inline error on the mobile birthday step when the chosen date could not be converted to a block height.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t estimate a height for that date. Enter a block height instead.'**
  String get onboardingBirthdayMobileEstimateFailed;

  /// Placeholder of the iOS birthday month field. The picked month replaces it in your language's numeric order (Korean 2026. 05., Chinese 2026/05), so write the same order and separators with letter placeholders.
  ///
  /// In en, this message translates to:
  /// **'mm/yyyy'**
  String get onboardingBirthdayMonthHint;

  /// Accessibility label of the Android birthday field that opens the date picker.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get onboardingBirthdayPickDate;

  /// Accessibility label of the iOS birthday field that opens the month picker.
  ///
  /// In en, this message translates to:
  /// **'Pick a month'**
  String get onboardingBirthdayPickMonth;

  /// Primary button on Android that opens the date picker of the birthday step.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get onboardingBirthdaySelectDate;

  /// Primary button on iOS that opens the month picker of the birthday step.
  ///
  /// In en, this message translates to:
  /// **'Select month'**
  String get onboardingBirthdaySelectMonth;

  /// Status line on the mobile birthday step while the block height for the chosen date is being estimated.
  ///
  /// In en, this message translates to:
  /// **'Estimating height...'**
  String get onboardingBirthdayStatusEstimating;

  /// Status line on the mobile birthday step while the wallet is being imported.
  ///
  /// In en, this message translates to:
  /// **'Importing wallet...'**
  String get onboardingBirthdayStatusImporting;

  /// Status line on the mobile birthday step while the running sync is paused before importing.
  ///
  /// In en, this message translates to:
  /// **'Pausing sync...'**
  String get onboardingBirthdayStatusPausingSync;

  /// Subtitle of the mobile birthday step; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'An estimate is enough — sync starts\nfrom there.'**
  String get onboardingBirthdaySubtitleMobile;

  /// Title of the wallet birthday step.
  ///
  /// In en, this message translates to:
  /// **'Around when did you create your wallet?'**
  String get onboardingBirthdayTitle;

  /// Placeholder of the block height field.
  ///
  /// In en, this message translates to:
  /// **'Block height'**
  String get onboardingBlockHeight;

  /// Error shown when creating a wallet fails because the current Zcash block height could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'We need the current Zcash block height to create your wallet. Check your network connection and try again.'**
  String get onboardingBlockHeightRequired;

  /// Disabled primary button label while the import looks for additional accounts of the same secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Checking accounts...'**
  String get onboardingCheckingAccounts;

  /// Subtitle of the desktop hardware wallet picker.
  ///
  /// In en, this message translates to:
  /// **'Select your hardware wallet.'**
  String get onboardingConnectHardwareSubtitleDesktop;

  /// Subtitle of the mobile hardware wallet picker.
  ///
  /// In en, this message translates to:
  /// **'Select your hardware device.'**
  String get onboardingConnectHardwareSubtitleMobile;

  /// Heading of the hardware wallet picker on desktop and mobile; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Connect\nHardware Wallet'**
  String get onboardingConnectHardwareTitle;

  /// Option on the import method picker for importing an account from a hardware wallet.
  ///
  /// In en, this message translates to:
  /// **'Connect hardware wallet'**
  String get onboardingConnectHardwareWallet;

  /// Import method and screen title for connecting a Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Connect Keystone'**
  String get onboardingConnectKeystone;

  /// Confirm button of the desktop unknown-birthday dialog.
  ///
  /// In en, this message translates to:
  /// **'Continue Anyway'**
  String get onboardingContinueAnywayDesktop;

  /// Disabled primary button label while the new wallet is being created.
  ///
  /// In en, this message translates to:
  /// **'Creating wallet...'**
  String get onboardingCreatingWallet;

  /// Subtitle under the customise-account heading.
  ///
  /// In en, this message translates to:
  /// **'Add personality to your account by setting an account name and choosing a profile picture.'**
  String get onboardingCustomiseAccountSubtitle;

  /// Instruction under the additional accounts title; the user ticks the accounts to import.
  ///
  /// In en, this message translates to:
  /// **'Choose the additional accounts to import.'**
  String get onboardingDiscoverySubtitle;

  /// Title of the dialog shown when the secret passphrase has more accounts with activity than the first one.
  ///
  /// In en, this message translates to:
  /// **'Additional accounts found'**
  String get onboardingDiscoveryTitle;

  /// Error under the import form when the imported account is already in this wallet.
  ///
  /// In en, this message translates to:
  /// **'This account is already in your wallet.'**
  String get onboardingDuplicateAccount;

  /// Error on the Keystone import screen when that hardware account is already in this wallet.
  ///
  /// In en, this message translates to:
  /// **'This Keystone account is already in your wallet.'**
  String get onboardingDuplicateKeystoneAccount;

  /// Error on the Ledger import screen when that hardware account is already in this wallet.
  ///
  /// In en, this message translates to:
  /// **'This Ledger account is already in your wallet.'**
  String get onboardingDuplicateLedgerAccount;

  /// [security] Accessibility label of the bar that reopens the BIP39 passphrase dialog for editing.
  ///
  /// In en, this message translates to:
  /// **'Edit BIP39 passphrase'**
  String get onboardingEditBip39Passphrase;

  /// Placeholder inside the wallet password field on the unlock screen.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get onboardingEnterPassword;

  /// Button label while the birthday height is estimated from a date.
  ///
  /// In en, this message translates to:
  /// **'Estimating...'**
  String get onboardingEstimating;

  /// Primary button on the last customise-account step that creates the wallet and finishes onboarding.
  ///
  /// In en, this message translates to:
  /// **'Finish setup'**
  String get onboardingFinishSetup;

  /// [security] Title of the final confirmation sheet before the app is reset.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get onboardingForgotPasscodeAreYouSure;

  /// [security] Explains that a forgotten passcode can only be fixed by wiping the app, which deletes all accounts and unshared gift card links.
  ///
  /// In en, this message translates to:
  /// **'If you can\'t remember your passcode, the only way to recover your account is to completely reset the Vizor app, which means deleting all accounts and requiring you to import accounts again. Unshared gift card links will be permanently lost.'**
  String get onboardingForgotPasscodeBody;

  /// [security] First line of the final reset confirmation, shown in red; the trailing line break separates it from the next sentence.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.\n'**
  String get onboardingForgotPasscodeCantBeUndone;

  /// [security] Destructive-flow button in the forgot-passcode sheet that goes on to the final reset confirmation.
  ///
  /// In en, this message translates to:
  /// **'Continue to reset Vizor'**
  String get onboardingForgotPasscodeContinueToReset;

  /// [security] Second line of the final reset confirmation; the user accepts responsibility for the loss of data.
  ///
  /// In en, this message translates to:
  /// **'Proceed on your responsibility.'**
  String get onboardingForgotPasscodeProceed;

  /// [security] Title of the sheet shown from the unlock screen when the user cannot remember the passcode.
  ///
  /// In en, this message translates to:
  /// **'Forgot Passcode?'**
  String get onboardingForgotPasscodeTitle;

  /// [security] Warning in the forgot-passcode sheet: without a backed-up secret passphrase, the funds are lost after a reset.
  ///
  /// In en, this message translates to:
  /// **'If you haven’t backed up an account’s secret passphrase, you can’t recover its funds after resetting Vizor.'**
  String get onboardingForgotPasscodeUnbackedWarning;

  /// Button on the desktop unlock screen that opens the lost-password flow.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get onboardingForgotPassword;

  /// Closing line of the Zcash intro shown after redeeming a gift card, desktop and mobile.
  ///
  /// In en, this message translates to:
  /// **'Your wallet is ready. Learn how Zcash protects your privacy and which address to use.'**
  String get onboardingGiftEducationClosing;

  /// Toast on the post-gift education steps when marking them as completed failed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save your progress. Try again.'**
  String get onboardingGiftEducationSaveFailed;

  /// Cancel button of the desktop unknown-birthday dialog that returns to the birthday step.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get onboardingGoBackDesktop;

  /// Description of the hardware wallet option when only Keystone is available.
  ///
  /// In en, this message translates to:
  /// **'Keystone wallet'**
  String get onboardingHardwareKeystoneOnly;

  /// Description of the hardware wallet option when both Ledger and Keystone are available.
  ///
  /// In en, this message translates to:
  /// **'Ledger or Keystone wallet'**
  String get onboardingHardwareLedgerOrKeystone;

  /// Ghost button on the Zcash intro that skips the education steps.
  ///
  /// In en, this message translates to:
  /// **'I know how to use Zcash'**
  String get onboardingIKnowHowToUseZcash;

  /// Button that confirms importing the selected accounts.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get onboardingImport;

  /// [security] Subtitle on the desktop import step listing the allowed secret passphrase lengths.
  ///
  /// In en, this message translates to:
  /// **'Accept 12, 15, 18, 21, or 24 words.'**
  String get onboardingImportAcceptWordCounts;

  /// [security] Toast on the mobile import step when the pasted secret passphrase could not be checked.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check secret passphrase'**
  String get onboardingImportCheckFailedError;

  /// Toast on the mobile import step when the clipboard has no text.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get onboardingImportClipboardEmpty;

  /// Toast on the mobile import step when the clipboard could not be read.
  ///
  /// In en, this message translates to:
  /// **'Can\'t read the clipboard'**
  String get onboardingImportClipboardReadError;

  /// [security] Accessibility label of the card that opens the manual word-by-word entry.
  ///
  /// In en, this message translates to:
  /// **'Enter secret passphrase manually'**
  String get onboardingImportEnterManuallySemantics;

  /// Description of the Keystone option on the hardware wallet picker.
  ///
  /// In en, this message translates to:
  /// **'Import from Keystone wallet'**
  String get onboardingImportFromKeystone;

  /// Description of the Ledger option on the hardware wallet picker.
  ///
  /// In en, this message translates to:
  /// **'Import from Ledger wallet'**
  String get onboardingImportFromLedger;

  /// [security] Toast on the mobile import step when the pasted words are not a valid secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Invalid secret passphrase'**
  String get onboardingImportInvalidPhraseError;

  /// [security] Inline error on the desktop import step when the typed secret passphrase is not valid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid secret passphrase with 12, 15, 18, 21, or 24 words.'**
  String get onboardingImportInvalidSecretPassphrase;

  /// Subtitle on the manual entry card.
  ///
  /// In en, this message translates to:
  /// **'Word by word.'**
  String get onboardingImportManualCardSubtitle;

  /// [security] Title on the card that opens manual word-by-word entry; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Manually Enter\nSecret Passphrase'**
  String get onboardingImportManualCardTitle;

  /// Subtitle of the import method picker.
  ///
  /// In en, this message translates to:
  /// **'Select the method you want.'**
  String get onboardingImportMethodSubtitle;

  /// Heading of the screen where the user picks how to import an account; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Import Account\nto Vizor'**
  String get onboardingImportMethodTitle;

  /// [security] Toast on the mobile import step when the pasted text contains no secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'No secret passphrase found'**
  String get onboardingImportNoPhraseError;

  /// Button on the mobile import step that pastes a secret passphrase from the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Or paste from clipboard'**
  String get onboardingImportPasteFromClipboard;

  /// [security] Subtitle of the mobile import step listing the allowed secret passphrase lengths; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'Accept 12, 15, 18, 21, or 24-word\nsecret passphrases'**
  String get onboardingImportPasteHelper;

  /// Label of the paste button while the clipboard is being read.
  ///
  /// In en, this message translates to:
  /// **'Reading clipboard data...'**
  String get onboardingImportReadingClipboard;

  /// [security] Option on the import method picker for importing a wallet from its secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Import secret passphrase'**
  String get onboardingImportSecretPassphrase;

  /// Description of the secret passphrase option on the desktop import method picker.
  ///
  /// In en, this message translates to:
  /// **'Vizor or any other Zcash wallet'**
  String get onboardingImportSecretPassphraseDescriptionDesktop;

  /// Description of the secret passphrase option on the mobile import method picker.
  ///
  /// In en, this message translates to:
  /// **'Vizor, ZODL, or any other wallet'**
  String get onboardingImportSecretPassphraseDescriptionMobile;

  /// Heading of the desktop step where the user enters their secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Import a Wallet'**
  String get onboardingImportWalletTitle;

  /// Heading of the mobile step where the user imports a secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Import Wallet'**
  String get onboardingImportWalletTitleMobile;

  /// Explains what shielded transactions hide, in the Zcash intro card on desktop and mobile.
  ///
  /// In en, this message translates to:
  /// **'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount — verified by cryptography, not trust.'**
  String get onboardingIntroCard;

  /// Closing line of the desktop Zcash intro step above the buttons; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'You\'re a few steps away from your first private wallet.\nLet\'s get you set up.'**
  String get onboardingIntroClosing;

  /// Closing paragraph of the mobile Zcash intro step above the buttons.
  ///
  /// In en, this message translates to:
  /// **'You\'re a few steps away from your first private wallet. Let\'s get you set up.'**
  String get onboardingIntroClosingMobile;

  /// Subtitle of the Zcash intro step; also used on the import birthday step.
  ///
  /// In en, this message translates to:
  /// **'Zcash (ZEC) built around financial privacy & self-custody.'**
  String get onboardingIntroSubtitle;

  /// Subtitle of the mobile Zcash intro step; the line break matches the design.
  ///
  /// In en, this message translates to:
  /// **'Zcash (ZEC) built around financial\nprivacy & self-custody.'**
  String get onboardingIntroSubtitleMobile;

  /// Heading of the Zcash intro step.
  ///
  /// In en, this message translates to:
  /// **'The Shielded World'**
  String get onboardingIntroTitle;

  /// Option on the mobile import method picker for linking accounts from the Vizor desktop app.
  ///
  /// In en, this message translates to:
  /// **'Link Vizor Desktop'**
  String get onboardingLinkVizorDesktop;

  /// Description of the option that links accounts from the Vizor desktop app by scanning a QR code.
  ///
  /// In en, this message translates to:
  /// **'Scan & connect to Vizor Desktop'**
  String get onboardingLinkVizorDesktopDescription;

  /// [security] Explanation on the lost-password screen. {resetAction} and {importAction} are bold phrases supplied by onboardingLostPasswordResetAction and onboardingLostPasswordImportAction; keep them in the sentence. The line breaks match the design.
  ///
  /// In en, this message translates to:
  /// **'If you\'ve lost your password, the only way to recover\nyour account is to {resetAction}.\nThis deletes all accounts and unshared gift card links.\nYou will need to {importAction}.'**
  String onboardingLostPasswordBody(String resetAction, String importAction);

  /// Bold phrase inside onboardingLostPasswordBody; the user has to import their accounts again after the reset.
  ///
  /// In en, this message translates to:
  /// **'import accounts again'**
  String get onboardingLostPasswordImportAction;

  /// [security] Bold phrase inside onboardingLostPasswordBody; the action of wiping the whole app. Written so that it fits after 'the only way ... is to'.
  ///
  /// In en, this message translates to:
  /// **'completely reset Vizor app'**
  String get onboardingLostPasswordResetAction;

  /// Disabled label of the destructive reset button while its safety countdown runs; {seconds} is the number of seconds left.
  ///
  /// In en, this message translates to:
  /// **'Reset after {seconds}s...'**
  String onboardingLostPasswordResetCountdown(int seconds);

  /// Heading of the lost-password screen.
  ///
  /// In en, this message translates to:
  /// **'Lost password?'**
  String get onboardingLostPasswordTitle;

  /// [security] Inline error under the word field when the typed word is not in the secret passphrase word list.
  ///
  /// In en, this message translates to:
  /// **'Invalid secret passphrase word.'**
  String get onboardingManualInvalidWord;

  /// Button on the manual import step that accepts the typed word and moves to the next one.
  ///
  /// In en, this message translates to:
  /// **'Next word'**
  String get onboardingManualNextWord;

  /// [security] Notice after pasting several words: the fill stopped at {word} because it is not a valid secret passphrase word. {word} is the first invalid word.
  ///
  /// In en, this message translates to:
  /// **'Stopped at \'{word}\' — it isn\'t in the passphrase word list.'**
  String onboardingManualStoppedAt(String word);

  /// [security] Subtitle of the mobile manual import step listing the allowed secret passphrase lengths.
  ///
  /// In en, this message translates to:
  /// **'Accept 12, 15, 18, 21 or 24 words'**
  String get onboardingManualSubtitle;

  /// [security] Heading of the mobile manual import step.
  ///
  /// In en, this message translates to:
  /// **'Enter your Secret Passphrase'**
  String get onboardingManualTitle;

  /// Button on the manual import step that removes the most recently accepted word.
  ///
  /// In en, this message translates to:
  /// **'Undo last word'**
  String get onboardingManualUndoLastWord;

  /// Disabled button label while the custom endpoint is being verified.
  ///
  /// In en, this message translates to:
  /// **'Checking endpoint…'**
  String get onboardingNetworkCheckingEndpoint;

  /// Helper text under the custom endpoint field; the server must be a lightwalletd server for the wallet's Zcash network.
  ///
  /// In en, this message translates to:
  /// **'Use a lightwalletd server for this wallet’s network.'**
  String get onboardingNetworkEndpointHelper;

  /// Error on the network settings sheet when the custom endpoint did not respond as a valid lightwalletd server.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify that endpoint. Check the address and try again.'**
  String get onboardingNetworkVerifyFailed;

  /// Primary button that moves to the next step.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Ghost button that skips an optional step for now.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get onboardingNotNow;

  /// [security] Heading of the step where the user chooses the 6-digit passcode of the wallet on mobile.
  ///
  /// In en, this message translates to:
  /// **'Create Passcode'**
  String get onboardingPasscodeCreateTitle;

  /// Accessibility label of a passcode keypad key; {digit} is the number on the key.
  ///
  /// In en, this message translates to:
  /// **'Digit {digit}'**
  String onboardingPasscodeDigitSemantics(int digit);

  /// [security] Subtitle of the confirm-passcode step.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your passcode.'**
  String get onboardingPasscodeReEnter;

  /// Subtitle of the create-passcode step while the wallet is being set up.
  ///
  /// In en, this message translates to:
  /// **'Setting up your wallet...'**
  String get onboardingPasscodeSettingUp;

  /// Tooltip and accessibility label of the dice button that picks a random account name and profile picture during account setup.
  ///
  /// In en, this message translates to:
  /// **'Randomise account name and profile picture'**
  String get onboardingRandomiseAccountPersona;

  /// Disabled primary button label while an interrupted wallet setup is being recovered.
  ///
  /// In en, this message translates to:
  /// **'Recovering wallet...'**
  String get onboardingRecoveringWallet;

  /// [security] Error on the mobile unlock screen when resetting the app after a forgotten passcode failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset the app. Please try again.'**
  String get onboardingResetAppFailed;

  /// Error shown on the final onboarding step when recovering an interrupted setup failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t resume setup. Please try again.'**
  String get onboardingResumeSetupFailed;

  /// Primary button on the final onboarding step that resumes an interrupted setup.
  ///
  /// In en, this message translates to:
  /// **'Retry setup'**
  String get onboardingRetrySetup;

  /// Label of the retry button on the startup failure screen while a retry is running.
  ///
  /// In en, this message translates to:
  /// **'Retrying'**
  String get onboardingRetrying;

  /// [security] Button on the review step that discards the entered secret passphrase and goes back.
  ///
  /// In en, this message translates to:
  /// **'Clear secret passphrase'**
  String get onboardingReviewClearSecretPassphrase;

  /// Primary button on the review step that accepts the secret passphrase and goes on to the birthday step.
  ///
  /// In en, this message translates to:
  /// **'Confirm & continue'**
  String get onboardingReviewConfirmContinue;

  /// [security] Subtitle of the review step; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'Review your secret passphrase\nbefore import starts.'**
  String get onboardingReviewImportSubtitle;

  /// [security] Heading of the step where the user reviews the entered secret passphrase before importing.
  ///
  /// In en, this message translates to:
  /// **'Review Import'**
  String get onboardingReviewImportTitle;

  /// Disabled primary button label while the already-created wallet is being saved after a retry.
  ///
  /// In en, this message translates to:
  /// **'Saving wallet...'**
  String get onboardingSavingWallet;

  /// [security] Heading of the cover shown before the secret passphrase is revealed on desktop.
  ///
  /// In en, this message translates to:
  /// **'You are about to see your Secret Passphrase.'**
  String get onboardingSecretPassphraseAboutToSee;

  /// [security] Heading of the cover shown before the secret passphrase is revealed on mobile; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'You are about to see your\nSecret Passphrase.'**
  String get onboardingSecretPassphraseAboutToSeeMobile;

  /// [security] Primary button on the desktop step that reveals the secret passphrase for the first time.
  ///
  /// In en, this message translates to:
  /// **'Reveal the phrase'**
  String get onboardingSecretPassphraseReveal;

  /// [security] Primary button on the mobile step that reveals the secret passphrase.
  ///
  /// In en, this message translates to:
  /// **'Reveal phrase'**
  String get onboardingSecretPassphraseRevealMobile;

  /// [security] Subtitle under the Secret Passphrase heading on desktop.
  ///
  /// In en, this message translates to:
  /// **'The master key to your wallet.'**
  String get onboardingSecretPassphraseSubtitleDesktop;

  /// [security] Subtitle under the Secret Passphrase heading on mobile.
  ///
  /// In en, this message translates to:
  /// **'The Master Key to your wallet.'**
  String get onboardingSecretPassphraseSubtitleMobile;

  /// [security] Warning on the cover before the secret passphrase is revealed, desktop and mobile. Must not be softened.
  ///
  /// In en, this message translates to:
  /// **'This phrase is the master key to your funds. Keep it safe, keep it secret. If you lose it, no one can help you recover your wallet. Not even us.'**
  String get onboardingSecretPassphraseWarning;

  /// [security] Placeholder inside an empty secret passphrase word box.
  ///
  /// In en, this message translates to:
  /// **'Seed word'**
  String get onboardingSeedWordHint;

  /// Primary button on the desktop set-password step that saves the password and completes setup.
  ///
  /// In en, this message translates to:
  /// **'Set password & finish'**
  String get onboardingSetPasswordAndFinish;

  /// [security] Placeholder in the new wallet password field describing the password rules.
  ///
  /// In en, this message translates to:
  /// **'Min. 8 characters and symbols'**
  String get onboardingSetPasswordPlaceholder;

  /// Subtitle under the set-password heading on desktop.
  ///
  /// In en, this message translates to:
  /// **'Set password for signing in to Vizor wallet.'**
  String get onboardingSetPasswordSubtitle;

  /// Disabled primary button label while the wallet password is being saved.
  ///
  /// In en, this message translates to:
  /// **'Setting password...'**
  String get onboardingSettingPassword;

  /// Error shown on the final onboarding step when account setup was cut off part-way; the primary button retries and recovers the wallet.
  ///
  /// In en, this message translates to:
  /// **'Setup interrupted. Retry to recover your wallet.'**
  String get onboardingSetupInterrupted;

  /// Sidebar step label for the explanation of shielded and transparent address types.
  ///
  /// In en, this message translates to:
  /// **'Address types'**
  String get onboardingStepAddressTypes;

  /// Step and screen title for importing contacts from a linked wallet.
  ///
  /// In en, this message translates to:
  /// **'Import contacts'**
  String get onboardingStepImportContacts;

  /// Sidebar step label for the introduction to Zcash during wallet creation.
  ///
  /// In en, this message translates to:
  /// **'Intro to Zcash'**
  String get onboardingStepIntroToZcash;

  /// [security] Onboarding step for setting the wallet password.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get onboardingStepSetPassword;

  /// Onboarding step and back-link name for choosing the wallet birthday height.
  ///
  /// In en, this message translates to:
  /// **'Wallet Birthday Height'**
  String get onboardingStepWalletBirthdayHeight;

  /// Button label while sync is stopped before import.
  ///
  /// In en, this message translates to:
  /// **'Stop syncing...'**
  String get onboardingStopSyncing;

  /// Body of the startup failure screen when the wallet database migration failed.
  ///
  /// In en, this message translates to:
  /// **'Vizor needs to update the local wallet database before opening this version. Try again, or quit and restart Vizor.'**
  String get onboardingStorageDbMigrationBody;

  /// Title of the startup failure screen when the wallet database could not be migrated.
  ///
  /// In en, this message translates to:
  /// **'Unable to update wallet database'**
  String get onboardingStorageDbMigrationTitle;

  /// Body of the Linux startup screen when the system keyring is locked.
  ///
  /// In en, this message translates to:
  /// **'Vizor needs access to the system keyring before it can open your wallet. Unlock the keyring, then try again.'**
  String get onboardingStorageKeyringLockedBody;

  /// Error shown on the startup failure screen after the user retried and the device secure storage could still not be opened.
  ///
  /// In en, this message translates to:
  /// **'Secure storage is still unavailable.'**
  String get onboardingStorageRetrySecureStorageFailed;

  /// Error shown on the startup failure screen after the user retried and the wallet database migration failed again.
  ///
  /// In en, this message translates to:
  /// **'The wallet database update still failed.'**
  String get onboardingStorageRetryWalletDbFailed;

  /// Body of the startup screen when the device secure storage is locked or unavailable.
  ///
  /// In en, this message translates to:
  /// **'Vizor needs access to secure storage before it can open your wallet. Unlock secure storage, then try again.'**
  String get onboardingStorageSecureStorageLockedBody;

  /// Title of the startup screen when the device secure storage is locked or unavailable.
  ///
  /// In en, this message translates to:
  /// **'Secure storage is locked'**
  String get onboardingStorageSecureStorageLockedTitle;

  /// Body of the startup failure screen when the app's local startup state could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not load the local startup state. Try again, or quit and restart Vizor.'**
  String get onboardingStorageStartupFailureBody;

  /// Detail line on the startup failure screen.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not load its startup state.'**
  String get onboardingStorageStartupFailureDetail;

  /// Inline onboarding error when creating or importing an account failed for a reason Vizor has no message for. Shown on one line; the cause is only logged.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t finish this step. Try again.'**
  String get onboardingSubmitFailed;

  /// Primary button on the Zcash education steps that continues to the next explanation.
  ///
  /// In en, this message translates to:
  /// **'Tell me how Zcash works'**
  String get onboardingTellMeHowZcashWorks;

  /// Body of the keep-privacy fact on the things-to-know step; advises using the transparent address for exchange withdrawals and shielding afterwards.
  ///
  /// In en, this message translates to:
  /// **'Some exchanges can\'t send to shielded addresses. If you\'re withdrawing from an exchange, use your transparent address. You can shield your ZEC after it arrives.'**
  String get onboardingThingsKeepPrivacyBody;

  /// Heading of the second fact on the things-to-know step.
  ///
  /// In en, this message translates to:
  /// **'How to keep privacy'**
  String get onboardingThingsKeepPrivacyTitle;

  /// Subtitle of the mobile things-to-know step.
  ///
  /// In en, this message translates to:
  /// **'Before you dive in.'**
  String get onboardingThingsSubtitleMobile;

  /// Body of the time-to-sync fact on the things-to-know step.
  ///
  /// In en, this message translates to:
  /// **'Your wallet syncs directly with the Zcash network instead of relying on a server. This protects your privacy, but takes a moment. Your funds are safe while the app catches up.'**
  String get onboardingThingsTimeToSyncBody;

  /// Heading of the first fact on the things-to-know step: the wallet needs a while to sync.
  ///
  /// In en, this message translates to:
  /// **'Time to sync'**
  String get onboardingThingsTimeToSyncTitle;

  /// Sidebar step label and heading of the step that lists a few facts to know before using the wallet.
  ///
  /// In en, this message translates to:
  /// **'Things to know'**
  String get onboardingThingsToKnow;

  /// Explains that skipping the wallet birthday makes Vizor scan from the earliest supported shielded block, which is safe but slow.
  ///
  /// In en, this message translates to:
  /// **'If you continue without a wallet birthday, Vizor will scan from the earliest supported shielded height. This is safe, but the first sync can take a very long time.'**
  String get onboardingUnknownHeightBody;

  /// Tip under the unknown-birthday explanation; an approximate date speeds up the first sync.
  ///
  /// In en, this message translates to:
  /// **'Choosing even an approximate date will be much faster.'**
  String get onboardingUnknownHeightHint;

  /// Title of the confirmation shown when the user does not know the wallet birthday, desktop and mobile.
  ///
  /// In en, this message translates to:
  /// **'Import from the earliest height?'**
  String get onboardingUnknownHeightTitle;

  /// Reason line shown in the system biometric prompt when the wallet is unlocked with Face ID, Touch ID or fingerprint.
  ///
  /// In en, this message translates to:
  /// **'Unlock your wallet'**
  String get onboardingUnlockBiometricReason;

  /// Subtitle on the desktop unlock screen asking for the wallet password.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to open Vizor.'**
  String get onboardingUnlockDescription;

  /// Subtitle of the mobile unlock screen asking for the 6-digit passcode.
  ///
  /// In en, this message translates to:
  /// **'Enter your passcode to open Vizor'**
  String get onboardingUnlockEnterPasscode;

  /// [security] Error under the password field on the desktop unlock screen when the typed wallet password is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Try again.'**
  String get onboardingUnlockIncorrectPassword;

  /// Error under the password field on the desktop unlock screen when unlocking failed because of an unexpected error.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open your wallet. Please try again.'**
  String get onboardingUnlockOpenFailed;

  /// Subtitle of the mobile unlock screen while the wallet is being opened after the passcode was entered.
  ///
  /// In en, this message translates to:
  /// **'Opening your wallet...'**
  String get onboardingUnlockOpening;

  /// Heading of the desktop unlock screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get onboardingUnlockWelcomeBack;

  /// Error when a wallet link from another device was made on another Zcash network (for example testnet) than this app or wallet.
  ///
  /// In en, this message translates to:
  /// **'This wallet link is for a different Zcash network.'**
  String get onboardingWalletLinkNetworkMismatch;

  /// Name of the Welcome screen, used in back links.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get onboardingWelcome;

  /// Button on the welcome screen that starts redeeming a gift card.
  ///
  /// In en, this message translates to:
  /// **'Activate gift card'**
  String get onboardingWelcomeActivateGiftCard;

  /// Primary button on the welcome screen that starts creating a new wallet.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingWelcomeGetStarted;

  /// Button on the welcome screen that starts importing an existing wallet.
  ///
  /// In en, this message translates to:
  /// **'Import wallet'**
  String get onboardingWelcomeImportWallet;

  /// [security] Title of the step that repeats a new 6-digit passcode.
  ///
  /// In en, this message translates to:
  /// **'Confirm Passcode'**
  String get passcodeConfirmTitle;

  /// [security] Error when the entered 6-digit passcode is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect Passcode'**
  String get passcodeIncorrect;

  /// [security] Hint that a passcode has 6 digits.
  ///
  /// In en, this message translates to:
  /// **'6 digits length'**
  String get passcodeSixDigits;

  /// [security] Error when the two new passcode entries differ.
  ///
  /// In en, this message translates to:
  /// **'Passcodes didn\'t match. Try again.'**
  String get passcodesDidNotMatch;

  /// [security] Error when the wallet password could not be checked.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your password. Please try again.'**
  String get passwordCheckFailed;

  /// [security] Label of the field that repeats a new wallet password.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get passwordConfirmLabel;

  /// [security] Error when the entered wallet password is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Please try again.'**
  String get passwordIncorrect;

  /// [security] Label of a wallet password field.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// Validation message when a wallet password contains characters other than printable English letters, numbers and symbols.
  ///
  /// In en, this message translates to:
  /// **'Use only English letters, numbers, and symbols.'**
  String get passwordPolicyAscii;

  /// Validation message when a wallet password is shorter than the minimum; {min} is the minimum length.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {min} characters.'**
  String passwordPolicyMinLength(int min);

  /// Validation message when the new wallet password equals the current one.
  ///
  /// In en, this message translates to:
  /// **'Use a different password.'**
  String get passwordPolicyMustDiffer;

  /// [security] Error when the two new password entries differ.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get passwordsDoNotMatch;

  /// Button that saves the new Pay recipient address to the address book.
  ///
  /// In en, this message translates to:
  /// **'Add to contacts'**
  String get payAddToContacts;

  /// Accessibility label of the read-only address in the mobile Pay add-contact card.
  ///
  /// In en, this message translates to:
  /// **'Address {address}'**
  String payAddressSemantics(String address);

  /// Accessibility label of the asset picker on the mobile Pay amount step.
  ///
  /// In en, this message translates to:
  /// **'Choose payment asset'**
  String get payAmountChooseAsset;

  /// Accessibility label of the toggle that switches the mobile Pay amount input to the asset.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in {symbol}'**
  String payAmountEnterIn(String symbol);

  /// Label before the estimated ZEC cost on the mobile Pay amount step.
  ///
  /// In en, this message translates to:
  /// **'Estimated:'**
  String get payAmountEstimated;

  /// Label before the estimated ZEC cost on the desktop Pay amount step.
  ///
  /// In en, this message translates to:
  /// **'Estimated spend'**
  String get payAmountEstimatedSpend;

  /// Text before the shielded balance chip on the desktop Pay amount step; reads 'Paying from your Shielded balance'.
  ///
  /// In en, this message translates to:
  /// **'Paying from your'**
  String get payAmountPayingFrom;

  /// Label next to the asset picker on the Pay amount step.
  ///
  /// In en, this message translates to:
  /// **'Paying in'**
  String get payAmountPayingIn;

  /// Back link of the first Pay step; goes to Home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get payBackHome;

  /// Disabled button label while the Pay quote is loading.
  ///
  /// In en, this message translates to:
  /// **'Fetching quote'**
  String get payFetchingQuote;

  /// Heading of the warning shown when the pasted Pay recipient address is not in the address book or recents.
  ///
  /// In en, this message translates to:
  /// **'New address detected.'**
  String get payNewAddressDetected;

  /// Warning text under the new-address heading on the Pay recipient step.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t interacted with this address before.'**
  String get payNewAddressWarning;

  /// Relative time of a recent Pay recipient used this many days ago; 'd' abbreviates days.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String payRecentDaysAgo(int days);

  /// Relative time of a recent Pay recipient used this many hours ago; 'h' abbreviates hours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String payRecentHoursAgo(int hours);

  /// Relative time of a recent Pay recipient used this many minutes ago; 'm' abbreviates minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String payRecentMinutesAgo(int minutes);

  /// Title of the list of recent Pay recipients on desktop.
  ///
  /// In en, this message translates to:
  /// **'Recently sent'**
  String get payRecentlySent;

  /// Title of the list of recent Pay recipients on mobile.
  ///
  /// In en, this message translates to:
  /// **'Recents'**
  String get payRecents;

  /// Placeholder of the Pay recipient search field.
  ///
  /// In en, this message translates to:
  /// **'Paste an address or scan QR code'**
  String get payRecipientAddressHint;

  /// Accessibility label of the Pay recipient search field.
  ///
  /// In en, this message translates to:
  /// **'Recipient address'**
  String get payRecipientAddressLabel;

  /// Disabled button label on the Pay review step while a new quote is loading.
  ///
  /// In en, this message translates to:
  /// **'Refreshing quote'**
  String get payRefreshingQuote;

  /// Primary button of the Pay review step that sends the payment.
  ///
  /// In en, this message translates to:
  /// **'Confirm & pay'**
  String get payReviewConfirmPay;

  /// Label of the row with the ZEC amount converted for the payment.
  ///
  /// In en, this message translates to:
  /// **'Converted amount'**
  String get payReviewConvertedAmount;

  /// Label of the paying amount row on the Pay review step.
  ///
  /// In en, this message translates to:
  /// **'Paying'**
  String get payReviewPaying;

  /// Text of the Pay review countdown after the quote expired.
  ///
  /// In en, this message translates to:
  /// **'Quote expired'**
  String get payReviewQuoteExpired;

  /// Text before the countdown on the Pay review step; a trailing space separates it from the time.
  ///
  /// In en, this message translates to:
  /// **'Quote expires in '**
  String get payReviewQuoteExpiresIn;

  /// Button on the mobile Pay review step when the quote expired.
  ///
  /// In en, this message translates to:
  /// **'Refresh quote'**
  String get payReviewRefreshQuote;

  /// Button on the desktop Pay review step when the quote expired.
  ///
  /// In en, this message translates to:
  /// **'Refresh the quote'**
  String get payReviewRefreshTheQuote;

  /// Button on the mobile Pay review step when the quote is no longer active.
  ///
  /// In en, this message translates to:
  /// **'Return to pay'**
  String get payReviewReturnToPay;

  /// Caption of the recipient row when the address is not a saved contact.
  ///
  /// In en, this message translates to:
  /// **'Unknown address'**
  String get payReviewUnknownAddress;

  /// Error in the Pay add-contact form when saving fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save this contact. Try again.'**
  String get paySaveContactError;

  /// Accessibility label of the tappable area that dismisses the mobile Pay modal.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get payScanBarrierDismiss;

  /// Caption of the camera scanner for the Pay recipient address.
  ///
  /// In en, this message translates to:
  /// **'Scan the recipient address QR code'**
  String get payScanCaption;

  /// Title of the camera permission prompt of the Pay recipient scanner.
  ///
  /// In en, this message translates to:
  /// **'Scan the recipient address'**
  String get payScanPermissionTitle;

  /// Subtitle of the card that opens the QR scanner on the mobile Pay recipient step.
  ///
  /// In en, this message translates to:
  /// **'Scan an address using camera'**
  String get payScanQrSubtitle;

  /// Title of the card that opens the QR scanner on the mobile Pay recipient step.
  ///
  /// In en, this message translates to:
  /// **'Scan a QR code'**
  String get payScanQrTitle;

  /// Button that confirms the Pay recipient and goes to the review step.
  ///
  /// In en, this message translates to:
  /// **'Select recipient'**
  String get paySelectRecipient;

  /// Label of the Pay wizard step where the user picks the recipient; also the back link from the review step.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get payStepRecipient;

  /// Label of the Pay wizard step where the user reviews the payment.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get payStepReview;

  /// Body of the mobile Pay submitted screen when submitting failed.
  ///
  /// In en, this message translates to:
  /// **'The payment could not be submitted. Try again.'**
  String get paySubmittedFailedBody;

  /// Secondary button of the mobile Pay submitted screen; opens Activity.
  ///
  /// In en, this message translates to:
  /// **'Go to activity'**
  String get paySubmittedGoToActivity;

  /// Notice on the mobile Pay submitted screen when the broadcast result is unknown; Activity is the app's transaction list.
  ///
  /// In en, this message translates to:
  /// **'The payment status is uncertain. Check Activity before trying again.'**
  String get paySubmittedStatusUncertainNotice;

  /// Body of the mobile Pay submitted screen while the payment is being broadcast.
  ///
  /// In en, this message translates to:
  /// **'Submitting your payment to the network...'**
  String get paySubmittedSubmittingBody;

  /// Title of the mobile Pay submitted screen while the payment is being broadcast.
  ///
  /// In en, this message translates to:
  /// **'Submitting payment...'**
  String get paySubmittedSubmittingTitle;

  /// Body of the mobile Pay submitted screen after broadcast; the line break is intentional and Activity is the app's transaction list.
  ///
  /// In en, this message translates to:
  /// **'It will confirm on-chain shortly.\nTrack it in Activity.'**
  String get paySubmittedSucceededBody;

  /// Title of the mobile Pay submitted screen after the payment was broadcast; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Payment\nSubmitted'**
  String get paySubmittedSucceededTitle;

  /// Notice on the mobile Pay submitted screen when the payment record is missing.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load this payment. Check Activity for its latest status.'**
  String get paySubmittedUnavailableNotice;

  /// Title of the mobile Pay submitted screen when the payment record is missing.
  ///
  /// In en, this message translates to:
  /// **'Payment unavailable'**
  String get paySubmittedUnavailableTitle;

  /// Title of the mobile Pay submitted screen when the broadcast result is unknown; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Payment status\nuncertain'**
  String get paySubmittedUncertainTitle;

  /// Title of the Pay amount step; the symbol is the asset the user pays in.
  ///
  /// In en, this message translates to:
  /// **'Pay in {symbol}'**
  String payTitleAmount(String symbol);

  /// Error under the Gift Card amount when it is larger than the available balance.
  ///
  /// In en, this message translates to:
  /// **'Above your maximum ZEC'**
  String get paymentLinkAboveMaximumZec;

  /// Message shown when the active account changed while redeeming a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Active account changed. Redeem this gift card again to receive it in the new account.'**
  String get paymentLinkAccountChangedRedeemAgain;

  /// Message shown when the active account changed while creating a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Active account changed. Review the gift card amount and fees again.'**
  String get paymentLinkAccountChangedReviewAmount;

  /// Error shown when the active account changed while a Gift Card was being created.
  ///
  /// In en, this message translates to:
  /// **'The active account changed. Review the amount and try again.'**
  String get paymentLinkActiveAccountChangedReviewAmount;

  /// Two-line heading shown while a Gift Card is still being prepared; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Gift Card is\nalmost ready!'**
  String get paymentLinkAlmostReadyHeading;

  /// Two-line heading shown while a received Gift Card is being prepared; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Your Gift Card\nis almost ready!'**
  String get paymentLinkAlmostReadyReceivedHeading;

  /// Screen reader label of a disabled currency toggle on the Gift Card amount field; {currency} is USD and {reason} explains why it is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in {currency}. {reason}'**
  String paymentLinkAmountCurrencyDisabledSemantic(
    String currency,
    String reason,
  );

  /// Placeholder of the Gift Card amount field when the amount is entered in US dollars.
  ///
  /// In en, this message translates to:
  /// **'Enter dollars'**
  String get paymentLinkAmountEnterDollars;

  /// Screen reader label of the Gift Card amount text field.
  ///
  /// In en, this message translates to:
  /// **'Gift card amount input'**
  String get paymentLinkAmountInputSemantic;

  /// Subtitle of the first steps of desktop Gift Card creation.
  ///
  /// In en, this message translates to:
  /// **'Enter amount & select the design.'**
  String get paymentLinkAmountStepSubtitleDesktop;

  /// Subtitle of the mobile amount step of Gift Card creation.
  ///
  /// In en, this message translates to:
  /// **'Enter amount & pick a design.'**
  String get paymentLinkAmountStepSubtitleMobile;

  /// Button that approves the funding and creates the Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Approve & create'**
  String get paymentLinkApproveAndCreate;

  /// Heading of the collapsible list of archived Gift Cards; {count} is how many cards are archived.
  ///
  /// In en, this message translates to:
  /// **'Archived ({count})'**
  String paymentLinkArchivedCount(int count);

  /// Heading above the list of archived Gift Cards.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get paymentLinkArchivedHeading;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Chest in crystal cave'**
  String get paymentLinkArtworkChestCave;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Chest in lava cave'**
  String get paymentLinkArtworkChestLava;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Zcash coin'**
  String get paymentLinkArtworkCoin;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Crystal'**
  String get paymentLinkArtworkCrystal;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get paymentLinkArtworkDiamond;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Dragon'**
  String get paymentLinkArtworkDragon;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Gift box'**
  String get paymentLinkArtworkGift;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Magic knight'**
  String get paymentLinkArtworkKnightMagic;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Rogue cat'**
  String get paymentLinkArtworkRogueCat;

  /// Name of a built-in Gift Card artwork, read aloud by screen readers.
  ///
  /// In en, this message translates to:
  /// **'Ruby'**
  String get paymentLinkArtworkRuby;

  /// Explanation shown while the result of claiming a received Gift Card is not yet confirmed.
  ///
  /// In en, this message translates to:
  /// **'Your claim result is not confirmed yet. Check again shortly.'**
  String get paymentLinkAvailabilityCheckingDescription;

  /// Status label of a received Gift Card whose claim result is being checked.
  ///
  /// In en, this message translates to:
  /// **'Checking result'**
  String get paymentLinkAvailabilityCheckingResult;

  /// Status label of a received Gift Card that is ready to be claimed.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get paymentLinkAvailabilityClaim;

  /// Status label of a received Gift Card whose claim did not complete.
  ///
  /// In en, this message translates to:
  /// **'Claim failed'**
  String get paymentLinkAvailabilityClaimFailed;

  /// Explanation shown when claiming a received Gift Card did not complete.
  ///
  /// In en, this message translates to:
  /// **'Your claim did not complete. Check the card before trying again.'**
  String get paymentLinkAvailabilityFailedDescription;

  /// Status label of a received Gift Card that currently holds no balance.
  ///
  /// In en, this message translates to:
  /// **'No balance'**
  String get paymentLinkAvailabilityNoBalance;

  /// Explanation shown for a received Gift Card that holds no balance.
  ///
  /// In en, this message translates to:
  /// **'There is currently no balance available to claim.'**
  String get paymentLinkAvailabilityNoBalanceDescription;

  /// Explanation shown for a received Gift Card that is ready to be claimed.
  ///
  /// In en, this message translates to:
  /// **'This gift card is ready to claim.'**
  String get paymentLinkAvailabilityReadyDescription;

  /// Explanation shown when the network rejected the claim of a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'The network did not accept this claim. Check its status before trying again.'**
  String get paymentLinkAvailabilityRejectedDescription;

  /// Button on the signing screens that returns to the Gift Card being created.
  ///
  /// In en, this message translates to:
  /// **'Back to gift card'**
  String get paymentLinkBackToGiftCard;

  /// Screen reader label of the button that increases the number of cards in a batch.
  ///
  /// In en, this message translates to:
  /// **'Add a card'**
  String get paymentLinkBatchAddCard;

  /// Heading above the list of cards in a batch.
  ///
  /// In en, this message translates to:
  /// **'Cards in this group'**
  String get paymentLinkBatchCardsInGroup;

  /// Status line of a batch when the usage of some cards could not be checked.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t check every card'**
  String get paymentLinkBatchCheckFailed;

  /// Status line of a batch while the usage of its cards is being checked.
  ///
  /// In en, this message translates to:
  /// **'Checking card use…'**
  String get paymentLinkBatchCheckingUse;

  /// Confirm button of the file-save dialog for Gift Card links.
  ///
  /// In en, this message translates to:
  /// **'Choose location'**
  String get paymentLinkBatchChooseLocation;

  /// Screen reader label of the button that copies the link of one card in a batch.
  ///
  /// In en, this message translates to:
  /// **'Copy link for card {number}'**
  String paymentLinkBatchCopyLinkSemantic(String number);

  /// Screen reader label of the field holding the number of cards in a batch; {max} is the largest allowed count.
  ///
  /// In en, this message translates to:
  /// **'Number of cards, 2 to {max}'**
  String paymentLinkBatchCountSemantic(int max);

  /// Subtitle of a batch detail page; {date} is the creation date.
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String paymentLinkBatchCreated(String date);

  /// Error shown when the details of the cards in a group could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Card details could not be saved. Try again.'**
  String get paymentLinkBatchDetailsNotSaved;

  /// Error shown when the network fee of a group changed after the quote.
  ///
  /// In en, this message translates to:
  /// **'The network fee changed. Review the new total.'**
  String get paymentLinkBatchFeeChanged;

  /// [security] Error shown when the funding for a group was sent but the cards could not be saved; the user must retry before closing the app or the links are lost.
  ///
  /// In en, this message translates to:
  /// **'Funding was sent, but the cards could not be saved. Try again before closing Vizor.'**
  String get paymentLinkBatchFundedNotSaved;

  /// Title of a batch detail page; {count} is the number of cards in the group.
  ///
  /// In en, this message translates to:
  /// **'{count} gift cards'**
  String paymentLinkBatchGiftCardsCount(int count);

  /// [security] Note on a batch whose payment is still confirming; its links must not be shared yet.
  ///
  /// In en, this message translates to:
  /// **'Links become shareable once the payment confirms.'**
  String get paymentLinkBatchLinksShareableLater;

  /// Hint of the message field in batch Gift Card creation.
  ///
  /// In en, this message translates to:
  /// **'Message (optional)'**
  String get paymentLinkBatchMessageOptional;

  /// Hint of the message field in batch Gift Card creation; the message is printed on every card.
  ///
  /// In en, this message translates to:
  /// **'Message (optional), appears on every card'**
  String get paymentLinkBatchMessageOptionalEveryCard;

  /// Error shown when none of the cards in a group was funded.
  ///
  /// In en, this message translates to:
  /// **'No cards were funded. Review the amount and try again.'**
  String get paymentLinkBatchNoneFunded;

  /// [security] Warning on a batch where some cards are not ready; none of the links should be shared until all cards are ready.
  ///
  /// In en, this message translates to:
  /// **'Not every card in this group is ready. Don’t share any links until they all are.'**
  String get paymentLinkBatchNotAllReady;

  /// Error shown when the group costs more than the available balance.
  ///
  /// In en, this message translates to:
  /// **'Reduce the amount or number of cards to fit your available balance.'**
  String get paymentLinkBatchOverBalance;

  /// [security] Warning on a batch whose payment could not be confirmed; the links must not be shared until the payment is confirmed.
  ///
  /// In en, this message translates to:
  /// **'Vizor hasn’t confirmed that the payment was sent. Keep these cards and check again before sharing any links.'**
  String get paymentLinkBatchPaymentUnconfirmed;

  /// Error shown when preparing the cards of a group failed.
  ///
  /// In en, this message translates to:
  /// **'These cards could not be prepared.'**
  String get paymentLinkBatchPrepareFailed;

  /// Message shown when the cards of a group were created under the previous account.
  ///
  /// In en, this message translates to:
  /// **'Cards were created under the previous account. Switch back to view them.'**
  String get paymentLinkBatchPreviousAccount;

  /// Error shown when a group cannot be created yet because the balance is still loading.
  ///
  /// In en, this message translates to:
  /// **'Available balance is still loading. Try again after wallet sync.'**
  String get paymentLinkBatchQuoteNotReady;

  /// Shown when a Gift Card group cannot be funded from a Keystone account because it would spend Sapling funds. Nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'This group would spend older Sapling funds, which your Keystone can’t sign. Try fewer cards or a smaller amount per card.'**
  String get paymentLinkBatchRejectedKeystoneSapling;

  /// Shown when a Gift Card group needs more spend signatures than one Keystone signing round. Nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'This group needs more inputs than your Keystone can sign at once. Try fewer cards or a smaller amount per card.'**
  String get paymentLinkBatchRejectedKeystoneSignatureLimit;

  /// Shown when a Gift Card group has more card recipients than a Ledger can show for review. {max} is that limit, such as 4. Nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'This group has more shielded recipients than your Ledger can display (maximum {max}). Try fewer cards or a smaller amount per card.'**
  String paymentLinkBatchRejectedLedgerRecipientLimit(String max);

  /// Shown when a Gift Card group cannot be funded from a Ledger account because it would spend Sapling funds. Nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'This group would spend older Sapling funds, which your Ledger can’t sign. Try fewer cards or a smaller amount per card.'**
  String get paymentLinkBatchRejectedLedgerSapling;

  /// Shown when a Gift Card group has more actions in one pool than a Ledger can sign. Nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'This group is too large for your Ledger to sign. Try fewer cards or a smaller amount per card.'**
  String get paymentLinkBatchRejectedLedgerTooLarge;

  /// Shown when a Gift Card group would need more than one funding transaction. Nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'This group can’t be funded in one transaction. Try fewer cards or a smaller amount per card.'**
  String get paymentLinkBatchRejectedNotOneTransaction;

  /// Screen reader label of the button that decreases the number of cards in a batch.
  ///
  /// In en, this message translates to:
  /// **'Remove a card'**
  String get paymentLinkBatchRemoveCard;

  /// Screen reader label of a card row in a batch; {number} is the zero-padded card number, {status} its usage status, and {failed} is true when refreshing the status failed.
  ///
  /// In en, this message translates to:
  /// **'Card {number}, {status}{failed, select, true{, update failed} other{}}'**
  String paymentLinkBatchRowSemantic(
    String number,
    String status,
    String failed,
  );

  /// Title of a card row in a batch; {number} is the zero-padded card number.
  ///
  /// In en, this message translates to:
  /// **'Card {number}'**
  String paymentLinkBatchRowTitle(String number);

  /// Note on a card row in a batch when refreshing its usage failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update'**
  String get paymentLinkBatchRowUpdateFailed;

  /// Button that saves the links of all Gift Cards in a batch to a CSV file.
  ///
  /// In en, this message translates to:
  /// **'Save all links as CSV'**
  String get paymentLinkBatchSaveAllCsv;

  /// Title of the file-save dialog for the links of all Gift Cards in a batch.
  ///
  /// In en, this message translates to:
  /// **'Save gift card links'**
  String get paymentLinkBatchSaveLinksTitle;

  /// [security] Warning in the file-save dialog for Gift Card links: the file holds secrets that let anyone who has it claim the funds, so it must be stored privately.
  ///
  /// In en, this message translates to:
  /// **'Anyone with this file can claim these cards. Save it somewhere private.'**
  String get paymentLinkBatchSaveLinksWarning;

  /// Screen reader label of the button that shows the QR code of one card in a batch.
  ///
  /// In en, this message translates to:
  /// **'Show QR code for card {number}'**
  String paymentLinkBatchShowQrSemantic(String number);

  /// [security] Error shown when Vizor could not confirm that the funding payment for a group was sent; the user must check before creating another group.
  ///
  /// In en, this message translates to:
  /// **'Vizor couldn’t confirm the payment was sent. Check this group in Gift Cards before creating another.'**
  String get paymentLinkBatchUncertain;

  /// Status line of a batch whose cards have not been checked yet.
  ///
  /// In en, this message translates to:
  /// **'Card use not checked yet'**
  String get paymentLinkBatchUseNotChecked;

  /// Label of the field holding the amount of each card in a batch.
  ///
  /// In en, this message translates to:
  /// **'Amount per card'**
  String get paymentLinkBulkAmountPerCard;

  /// Screen reader label shown while the wallet balance next to the batch amount loads.
  ///
  /// In en, this message translates to:
  /// **'Balance loading'**
  String get paymentLinkBulkBalanceLoading;

  /// Label of the section where the user picks the artwork of the cards in a batch.
  ///
  /// In en, this message translates to:
  /// **'Card design'**
  String get paymentLinkBulkCardDesign;

  /// Screen reader label of a preset button that sets the number of cards in a batch.
  ///
  /// In en, this message translates to:
  /// **'{count} cards'**
  String paymentLinkBulkCountSemantic(int count);

  /// Button that creates a batch of Gift Cards; {count} is the number of cards.
  ///
  /// In en, this message translates to:
  /// **'Create {count} cards'**
  String paymentLinkBulkCreateCards(int count);

  /// Title of the batch creation page for Ledger accounts.
  ///
  /// In en, this message translates to:
  /// **'Create multiple cards'**
  String get paymentLinkBulkCreateMultiple;

  /// Label of the option that gives every card in a batch a different design.
  ///
  /// In en, this message translates to:
  /// **'Different design on each card'**
  String get paymentLinkBulkDifferentDesign;

  /// Breadcrumb label for editing the cards of a batch before creating them.
  ///
  /// In en, this message translates to:
  /// **'Edit cards'**
  String get paymentLinkBulkEditCards;

  /// Subtitle of the batch creation page for Ledger accounts; {max} is the maximum number of cards.
  ///
  /// In en, this message translates to:
  /// **'Create up to {max} cards at once with Ledger.'**
  String paymentLinkBulkLedgerLimit(int max);

  /// Title and button of the batch review step; {count} is the number of cards.
  ///
  /// In en, this message translates to:
  /// **'Review {count} cards'**
  String paymentLinkBulkReviewCards(int count);

  /// Screen reader label of the spendable balance next to the batch amount; {amount} is the formatted amount.
  ///
  /// In en, this message translates to:
  /// **'{amount} ZEC available'**
  String paymentLinkBulkZecAvailable(String amount);

  /// Label of the Gift Card amount row in the review step.
  ///
  /// In en, this message translates to:
  /// **'Card amount'**
  String get paymentLinkCardAmountLabel;

  /// Toast shown when checking the balance of a received Gift Card failed.
  ///
  /// In en, this message translates to:
  /// **'Card balance could not be checked. Try again.'**
  String get paymentLinkCardBalanceCheckFailed;

  /// Screen reader label of a Gift Card artwork choice; {design} is the artwork name, for example Knight or Dragon.
  ///
  /// In en, this message translates to:
  /// **'{design} card design'**
  String paymentLinkCardDesignSemantic(String design);

  /// Help text explaining the Gift Card fee: the creation fee plus the fee reserved for the recipient to claim.
  ///
  /// In en, this message translates to:
  /// **'Includes the creation fee and the fee reserved for claiming.'**
  String get paymentLinkCardFeeHelpText;

  /// Label of the row showing the combined fee to fund a Gift Card and the fee reserved for the recipient to redeem it.
  ///
  /// In en, this message translates to:
  /// **'Card fee (deposit + redeem)'**
  String get paymentLinkCardFeeLabel;

  /// Toast shown when removing a Gift Card from the list failed.
  ///
  /// In en, this message translates to:
  /// **'Card could not be removed. Try again.'**
  String get paymentLinkCardRemoveFailed;

  /// Toast shown when checking the status of a Gift Card failed.
  ///
  /// In en, this message translates to:
  /// **'Card status could not be checked. Try again.'**
  String get paymentLinkCardStatusCheckFailed;

  /// Title shown when a scanned Gift Card QR code could not be read.
  ///
  /// In en, this message translates to:
  /// **'This card could not be read.'**
  String get paymentLinkCardUnreadable;

  /// Toast shown when archiving or restoring a Gift Card failed.
  ///
  /// In en, this message translates to:
  /// **'Card could not be updated. Try again.'**
  String get paymentLinkCardUpdateFailed;

  /// Error shown in place of the Gift Cards list when loading it failed.
  ///
  /// In en, this message translates to:
  /// **'Gift cards could not be loaded.'**
  String get paymentLinkCardsLoadFailed;

  /// Progress text while the app checks a received Gift Card; {phase} is finding or checking and {percent} is the percentage done.
  ///
  /// In en, this message translates to:
  /// **'{phase, select, finding{Finding the gift} other{Checking the gift}}… {percent}%'**
  String paymentLinkCheckProgress(String phase, String percent);

  /// Button that checks the current status of a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Check status'**
  String get paymentLinkCheckStatus;

  /// Caption showing that the Gift Card usage was checked {hours} hours ago.
  ///
  /// In en, this message translates to:
  /// **'Checked {hours}h ago'**
  String paymentLinkCheckedHoursAgo(int hours);

  /// Caption showing that the Gift Card usage was checked less than a minute ago.
  ///
  /// In en, this message translates to:
  /// **'Checked just now'**
  String get paymentLinkCheckedJustNow;

  /// Caption showing that the Gift Card usage was checked {minutes} minutes ago.
  ///
  /// In en, this message translates to:
  /// **'Checked {minutes}m ago'**
  String paymentLinkCheckedMinutesAgo(int minutes);

  /// Caption showing the date the Gift Card usage was last checked.
  ///
  /// In en, this message translates to:
  /// **'Checked {date}'**
  String paymentLinkCheckedOnDate(String date);

  /// Status text while the app checks a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Checking the gift…'**
  String get paymentLinkCheckingGiftEllipsis;

  /// Invisible sizing placeholder that reserves the width of the Gift Card check progress text.
  ///
  /// In en, this message translates to:
  /// **'Checking the gift… 100%'**
  String get paymentLinkCheckingGiftFull;

  /// Title and screen reader label of the sheet where the user picks which account receives a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Choose receiving account'**
  String get paymentLinkChooseReceivingAccount;

  /// Error in the receiving-account sheet when preparing the Gift Card claim failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t prepare this gift. Try again or choose another account.'**
  String get paymentLinkClaimAccountPrepareFailed;

  /// Button that creates a new account to claim a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Create an account to claim'**
  String get paymentLinkClaimActionCreateAccount;

  /// Button that creates a new wallet to claim a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Create a wallet to claim'**
  String get paymentLinkClaimActionCreateWallet;

  /// Button that claims a received Gift Card with a wallet the user already has.
  ///
  /// In en, this message translates to:
  /// **'Claim with an existing wallet'**
  String get paymentLinkClaimActionExistingWallet;

  /// Two-line description shown while the app checks whether a received Gift Card was already claimed; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Checking whether this gift card\nhas already been claimed.'**
  String get paymentLinkClaimCheckingDescription;

  /// Two-line heading shown while a received Gift Card is checked; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Checking your\ngift card'**
  String get paymentLinkClaimCheckingHeading;

  /// Message shown when claiming a Gift Card failed; the card may still be confirming or may already have been claimed.
  ///
  /// In en, this message translates to:
  /// **'Gift card claim failed. It may still be waiting for confirmation or may already be spent.'**
  String get paymentLinkClaimFailedMaybePending;

  /// Toast shown when redeeming a received Gift Card failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t redeem your gift card.'**
  String get paymentLinkClaimFailureToast;

  /// Button in the receiving-account sheet that claims the Gift Card into the selected account.
  ///
  /// In en, this message translates to:
  /// **'Claim gift'**
  String get paymentLinkClaimGiftButton;

  /// Toast shown when a received Gift Card cannot be saved because too many other cards are already waiting to be redeemed.
  ///
  /// In en, this message translates to:
  /// **'Too many gift cards are waiting. Finish another card first.'**
  String get paymentLinkClaimQueueFull;

  /// Message shown when the result of claiming a Gift Card is not confirmed yet.
  ///
  /// In en, this message translates to:
  /// **'Claim result is not confirmed. Check its status.'**
  String get paymentLinkClaimResultNotConfirmed;

  /// Toast shown when a received Gift Card could not be saved before account setup.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the card. Try again.'**
  String get paymentLinkClaimSaveFailed;

  /// Status shown when a received Gift Card was already claimed by someone else.
  ///
  /// In en, this message translates to:
  /// **'This gift has already been claimed.'**
  String get paymentLinkClaimStatusAlreadyClaimed;

  /// Detail under the already-claimed status suggesting the user ask the sender for a new Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Ask the sender for a new one.'**
  String get paymentLinkClaimStatusAskSender;

  /// Detail under the network error while checking a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get paymentLinkClaimStatusCheckConnection;

  /// Detail while the Gift Card deposit confirms, for a user who already has a wallet.
  ///
  /// In en, this message translates to:
  /// **'You can create your account now.'**
  String get paymentLinkClaimStatusCreateAccountNow;

  /// Detail under Gift found for a user who already has a wallet.
  ///
  /// In en, this message translates to:
  /// **'Create an account or use one you have to claim it.'**
  String get paymentLinkClaimStatusCreateAccountOrUseOne;

  /// Detail while the Gift Card deposit confirms, for a user who has no wallet yet.
  ///
  /// In en, this message translates to:
  /// **'You can create your wallet now.'**
  String get paymentLinkClaimStatusCreateWalletNow;

  /// Detail under Gift found for a user who has no wallet yet.
  ///
  /// In en, this message translates to:
  /// **'Create a wallet or use one you have to claim it.'**
  String get paymentLinkClaimStatusCreateWalletOrUseOne;

  /// Status title shown when a received Gift Card holds a balance that can be claimed.
  ///
  /// In en, this message translates to:
  /// **'Gift found'**
  String get paymentLinkClaimStatusGiftFound;

  /// Detail under the no-balance status of a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'The sender may not have funded it yet.'**
  String get paymentLinkClaimStatusMayNotBeFunded;

  /// Status shown when the app could not reach the network while checking a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t reach the network.'**
  String get paymentLinkClaimStatusNetworkUnreachable;

  /// Status shown when a received Gift Card was created for a different Zcash network than the wallet uses.
  ///
  /// In en, this message translates to:
  /// **'This gift card is for a different network.'**
  String get paymentLinkClaimStatusOtherNetwork;

  /// Status shown while the Gift Card funding deposit is confirming; {count} is the confirmations seen and {target} the number needed.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the deposit to confirm · {count} of {target}'**
  String paymentLinkClaimStatusWaitingDeposit(int count, int target);

  /// Title shown after a Gift Card claim was submitted to the network.
  ///
  /// In en, this message translates to:
  /// **'Gift claim submitted'**
  String get paymentLinkClaimSubmitted;

  /// Button that claims a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Claim the gift'**
  String get paymentLinkClaimTheGift;

  /// Button that claims a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Claim the gift card'**
  String get paymentLinkClaimTheGiftCard;

  /// Description while a received Gift Card is not yet ready to claim.
  ///
  /// In en, this message translates to:
  /// **'Your gift will be ready to claim shortly.'**
  String get paymentLinkClaimWaitingDescription;

  /// Explanation shown when a received Gift Card was already claimed in another wallet.
  ///
  /// In en, this message translates to:
  /// **'This card was claimed in another wallet first. Your balance hasn\'t changed.'**
  String get paymentLinkClaimedElsewhereDescription;

  /// Status label of a received Gift Card that someone claimed in another wallet before the user.
  ///
  /// In en, this message translates to:
  /// **'Claimed elsewhere'**
  String get paymentLinkClaimedElsewhereLabel;

  /// Button label while a Gift Card is being claimed.
  ///
  /// In en, this message translates to:
  /// **'Claiming…'**
  String get paymentLinkClaiming;

  /// [security] Button that clears the clipboard after a Gift Card link was pasted, so the bearer link does not stay copied.
  ///
  /// In en, this message translates to:
  /// **'Clear clipboard'**
  String get paymentLinkClearClipboardLabel;

  /// Hint under a received Gift Card on desktop explaining how to read its message.
  ///
  /// In en, this message translates to:
  /// **'Click on the card to reveal the message.'**
  String get paymentLinkClickToRevealMessage;

  /// Hint under a received Gift Card on desktop; the message is revealed by clicking the card.
  ///
  /// In en, this message translates to:
  /// **'Click on the card to reveal'**
  String get paymentLinkClickToRevealShort;

  /// Title of the hardware wallet signing screen for creating a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Confirm Gift Card'**
  String get paymentLinkConfirmGiftCardTitle;

  /// Hint on the Gift Card ready screen that the link can be copied again later from the settings.
  ///
  /// In en, this message translates to:
  /// **'You can copy this link again from Settings → My gift cards.'**
  String get paymentLinkCopyLinkAgainHint;

  /// Screen reader label of the button that copies a Gift Card link.
  ///
  /// In en, this message translates to:
  /// **'Copy gift card link'**
  String get paymentLinkCopyLinkSemanticLabel;

  /// Button label while a Gift Card link is being copied.
  ///
  /// In en, this message translates to:
  /// **'Copying…'**
  String get paymentLinkCopying;

  /// Label of the cost row showing how much more ZEC the user needs for the batch.
  ///
  /// In en, this message translates to:
  /// **'Additional ZEC needed'**
  String get paymentLinkCostAdditionalZecNeeded;

  /// Value of the additional-ZEC row when the total is not known yet; {amount} is the formatted minimum shortfall.
  ///
  /// In en, this message translates to:
  /// **'At least {amount}'**
  String paymentLinkCostAtLeast(String amount);

  /// Screen reader label shown while the network fee of a batch is calculated.
  ///
  /// In en, this message translates to:
  /// **'Calculating network fee'**
  String get paymentLinkCostCalculatingFee;

  /// Label of the cost row showing the number of cards the per-card cost is multiplied by.
  ///
  /// In en, this message translates to:
  /// **'× {count} cards'**
  String paymentLinkCostCardsMultiplier(int count);

  /// Label of the row showing the message printed on every card in a batch.
  ///
  /// In en, this message translates to:
  /// **'Message on every card'**
  String get paymentLinkCostMessageOnEveryCard;

  /// Label of the cost row showing the cost of one card.
  ///
  /// In en, this message translates to:
  /// **'Per card'**
  String get paymentLinkCostPerCard;

  /// Caption under the per-card cost; {amount} is the card amount and {fee} the fee reserved for redeeming, or a dash if unknown.
  ///
  /// In en, this message translates to:
  /// **'{amount} ZEC + {fee} ZEC redeem fee'**
  String paymentLinkCostPerCardBreakdown(String amount, String fee);

  /// Shown in place of the network fee while the wallet is still syncing.
  ///
  /// In en, this message translates to:
  /// **'Waiting for sync'**
  String get paymentLinkCostWaitingForSync;

  /// Label of the row showing the total the user will spend on a batch.
  ///
  /// In en, this message translates to:
  /// **'You will spend'**
  String get paymentLinkCostYouWillSpend;

  /// Button that creates the Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Create card'**
  String get paymentLinkCreateCardButton;

  /// Button or entry label that starts creating a Gift Card to send to someone.
  ///
  /// In en, this message translates to:
  /// **'Create a card'**
  String get paymentLinkCreateCardLabel;

  /// Title of the desktop page and wizard where the user creates a single Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Create Gift Card'**
  String get paymentLinkCreateGiftCardTitle;

  /// Button that starts creating a new Gift Card on desktop.
  ///
  /// In en, this message translates to:
  /// **'Create new card'**
  String get paymentLinkCreateNewCard;

  /// Error shown when creating a Gift Card failed.
  ///
  /// In en, this message translates to:
  /// **'Gift card creation failed. Try again.'**
  String get paymentLinkCreationFailed;

  /// Screen reader label of the button that clears the message on a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Delete gift card message'**
  String get paymentLinkDeleteMessageSemantic;

  /// Title of the empty state shown on the Gift Cards page when the user has no cards.
  ///
  /// In en, this message translates to:
  /// **'No Gift Cards yet'**
  String get paymentLinkEmptyTitle;

  /// Error shown when the Gift Card amount is missing or invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid gift card amount.'**
  String get paymentLinkEnterValidAmount;

  /// Explanation on the desktop redeem screen when redeeming creates a new account in the wallet.
  ///
  /// In en, this message translates to:
  /// **'Redeem the card to create a new account with the card’s balance in your wallet.'**
  String get paymentLinkEntryExplainAccountDesktop;

  /// Explanation on the desktop redeem screen when redeeming creates a new wallet.
  ///
  /// In en, this message translates to:
  /// **'Once the card is redeemed, we will create a new Vizor wallet with the card’s balance.'**
  String get paymentLinkEntryExplainWalletDesktop;

  /// Explanation on the redeem screen when redeeming creates a new account in an existing wallet.
  ///
  /// In en, this message translates to:
  /// **'Create a new account to receive the card’s balance.'**
  String get paymentLinkEntryExplanationAccount;

  /// Explanation on the redeem screen when redeeming creates a new wallet.
  ///
  /// In en, this message translates to:
  /// **'Create a new Vizor wallet to receive the card’s balance.'**
  String get paymentLinkEntryExplanationWallet;

  /// Two-line instruction to paste the received Gift Card link; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Copy the card link you’ve\nreceived, and paste it below.'**
  String get paymentLinkEntrySubtitle;

  /// Title of the screen shown before an account exists; redeeming a Gift Card creates a new account.
  ///
  /// In en, this message translates to:
  /// **'Create account by redeeming Vizor Gift Card'**
  String get paymentLinkEntryTitleAccount;

  /// Title of the screen shown to a user with no wallet; redeeming a Gift Card creates a new wallet.
  ///
  /// In en, this message translates to:
  /// **'Create wallet by redeeming Vizor Gift Card'**
  String get paymentLinkEntryTitleWallet;

  /// [security] Message shown when exporting links of a group is not possible because not every card is ready.
  ///
  /// In en, this message translates to:
  /// **'All cards must be ready before exporting links.'**
  String get paymentLinkExportNotReady;

  /// Message shown when the account or card status changed while exporting links.
  ///
  /// In en, this message translates to:
  /// **'The account or card status changed. Check the cards and try again.'**
  String get paymentLinkExportStatusChanged;

  /// Error under the Gift Card amount when the fee could not be estimated.
  ///
  /// In en, this message translates to:
  /// **'Card fee could not be estimated. Try again.'**
  String get paymentLinkFeeEstimateFailed;

  /// Supporting text under the Gift Card amount while the wallet is still syncing and the fee cannot be estimated.
  ///
  /// In en, this message translates to:
  /// **'Card fee will be estimated when wallet sync completes.'**
  String get paymentLinkFeeEstimatedAfterSync;

  /// Screen reader label of the info button next to the Gift Card fee on mobile.
  ///
  /// In en, this message translates to:
  /// **'About the gift card fee'**
  String get paymentLinkFeeHelpSemantic;

  /// Help text of the info icon next to the total Gift Card amount; explains the funding fee and the fee reserved for the recipient.
  ///
  /// In en, this message translates to:
  /// **'Includes the fee to fund the gift card and the fee reserved for the recipient to claim it.'**
  String get paymentLinkFeeHelpTextLong;

  /// Error shown when the fee of a Gift Card could not be updated.
  ///
  /// In en, this message translates to:
  /// **'Card fee could not be updated. Return to the amount step and try again.'**
  String get paymentLinkFeeUpdateFailed;

  /// Screen reader label shown while the fiat value of the Gift Card amount loads.
  ///
  /// In en, this message translates to:
  /// **'Fiat value loading'**
  String get paymentLinkFiatLoadingSemantic;

  /// Screen reader label of the control that flips a Gift Card over.
  ///
  /// In en, this message translates to:
  /// **'Flip gift card'**
  String get paymentLinkFlipCardSemanticLabel;

  /// [security] Message shown when the funding of a Gift Card expired before it was sent; the user must create the card again.
  ///
  /// In en, this message translates to:
  /// **'Gift card funding expired. Create it again.'**
  String get paymentLinkFundingExpired;

  /// Status label of a Gift Card whose funding payment did not complete.
  ///
  /// In en, this message translates to:
  /// **'Funding incomplete'**
  String get paymentLinkFundingIncompleteStatus;

  /// Title of the Ledger signing screen when the funding needs the user's attention.
  ///
  /// In en, this message translates to:
  /// **'Gift card funding needs attention'**
  String get paymentLinkFundingNeedsAttention;

  /// [security] Error shown when the funding transaction was sent but the Gift Card could not be saved; the user must retry before closing the app or the card link is lost.
  ///
  /// In en, this message translates to:
  /// **'Funding was sent, but the gift card could not be saved. Try again before closing Vizor.'**
  String get paymentLinkFundingSentCardNotSaved;

  /// Message shown while the Gift Card funding transaction is still being verified.
  ///
  /// In en, this message translates to:
  /// **'Funding is still being verified. Vizor will keep checking it.'**
  String get paymentLinkFundingStillVerifying;

  /// Message shown when the funding transaction was sent but the wallet has not yet stored it locally.
  ///
  /// In en, this message translates to:
  /// **'Funding was sent, but local transaction storage needs to sync.'**
  String get paymentLinkFundingStorageNeedsSync;

  /// Label above the amount of a received Gift Card in the sheet where the user picks the receiving account.
  ///
  /// In en, this message translates to:
  /// **'Gift amount'**
  String get paymentLinkGiftAmountLabel;

  /// Screen reader label of the front of a Gift Card; {design} is the artwork name.
  ///
  /// In en, this message translates to:
  /// **'Gift card, {design} design'**
  String paymentLinkGiftCardDesignSemantic(String design);

  /// Screen reader label of the message side of a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Gift card message'**
  String get paymentLinkGiftCardMessageSemantic;

  /// Breadcrumb label of the Gift Cards section on desktop.
  ///
  /// In en, this message translates to:
  /// **'Gift cards'**
  String get paymentLinkGiftCardsLowerBreadcrumb;

  /// Title of the Gift Cards page and its breadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Gift Cards'**
  String get paymentLinkGiftCardsTitle;

  /// Label of the message attached to a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Gift message'**
  String get paymentLinkGiftMessageLabel;

  /// Status of a group of Gift Cards while its payment is confirming.
  ///
  /// In en, this message translates to:
  /// **'Confirming payment'**
  String get paymentLinkGroupConfirmingPayment;

  /// Title of the batch-creation entry shown for non-Ledger accounts.
  ///
  /// In en, this message translates to:
  /// **'For a group'**
  String get paymentLinkGroupEntryForGroup;

  /// Screen reader label and title of the button that opens batch Gift Card creation.
  ///
  /// In en, this message translates to:
  /// **'Create cards for a group'**
  String get paymentLinkGroupEntryGroupSemantic;

  /// Screen reader label of the button that opens batch Gift Card creation for a Ledger account; {max} is the maximum number of cards.
  ///
  /// In en, this message translates to:
  /// **'Create multiple cards, up to {max} with Ledger'**
  String paymentLinkGroupEntryLedgerSemantic(int max);

  /// Title of the batch-creation entry shown for Ledger accounts.
  ///
  /// In en, this message translates to:
  /// **'Multiple cards'**
  String get paymentLinkGroupEntryMultipleCards;

  /// Subtitle of the batch-creation entry for Ledger accounts; {max} is the maximum number of cards.
  ///
  /// In en, this message translates to:
  /// **'Up to {max} with Ledger'**
  String paymentLinkGroupEntryUpToWithLedger(int max);

  /// Message shown when a group of Gift Cards was never funded.
  ///
  /// In en, this message translates to:
  /// **'This group wasn’t funded. Create it again.'**
  String get paymentLinkGroupNotFunded;

  /// Message shown for a group of Gift Cards that was created under another account.
  ///
  /// In en, this message translates to:
  /// **'This group belongs to another account. Switch accounts to view it.'**
  String get paymentLinkGroupOtherAccount;

  /// Status of a group of Gift Cards whose payment status is unknown.
  ///
  /// In en, this message translates to:
  /// **'Payment status pending'**
  String get paymentLinkGroupPaymentPending;

  /// Status of a group of Gift Cards when some cards are not ready.
  ///
  /// In en, this message translates to:
  /// **'Some cards aren’t ready'**
  String get paymentLinkGroupSomeNotReady;

  /// Heading above the list of Gift Card groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get paymentLinkGroupsHeading;

  /// Button that moves a Gift Card to the archive list.
  ///
  /// In en, this message translates to:
  /// **'Hide card'**
  String get paymentLinkHideCard;

  /// First step of the Gift Cards explainer on desktop.
  ///
  /// In en, this message translates to:
  /// **'Enter amount to gift, pick a design, add a message (optional) and create your Card with a single click.'**
  String get paymentLinkHowDesktopStepCreate;

  /// Third step of the Gift Cards explainer on desktop.
  ///
  /// In en, this message translates to:
  /// **'Recipient can redeem the Card in their Vizor wallet using the Link. The sender covers the deposit and redeem fees, so the recipient receives the full Card amount.'**
  String get paymentLinkHowDesktopStepRedeem;

  /// [security] Second step of the Gift Cards explainer on desktop; the link contains a secret that gives access to the funds and must only be sent to the recipient.
  ///
  /// In en, this message translates to:
  /// **'After the card is created, you will get a unique Link containing its claim secret. Send it only to the intended recipient.'**
  String get paymentLinkHowDesktopStepShare;

  /// Breadcrumb and button label that open the Gift Cards explainer on desktop.
  ///
  /// In en, this message translates to:
  /// **'How gift cards work'**
  String get paymentLinkHowGiftCardsWork;

  /// Subtitle under the Gift Cards explainer title; a friendly tagline.
  ///
  /// In en, this message translates to:
  /// **'A great way to celebrate anything.'**
  String get paymentLinkHowItWorksSubtitle;

  /// Title of the explainer that describes how Gift Cards are created and redeemed.
  ///
  /// In en, this message translates to:
  /// **'How Gift Cards work'**
  String get paymentLinkHowItWorksTitle;

  /// First step of the Gift Cards explainer on mobile.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount, pick a design, and add an optional message.'**
  String get paymentLinkHowStepCreate;

  /// Third step of the Gift Cards explainer on mobile.
  ///
  /// In en, this message translates to:
  /// **'The recipient opens the link in Vizor and claims the full card amount. The sender covers both fees.'**
  String get paymentLinkHowStepRedeem;

  /// [security] Second step of the Gift Cards explainer on mobile; warns that the link is a secret that gives access to the funds and must only be sent to the recipient.
  ///
  /// In en, this message translates to:
  /// **'Once funding reaches the network, copy the unique link and send it only to the intended recipient.'**
  String get paymentLinkHowStepShare;

  /// Label of the link that opens the Gift Cards explainer on mobile.
  ///
  /// In en, this message translates to:
  /// **'How the gift card works'**
  String get paymentLinkHowTheCardWorks;

  /// Toast shown when an incoming Gift Card link could not be read or opened.
  ///
  /// In en, this message translates to:
  /// **'Payment link could not be opened.'**
  String get paymentLinkIntakeCouldNotOpen;

  /// Toast shown when an incoming Gift Card link is rejected because too many links are already queued to open.
  ///
  /// In en, this message translates to:
  /// **'Too many payment links are waiting to open.'**
  String get paymentLinkIntakeQueueFull;

  /// Error shown when checking a received Gift Card was interrupted.
  ///
  /// In en, this message translates to:
  /// **'Card check was interrupted. Try again.'**
  String get paymentLinkInterruptedCheckMessage;

  /// Hint under the invalid-link title telling the user to copy the link again.
  ///
  /// In en, this message translates to:
  /// **'Copy the link & try again'**
  String get paymentLinkInvalidSubtitle;

  /// Title shown when the pasted Gift Card link is not valid.
  ///
  /// In en, this message translates to:
  /// **'The link doesn’t look legit.'**
  String get paymentLinkInvalidTitle;

  /// Error on the Keystone signing screen when the funding transaction could not be sent.
  ///
  /// In en, this message translates to:
  /// **'Gift card funding could not be broadcast.'**
  String get paymentLinkKeystoneBroadcastFailed;

  /// Title of the Keystone signing screen while the funding transaction is being sent.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting gift card funding'**
  String get paymentLinkKeystoneBroadcastingTitle;

  /// Status on the mobile Keystone signing screen while the Gift Card is created after signing.
  ///
  /// In en, this message translates to:
  /// **'Creating your gift card…'**
  String get paymentLinkKeystoneCreatingGiftCard;

  /// Error on the Keystone signing screen when the network response did not confirm the funding transaction.
  ///
  /// In en, this message translates to:
  /// **'The funding status is uncertain. Check activity before trying again.'**
  String get paymentLinkKeystoneFundingUncertain;

  /// Caption on the mobile Keystone signing screen asking the user to scan the signature QR code shown on the device.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to finish creating'**
  String get paymentLinkKeystoneScanCaption;

  /// Title of the Keystone signing screen on desktop.
  ///
  /// In en, this message translates to:
  /// **'Sign gift card on Keystone'**
  String get paymentLinkKeystoneSignTitle;

  /// Error on the Keystone signing screen when signing failed for another reason.
  ///
  /// In en, this message translates to:
  /// **'Gift card signing could not be completed.'**
  String get paymentLinkKeystoneSigningFailed;

  /// [security] Warning that the newly created Gift Card links must be saved or copied before the user leaves, otherwise the funds are lost.
  ///
  /// In en, this message translates to:
  /// **'Save these gift cards before leaving this screen.'**
  String get paymentLinkLeaveSaveMany;

  /// [security] Warning that the newly created Gift Card link must be saved or copied before the user leaves, otherwise the funds are lost.
  ///
  /// In en, this message translates to:
  /// **'Save this gift card before leaving this screen.'**
  String get paymentLinkLeaveSaveOne;

  /// Error shown on the Gift Card signing screen when the funding transaction expired or the network rejected it.
  ///
  /// In en, this message translates to:
  /// **'This gift card transaction expired or was rejected. Go back to create a new gift card.'**
  String get paymentLinkLedgerFundingExpired;

  /// Message on the Ledger signing screen when the user rejected the funding transaction on the device.
  ///
  /// In en, this message translates to:
  /// **'The gift card funding was rejected on your Ledger.'**
  String get paymentLinkLedgerFundingRejected;

  /// Message on the Ledger signing screen when the funding transaction was already saved and the user should retry to finish.
  ///
  /// In en, this message translates to:
  /// **'Gift card funding is saved for recovery. Try again to check its status and finish saving.'**
  String get paymentLinkLedgerSavedForRecovery;

  /// Toast shown after a Gift Card link was copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Gift link copied'**
  String get paymentLinkLinkCopied;

  /// Toast shown after a Gift Card link was copied but its shared status could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Gift link copied, but its status could not be updated.'**
  String get paymentLinkLinkCopiedStatusFailed;

  /// Toast shown when copying a Gift Card link failed.
  ///
  /// In en, this message translates to:
  /// **'Gift link could not be copied.'**
  String get paymentLinkLinkCopyFailed;

  /// Toast shown when saving the links of a group of Gift Cards to a file failed.
  ///
  /// In en, this message translates to:
  /// **'Gift card links could not be saved. Try again.'**
  String get paymentLinkLinksSaveFailed;

  /// Toast shown after the links of a group of Gift Cards were saved to a file.
  ///
  /// In en, this message translates to:
  /// **'Gift card links saved'**
  String get paymentLinkLinksSaved;

  /// Screen reader label shown while a Gift Card is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading gift card'**
  String get paymentLinkLoadingGiftCard;

  /// Body of the long-scan warning shown before checking a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Vizor needs to scan more history than usual before it can verify the balance. This is safe, but it may take a long time.'**
  String get paymentLinkLongSyncBody;

  /// Button in the long-scan warning that starts checking the Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Check gift card'**
  String get paymentLinkLongSyncConfirm;

  /// Reassurance in the long-scan warning that the user can leave without starting the scan.
  ///
  /// In en, this message translates to:
  /// **'You can go back without starting the scan.'**
  String get paymentLinkLongSyncSupporting;

  /// Title of the warning shown before checking a Gift Card that needs a long wallet scan.
  ///
  /// In en, this message translates to:
  /// **'This gift card may take a while'**
  String get paymentLinkLongSyncTitle;

  /// Subtitle of the message step and the review step of mobile Gift Card creation; the message is stored as an encrypted memo.
  ///
  /// In en, this message translates to:
  /// **'Attach a short encrypted memo (optional).'**
  String get paymentLinkMemoOptionalSubtitle;

  /// Title shown when a gift message is attached to a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Message attached.'**
  String get paymentLinkMessageAttachedTitle;

  /// Screen reader label of the text field for a Gift Card message.
  ///
  /// In en, this message translates to:
  /// **'Gift card message input'**
  String get paymentLinkMessageInputSemantic;

  /// Title of the message step of mobile Gift Card creation.
  ///
  /// In en, this message translates to:
  /// **'Enter a message'**
  String get paymentLinkMessageStepTitle;

  /// Error under the Gift Card message field when the message does not fit in the memo.
  ///
  /// In en, this message translates to:
  /// **'This message is too large. Try using fewer complex emoji.'**
  String get paymentLinkMessageTooLarge;

  /// Title of the page listing the user's own Gift Cards on desktop.
  ///
  /// In en, this message translates to:
  /// **'My Cards'**
  String get paymentLinkMyCards;

  /// Status label on the Ledger signing screen when the request cannot be retried and a new gift card must be created.
  ///
  /// In en, this message translates to:
  /// **'New gift card required'**
  String get paymentLinkNewGiftCardRequired;

  /// Error shown when no account is active while creating a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'No active account is available.'**
  String get paymentLinkNoActiveAccountAvailable;

  /// Empty-state text on the Created tab of the Gift Cards page.
  ///
  /// In en, this message translates to:
  /// **'No created cards yet.'**
  String get paymentLinkNoCreatedCardsText;

  /// Empty-state text on the Received tab of the Gift Cards page.
  ///
  /// In en, this message translates to:
  /// **'No received cards yet.'**
  String get paymentLinkNoReceivedCardsText;

  /// Screen reader label of a batch row that is being checked, read as the last part of the description.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get paymentLinkOpenGroupChecking;

  /// Screen reader label of a batch row; {date} is the creation date.
  ///
  /// In en, this message translates to:
  /// **'created {date}'**
  String paymentLinkOpenGroupCreated(String date);

  /// Screen reader label of a batch row; {amount} is the amount of one card.
  ///
  /// In en, this message translates to:
  /// **'{amount} each'**
  String paymentLinkOpenGroupEach(String amount);

  /// Screen reader label of a batch row; first part of the description, {count} is the number of cards.
  ///
  /// In en, this message translates to:
  /// **'Open group of {count} gift cards'**
  String paymentLinkOpenGroupSemantic(int count);

  /// Button that pastes the Gift Card link from the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste card link'**
  String get paymentLinkPasteLabel;

  /// Tooltip and screen reader label of the button that turns privacy mode off, which hides amounts.
  ///
  /// In en, this message translates to:
  /// **'Turn off privacy mode'**
  String get paymentLinkPrivacyModeOff;

  /// Tooltip and screen reader label of the button that turns privacy mode on, which hides amounts.
  ///
  /// In en, this message translates to:
  /// **'Turn on privacy mode'**
  String get paymentLinkPrivacyModeOn;

  /// Two-line heading on the shareable Gift Card QR image; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'You’ve\ngot ZEC'**
  String get paymentLinkQrCardHeading;

  /// Caption on the shareable Gift Card QR image telling the recipient to scan it.
  ///
  /// In en, this message translates to:
  /// **'Scan to redeem'**
  String get paymentLinkQrCardScanToRedeem;

  /// Screen reader label of the shareable Gift Card QR image.
  ///
  /// In en, this message translates to:
  /// **'Gift card QR code'**
  String get paymentLinkQrCardSemantic;

  /// Message shown in place of the Gift Card QR image when it could not be drawn.
  ///
  /// In en, this message translates to:
  /// **'QR code could not be generated'**
  String get paymentLinkQrCouldNotBeGenerated;

  /// Toast shown when saving the Gift Card QR image failed.
  ///
  /// In en, this message translates to:
  /// **'Gift card QR could not be saved.'**
  String get paymentLinkQrSaveFailed;

  /// Toast shown after the Gift Card QR image was saved.
  ///
  /// In en, this message translates to:
  /// **'Gift card QR saved'**
  String get paymentLinkQrSaved;

  /// Toast shown after the Gift Card QR image was saved but its shared status could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Gift card QR saved, but its status could not be updated.'**
  String get paymentLinkQrSavedStatusFailed;

  /// Heading shown when a created Gift Card is ready to be shared.
  ///
  /// In en, this message translates to:
  /// **'Ready to share'**
  String get paymentLinkReadyHeading;

  /// Message shown when finishing the receipt of a Gift Card failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish receiving this gift. Try again to check its status.'**
  String get paymentLinkReceiveFinishFailed;

  /// Label above the account that will receive a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Receive to'**
  String get paymentLinkReceiveToLabel;

  /// Error shown in place of the received Gift Cards list when loading it failed.
  ///
  /// In en, this message translates to:
  /// **'Received gift cards could not be loaded.'**
  String get paymentLinkReceivedCardsLoadFailed;

  /// Heading shown when a Gift Card was received.
  ///
  /// In en, this message translates to:
  /// **'You’ve received a gift!'**
  String get paymentLinkReceivedGiftHeading;

  /// Two-line heading on the desktop screen for a received Gift Card; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'You’ve received\na gift card!'**
  String get paymentLinkReceivedHeadingDesktop;

  /// Message shown when the receiving account changed while a Gift Card was being claimed.
  ///
  /// In en, this message translates to:
  /// **'Receiving account changed. Open the gift card again to continue.'**
  String get paymentLinkReceivingAccountChangedReopen;

  /// Message shown when the receiving account changed while a Gift Card was being checked.
  ///
  /// In en, this message translates to:
  /// **'Receiving account changed. Try again to check this gift.'**
  String get paymentLinkReceivingAccountChangedRetry;

  /// Status label of a received Gift Card while it is being received.
  ///
  /// In en, this message translates to:
  /// **'Receiving…'**
  String get paymentLinkReceivingStatus;

  /// Button or entry label that starts redeeming a Gift Card someone sent the user.
  ///
  /// In en, this message translates to:
  /// **'Redeem a card'**
  String get paymentLinkRedeemCardLabel;

  /// Title of the desktop setup steps shown while redeeming a Gift Card into a new account.
  ///
  /// In en, this message translates to:
  /// **'Redeem the card'**
  String get paymentLinkRedeemCardStepTitle;

  /// Subtitle of the mobile redeem screen.
  ///
  /// In en, this message translates to:
  /// **'Paste a card link or scan its QR code.'**
  String get paymentLinkRedeemPasteOrScan;

  /// Instruction on the redeem screen asking the user to paste the received Gift Card link.
  ///
  /// In en, this message translates to:
  /// **'Copy the card link you’ve received, and paste it below.'**
  String get paymentLinkRedeemSubtitle;

  /// Title of the screen where a recipient redeems a received Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Redeem the Card'**
  String get paymentLinkRedeemTheCardTitle;

  /// [security] Warning in the remove-account and reset dialogs when the app could not check for funded Gift Card links that were never shared; {action} is reset or remove.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for unshared gift card links. Copy any links you still need before {action, select, reset{resetting Vizor} other{removing this account}}.'**
  String paymentLinkRemovalWarningCheckFailed(String action);

  /// [security] Warning in the remove-account and reset dialogs that funded Gift Card links which were never shared will be permanently lost; {count} is how many, {subject} is reset or remove.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 funded gift card link has not been shared. {subject, select, reset{Resetting Vizor} other{Removing this account}} loses it. Copy the link first.} other{{count} funded gift card links have not been shared. {subject, select, reset{Resetting Vizor} other{Removing this account}} loses them. Copy the links first.}}'**
  String paymentLinkRemovalWarningUnshared(int count, String subject);

  /// Confirm button of the dialog for removing a Gift Card from the list.
  ///
  /// In en, this message translates to:
  /// **'Remove card'**
  String get paymentLinkRemoveCardLabel;

  /// [security] Warning in the remove-card dialog that removing the card, and with it access to its link, is irreversible.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get paymentLinkRemoveCardSupporting;

  /// Title of the confirmation dialog for removing a Gift Card from the list.
  ///
  /// In en, this message translates to:
  /// **'Remove this card?'**
  String get paymentLinkRemoveCardTitle;

  /// Button that moves an archived Gift Card back to the active list.
  ///
  /// In en, this message translates to:
  /// **'Restore card'**
  String get paymentLinkRestoreCard;

  /// Screen reader label of the control that reveals the message on a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Reveal gift card message'**
  String get paymentLinkRevealMessageSemanticLabel;

  /// Button that continues to the review step of Gift Card creation.
  ///
  /// In en, this message translates to:
  /// **'Review & confirm'**
  String get paymentLinkReviewAndConfirm;

  /// Title of the review step of mobile Gift Card creation.
  ///
  /// In en, this message translates to:
  /// **'Review a Card'**
  String get paymentLinkReviewCardTitle;

  /// Button that saves the Gift Card QR code image.
  ///
  /// In en, this message translates to:
  /// **'Save QR code'**
  String get paymentLinkSaveQrCode;

  /// Button label while a Gift Card is being saved.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get paymentLinkSaving;

  /// Hint shown when a scanned Gift Card QR code could not be read.
  ///
  /// In en, this message translates to:
  /// **'Scan again or paste another card link.'**
  String get paymentLinkScanAgainOrPaste;

  /// Message shown on the desktop scan screen when no camera is available.
  ///
  /// In en, this message translates to:
  /// **'Connect a camera to scan the gift card QR code, or go back to paste the card link.'**
  String get paymentLinkScanCameraHint;

  /// Screen reader label of the camera preview in the Gift Card QR scanner sheet.
  ///
  /// In en, this message translates to:
  /// **'Scan the gift card QR code'**
  String get paymentLinkScanSheetSemantic;

  /// Title of the Gift Card QR scanner sheet.
  ///
  /// In en, this message translates to:
  /// **'Scan gift card QR'**
  String get paymentLinkScanSheetTitle;

  /// Instruction on the desktop scan screen to hold the Gift Card QR code in front of the camera.
  ///
  /// In en, this message translates to:
  /// **'Show the gift card QR code to your camera'**
  String get paymentLinkScanShowQrToCamera;

  /// Screen reader label of the back of a received Gift Card, which shows the sender's message; {message} is the sender's text.
  ///
  /// In en, this message translates to:
  /// **'Sender message: {message}; Show gift card front'**
  String paymentLinkSenderMessageSemantic(String message);

  /// Button that shares the Gift Card image and link through the system share sheet.
  ///
  /// In en, this message translates to:
  /// **'Share card'**
  String get paymentLinkShareCard;

  /// Toast shown when sharing a Gift Card link failed.
  ///
  /// In en, this message translates to:
  /// **'Gift link could not be shared.'**
  String get paymentLinkShareFailed;

  /// Toast shown when sharing a Gift Card failed and copying the link is suggested.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share this gift card. Copy the link instead.'**
  String get paymentLinkShareFailedCopyInstead;

  /// Title of the desktop dialog where a created Gift Card is shared.
  ///
  /// In en, this message translates to:
  /// **'Share Gift Card'**
  String get paymentLinkShareGiftCardTitle;

  /// [security] Instruction on the Gift Card ready screen; the link is a secret that gives access to the funds and must only be shared with the intended recipient.
  ///
  /// In en, this message translates to:
  /// **'Share this link with the intended recipient so they can claim the Card using their Vizor app.'**
  String get paymentLinkShareLinkInstruction;

  /// [security] Two-line instruction on the desktop Gift Card ready screen; the link is a secret that gives access to the funds and must only be shared with the intended recipient. The line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Share this link with the intended recipient so they\ncan claim the Card using their Vizor app.'**
  String get paymentLinkShareLinkInstructionDesktop;

  /// Title of the sheet where a created Gift Card is shared.
  ///
  /// In en, this message translates to:
  /// **'Share gift card'**
  String get paymentLinkShareSheetTitle;

  /// Description while the created Gift Card is not yet ready to share.
  ///
  /// In en, this message translates to:
  /// **'We’re getting your gift card ready to share.'**
  String get paymentLinkShareWaitingDescription;

  /// Toast shown after a Gift Card was shared but its shared status could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Gift card shared, but its status could not be updated.'**
  String get paymentLinkSharedStatusFailed;

  /// Button label while a Gift Card is being shared.
  ///
  /// In en, this message translates to:
  /// **'Sharing…'**
  String get paymentLinkSharing;

  /// Screen reader label of the control that turns a Gift Card back to its front.
  ///
  /// In en, this message translates to:
  /// **'Show gift card front'**
  String get paymentLinkShowCardFrontSemantic;

  /// Screen reader label of the button that opens the Gift Cards explainer.
  ///
  /// In en, this message translates to:
  /// **'Show how gift cards work'**
  String get paymentLinkShowHowCardsWork;

  /// Screen reader label of the button that shows the QR code of a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Show gift card QR code'**
  String get paymentLinkShowQrSemantic;

  /// Button that skips adding a message to a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Skip message'**
  String get paymentLinkSkipMessage;

  /// Placeholder of the message field on the back of a Gift Card being written.
  ///
  /// In en, this message translates to:
  /// **'Start typing…'**
  String get paymentLinkStartTyping;

  /// Screen reader label of the button that starts writing a message on a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Start writing gift card message'**
  String get paymentLinkStartWritingMessage;

  /// Label of the second step in the Gift Card creation stepper.
  ///
  /// In en, this message translates to:
  /// **'Add Message'**
  String get paymentLinkStepAddMessage;

  /// Label of the first step in the Gift Card creation stepper.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get paymentLinkStepCreate;

  /// Label of the third step in the Gift Card creation stepper.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get paymentLinkStepReview;

  /// [security] Error shown when saving a Gift Card failed again; the user must retry before closing the app or the card link is lost.
  ///
  /// In en, this message translates to:
  /// **'The gift card still could not be saved. Try again before closing Vizor.'**
  String get paymentLinkStillNotSaved;

  /// Hint under a received Gift Card on touch devices explaining how to read its message.
  ///
  /// In en, this message translates to:
  /// **'Tap on the card to reveal the message.'**
  String get paymentLinkTapToRevealMessage;

  /// Two-line hint under a received Gift Card on mobile explaining how to read its message; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Tap on the card to reveal\nthe message.'**
  String get paymentLinkTapToRevealMessageTwoLines;

  /// Screen reader label of the info button next to the total Gift Card amount on desktop.
  ///
  /// In en, this message translates to:
  /// **'About the total gift card amount'**
  String get paymentLinkTotalAmountHelpSemantic;

  /// Label of the row showing the total amount taken from the wallet to create a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'Total amount deducted'**
  String get paymentLinkTotalDeductedLabel;

  /// Button that retries saving a Gift Card after saving failed.
  ///
  /// In en, this message translates to:
  /// **'Try saving again'**
  String get paymentLinkTrySavingAgain;

  /// Section heading above Gift Cards that nobody has claimed yet.
  ///
  /// In en, this message translates to:
  /// **'Unused'**
  String get paymentLinkUnusedSectionLabel;

  /// Summary of a group of Gift Cards when every card has been used.
  ///
  /// In en, this message translates to:
  /// **'All used'**
  String get paymentLinkUsageAllUsed;

  /// Explanation of the Unverified usage status: the funded amount differs from the card amount.
  ///
  /// In en, this message translates to:
  /// **'The observed funding amount does not match the expected card funding.'**
  String get paymentLinkUsageAmountMismatch;

  /// Explanation under the usage status of a new Gift Card: the link can be shared while the funding payment confirms.
  ///
  /// In en, this message translates to:
  /// **'Your link is ready to share. Usage tracking will begin once the funding transaction is confirmed.'**
  String get paymentLinkUsageAwaitingConfirmation;

  /// Tooltip and caption showing the usage status of a Gift Card; {label} is the status and {suffix} is checking, failed or none to append the refresh state.
  ///
  /// In en, this message translates to:
  /// **'Card use: {label}{suffix, select, checking{ · Checking…} failed{ · Update failed} other{}}'**
  String paymentLinkUsageCardUse(String label, String suffix);

  /// Explanation of the Unverified usage status: the funding transaction was not found in the scanned history.
  ///
  /// In en, this message translates to:
  /// **'The funding transaction could not yet be verified in the tracking history.'**
  String get paymentLinkUsageFundingNotObserved;

  /// Caption showing when the Gift Card usage was last checked; {time} is a formatted date and time.
  ///
  /// In en, this message translates to:
  /// **'Last checked: {time}'**
  String paymentLinkUsageLastChecked(String time);

  /// Explanation of the Unverified usage status: the saved funding details are missing.
  ///
  /// In en, this message translates to:
  /// **'The saved funding information is incomplete, so usage could not be verified.'**
  String get paymentLinkUsageMissingFundingInfo;

  /// Explanation of the Unverified usage status when no specific reason is known.
  ///
  /// In en, this message translates to:
  /// **'There is not enough information yet to verify whether this card has been used.'**
  String get paymentLinkUsageNotEnoughInfo;

  /// Explanation of the Unverified usage status: the wallet scan has not yet reached the funding transaction.
  ///
  /// In en, this message translates to:
  /// **'The tracking history has not yet reached the funding transaction.'**
  String get paymentLinkUsageScanIncomplete;

  /// Screen reader description of the inline Gift Card usage status; {state} is checking, failed or none, and {explanation} is the usage explanation when {hasExplanation} is true.
  ///
  /// In en, this message translates to:
  /// **'Card use: {label}{state, select, checking{. Checking} failed{. Update failed} other{}}{hasExplanation, select, true{. {explanation}} other{}}'**
  String paymentLinkUsageSemantics(
    String label,
    String state,
    String hasExplanation,
    String explanation,
  );

  /// Summary of a group of Gift Cards; {unused} is how many cards are unused out of {count}.
  ///
  /// In en, this message translates to:
  /// **'{unused} of {count} unused'**
  String paymentLinkUsageUnusedOfCount(int unused, int count);

  /// Usage status of a Gift Card whose usage could not be verified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get paymentLinkUsageUnverified;

  /// Usage status of a Gift Card when the app saw funds leave the card but has not confirmed the claim.
  ///
  /// In en, this message translates to:
  /// **'Use detected'**
  String get paymentLinkUsageUseDetected;

  /// Summary of a group of Gift Cards; {used} is how many cards were used out of {count}.
  ///
  /// In en, this message translates to:
  /// **'{used} of {count} used'**
  String paymentLinkUsageUsedOfCount(int used, int count);

  /// Reason shown on the disabled USD toggle when the amount is too small to enter in US dollars.
  ///
  /// In en, this message translates to:
  /// **'Amount is too small for USD input.'**
  String get paymentLinkUsdAmountTooSmall;

  /// Reason shown on the disabled USD toggle while the ZEC price in US dollars is loading.
  ///
  /// In en, this message translates to:
  /// **'Fetching USD price…'**
  String get paymentLinkUsdFetchingPrice;

  /// Reason shown on the disabled USD toggle when the ZEC price in US dollars could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'USD price unavailable'**
  String get paymentLinkUsdPriceUnavailable;

  /// Screen reader label of the control that fills in the maximum Gift Card amount; {amount} is the formatted maximum and {currency} its currency symbol.
  ///
  /// In en, this message translates to:
  /// **'Use max: {amount} {currency}'**
  String paymentLinkUseMaxCurrencySemantic(String amount, String currency);

  /// Visible text and screen reader label of the control that fills in the maximum Gift Card amount; {amount} is the formatted maximum.
  ///
  /// In en, this message translates to:
  /// **'Use max: {amount}'**
  String paymentLinkUseMaxSemantic(String amount);

  /// Section heading above Gift Cards that have already been claimed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get paymentLinkUsedSectionLabel;

  /// Action button on a toast or row that opens a Gift Card.
  ///
  /// In en, this message translates to:
  /// **'View card'**
  String get paymentLinkViewCardAction;

  /// Status label of a received Gift Card telling the user how long until it can be claimed; {minutes}:{seconds} is a countdown.
  ///
  /// In en, this message translates to:
  /// **'Wait {minutes}:{seconds} to claim'**
  String paymentLinkWaitToClaim(int minutes, String seconds);

  /// Sample status label (preview only) telling the user how long to wait before a received Gift Card can be claimed.
  ///
  /// In en, this message translates to:
  /// **'Wait 3:45 to claim'**
  String get paymentLinkWaitToClaimSample;

  /// Status label of a created Gift Card telling the user how long until the link is available; {minutes}:{seconds} is a countdown.
  ///
  /// In en, this message translates to:
  /// **'Wait {minutes}:{seconds} to get the link'**
  String paymentLinkWaitToGetLink(int minutes, String seconds);

  /// Secondary line shown while a Gift Card is being prepared.
  ///
  /// In en, this message translates to:
  /// **'This may take a little while.'**
  String get paymentLinkWaitingDescription;

  /// Sample status label (preview only) telling the user how long to wait before the Gift Card link is available.
  ///
  /// In en, this message translates to:
  /// **'Wait 1:15 to get the link'**
  String get paymentLinkWaitingStatusLabel;

  /// Error shown on the account setup screen after redeeming a Gift Card when saving the new wallet could not be finished.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t finish saving your wallet. Try again.'**
  String get paymentLinkWalletSaveRecoveryFailed;

  /// Toast shown when a payment request link waited too long before it could be opened.
  ///
  /// In en, this message translates to:
  /// **'That request link timed out. Open it again to pay.'**
  String get paymentUriExpired;

  /// Toast shown when a payment request link cannot be read.
  ///
  /// In en, this message translates to:
  /// **'This request link isn\'t valid. Ask the sender for a new one.'**
  String get paymentUriMalformed;

  /// Toast shown when a payment request link is opened while an Ironwood migration blocks sending.
  ///
  /// In en, this message translates to:
  /// **'Finish your Ironwood migration before opening request links.'**
  String get paymentUriMigrationSendGate;

  /// Toast shown when a payment request link is opened but no wallet exists yet.
  ///
  /// In en, this message translates to:
  /// **'Set up or import a wallet before opening request links.'**
  String get paymentUriNoWallet;

  /// Toast shown when a payment request link is opened while the user is part-way through wallet setup.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up your wallet before opening request links.'**
  String get paymentUriOnboarding;

  /// Toast shown when a second payment request link arrives before the first one was handled, so only the newest is kept.
  ///
  /// In en, this message translates to:
  /// **'Only the newest request link was kept. Open the earlier one again to pay it.'**
  String get paymentUriReplaced;

  /// Toast shown when a payment request link cannot be opened because of a storage failure or a wallet load error.
  ///
  /// In en, this message translates to:
  /// **'Vizor couldn\'t open this request link. Open it again once your wallet has loaded.'**
  String get paymentUriUnavailable;

  /// Message shown when a payment request link or QR code asks for a feature Vizor does not support, such as several recipients.
  ///
  /// In en, this message translates to:
  /// **'This request link uses a feature Vizor doesn\'t support yet.'**
  String get paymentUriUnsupported;

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

  /// [security] Error shown when the wallet still requires private recovery because turning off Private queries did not finish.
  ///
  /// In en, this message translates to:
  /// **'Turning off Private queries didn\'t finish. Turn it off again in Settings to use transparent funds.'**
  String get privateQueriesOptOutUnfinished;

  /// Button or label that opens the profile picture picker.
  ///
  /// In en, this message translates to:
  /// **'Change profile picture'**
  String get profilePictureChange;

  /// Name of a built-in profile picture character, shown in the profile picture picker; {id} is the picture number such as p01.
  ///
  /// In en, this message translates to:
  /// **'{id, select, p01{Knight} p02{Viking} p03{Samurai} p04{Monarch} p05{Iron helm} p06{Ronin} p07{Skull knight} p08{Seer} p09{Berserker} p10{Rogue} p11{Mage} p12{Masked cat} p13{Warden} p14{Bronze helm} p15{Fish knight} other{}}'**
  String profilePictureName(String id);

  /// Title of the profile picture picker.
  ///
  /// In en, this message translates to:
  /// **'Select profile picture'**
  String get profilePictureSelect;

  /// Error in the profile picture picker when saving failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update profile picture.'**
  String get profilePictureUpdateFailed;

  /// Accessibility label of the help button that explains shielded versus transparent addresses.
  ///
  /// In en, this message translates to:
  /// **'About this address type'**
  String get receiveAboutAddressType;

  /// Text shown in the address line when the address is empty because loading failed.
  ///
  /// In en, this message translates to:
  /// **'Address couldn\'t be loaded. Try again.'**
  String get receiveAddressCouldNotLoad;

  /// Message shown in place of the QR code when the address could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your address. Try again in a moment.'**
  String get receiveAddressLoadFailed;

  /// Button label and accessibility label that copies the transparent address.
  ///
  /// In en, this message translates to:
  /// **'Copy transparent address'**
  String get receiveCopyTransparentAddress;

  /// Accessibility label of the renew button that generates a new shielded address.
  ///
  /// In en, this message translates to:
  /// **'Generate new shielded address'**
  String get receiveGenerateNewShieldedAddress;

  /// [security] Bullet in the shielded address explainer: new addresses come from the same key and reach the same wallet.
  ///
  /// In en, this message translates to:
  /// **'Each new address is a diversified address derived from the same key. They all receive to the same wallet.'**
  String get receiveInfoShieldedDiversified;

  /// [security] Bullet in the shielded address explainer on desktop; says transaction details are encrypted.
  ///
  /// In en, this message translates to:
  /// **'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.'**
  String get receiveInfoShieldedHiddenDesktop;

  /// [security] Bullet in the shielded address explainer on mobile; says transaction details are encrypted. Keep the em dashes.
  ///
  /// In en, this message translates to:
  /// **'Tx details — sender, receiver, and amount — are encrypted on-chain & hidden.'**
  String get receiveInfoShieldedHiddenMobile;

  /// [security] Bullet in the shielded address explainer on desktop about when a new address is generated.
  ///
  /// In en, this message translates to:
  /// **'A new Zcash shielded address is generated only when you click the renew button.'**
  String get receiveInfoShieldedRenewClick;

  /// [security] Bullet in the shielded address explainer on touch devices about when a new address is generated.
  ///
  /// In en, this message translates to:
  /// **'A new Zcash shielded address is generated only when you tap the renew button.'**
  String get receiveInfoShieldedRenewTap;

  /// [security] Subtitle of the shielded address explainer.
  ///
  /// In en, this message translates to:
  /// **'Strong privacy by default.'**
  String get receiveInfoShieldedSubtitle;

  /// Bullet in the transparent address explainer about where transparent addresses are used.
  ///
  /// In en, this message translates to:
  /// **'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.'**
  String get receiveInfoTransparentExchanges;

  /// [security] Bullet in the transparent address explainer on desktop; says transaction details are public.
  ///
  /// In en, this message translates to:
  /// **'All tx details - sender, receiver, and amount - are publicly visible on-chain.'**
  String get receiveInfoTransparentPublicDesktop;

  /// [security] Bullet in the transparent address explainer on mobile; says transaction details are public. Keep the em dashes.
  ///
  /// In en, this message translates to:
  /// **'All tx details — sender, receiver, and amount — are publicly visible on-chain.'**
  String get receiveInfoTransparentPublicMobile;

  /// [security] Bullet in the transparent address explainer: the transparent address rotates after receiving funds.
  ///
  /// In en, this message translates to:
  /// **'After this address receives ZEC and Vizor syncs, your next transparent address will automatically change. Previous addresses still belong to this wallet.'**
  String get receiveInfoTransparentRotates;

  /// [security] Bullet in the transparent address explainer: funds must be shielded before sending. {ticker} is the currency ticker.
  ///
  /// In en, this message translates to:
  /// **'After receiving {ticker} to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.'**
  String receiveInfoTransparentShieldFirst(String ticker);

  /// [security] Subtitle of the transparent address explainer; its activity is public.
  ///
  /// In en, this message translates to:
  /// **'Publicly visible'**
  String get receiveInfoTransparentSubtitle;

  /// Error toast on the Receive screen when saving the payment-request QR image fails.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save the QR image. Try another folder, or copy the request link instead.'**
  String get receiveQrSaveFailed;

  /// Toast on the Receive screen after a payment-request QR image is saved. {folder} is the folder name.
  ///
  /// In en, this message translates to:
  /// **'QR image saved to {folder}'**
  String receiveQrSaved(String folder);

  /// Placeholder shown where a QR code would be when it cannot be drawn.
  ///
  /// In en, this message translates to:
  /// **'QR unavailable'**
  String get receiveQrUnavailable;

  /// Toast and inline error on the Receive screen when generating a new shielded address fails.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t refresh your shielded address. Try again, or use your current one.'**
  String get receiveRenewAddressError;

  /// Inline error under the payment request amount field when the amount has more than 8 decimal places.
  ///
  /// In en, this message translates to:
  /// **'Enter up to 8 decimals'**
  String get receiveRequestAmountDecimalsError;

  /// Inline error under the payment request amount field when the text is not a number.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount like 0.5'**
  String get receiveRequestAmountFormatError;

  /// Inline error under the payment request amount field when the amount is larger than the total ZEC supply.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds the ZEC supply'**
  String get receiveRequestAmountSupplyError;

  /// Button on the mobile Receive screen that opens the payment request sheet, and the title of the payment request dialog on both form factors. {ticker} is the currency ticker such as ZEC.
  ///
  /// In en, this message translates to:
  /// **'Request {ticker}'**
  String receiveRequestButton(String ticker);

  /// Accessibility label of the close button of the payment request dialog.
  ///
  /// In en, this message translates to:
  /// **'Close request'**
  String get receiveRequestCloseRequest;

  /// Error toast on the mobile payment request when copying the link fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t copy the request link. Try sharing it instead.'**
  String get receiveRequestCopyFailed;

  /// Button on the desktop payment request result that copies the request link.
  ///
  /// In en, this message translates to:
  /// **'Copy request link'**
  String get receiveRequestCopyRequestLink;

  /// Button that turns the entered amount and message into a payment request.
  ///
  /// In en, this message translates to:
  /// **'Create request'**
  String get receiveRequestCreate;

  /// Accessibility label of the toggle that switches the amount field to ZEC.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in ZEC'**
  String get receiveRequestEnterZec;

  /// Toast shown after the payment request link is copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Request link copied'**
  String get receiveRequestLinkCopied;

  /// [security] Help text under the payment request message field: the message is stored in the link itself, so anyone who sees the link can read it.
  ///
  /// In en, this message translates to:
  /// **'Shielded addresses only — anyone with this link can read it.'**
  String get receiveRequestMessageHelp;

  /// [security] Placeholder in the payment request message field: the message is readable by anyone who gets the link.
  ///
  /// In en, this message translates to:
  /// **'Anyone you send the link to can read this'**
  String get receiveRequestMessageHint;

  /// Button on the desktop payment request result that saves the QR code as an image file.
  ///
  /// In en, this message translates to:
  /// **'Save QR image'**
  String get receiveRequestSaveQr;

  /// Button on the mobile payment request result that shares the request QR image.
  ///
  /// In en, this message translates to:
  /// **'Share request'**
  String get receiveRequestShare;

  /// Error toast on the mobile payment request when sharing fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share this request. Copy the link instead.'**
  String get receiveRequestShareFailed;

  /// Button on the desktop Receive pane that opens the payment request card.
  ///
  /// In en, this message translates to:
  /// **'Request ZEC'**
  String get receiveRequestZecButton;

  /// Visible label of the mobile Receive button that shares the selected address.
  ///
  /// In en, this message translates to:
  /// **'Share address'**
  String get receiveShareAddress;

  /// Toast on the Receive screen when the system share sheet fails for an address.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share this address. Copy it instead.'**
  String get receiveShareFailed;

  /// Tooltip and accessibility label of the button that shares the shielded address.
  ///
  /// In en, this message translates to:
  /// **'Share shielded address'**
  String get receiveShareShieldedAddress;

  /// Tooltip and accessibility label of the button that shares the transparent address.
  ///
  /// In en, this message translates to:
  /// **'Share transparent address'**
  String get receiveShareTransparentAddress;

  /// Summary line of the inline Receive error when the shielded address could not be read; a technical details line follows.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load your shielded address. Try again in a moment.'**
  String get receiveShieldedAddressLoadFailed;

  /// Title of the Receive screen. {ticker} is the currency ticker such as ZEC.
  ///
  /// In en, this message translates to:
  /// **'Receive {ticker}'**
  String receiveTitle(String ticker);

  /// Summary line of the inline Receive error when the transparent address could not be read; a technical details line follows.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load your transparent address. Try again in a moment.'**
  String get receiveTransparentAddressLoadFailed;

  /// [security] Button that copies the seed phrase to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy secret passphrase'**
  String get secretPassphraseCopy;

  /// [security] Name of the seed phrase screen or step.
  ///
  /// In en, this message translates to:
  /// **'Secret Passphrase'**
  String get secretPassphraseTitle;

  /// Button on the send screen that reveals the optional memo field.
  ///
  /// In en, this message translates to:
  /// **'Add a memo'**
  String get sendAddMemo;

  /// Fallback label for a recipient whose address is a transparent-source-only (TEX) address.
  ///
  /// In en, this message translates to:
  /// **'TEX address'**
  String get sendAddressTypeTex;

  /// [security] Error under the recipient field when checking the address failed unexpectedly.
  ///
  /// In en, this message translates to:
  /// **'Address validation failed'**
  String get sendAddressValidationFailed;

  /// Label of the disabled primary button on the mobile amount step before an amount is entered.
  ///
  /// In en, this message translates to:
  /// **'Enter amount to continue'**
  String get sendAmountCtaEnterAmount;

  /// Error when the user declined the proving-parameter download during a send.
  ///
  /// In en, this message translates to:
  /// **'Sending was cancelled before proving parameters were downloaded.'**
  String get sendBroadcastCancelledBeforeParams;

  /// [security] Status when the first of two linked transactions was accepted but the second did not complete; the user must check Activity before sending again.
  ///
  /// In en, this message translates to:
  /// **'The first transaction was accepted, but the dependent transaction did not complete. Check Activity before sending again.'**
  String get sendBroadcastDependentIncomplete;

  /// [security] Status when confirmation of the first transaction timed out; it may have been sent, so the user must check Activity before sending again.
  ///
  /// In en, this message translates to:
  /// **'The first transaction is stored locally and may have reached the network, but confirmation timed out. Check Activity before sending again.'**
  String get sendBroadcastFirstUnknown;

  /// [security] Error when a hardware-wallet signing request expired before it could be broadcast; the user must return, wait for sync and review the payment again.
  ///
  /// In en, this message translates to:
  /// **'The hardware signing request expired before broadcast. Return to your wallet, wait for sync, then review the payment and try again.'**
  String get sendBroadcastHardwareExpired;

  /// [security] Fallback status when broadcasting did not complete; the user must check Activity before sending again.
  ///
  /// In en, this message translates to:
  /// **'The transaction broadcast did not complete. Check Activity before sending again.'**
  String get sendBroadcastIncomplete;

  /// [security] Ledger-flow status when confirmation of the first transaction timed out; the user must check Activity before sending again.
  ///
  /// In en, this message translates to:
  /// **'The first transaction may have reached the network, but confirmation timed out. Check Activity before sending again.'**
  String get sendBroadcastLedgerFirstUnknown;

  /// [security] Ledger-flow status when the transaction was broadcast but could not be stored locally; the user must not send again until sync or an explorer confirms the status.
  ///
  /// In en, this message translates to:
  /// **'The transaction reached the network, but Vizor could not store it locally. Do not send again until sync or an explorer confirms the latest status.'**
  String get sendBroadcastLedgerNotStored;

  /// Ledger-flow status when the network rejected the transaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction was rejected by the network. Please try again later.'**
  String get sendBroadcastLedgerRejected;

  /// [security] Status when a locally created transaction could not be broadcast; it retries automatically and the user must not send again unless it expires.
  ///
  /// In en, this message translates to:
  /// **'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.'**
  String get sendBroadcastLocalRetry;

  /// [security] Error when the secret passphrase (mnemonic) of the sending account cannot be found on the device.
  ///
  /// In en, this message translates to:
  /// **'Mnemonic not found for the proposal account.'**
  String get sendBroadcastMnemonicMissing;

  /// [security] Status when only part of a multi-transaction send was broadcast; the rest retries automatically and the user must not send again before checking activity.
  ///
  /// In en, this message translates to:
  /// **'Some transactions were broadcast and the rest will retry automatically. Check activity before sending again.'**
  String get sendBroadcastPartial;

  /// Error when the user declines the proving-parameter download while retrying a signed transaction.
  ///
  /// In en, this message translates to:
  /// **'Proof parameters are required to retry this signed transaction.'**
  String get sendBroadcastProofParamsRequired;

  /// [security] Status when the network rejected a locally created transaction; the wallet keeps retrying and the user must not send again unless it expires.
  ///
  /// In en, this message translates to:
  /// **'Transaction was created locally but didn\'t reach the network. The wallet will keep retrying until it expires. Don\'t send again unless this one expires.'**
  String get sendBroadcastRejectedLocal;

  /// [security] Status when the transaction reached the network but the wallet failed to record it; the user must check Activity or an explorer before sending again.
  ///
  /// In en, this message translates to:
  /// **'The transaction reached the network, but local tracking failed. Check Activity or an explorer before sending again.'**
  String get sendBroadcastTrackingFailed;

  /// Message shown while the maximum sendable amount is still being calculated.
  ///
  /// In en, this message translates to:
  /// **'Calculating max amount'**
  String get sendCalculatingMax;

  /// Empty-state title in the contact picker when the user has no Zcash contacts.
  ///
  /// In en, this message translates to:
  /// **'No Zcash contacts'**
  String get sendContactPickerEmpty;

  /// Title of the contact picker modal opened from the send screen, listing Zcash contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts Zcash'**
  String get sendContactPickerTitle;

  /// [security] Title of the sheet that shows the full Vizor donation address so the user can verify it.
  ///
  /// In en, this message translates to:
  /// **'Vizor donation address'**
  String get sendDonationAddressTitle;

  /// Label of the disabled primary button on the mobile recipient step before an address is entered.
  ///
  /// In en, this message translates to:
  /// **'Enter address to continue'**
  String get sendEnterAddressToContinue;

  /// [security] Error shown when the user tries to continue without a valid recipient address.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid address'**
  String get sendEnterValidAddress;

  /// [security] Generic error when broadcasting failed; asks the user to check the wallet's latest status before trying again.
  ///
  /// In en, this message translates to:
  /// **'Transaction couldn\'t be sent. Go back to your wallet and check the latest status.'**
  String get sendErrorCouldNotBeSent;

  /// Generic error when a donation could not be sent.
  ///
  /// In en, this message translates to:
  /// **'Donation failed. Try again.'**
  String get sendErrorDonationFailed;

  /// Error when the transaction expired before it could be broadcast.
  ///
  /// In en, this message translates to:
  /// **'Transaction expired before it could be sent.'**
  String get sendErrorExpiredBeforeSent;

  /// Error when the transaction proposal expired before it could be sent.
  ///
  /// In en, this message translates to:
  /// **'Transaction expired before it could be sent. Try again.'**
  String get sendErrorExpiredTryAgain;

  /// [security] Error shown when the shielded balance cannot cover the amount plus the network fee.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance to cover amount and fee.'**
  String get sendErrorInsufficientShielded;

  /// Error shown when the wallet could not reach the network while sending.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection and try again.'**
  String get sendErrorNetwork;

  /// [security] Error when part of a multi-transaction send was already broadcast; the user must check Activity before retrying to avoid paying twice.
  ///
  /// In en, this message translates to:
  /// **'Some parts of this transaction were sent. Open Activity to see what went through before you try again.'**
  String get sendErrorPartiallySent;

  /// Error when the network rejected the transaction while it was being prepared.
  ///
  /// In en, this message translates to:
  /// **'The network rejected this transaction. Try again.'**
  String get sendErrorRejectedTryAgain;

  /// Error when the network rejected the transaction at broadcast time.
  ///
  /// In en, this message translates to:
  /// **'The network rejected this transaction. Try again later.'**
  String get sendErrorRejectedTryLater;

  /// Generic error when a send could not be completed.
  ///
  /// In en, this message translates to:
  /// **'Send failed. Try again.'**
  String get sendErrorSendFailed;

  /// Error shown when the wallet is still finishing its sync and cannot build a send yet.
  ///
  /// In en, this message translates to:
  /// **'Finishing wallet sync. Try again shortly.'**
  String get sendErrorSyncFinishing;

  /// Accessibility label of the fee row on the mobile review step; opens an explanation of the network fee.
  ///
  /// In en, this message translates to:
  /// **'About the transaction fee'**
  String get sendFeeAboutSemantics;

  /// [security] Notice on the mobile review step when the network fee could not be calculated.
  ///
  /// In en, this message translates to:
  /// **'Fee unavailable. Try again.'**
  String get sendFeeUnavailableTryAgain;

  /// [security] Notice on the mobile review step: the fee changed after the wallet synced, so the user must review the new fee before confirming.
  ///
  /// In en, this message translates to:
  /// **'Fee updated after sync. Review and confirm again.'**
  String get sendFeeUpdatedAfterSync;

  /// Notice on the mobile review step while the wallet is finishing its sync before the fee can be shown.
  ///
  /// In en, this message translates to:
  /// **'Finishing wallet sync.'**
  String get sendFinishingSync;

  /// [security] Error under the send amount field when the amount plus the network fee exceeds the spendable balance. Variant for a shielded or transparent recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance including fee'**
  String get sendInsufficientBalanceIncludingFeeShielded;

  /// [security] Error under the send amount field when the amount plus the network fee exceeds the spendable balance. Variant for a transparent-only (TEX) recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance including fee'**
  String get sendInsufficientBalanceIncludingFeeTex;

  /// [security] Error shown on the send screen when the user tries to review an amount above the spendable balance. Variant for a shielded or transparent recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance.'**
  String get sendInsufficientBalanceSentenceShielded;

  /// [security] Error shown on the send screen when the user tries to review an amount above the spendable balance. Variant for a transparent-only (TEX) recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance.'**
  String get sendInsufficientBalanceSentenceTex;

  /// [security] Error under the send amount field when the amount exceeds the spendable balance. Variant for a shielded or transparent recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance'**
  String get sendInsufficientBalanceShielded;

  /// [security] Error under the send amount field when the amount exceeds the spendable balance. Variant for a transparent-only (TEX) recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance'**
  String get sendInsufficientBalanceTex;

  /// [security] Error under the send amount field when the maximum amount cannot cover the network fee. Variant for a shielded or transparent recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance to cover fee'**
  String get sendInsufficientBalanceToCoverFeeShielded;

  /// [security] Error under the send amount field when the maximum amount cannot cover the network fee. Variant for a transparent-only (TEX) recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance to cover fee'**
  String get sendInsufficientBalanceToCoverFeeTex;

  /// [security] Error under the send amount field when the amount is above the spendable balance; {fee} is the formatted network fee. Variant for a shielded or transparent recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient shielded balance (fee: {fee})'**
  String sendInsufficientBalanceWithFeeShielded(String fee);

  /// [security] Error under the send amount field when the amount is above the spendable balance; {fee} is the formatted network fee. Variant for a transparent-only (TEX) recipient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance (fee: {fee})'**
  String sendInsufficientBalanceWithFeeTex(String fee);

  /// [security] Error under the recipient field when the address is not valid.
  ///
  /// In en, this message translates to:
  /// **'Invalid address'**
  String get sendInvalidAddress;

  /// Error under the amount field when the entered amount cannot be parsed.
  ///
  /// In en, this message translates to:
  /// **'Invalid amount'**
  String get sendInvalidAmount;

  /// Error on the mobile review screen when the Keystone signing request could not be prepared.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared. Go back and try again.'**
  String get sendKeystonePrepareFailedGoBack;

  /// Error on the desktop review screen when the Keystone signing request could not be prepared.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing could not be prepared. Return to Send and try again.'**
  String get sendKeystonePrepareFailedReturnToSend;

  /// [security] Error when the scanned signature QR code does not belong to the signing request currently displayed.
  ///
  /// In en, this message translates to:
  /// **'This QR code does not match the current Keystone signing request.'**
  String get sendKeystoneQrMismatch;

  /// Message shown on the Keystone scan screen when no camera is available.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing uses camera QR scanning only. Connect a camera and try again.'**
  String get sendKeystoneScanCameraOnly;

  /// Error when the scanned QR code is not a valid Keystone signature.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be decoded as a Keystone transaction signature.'**
  String get sendKeystoneScanDecodeFailed;

  /// Subtitle on the desktop Keystone scan screen.
  ///
  /// In en, this message translates to:
  /// **'Hold the QR code steady in front of your camera'**
  String get sendKeystoneScanHoldSteady;

  /// [security] Instruction in the desktop Keystone modal while proofs are still being prepared.
  ///
  /// In en, this message translates to:
  /// **'Scan now. Signature import unlocks after proofs are ready.'**
  String get sendKeystoneScanNow;

  /// Caption under the camera view asking the user to scan the signature QR code shown on the Keystone to finish sending.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to finish sending'**
  String get sendKeystoneScanToFinish;

  /// [security] Instruction on the mobile Keystone screen for a TEX send that needs two device approvals; {index} is 1 or 2.
  ///
  /// In en, this message translates to:
  /// **'This TEX send requires two Keystone approvals. Scan transaction {index} of 2.'**
  String sendKeystoneTexTwoApprovals(int index);

  /// [security] Subtitle of the desktop Keystone modal for a two-transaction send; {index} is 1 or 2.
  ///
  /// In en, this message translates to:
  /// **'Transaction {index} of 2'**
  String sendKeystoneTransactionOfTwo(int index);

  /// Failure message asking the user to reconnect and unlock the Ledger; {instruction} is a sentence telling which app to open on the device.
  ///
  /// In en, this message translates to:
  /// **'Connect and unlock your Ledger. {instruction}'**
  String sendLedgerConnectAndUnlock(String instruction);

  /// Title of the Ledger signing failure panel when Vizor could not complete preparing or signing the transaction.
  ///
  /// In en, this message translates to:
  /// **'Could not finish transaction'**
  String get sendLedgerCouldNotFinishTitle;

  /// Ledger failure message when Vizor failed to prepare the transaction proofs before the device signed.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not prepare the transaction. Try again.'**
  String get sendLedgerCouldNotPrepare;

  /// Title shown when the signed transaction could not be saved locally after the Ledger signed it.
  ///
  /// In en, this message translates to:
  /// **'Could not save signed transaction'**
  String get sendLedgerCouldNotSaveTitle;

  /// [security] Warning that the saved signed transaction could not be verified; the user must not sign or send it again to avoid a duplicate payment.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not verify the saved transaction. Do not sign or send it again.'**
  String get sendLedgerCouldNotVerifySaved;

  /// Button on a Ledger failure panel that discards the failed transaction and returns to build a new one.
  ///
  /// In en, this message translates to:
  /// **'Create new transaction'**
  String get sendLedgerCreateNewTransaction;

  /// [security] Ledger failure message: the expired transaction cannot be signed anymore and the user must start a new one.
  ///
  /// In en, this message translates to:
  /// **'This transaction can no longer be signed. Create and review a new transaction.'**
  String get sendLedgerExpiredMessage;

  /// [security] Ledger failure message: the device already signed, so the user only needs to retry in Vizor without approving again on the Ledger.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open and try again. No new Ledger approval needed.'**
  String get sendLedgerKeepOpenRetry;

  /// [security] Message telling the user to keep Vizor open and retry saving the signed transaction; no new Ledger approval is needed.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open and retry saving. No new Ledger approval needed.'**
  String get sendLedgerKeepOpenRetrySaving;

  /// [security] Failure message when the user declined the transaction on their Ledger device.
  ///
  /// In en, this message translates to:
  /// **'The transaction was rejected on your Ledger.'**
  String get sendLedgerRejectedOnDevice;

  /// [security] Message saying the Ledger signature was kept; the user should retry saving and must not approve another transaction on the device.
  ///
  /// In en, this message translates to:
  /// **'Your Ledger signature is preserved. Retry saving without approving another transaction.'**
  String get sendLedgerSignaturePreservedMessage;

  /// [security] Title shown when the signed transaction could not be verified and must not be signed or sent again.
  ///
  /// In en, this message translates to:
  /// **'Signed transaction needs attention'**
  String get sendLedgerSignedNeedsAttentionTitle;

  /// Title of the failure panel when the Ledger cannot sign this kind of transaction.
  ///
  /// In en, this message translates to:
  /// **'Ledger signing unavailable'**
  String get sendLedgerSigningUnavailableTitle;

  /// Status chip telling the user the failed transaction cannot be reused and a new one must be created.
  ///
  /// In en, this message translates to:
  /// **'New transaction required'**
  String get sendLedgerStatusNewTransactionRequired;

  /// Status chip when a signed Ledger transaction needs recovery before anything else.
  ///
  /// In en, this message translates to:
  /// **'Recovery required'**
  String get sendLedgerStatusRecoveryRequired;

  /// Status chip saying the Ledger signature was kept and saving can be retried.
  ///
  /// In en, this message translates to:
  /// **'Signature preserved'**
  String get sendLedgerStatusSignaturePreserved;

  /// Status chip when the Ledger device app does not support the transaction type.
  ///
  /// In en, this message translates to:
  /// **'Unsupported transaction'**
  String get sendLedgerStatusUnsupportedTransaction;

  /// Message shown on the send screen when the wallet fails to load; {error} is technical error text.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again in a moment.\n\nDetails: {error}'**
  String sendLoadError(String error);

  /// Label of the button on the mobile amount step that fills in the maximum spendable amount.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get sendMaxButton;

  /// Error shown when the user taps Max before entering a valid recipient address.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid address to use Max'**
  String get sendMaxNeedsAddress;

  /// Error under the amount field when the maximum sendable amount could not be calculated.
  ///
  /// In en, this message translates to:
  /// **'Max amount unavailable'**
  String get sendMaxUnavailable;

  /// Prompt on the mobile review step's memo row when no message has been added.
  ///
  /// In en, this message translates to:
  /// **'Add short encrypted message'**
  String get sendMemoAddShortEncrypted;

  /// Label of the memo sheet's button that removes the existing memo.
  ///
  /// In en, this message translates to:
  /// **'Clear memo'**
  String get sendMemoClear;

  /// Value of the message row when expanded; tapping it collapses the full message.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get sendMemoCollapse;

  /// Caption under Add a memo explaining memos work only for shielded recipients.
  ///
  /// In en, this message translates to:
  /// **'Encrypted, for shielded addresses only.'**
  String get sendMemoEncryptedHint;

  /// Placeholder in the memo entry sheet explaining that the message is encrypted for the recipient.
  ///
  /// In en, this message translates to:
  /// **'Only the recipient can read this'**
  String get sendMemoRecipientOnly;

  /// Title of the memo entry sheet and label of its confirm button on the mobile review step.
  ///
  /// In en, this message translates to:
  /// **'Add Memo'**
  String get sendMemoSheetAdd;

  /// Error under the message field when a memo is entered for a transparent recipient.
  ///
  /// In en, this message translates to:
  /// **'Message is only available for shielded addresses'**
  String get sendMemoShieldedOnly;

  /// Muted value shown in place of a message that consists only of spaces or blank lines.
  ///
  /// In en, this message translates to:
  /// **'Whitespace only'**
  String get sendMemoWhitespaceOnly;

  /// Accessibility label of the control that opens the contact picker.
  ///
  /// In en, this message translates to:
  /// **'Open contacts'**
  String get sendOpenContacts;

  /// Button inside the empty recipient field that pastes the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get sendPasteAction;

  /// [security] Shown on the payment request card instead of an amount when the link does not ask for a specific amount.
  ///
  /// In en, this message translates to:
  /// **'Amount not specified'**
  String get sendPaymentRequestAmountNotSpecified;

  /// [security] Warning that a payment request link can be altered by other apps, so the address or amount may not be what the requester intended.
  ///
  /// In en, this message translates to:
  /// **'Other apps can change the address or amount in a request link.'**
  String get sendPaymentRequestCheckBeforePayBody;

  /// [security] Heading of the notice shown when a payment request came from a link and the user is advised to verify it against the original QR code.
  ///
  /// In en, this message translates to:
  /// **'Check before you pay'**
  String get sendPaymentRequestCheckBeforePayTitle;

  /// Fallback status line on the payment request card when checking the request failed without a specific reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check this request'**
  String get sendPaymentRequestCheckFailed;

  /// Status line on the payment request card when the check failed for an unspecified reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check this request — try again or edit the details'**
  String get sendPaymentRequestCheckGeneric;

  /// Status line on the payment request card when the check failed because the network was unreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the network — check your connection and try again'**
  String get sendPaymentRequestCheckNetwork;

  /// Status line on the payment request card when no account is selected.
  ///
  /// In en, this message translates to:
  /// **'No active account — choose one, then open this link again'**
  String get sendPaymentRequestCheckNoAccount;

  /// Status line on the payment request card when the link's amount cannot be paid as written.
  ///
  /// In en, this message translates to:
  /// **'This link doesn\'t ask for a payable amount — enter one to continue'**
  String get sendPaymentRequestCheckNoAmount;

  /// Status line on the payment request card while sending is paused just before a network upgrade.
  ///
  /// In en, this message translates to:
  /// **'Paused for the network upgrade. Try again in a few minutes.'**
  String get sendPaymentRequestCheckUpgradeHold;

  /// Status line on the payment request card when a network upgrade changed the migration schedule.
  ///
  /// In en, this message translates to:
  /// **'The network upgrade changed the migration timing. Review the plan and start again.'**
  String get sendPaymentRequestCheckUpgradeScheduleChanged;

  /// Accessibility label of the button that closes the payment request card.
  ///
  /// In en, this message translates to:
  /// **'Close payment request'**
  String get sendPaymentRequestClose;

  /// [security] Advice in the check-before-you-pay notice to confirm the payment details with the sender when no QR code can be scanned.
  ///
  /// In en, this message translates to:
  /// **'Confirm the details with the person who sent it.'**
  String get sendPaymentRequestConfirmWithSender;

  /// Accessibility label of the control that collapses the full recipient address.
  ///
  /// In en, this message translates to:
  /// **'Hide full recipient address'**
  String get sendPaymentRequestHideFullAddress;

  /// Label of the toggle that collapses the payment details (memo) on the payment request card.
  ///
  /// In en, this message translates to:
  /// **'Hide payment details'**
  String get sendPaymentRequestHidePaymentDetails;

  /// Accessibility label of the toggle that collapses the requester details on the payment request card.
  ///
  /// In en, this message translates to:
  /// **'Hide requester information'**
  String get sendPaymentRequestHideRequesterInfo;

  /// Accessibility label of the toggle that collapses the requester details; {name} is the name supplied by the link.
  ///
  /// In en, this message translates to:
  /// **'Hide requester information for {name}'**
  String sendPaymentRequestHideRequesterInfoFor(String name);

  /// [security] Status line on the payment request card when the spendable balance cannot cover the requested amount plus the network fee.
  ///
  /// In en, this message translates to:
  /// **'Not enough ZEC for this amount and the network fee'**
  String get sendPaymentRequestInsufficientFunds;

  /// [security] Status line on the payment request card when the balance cannot cover the amount plus fee; {spendable} is the spendable amount without a currency suffix.
  ///
  /// In en, this message translates to:
  /// **'Not enough ZEC for this amount and the network fee ({spendable} available)'**
  String sendPaymentRequestInsufficientFundsWithSpendable(String spendable);

  /// [security] Status line on the payment request card when the requested recipient address is not valid.
  ///
  /// In en, this message translates to:
  /// **'Recipient address doesn\'t look right'**
  String get sendPaymentRequestInvalidAddress;

  /// [security] Warning that the payment request link had a different recipient address than the scanned QR code.
  ///
  /// In en, this message translates to:
  /// **'The link had a different address'**
  String get sendPaymentRequestLinkDifferentAddress;

  /// [security] Warning that the payment request link had a different amount than the scanned QR code.
  ///
  /// In en, this message translates to:
  /// **'The link had a different amount'**
  String get sendPaymentRequestLinkDifferentAmount;

  /// [security] Warning that the payment request link differs from the scanned QR code in more than one way.
  ///
  /// In en, this message translates to:
  /// **'The link had different details'**
  String get sendPaymentRequestLinkDifferentDetails;

  /// [security] Warning that the payment request link had a different memo than the scanned QR code.
  ///
  /// In en, this message translates to:
  /// **'The link had a different memo'**
  String get sendPaymentRequestLinkDifferentMemo;

  /// Confirmation on the payment request card that the scanned QR code has the same details as the link.
  ///
  /// In en, this message translates to:
  /// **'Matches the link'**
  String get sendPaymentRequestMatchesLink;

  /// Caption under the payment details toggle saying the request carries a memo.
  ///
  /// In en, this message translates to:
  /// **'Memo included'**
  String get sendPaymentRequestMemoIncluded;

  /// Accessibility value of the payment details toggle saying a memo is included.
  ///
  /// In en, this message translates to:
  /// **'Memo included. View the transaction memo.'**
  String get sendPaymentRequestMemoIncludedHint;

  /// [security] Warning on the payment request card: the requester name is unverified and does not prove who owns the receiving address.
  ///
  /// In en, this message translates to:
  /// **'This name comes from the request. It doesn\'t confirm who owns the receiving address.'**
  String get sendPaymentRequestNameDisclaimer;

  /// Accessibility value saying the shown name was typed into the link by the requester.
  ///
  /// In en, this message translates to:
  /// **'Name supplied in the request.'**
  String get sendPaymentRequestNameSuppliedInRequest;

  /// Label for a note that came with the payment request link, written by whoever created the link.
  ///
  /// In en, this message translates to:
  /// **'Note from requester'**
  String get sendPaymentRequestNoteFromRequester;

  /// Label of the toggle that expands the payment details (memo) on the payment request card.
  ///
  /// In en, this message translates to:
  /// **'Payment details'**
  String get sendPaymentRequestPaymentDetails;

  /// Label above the recipient on the payment request card.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get sendPaymentRequestRecipient;

  /// Small notice on the payment request card saying this request replaced a payment link the user opened earlier.
  ///
  /// In en, this message translates to:
  /// **'Replaced an earlier link'**
  String get sendPaymentRequestReplacedNotice;

  /// Label above the name the requester put in the payment request link.
  ///
  /// In en, this message translates to:
  /// **'Request from'**
  String get sendPaymentRequestRequestFrom;

  /// Button that shows the details of the payment request link.
  ///
  /// In en, this message translates to:
  /// **'Review link details'**
  String get sendPaymentRequestReviewLinkDetails;

  /// Label of the primary button on the payment request card that continues to the review step.
  ///
  /// In en, this message translates to:
  /// **'Review payment'**
  String get sendPaymentRequestReviewPayment;

  /// [security] Advice in the check-before-you-pay notice to scan the requester's original QR code in Vizor instead of trusting a link.
  ///
  /// In en, this message translates to:
  /// **'Scan the original QR code directly in Vizor.'**
  String get sendPaymentRequestScanOriginalHint;

  /// [security] Accessibility label of the control that expands the full recipient address so the user can verify it.
  ///
  /// In en, this message translates to:
  /// **'Show full recipient address'**
  String get sendPaymentRequestShowFullAddress;

  /// Accessibility label of the toggle that expands the requester details on the payment request card.
  ///
  /// In en, this message translates to:
  /// **'Show requester information'**
  String get sendPaymentRequestShowRequesterInfo;

  /// Accessibility label of the toggle that expands the requester details; {name} is the name supplied by the link.
  ///
  /// In en, this message translates to:
  /// **'Show requester information for {name}'**
  String sendPaymentRequestShowRequesterInfoFor(String name);

  /// Status line on the payment request card when syncing has stalled and the user must press Check again later.
  ///
  /// In en, this message translates to:
  /// **'Still syncing — check again when the wallet is up to date'**
  String get sendPaymentRequestSyncStalled;

  /// Status line on the payment request card while the wallet is still syncing; the check reruns automatically afterwards.
  ///
  /// In en, this message translates to:
  /// **'Wallet is still syncing — this will update when it finishes'**
  String get sendPaymentRequestSyncing;

  /// Label above the memo text on the payment request card.
  ///
  /// In en, this message translates to:
  /// **'Transaction memo'**
  String get sendPaymentRequestTransactionMemo;

  /// Accessibility label of a disabled button on the payment request card; {label} is the button label.
  ///
  /// In en, this message translates to:
  /// **'{label}, unavailable'**
  String sendPaymentRequestUnavailableLabel(String label);

  /// Accessibility label of a disabled button on the payment request card; {label} is the button label and {reason} the status message explaining why.
  ///
  /// In en, this message translates to:
  /// **'{label}, unavailable. {reason}'**
  String sendPaymentRequestUnavailableWithReason(String label, String reason);

  /// [security] Explains that the card uses the scanned QR details because the link may have been tampered with.
  ///
  /// In en, this message translates to:
  /// **'Using the QR instead — the link may have been changed.'**
  String get sendPaymentRequestUsingQrInstead;

  /// Prompt on the collapsed requester row to open the requester's note.
  ///
  /// In en, this message translates to:
  /// **'View note'**
  String get sendPaymentRequestViewNote;

  /// Sub-label shown when the recipient address of a request belongs to one of the user's own accounts.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get sendPaymentRequestYourAccount;

  /// Toast shown when the payment-request QR scanner could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the QR scanner. Try again.'**
  String get sendQrScannerOpenFailed;

  /// Section header above recently used recipients on the mobile recipient step.
  ///
  /// In en, this message translates to:
  /// **'Recents'**
  String get sendRecentsSection;

  /// Placeholder in the recipient field; the user can type an address or paste a zcash: payment request link.
  ///
  /// In en, this message translates to:
  /// **'Address or request link'**
  String get sendRecipientHint;

  /// Label above the recipient address field on the send screen.
  ///
  /// In en, this message translates to:
  /// **'Send to'**
  String get sendRecipientLabel;

  /// [security] Error under the recipient field when a pasted zcash: payment link is not a valid address or request.
  ///
  /// In en, this message translates to:
  /// **'This request link couldn\'t be read'**
  String get sendRecipientUnreadableRequestLink;

  /// [security] Error under the recipient field when a well-formed Zcash address belongs to another network than this wallet (for example a testnet address on mainnet).
  ///
  /// In en, this message translates to:
  /// **'This address is for a different Zcash network'**
  String get sendRecipientWrongNetwork;

  /// Error when a scanned payment request QR code could not be checked.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check this QR code. Try again.'**
  String get sendRequestScanCheckFailed;

  /// Error shown after scanning a QR code whose address is not valid.
  ///
  /// In en, this message translates to:
  /// **'This QR code isn\'t a valid Zcash address.'**
  String get sendRequestScanInvalidAddress;

  /// Error shown after scanning a QR code that holds an unreadable zcash: payment request.
  ///
  /// In en, this message translates to:
  /// **'This QR code doesn\'t contain a valid payment request.'**
  String get sendRequestScanInvalidRequest;

  /// Error shown after scanning a QR code that is neither a Zcash address nor a payment request.
  ///
  /// In en, this message translates to:
  /// **'This QR code isn\'t a Zcash address or payment request.'**
  String get sendRequestScanNotRequest;

  /// Explains why camera permission is needed for scanning the payment request QR code and that it can be changed in settings.
  ///
  /// In en, this message translates to:
  /// **'A camera is required to scan the payment request QR code.\nYou can change camera access in settings at any time.'**
  String get sendRequestScanPermission;

  /// Subtitle of the payment request scan screen.
  ///
  /// In en, this message translates to:
  /// **'Show the requester’s original QR code to your camera'**
  String get sendRequestScanSubtitle;

  /// Troubleshooting tip when the payment request QR code cannot be scanned.
  ///
  /// In en, this message translates to:
  /// **'Open the requester’s original QR code full screen on another device.'**
  String get sendRequestScanTipOriginal;

  /// Message when no camera is available for scanning the payment request QR code.
  ///
  /// In en, this message translates to:
  /// **'Connect a camera, or go back and review the link details.'**
  String get sendRequestScanUnavailable;

  /// Error shown after scanning a QR code whose address is for another Zcash network.
  ///
  /// In en, this message translates to:
  /// **'This address belongs to a different network.'**
  String get sendRequestScanWrongNetwork;

  /// Label of the primary button on the send screen that opens the review step.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get sendReviewAction;

  /// [security] Label of the disabled review button while the network fee is being calculated.
  ///
  /// In en, this message translates to:
  /// **'Calculating fee...'**
  String get sendReviewCalculatingFee;

  /// [security] Primary button on the send review screen that approves and broadcasts the transaction.
  ///
  /// In en, this message translates to:
  /// **'Confirm & send'**
  String get sendReviewConfirmAndSend;

  /// [security] Primary button on the mobile review step that approves and sends the transaction.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Send'**
  String get sendReviewConfirmAndSendMobile;

  /// [security] Primary button on the donation review screen.
  ///
  /// In en, this message translates to:
  /// **'Confirm donation'**
  String get sendReviewConfirmDonation;

  /// [security] Primary button on the review screen for a Ledger account; starts signing on the Ledger device.
  ///
  /// In en, this message translates to:
  /// **'Confirm with Ledger'**
  String get sendReviewConfirmWithLedger;

  /// [security] Label of the disabled review button when the network fee could not be determined.
  ///
  /// In en, this message translates to:
  /// **'Fee unavailable'**
  String get sendReviewFeeUnavailable;

  /// Label of the disabled review button while the wallet finishes syncing.
  ///
  /// In en, this message translates to:
  /// **'Finishing wallet sync...'**
  String get sendReviewFinishingSyncButton;

  /// Line under the amount on the payment-request review screen showing the amount the requester asked for; {amount} is a formatted amount with currency.
  ///
  /// In en, this message translates to:
  /// **'Requested {amount}'**
  String sendReviewRequestedAmount(String amount);

  /// Row label on the review screen for the recipient of a payment request; the value is the address or contact that asked to be paid.
  ///
  /// In en, this message translates to:
  /// **'Requested by'**
  String get sendReviewRequestedBy;

  /// [security] Title of the review screen shown before the user approves an irreversible send.
  ///
  /// In en, this message translates to:
  /// **'Review send'**
  String get sendReviewTitle;

  /// Body of the dialog explaining that about 50MB of cryptographic proving parameters must be downloaded to create a private transaction.
  ///
  /// In en, this message translates to:
  /// **'To create this private transaction, your wallet needs to download about 50MB of cryptographic parameters.'**
  String get sendSaplingDownloadBody;

  /// Note under the download explanation: the download happens only once and may use mobile data.
  ///
  /// In en, this message translates to:
  /// **'This happens once, then it\'s done.\nNetwork data charges may apply.'**
  String get sendSaplingDownloadNote;

  /// Title of the dialog asking permission to download proving parameters before a private send.
  ///
  /// In en, this message translates to:
  /// **'Download Required'**
  String get sendSaplingDownloadTitle;

  /// Toast shown after a pasted payment link is reduced to its address because the rest of the request is malformed or unsupported.
  ///
  /// In en, this message translates to:
  /// **'Pasted the address only — the payment request couldn\'t be read'**
  String get sendScanDowngradePastedMalformedRequest;

  /// Toast shown after a pasted payment link is reduced to its first recipient because the link asks to pay several recipients.
  ///
  /// In en, this message translates to:
  /// **'Pasted the first recipient only — this request asks for more than one'**
  String get sendScanDowngradePastedMultipleRecipients;

  /// Toast shown after a pasted payment link is reduced to its address because the memo it carries cannot be read as text.
  ///
  /// In en, this message translates to:
  /// **'Pasted the address only — the request\'s message couldn\'t be read'**
  String get sendScanDowngradePastedUnsupportedMemo;

  /// Message shown after a scanned QR payment request is reduced to its address because the rest of the request is malformed or unsupported.
  ///
  /// In en, this message translates to:
  /// **'Scanned the address only — the payment request couldn\'t be read'**
  String get sendScanDowngradeScannedMalformedRequest;

  /// Message shown after a scanned QR payment request is reduced to its first recipient because it asks to pay several recipients.
  ///
  /// In en, this message translates to:
  /// **'Scanned the first recipient only — this request asks for more than one'**
  String get sendScanDowngradeScannedMultipleRecipients;

  /// Message shown after a scanned QR payment request is reduced to its address because the memo it carries cannot be read as text.
  ///
  /// In en, this message translates to:
  /// **'Scanned the address only — the request\'s message couldn\'t be read'**
  String get sendScanDowngradeScannedUnsupportedMemo;

  /// [security] Error in the mobile scanner when the scanned QR code does not hold a Zcash address.
  ///
  /// In en, this message translates to:
  /// **'This QR code isn\'t a Zcash address.'**
  String get sendScanNotZcashAddress;

  /// Subtitle of the row that opens the QR scanner on the mobile recipient step.
  ///
  /// In en, this message translates to:
  /// **'Scan an address or payment request'**
  String get sendScanQrSubtitle;

  /// Title of the row on the mobile recipient step that opens the QR scanner.
  ///
  /// In en, this message translates to:
  /// **'Scan a QR Code'**
  String get sendScanQrTitle;

  /// Label above the chosen recipient on the mobile amount step.
  ///
  /// In en, this message translates to:
  /// **'Sending to'**
  String get sendSendingToLabel;

  /// Title of the mobile hardware-wallet signing screen.
  ///
  /// In en, this message translates to:
  /// **'Confirm transaction'**
  String get sendSignConfirmTransaction;

  /// Title of the mobile Keystone signing screen for a two-transaction send; {index} is 1 or 2.
  ///
  /// In en, this message translates to:
  /// **'Confirm transaction {index} of 2'**
  String sendSignConfirmTransactionOfTwo(int index);

  /// Accessibility label of the help icon that opens the spendable balance tooltip.
  ///
  /// In en, this message translates to:
  /// **'Spendable balance info'**
  String get sendSpendableInfoLabel;

  /// [security] Body of the tooltip next to Use Max explaining confirmation counts before funds are spendable.
  ///
  /// In en, this message translates to:
  /// **'Funds need confirmations before they can be spent: 3 for change from your own wallet, 6 for funds received from others. Shielded notes also need to be fully scanned. They\'ll become available shortly.'**
  String get sendSpendableTooltipBody;

  /// [security] Bold first line of the tooltip next to Use Max explaining why spendable balance can be lower than total.
  ///
  /// In en, this message translates to:
  /// **'Your spendable balance may be lower than your total balance.'**
  String get sendSpendableTooltipTitle;

  /// Title on the status screen when a donation failed.
  ///
  /// In en, this message translates to:
  /// **'Donation failed'**
  String get sendStatusDonationFailed;

  /// Title on the status screen while a donation is being sent.
  ///
  /// In en, this message translates to:
  /// **'Donation in progress...'**
  String get sendStatusDonationInProgress;

  /// Line on the mobile failed-send screen summarising the attempted payment; {amount} is a formatted amount with currency and {recipient} is a contact name or truncated address.
  ///
  /// In en, this message translates to:
  /// **'{amount} to {recipient}'**
  String sendStatusFailureSummary(String amount, String recipient);

  /// Subtitle on the mobile status screen after a successful send.
  ///
  /// In en, this message translates to:
  /// **'It will confirm on-chain shortly. Track it in Activity.'**
  String get sendStatusMobileConfirmSoon;

  /// Title on the mobile status screen when a donation was created and queued for submission.
  ///
  /// In en, this message translates to:
  /// **'Donation queued'**
  String get sendStatusMobileDonationQueued;

  /// Subtitle on the mobile status screen after a donation succeeded.
  ///
  /// In en, this message translates to:
  /// **'Your support keeps Vizor going.'**
  String get sendStatusMobileDonationSupport;

  /// Title on the mobile status screen after a donation succeeded; the line break is intentional.
  ///
  /// In en, this message translates to:
  /// **'Thank you for\nsupporting Vizor'**
  String get sendStatusMobileDonationThanks;

  /// [security] Subtitle on the mobile status screen after a failed send: nothing left the wallet, so the user's funds are unchanged.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent, your funds haven\'t moved. Try again.'**
  String get sendStatusMobileNothingSent;

  /// [security] Subtitle when the transaction was created but not yet submitted; warns the user to check Activity before sending again so they do not pay twice.
  ///
  /// In en, this message translates to:
  /// **'Your transaction was created and will be submitted automatically. Check the Activity page before sending again.'**
  String get sendStatusMobilePendingDefault;

  /// Title on the mobile status screen when the transaction was created and will be submitted automatically.
  ///
  /// In en, this message translates to:
  /// **'Queued to send'**
  String get sendStatusMobileQueued;

  /// Button on the mobile status screen that returns to Settings after a donation attempt.
  ///
  /// In en, this message translates to:
  /// **'Return to settings'**
  String get sendStatusMobileReturnToSettings;

  /// Title on the mobile status screen while a donation is being sent.
  ///
  /// In en, this message translates to:
  /// **'Sending donation...'**
  String get sendStatusMobileSendingDonation;

  /// Title on the mobile status screen after the transaction was sent.
  ///
  /// In en, this message translates to:
  /// **'Sent!'**
  String get sendStatusMobileSent;

  /// Subtitle on the mobile status screen while the transaction is being submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitting your transaction to the network...'**
  String get sendStatusMobileSubmitting;

  /// [security] Message shown when a signed transaction could not be sent yet; the user should wait for sync and retry the same transaction instead of creating a new one.
  ///
  /// In en, this message translates to:
  /// **'Wait for wallet sync, then retry this signed transaction.'**
  String get sendStatusRetryAfterSync;

  /// Row label on the send receipt for the transaction status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get sendStatusRowStatus;

  /// [security] Heading on the desktop send status screen asking the user to scan the signing QR code shown on their Keystone hardware wallet.
  ///
  /// In en, this message translates to:
  /// **'Scan your Keystone QR Code'**
  String get sendStatusScanKeystoneTitle;

  /// Title on the send status screen while the transaction is being sent.
  ///
  /// In en, this message translates to:
  /// **'Send in progress...'**
  String get sendStatusTitleInProgress;

  /// Title of the second step of the mobile send flow where the user enters the amount.
  ///
  /// In en, this message translates to:
  /// **'Enter Amount'**
  String get sendStepEnterAmount;

  /// [security] Title of the review step of a mobile donation, before the user approves an irreversible payment.
  ///
  /// In en, this message translates to:
  /// **'Review donation'**
  String get sendStepReviewDonation;

  /// [security] Title of the review step of the mobile send flow, before the user approves an irreversible send.
  ///
  /// In en, this message translates to:
  /// **'Review Send'**
  String get sendStepReviewSend;

  /// Page title of the send screen; {currency} is the network ticker such as ZEC.
  ///
  /// In en, this message translates to:
  /// **'Send {currency}'**
  String sendTitle(String currency);

  /// Button label that fills the amount field with the maximum spendable balance.
  ///
  /// In en, this message translates to:
  /// **'Use Max'**
  String get sendUseMax;

  /// Accessibility label of the Use Max button; {spendable} is the formatted spendable balance.
  ///
  /// In en, this message translates to:
  /// **'Use maximum spendable balance, {spendable} available'**
  String sendUseMaxSemantics(String spendable);

  /// Accessibility label of the Max button on the mobile amount step.
  ///
  /// In en, this message translates to:
  /// **'Use maximum spendable balance'**
  String get sendUseMaxSemanticsShort;

  /// Sub-line under a saved contact's name in the verify-address dialog giving how many earlier transactions were sent to them.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 previous transaction} other{{count} previous transactions}}'**
  String sendVerifyAddressPreviousTransactions(int count);

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

  /// Prefix (with trailing space) before the highlighted host and port of the endpoint in use.
  ///
  /// In en, this message translates to:
  /// **'Current: '**
  String get settingsEndpointCurrentPrefix;

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

  /// Settings > Explorer field error when the field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter an explorer URL.'**
  String get settingsExplorerErrorEmpty;

  /// Settings > Explorer field error when the URL has no host. Keep explorer.example as is.
  ///
  /// In en, this message translates to:
  /// **'Enter a host, like explorer.example.'**
  String get settingsExplorerErrorHost;

  /// Settings > Explorer field error when the URL is not http or https.
  ///
  /// In en, this message translates to:
  /// **'Enter an http or https URL.'**
  String get settingsExplorerErrorScheme;

  /// [security] Privacy note under the block explorer setting: opening a public explorer can link the user's IP address to a transaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction links open in this explorer. Use ZecBlock or another site you prefer. Opening a public explorer after you send can link your IP address to that transaction.'**
  String get settingsExplorerPrivacyCopy;

  /// Error shown under the custom explorer URL field when saving it failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that explorer URL.'**
  String get settingsExplorerSaveFailed;

  /// Hint under the custom block explorer field; {txid} and {txHash} are the literal URL placeholders the user types, passed in as arguments, and must stay unchanged in translation.
  ///
  /// In en, this message translates to:
  /// **'Use {txid} or {txHash} in the path, or enter just the origin.'**
  String settingsExplorerTemplateHint(String txid, String txHash);

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

  /// Explains the keep-screen-awake setting during sync and that the app still locks after one minute of inactivity.
  ///
  /// In en, this message translates to:
  /// **'Prevents your phone from sleeping so sync can finish faster. The app still locks after 1 minute of inactivity.'**
  String get settingsKeepAwakeDescription;

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

  /// Placeholder inside the wallet password field on the access confirmation card.
  ///
  /// In en, this message translates to:
  /// **'Your password...'**
  String get settingsPasswordHint;

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

  /// [security] Description under the Private queries setting.
  ///
  /// In en, this message translates to:
  /// **'Experimental. Recovers transparent funds privately, preventing the server from learning your transparent addresses. Looks up supported transactions without revealing their IDs to servers.'**
  String get settingsPrivateQueriesCopy;

  /// Extra sentence on iOS under the Private queries description: migration confirmations are not checked in the background while it is on.
  ///
  /// In en, this message translates to:
  /// **'While on, migration confirmations are checked only when Vizor is open.'**
  String get settingsPrivateQueriesIosNote;

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

  /// [security] Body of the warning about screenshots of the Secret Passphrase. {highlight} is the bold phrase 'Screenshots are not reliable' and can be moved anywhere in the first sentence.
  ///
  /// In en, this message translates to:
  /// **'{highlight}. Anyone who has access to your phone or your photo library will be able to see your Secret Passphrase. Write down your Phrase on a piece of paper instead.'**
  String settingsSeedScreenshotBody(String highlight);

  /// [security] Bold phrase inserted into the screenshot warning body, where it starts the first sentence.
  ///
  /// In en, this message translates to:
  /// **'Screenshots are not reliable'**
  String get settingsSeedScreenshotBodyLead;

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

  /// Destructive button that confirms turning off a setting such as private queries or a biometric unlock.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get settingsTurnOffConfirm;

  /// [security] Blocks uninstalling while swaps are still in progress, because funds could arrive after the wipe and be lost.
  ///
  /// In en, this message translates to:
  /// **'This wallet has {count, plural, =1{1 active swap} other{{count} active swaps}}. Wait for them to complete before uninstalling.'**
  String settingsUninstallActiveSwaps(int count);

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

  /// [security] Heading and button label for setting a new wallet password.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get settingsUpdatePasswordTitle;

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

  /// Screen-reader label of the sidebar button that hides amounts.
  ///
  /// In en, this message translates to:
  /// **'Hide balance'**
  String get sidebarHideBalance;

  /// Sidebar Ironwood migration item when the user must act.
  ///
  /// In en, this message translates to:
  /// **'Needs input'**
  String get sidebarMigrationNeedsInput;

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

  /// Primary button label on the swap screen that opens the recipient address editor.
  ///
  /// In en, this message translates to:
  /// **'Add recipient address'**
  String get swapActionAddRecipientAddress;

  /// Primary button label on the swap screen that opens the refund address editor.
  ///
  /// In en, this message translates to:
  /// **'Add refund address'**
  String get swapActionAddRefundAddress;

  /// Primary button label on the swap screen while a quote is loading.
  ///
  /// In en, this message translates to:
  /// **'Getting quote'**
  String get swapActionGettingQuote;

  /// Default contact label suggestion when saving a swap refund address to the address book.
  ///
  /// In en, this message translates to:
  /// **'{symbol} refund'**
  String swapActivityAddressBookRefund(String symbol);

  /// Compact countdown until the deposit deadline in hours (two or more); 'hrs' abbreviates hours.
  ///
  /// In en, this message translates to:
  /// **'{hours}hrs'**
  String swapActivityDeadlineHours(int hours);

  /// Compact countdown until the deposit deadline in minutes (two or more); 'mins' abbreviates minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}mins'**
  String swapActivityDeadlineMinutes(int minutes);

  /// Label of the deposited amount on a failed or refunded swap status screen.
  ///
  /// In en, this message translates to:
  /// **'Deposit amount'**
  String get swapActivityDepositAmount;

  /// Lowercase fallback name of the deposited asset when a swap record has no symbol.
  ///
  /// In en, this message translates to:
  /// **'deposit asset'**
  String get swapActivityDepositAssetFallback;

  /// Label of the deposit address field when the user sends the asset from Vizor.
  ///
  /// In en, this message translates to:
  /// **'{symbol} deposit'**
  String swapActivityDepositInstructionDepositLabel(String symbol);

  /// Warning under a one-time deposit address QR code.
  ///
  /// In en, this message translates to:
  /// **'Do not reuse this address'**
  String get swapActivityDepositInstructionReuseWarning;

  /// Instruction title telling the user to send the asset from its own chain.
  ///
  /// In en, this message translates to:
  /// **'Send {symbol} from source chain'**
  String swapActivityDepositInstructionSendFromSource(String symbol);

  /// Label of the deposit address field when the user sends the asset from its source chain.
  ///
  /// In en, this message translates to:
  /// **'{symbol} source deposit'**
  String swapActivityDepositInstructionSourceDepositLabel(String symbol);

  /// Button that submits the deposit transaction hash.
  ///
  /// In en, this message translates to:
  /// **'Submit {symbol} deposit'**
  String swapActivityDepositInstructionSubmit(String symbol);

  /// Placeholder of the field where the user enters the deposit transaction hash.
  ///
  /// In en, this message translates to:
  /// **'{symbol} source-chain transaction hash'**
  String swapActivityDepositInstructionTxHashHint(String symbol);

  /// Label of the field where the user enters the deposit transaction hash.
  ///
  /// In en, this message translates to:
  /// **'{symbol} deposit tx hash'**
  String swapActivityDepositInstructionTxHashLabel(String symbol);

  /// Value of the slippage tolerance row when the swap used the quote's own setting.
  ///
  /// In en, this message translates to:
  /// **'Configured quote'**
  String get swapActivityDetailConfiguredQuote;

  /// Label of a status detail row holding the transaction hash that delivered the asset to the recipient.
  ///
  /// In en, this message translates to:
  /// **'{symbol} delivery tx'**
  String swapActivityDetailDeliveryTx(String symbol);

  /// Label of a status detail row with the time by which the deposit must arrive.
  ///
  /// In en, this message translates to:
  /// **'Deposit deadline'**
  String get swapActivityDetailDepositDeadline;

  /// Label of a status detail row holding the address the user deposits the asset to.
  ///
  /// In en, this message translates to:
  /// **'Deposit {symbol} to'**
  String swapActivityDetailDepositTo(String symbol);

  /// Label of a status detail row holding the transaction hash of the deposit.
  ///
  /// In en, this message translates to:
  /// **'{symbol} deposit tx'**
  String swapActivityDetailDepositTx(String symbol);

  /// Label of a status detail row with the deposit amount the provider detected.
  ///
  /// In en, this message translates to:
  /// **'Detected deposit'**
  String get swapActivityDetailDetectedDeposit;

  /// Label of a status detail row with the fees of a payment.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get swapActivityDetailFees;

  /// Value of the fees row when the fee is already included in the quote.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get swapActivityDetailIncluded;

  /// Value of the swap fee row when the fee is already part of the displayed rate.
  ///
  /// In en, this message translates to:
  /// **'Included in shown rate'**
  String get swapActivityDetailIncludedInRate;

  /// Label of a status detail row with how much more the user must deposit.
  ///
  /// In en, this message translates to:
  /// **'Missing deposit'**
  String get swapActivityDetailMissingDeposit;

  /// Label of a status detail row with the slippage a finished swap actually had.
  ///
  /// In en, this message translates to:
  /// **'Realized slippage'**
  String get swapActivityDetailRealizedSlippage;

  /// Label of a status detail row with the deposit amount the swap requires.
  ///
  /// In en, this message translates to:
  /// **'Required deposit'**
  String get swapActivityDetailRequiredDeposit;

  /// Label of a status detail row holding the shielded transaction hash that spent the asset.
  ///
  /// In en, this message translates to:
  /// **'{symbol} tx (shielded)'**
  String swapActivityDetailSourceTxShielded(String symbol);

  /// Label of a status detail row with the total fees of a swap.
  ///
  /// In en, this message translates to:
  /// **'Total fees'**
  String get swapActivityDetailTotalFees;

  /// Label of the quoted receive amount on a failed or refunded swap status screen, since nothing was delivered.
  ///
  /// In en, this message translates to:
  /// **'Expected to receive'**
  String get swapActivityExpectedToReceive;

  /// Title and status of a swap whose deposit was smaller than required.
  ///
  /// In en, this message translates to:
  /// **'Incomplete deposit'**
  String get swapActivityIncompleteDeposit;

  /// Title of a payment status screen when the deposit was smaller than required.
  ///
  /// In en, this message translates to:
  /// **'Incomplete payment'**
  String get swapActivityIncompletePayment;

  /// Under a progress step: the provider status was checked less than a minute ago.
  ///
  /// In en, this message translates to:
  /// **'Last check: just now'**
  String get swapActivityLastCheckJustNow;

  /// Under a progress step: the provider status was checked this many minutes ago; 'm' abbreviates minutes.
  ///
  /// In en, this message translates to:
  /// **'Last check: {minutes}m ago'**
  String swapActivityLastCheckMinutesAgo(int minutes);

  /// Value shown in a status row when the provider or wallet has no data for it yet.
  ///
  /// In en, this message translates to:
  /// **'Not reported'**
  String get swapActivityNotReported;

  /// Title of the pay status header after a payment completed.
  ///
  /// In en, this message translates to:
  /// **'Paid successfully'**
  String get swapActivityPaidSuccessfullyTitle;

  /// Title of the pay status header while a payment is in progress.
  ///
  /// In en, this message translates to:
  /// **'Pay in progress...'**
  String get swapActivityPayInProgressTitle;

  /// Title of a payment status screen after the payment completed.
  ///
  /// In en, this message translates to:
  /// **'Payment complete'**
  String get swapActivityPaymentComplete;

  /// Empty state of the contact picker for recipients.
  ///
  /// In en, this message translates to:
  /// **'No saved {symbol} recipients'**
  String swapActivityPickerNoRecipients(String symbol);

  /// Empty state of the contact picker for refund addresses.
  ///
  /// In en, this message translates to:
  /// **'No saved {symbol} refunds'**
  String swapActivityPickerNoRefunds(String symbol);

  /// Title of the contact picker when choosing a recipient of the swapped asset.
  ///
  /// In en, this message translates to:
  /// **'{symbol} recipients'**
  String swapActivityPickerRecipientsTitle(String symbol);

  /// Title of the contact picker when choosing a refund address for the deposited asset.
  ///
  /// In en, this message translates to:
  /// **'{symbol} refunds'**
  String swapActivityPickerRefundsTitle(String symbol);

  /// Lowercase fallback name of the received asset when a swap record has no symbol.
  ///
  /// In en, this message translates to:
  /// **'receive asset'**
  String get swapActivityReceiveAssetFallback;

  /// Label of the amount the payment recipient received, on a completed payment status screen.
  ///
  /// In en, this message translates to:
  /// **'Recipient received'**
  String get swapActivityRecipientReceived;

  /// Hint of the swap destination field: an address or account on the named chain.
  ///
  /// In en, this message translates to:
  /// **'{chain} address or account'**
  String swapActivityStateAddressOrAccountHint(String chain);

  /// Error when the selected asset on the selected chain cannot be swapped.
  ///
  /// In en, this message translates to:
  /// **'{symbol} on {chain} is not currently supported.'**
  String swapActivityStateAssetUnsupported(String symbol, String chain);

  /// Error under the amount field when the entered amount has more decimals than the asset supports.
  ///
  /// In en, this message translates to:
  /// **'{symbol} supports up to {decimals} decimal places.'**
  String swapActivityStateDecimalPlaces(String symbol, int decimals);

  /// Label of the address field of the swap address modal when the user sends ZEC.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get swapActivityStateDestination;

  /// Warning on review when the live quote delivers more than the earlier estimate.
  ///
  /// In en, this message translates to:
  /// **'Live quote is {percent}% higher than the earlier estimate. Check the guaranteed minimum before you continue.'**
  String swapActivityStateQuoteHigher(String percent);

  /// Warning on review when the live quote delivers less than the earlier estimate.
  ///
  /// In en, this message translates to:
  /// **'Live quote is {percent}% lower than the earlier estimate. Check the guaranteed minimum before you continue.'**
  String swapActivityStateQuoteLower(String percent);

  /// Warning on review when the live quote needs a different amount of the sold asset than the earlier estimate.
  ///
  /// In en, this message translates to:
  /// **'Live quote uses {liveAmount} {symbol} instead of {estimateAmount} {symbol}. Check the guaranteed minimum before you continue.'**
  String swapActivityStateQuoteUsesDifferentSell(
    String liveAmount,
    String estimateAmount,
    String symbol,
  );

  /// Status label of a swap that is waiting for the deposit.
  ///
  /// In en, this message translates to:
  /// **'Awaiting deposit'**
  String get swapActivityStatusAwaitingDeposit;

  /// Status label of a swap that is waiting for the user to send a deposit from another chain.
  ///
  /// In en, this message translates to:
  /// **'Awaiting external deposit'**
  String get swapActivityStatusAwaitingExternalDeposit;

  /// Status label of a completed swap.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get swapActivityStatusComplete;

  /// Status label of a swap whose deposit was seen by the provider.
  ///
  /// In en, this message translates to:
  /// **'Deposit observed'**
  String get swapActivityStatusDepositObserved;

  /// Status label of a swap whose quote or deposit window expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get swapActivityStatusExpired;

  /// Status label of a swap that the provider is processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get swapActivityStatusProcessing;

  /// Title of the second payment progress step.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get swapActivityStepConvert;

  /// Description of the second payment progress step.
  ///
  /// In en, this message translates to:
  /// **'Converting the shielded spend into the payment asset.'**
  String get swapActivityStepConvertDescription;

  /// Title of the active second payment progress step.
  ///
  /// In en, this message translates to:
  /// **'Converting...'**
  String get swapActivityStepConverting;

  /// Title of a progress step: the provider delivers the asset to the recipient.
  ///
  /// In en, this message translates to:
  /// **'Deliver {symbol}'**
  String swapActivityStepDeliver(String symbol);

  /// Title of the active swap delivery progress step.
  ///
  /// In en, this message translates to:
  /// **'Deliver {symbol}...'**
  String swapActivityStepDeliverActive(String symbol);

  /// Description of the payment delivery progress step.
  ///
  /// In en, this message translates to:
  /// **'Delivering the payment to the recipient address.'**
  String get swapActivityStepDeliverPayDescription;

  /// Description of the last swap progress step.
  ///
  /// In en, this message translates to:
  /// **'Delivering the output asset to the recipient address.'**
  String get swapActivityStepDeliverSwapDescription;

  /// Title of the active payment delivery progress step.
  ///
  /// In en, this message translates to:
  /// **'Delivering {symbol}...'**
  String swapActivityStepDelivering(String symbol);

  /// Title of the pending first swap progress step when the user deposits an external asset.
  ///
  /// In en, this message translates to:
  /// **'Deposit {symbol}'**
  String swapActivityStepDeposit(String symbol);

  /// Title of the second swap progress step.
  ///
  /// In en, this message translates to:
  /// **'Deposit confirmation'**
  String get swapActivityStepDepositConfirmation;

  /// Title of the active second swap progress step.
  ///
  /// In en, this message translates to:
  /// **'Deposit confirmation...'**
  String get swapActivityStepDepositConfirmationActive;

  /// Description of the second swap progress step.
  ///
  /// In en, this message translates to:
  /// **'Confirming the deposit before the swap route starts.'**
  String get swapActivityStepDepositConfirmationDescription;

  /// Title of the completed first swap progress step when the user deposits an external asset.
  ///
  /// In en, this message translates to:
  /// **'{symbol} Deposited'**
  String swapActivityStepDeposited(String symbol);

  /// Title of the active first swap progress step when the user deposits an external asset.
  ///
  /// In en, this message translates to:
  /// **'Depositing {symbol}...'**
  String swapActivityStepDepositing(String symbol);

  /// Title of the last payment progress step.
  ///
  /// In en, this message translates to:
  /// **'Recipient receives'**
  String get swapActivityStepRecipientReceives;

  /// Title of the active last payment progress step.
  ///
  /// In en, this message translates to:
  /// **'Recipient receives {symbol}...'**
  String swapActivityStepRecipientReceivesAsset(String symbol);

  /// Description of the last payment progress step.
  ///
  /// In en, this message translates to:
  /// **'Confirming the recipient-side payment.'**
  String get swapActivityStepRecipientReceivesDescription;

  /// Title of a progress step or button: send the asset.
  ///
  /// In en, this message translates to:
  /// **'Send {symbol}'**
  String swapActivityStepSend(String symbol);

  /// Title of the active swap delivery progress step when the provider sends the external asset to the user.
  ///
  /// In en, this message translates to:
  /// **'Send {symbol}...'**
  String swapActivityStepSendActive(String symbol);

  /// Title of the active first swap progress step when the user sends the asset.
  ///
  /// In en, this message translates to:
  /// **'Sending {symbol}...'**
  String swapActivityStepSending(String symbol);

  /// Title of the completed first swap progress step when the user sends the asset.
  ///
  /// In en, this message translates to:
  /// **'{symbol} sent'**
  String swapActivityStepSent(String symbol);

  /// Description of the first swap progress step: waiting for the source chain and provider to recognise the deposit.
  ///
  /// In en, this message translates to:
  /// **'Confirm waiting for the source chain and provider to recognise the deposit'**
  String get swapActivityStepSourceDescription;

  /// Title of the first payment progress step: spending the asset from the shielded balance.
  ///
  /// In en, this message translates to:
  /// **'Spend {symbol}'**
  String swapActivityStepSpend(String symbol);

  /// Description of the first payment progress step.
  ///
  /// In en, this message translates to:
  /// **'Spending from shielded balance.'**
  String get swapActivityStepSpendDescription;

  /// Title of the active first payment progress step.
  ///
  /// In en, this message translates to:
  /// **'Spending {symbol}...'**
  String swapActivityStepSpending(String symbol);

  /// Title of the completed first payment progress step.
  ///
  /// In en, this message translates to:
  /// **'{symbol} spent'**
  String swapActivityStepSpent(String symbol);

  /// Title of the third swap progress step.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get swapActivityStepSwap;

  /// Title of the active third swap progress step.
  ///
  /// In en, this message translates to:
  /// **'Swap...'**
  String get swapActivityStepSwapActive;

  /// Description of the third swap progress step.
  ///
  /// In en, this message translates to:
  /// **'The provider is executing the swap route.'**
  String get swapActivityStepSwapDescription;

  /// Title of a swap status screen after the swap completed.
  ///
  /// In en, this message translates to:
  /// **'Swap completed'**
  String get swapActivitySwapCompleted;

  /// Title of a swap status screen while the swap is in progress.
  ///
  /// In en, this message translates to:
  /// **'Swap in progress...'**
  String get swapActivitySwapInProgress;

  /// Tooltip of the swap fee rows.
  ///
  /// In en, this message translates to:
  /// **'Covers our fee and the route providers\' costs to process this swap. Already included in the rate above.'**
  String get swapActivityTooltipFees;

  /// Tooltip of the guaranteed minimum row, naming the received asset.
  ///
  /// In en, this message translates to:
  /// **'The lowest amount of {symbol} you\'ll get after slippage. You may get more, never less.'**
  String swapActivityTooltipMinimumReceive(String symbol);

  /// Tooltip of the guaranteed minimum row when no asset is named.
  ///
  /// In en, this message translates to:
  /// **'The lowest amount you\'ll get after slippage. You may get more, never less.'**
  String get swapActivityTooltipMinimumReceiveGeneric;

  /// Tooltip explaining the slippage tolerance row.
  ///
  /// In en, this message translates to:
  /// **'How much of the received amount your slippage tolerance protects. The swap is refunded if the rate moves past this.'**
  String get swapActivityTooltipPriceProtection;

  /// Tooltip of a status detail row without its own explanation.
  ///
  /// In en, this message translates to:
  /// **'Details are based on the latest swap record and provider status.'**
  String get swapActivityTooltipStatusDetail;

  /// Label of the amount the user paid, on a completed swap or payment status screen.
  ///
  /// In en, this message translates to:
  /// **'You paid'**
  String get swapActivityYouPaid;

  /// Label of the amount received on a completed swap status screen.
  ///
  /// In en, this message translates to:
  /// **'You received'**
  String get swapActivityYouReceived;

  /// Helper text in the swap address editor explaining where the swapped asset is sent; {symbol} is the asset ticker.
  ///
  /// In en, this message translates to:
  /// **'Your {symbol} will be delivered to this address.'**
  String swapAddressRecipientDescription(String symbol);

  /// Field label above the recipient address input in the swap address editor.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get swapAddressRecipientFieldLabel;

  /// Title of the swap address editor when the user receives an external asset; {symbol} is the asset ticker.
  ///
  /// In en, this message translates to:
  /// **'{symbol} recipient address'**
  String swapAddressRecipientTitle(String symbol);

  /// Helper text in the swap address editor explaining where a refund is sent; {symbol} is the asset ticker and {chain} the chain name.
  ///
  /// In en, this message translates to:
  /// **'If the swap fails or the rate moves, you\'ll be refunded in {symbol} on {chain}, minus the fee.'**
  String swapAddressRefundDescription(String symbol, String chain);

  /// Toggle label in the swap address editor that saves the address for future recipients.
  ///
  /// In en, this message translates to:
  /// **'Remember this address for recipients'**
  String get swapAddressRememberRecipient;

  /// Toggle label in the swap address editor that saves the address for future refunds.
  ///
  /// In en, this message translates to:
  /// **'Remember this address for refunds'**
  String get swapAddressRememberRefund;

  /// Empty-state text in the swap asset picker when the search has no match.
  ///
  /// In en, this message translates to:
  /// **'No tokens or chains found'**
  String get swapAssetSelectorEmpty;

  /// Placeholder of the search field in the swap asset picker.
  ///
  /// In en, this message translates to:
  /// **'Search token or chain'**
  String get swapAssetSelectorSearchHint;

  /// Title of the modal that lists assets to swap.
  ///
  /// In en, this message translates to:
  /// **'Select asset'**
  String get swapAssetSelectorTitle;

  /// Placeholder in the swap composer address row when no recipient address is set; tapping opens the editor.
  ///
  /// In en, this message translates to:
  /// **'Add recipient address...'**
  String get swapComposerAddRecipientAddressEllipsis;

  /// Placeholder in the swap composer address row when no refund address is set; tapping opens the editor.
  ///
  /// In en, this message translates to:
  /// **'Add refund address...'**
  String get swapComposerAddRefundAddressEllipsis;

  /// Button text in the swap composer showing the maximum amount available to swap; {amount} is a formatted amount with its ticker.
  ///
  /// In en, this message translates to:
  /// **'Max: {amount}'**
  String swapComposerMaxAmount(String amount);

  /// Label above the amount the user gets in the swap composer.
  ///
  /// In en, this message translates to:
  /// **'You receive'**
  String get swapComposerYouReceive;

  /// Toast on mobile after the user tries to save a swap address that is already in the address book.
  ///
  /// In en, this message translates to:
  /// **'Already in your address book'**
  String get swapContactAlreadyInAddressBook;

  /// Toast shown after the user tries to save a swap address that is already in the address book.
  ///
  /// In en, this message translates to:
  /// **'Already in your contacts'**
  String get swapContactAlreadySaved;

  /// Toast after the user copies the deposit amount on desktop.
  ///
  /// In en, this message translates to:
  /// **'Amount Copied'**
  String get swapDepositAmountCopiedDesktop;

  /// Toast after the user copies the deposit amount on mobile.
  ///
  /// In en, this message translates to:
  /// **'Amount copied'**
  String get swapDepositAmountCopiedMobile;

  /// Row label for the amount to send on the mobile deposit screen.
  ///
  /// In en, this message translates to:
  /// **'Amount to deposit'**
  String get swapDepositAmountToDeposit;

  /// Button text while the wallet checks whether the user’s deposit arrived.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get swapDepositChecking;

  /// Button on the desktop deposit screen the user taps after sending funds to the one-time deposit address.
  ///
  /// In en, this message translates to:
  /// **'I\'ve deposited'**
  String get swapDepositDoneDesktop;

  /// Button on the mobile deposit screen the user taps after sending funds to the one-time deposit address.
  ///
  /// In en, this message translates to:
  /// **'I’ve deposited tokens'**
  String get swapDepositDoneMobile;

  /// Deposit deadline label for several hours remaining; {count} is the number of hours.
  ///
  /// In en, this message translates to:
  /// **'{count}hrs'**
  String swapDepositHoursMany(int count);

  /// Toast after the user copies the deposit memo.
  ///
  /// In en, this message translates to:
  /// **'Memo copied'**
  String get swapDepositMemoCopied;

  /// Deposit deadline label for several minutes remaining; {count} is the number of minutes.
  ///
  /// In en, this message translates to:
  /// **'{count}mins'**
  String swapDepositMinutesMany(int count);

  /// [security] Row label for the one-time deposit address; it must not be reused.
  ///
  /// In en, this message translates to:
  /// **'One-time address'**
  String get swapDepositOneTimeAddress;

  /// [security] Warning under the deposit address telling the user to send only this asset on this chain, otherwise funds may be lost; {symbol} is the ticker and {chain} the chain name.
  ///
  /// In en, this message translates to:
  /// **'Send only {symbol} on {chain}'**
  String swapDepositSendOnly(String symbol, String chain);

  /// [security] Body on the desktop deposit screen after the deposit window ended; the deposit address must not be used any more. Contains a line break.
  ///
  /// In en, this message translates to:
  /// **'This deposit address is no longer valid.\nPlease, start another swap transaction.'**
  String get swapDepositTimeoutBody;

  /// Title of the desktop screen showing the one-time deposit address for a swap.
  ///
  /// In en, this message translates to:
  /// **'Deposit tokens'**
  String get swapDepositTitle;

  /// Label before the countdown showing how long the user has to deposit.
  ///
  /// In en, this message translates to:
  /// **'Deposit within'**
  String get swapDepositWithin;

  /// Button on the deposit screen that sends the ZEC deposit from the wallet.
  ///
  /// In en, this message translates to:
  /// **'Deposit ZEC'**
  String get swapDepositZecButton;

  /// Accessibility label of the tappable backdrop behind swap modals on mobile.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get swapDismissBarrierLabel;

  /// Swap or Pay quote error: the amount has more decimal places than the token supports.
  ///
  /// In en, this message translates to:
  /// **'Amount has too many decimal places.\nUse fewer decimals and try again.'**
  String get swapFailureAmountPrecision;

  /// Pay error under the amount field: the payment provider rejected the amount as below its minimum.
  ///
  /// In en, this message translates to:
  /// **'Amount is too low for this payment.\nTry a larger amount.'**
  String get swapFailureAmountTooLowPay;

  /// Swap error under the amount field: the swap provider rejected the amount as below its minimum.
  ///
  /// In en, this message translates to:
  /// **'Amount is too low for this swap.\nTry a larger amount.'**
  String get swapFailureAmountTooLowSwap;

  /// Swap or Pay error: the provider does not currently offer the chosen asset.
  ///
  /// In en, this message translates to:
  /// **'This asset is not available for swap right now.\nChoose another asset or try again later.'**
  String get swapFailureAssetUnavailable;

  /// Swap status panel: the provider has not seen the deposit transaction yet.
  ///
  /// In en, this message translates to:
  /// **'Deposit is not indexed yet.\nCheck again in a few minutes.'**
  String get swapFailureDepositNotIndexed;

  /// [security] Swap status panel: the provider rejected the submitted deposit transaction. Tells the user which deposit details to check.
  ///
  /// In en, this message translates to:
  /// **'Deposit transaction was rejected.\nCheck the address, memo, and tx hash.'**
  String get swapFailureDepositRejected;

  /// Swap status panel: telling the provider about the deposit transaction failed.
  ///
  /// In en, this message translates to:
  /// **'Deposit status could not be submitted.\nTry again later.'**
  String get swapFailureDepositSubmitFailed;

  /// Swap or Pay quote error: no provider can fill this route or amount.
  ///
  /// In en, this message translates to:
  /// **'No quote is available for this route or amount.\nAdjust the amount, slippage, or asset and try again.'**
  String get swapFailureNoQuote;

  /// Swap or Pay error: the quote request to the provider timed out.
  ///
  /// In en, this message translates to:
  /// **'Quote request timed out.\nCheck your connection and try again.'**
  String get swapFailureQuoteTimeout;

  /// Swap or Pay error: requesting a quote failed for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Quote is unavailable right now.\nTry again later.'**
  String get swapFailureQuoteUnavailable;

  /// Swap or Pay error: the provider's quote did not match the request or was malformed, so the wallet refused it.
  ///
  /// In en, this message translates to:
  /// **'Quote response could not be verified.\nTry again later.'**
  String get swapFailureQuoteUnverified;

  /// Swap status panel: checking the swap status with the provider failed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh swap status.\nTry again later.'**
  String get swapFailureRefreshFailed;

  /// Swap or Pay error: a request to the swap provider timed out.
  ///
  /// In en, this message translates to:
  /// **'Request timed out.\nCheck your connection and try again.'**
  String get swapFailureRequestTimeout;

  /// Swap or Pay error: a provider response was malformed, so the wallet refused it.
  ///
  /// In en, this message translates to:
  /// **'Swap response could not be verified.\nTry again later.'**
  String get swapFailureResponseUnverified;

  /// Swap or Pay error: the provider rejected the asset route or the destination/refund address.
  ///
  /// In en, this message translates to:
  /// **'This route or address was rejected.\nEdit the details and request a new quote.'**
  String get swapFailureRouteRejected;

  /// Swap or Pay error: the swap provider is down or refused the request.
  ///
  /// In en, this message translates to:
  /// **'Swap service is temporarily unavailable.\nTry again later.'**
  String get swapFailureServiceUnavailable;

  /// Swap or Pay error on review: starting the swap with the provider failed.
  ///
  /// In en, this message translates to:
  /// **'Swap could not be started.\nTry again later.'**
  String get swapFailureStartFailed;

  /// [security] Swap status panel: the provider reports a status for an asset pair this wallet does not support. Warns the user not to send the deposit again.
  ///
  /// In en, this message translates to:
  /// **'Swap status uses an unsupported asset pair.\nDo not resend funds. Try again later.'**
  String get swapFailureStatusAssetUnsupported;

  /// Swap or Pay status panel: the provider status check failed for a temporary reason; the screen keeps retrying. Two lines: what happened, then what happens next.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t refresh the latest status.\nWe\'ll keep trying and update this screen automatically.'**
  String get swapFailureStatusAutoRefresh;

  /// Swap or Pay error: the provider asked the wallet to retry later (busy or rate limited).
  ///
  /// In en, this message translates to:
  /// **'Swap service is still processing.\nWait a moment and try again.'**
  String get swapFailureStillProcessing;

  /// Swap or Pay error: the list of supported tokens failed to load.
  ///
  /// In en, this message translates to:
  /// **'Swap tokens could not be loaded.\nTry again later.'**
  String get swapFailureTokensUnavailable;

  /// Pay error: the payment provider blocks requests from Tor exit nodes. Tells the user how to pay anyway.
  ///
  /// In en, this message translates to:
  /// **'Pay is unavailable over Tor because the service blocked this connection.\nTurn off Tor in Settings to pay.'**
  String get swapFailureTorBlockedPay;

  /// Swap error: the swap provider blocks requests from Tor exit nodes. Tells the user how to swap anyway.
  ///
  /// In en, this message translates to:
  /// **'Swap is unavailable over Tor because the service blocked this connection.\nTurn off Tor in Settings to use swap.'**
  String get swapFailureTorBlockedSwap;

  /// Swap error when preparing the ZEC deposit: the spendable balance cannot cover the amount plus the network fee. Max is the button that fills the largest amount.
  ///
  /// In en, this message translates to:
  /// **'Not enough spendable ZEC to cover this swap and its network fee.\nTry a smaller amount or use Max.'**
  String get swapFailureZecDepositFunding;

  /// Swap error: the wallet could not build the ZEC deposit transaction before starting the swap.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit could not be prepared.\nCheck your balance and try again.'**
  String get swapFailureZecDepositPreflight;

  /// Swap or Pay error: sending the ZEC deposit transaction failed.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit could not be sent.\nTry again later.'**
  String get swapFailureZecDepositSendFailed;

  /// [security] Error in swap Keystone signing when broadcasting failed.
  ///
  /// In en, this message translates to:
  /// **'Transaction could not be broadcast.'**
  String get swapKeystoneBroadcastFailed;

  /// [security] Title of the swap Keystone signing overlay while the signed ZEC deposit is being broadcast.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting ZEC deposit'**
  String get swapKeystoneBroadcastingTitle;

  /// [security] Title of the mobile swap Keystone screen when signing failed.
  ///
  /// In en, this message translates to:
  /// **'Keystone signing failed'**
  String get swapKeystoneFailedTitle;

  /// [security] Label on the mobile swap Keystone screen while the signed deposit is broadcast.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting ZEC deposit...'**
  String get swapKeystoneFinalizing;

  /// [security] Generic error in swap Keystone signing when signing the ZEC deposit fails.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit signing could not be completed.'**
  String get swapKeystoneIncomplete;

  /// [security] Error in swap Keystone signing when the transaction is a TEX send.
  ///
  /// In en, this message translates to:
  /// **'Keystone does not support TEX sends yet.'**
  String get swapKeystoneNoTex;

  /// [security] Caption under the signature scanner on the mobile swap Keystone screen.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to finish the ZEC deposit'**
  String get swapKeystoneScanCaption;

  /// [security] Title of the swap Keystone signing overlay asking the user to scan and sign the ZEC deposit.
  ///
  /// In en, this message translates to:
  /// **'Sign ZEC deposit on Keystone'**
  String get swapKeystoneSignTitle;

  /// [security] Error in the swap Keystone signing overlay when the broadcast outcome is unknown.
  ///
  /// In en, this message translates to:
  /// **'The transaction status is uncertain. Refresh activity before trying again.'**
  String get swapKeystoneStatusUncertain;

  /// Button in the swap Ledger signing modal that leaves the modal and returns to the activity list.
  ///
  /// In en, this message translates to:
  /// **'Back to activity'**
  String get swapLedgerBackToActivity;

  /// [security] Error in the swap Ledger signing modal when broadcasting the signed ZEC deposit failed.
  ///
  /// In en, this message translates to:
  /// **'The ZEC deposit could not be broadcast.'**
  String get swapLedgerBroadcastFailed;

  /// [security] Error in the swap Ledger signing modal when the user rejected the ZEC deposit on the device.
  ///
  /// In en, this message translates to:
  /// **'The ZEC deposit was rejected on your Ledger.'**
  String get swapLedgerDeclined;

  /// [security] Body of the swap Ledger modal when a background operation already owns the transaction.
  ///
  /// In en, this message translates to:
  /// **'Vizor is already finishing this transaction in the background.'**
  String get swapLedgerMessageBackground;

  /// [security] Body of the swap Ledger recovery modal when the transaction expired and funds are still reserved.
  ///
  /// In en, this message translates to:
  /// **'The transaction expired before it was sent. Vizor still needs to release its reserved funds.'**
  String get swapLedgerMessageExpired;

  /// [security] Body of the swap Ledger recovery modal when the transaction was sent but local saving failed.
  ///
  /// In en, this message translates to:
  /// **'The transaction was sent, but Vizor could not finish saving it.'**
  String get swapLedgerMessageSentNotSaved;

  /// [security] Body of the swap Ledger recovery modal when it is unknown whether the transaction was sent.
  ///
  /// In en, this message translates to:
  /// **'Vizor could not confirm whether the transaction was sent, and still needs to save its status.'**
  String get swapLedgerMessageUncertain;

  /// [security] Button in the swap Ledger recovery modal that retries releasing reserved funds.
  ///
  /// In en, this message translates to:
  /// **'Retry cleanup'**
  String get swapLedgerRetryCleanup;

  /// [security] Generic error in the swap Ledger signing modal when signing fails for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Ledger signing could not be completed.'**
  String get swapLedgerSigningIncomplete;

  /// [security] Status chip in the swap Ledger recovery modal when reserved funds still need to be released.
  ///
  /// In en, this message translates to:
  /// **'Cleanup needed'**
  String get swapLedgerStatusCleanup;

  /// [security] Status chip in the swap Ledger recovery modal while the sent transaction is saved locally.
  ///
  /// In en, this message translates to:
  /// **'Saving transaction'**
  String get swapLedgerStatusSaving;

  /// [security] Title of the swap Ledger recovery modal when it is unknown whether the transaction was sent.
  ///
  /// In en, this message translates to:
  /// **'Transaction status pending'**
  String get swapLedgerTitlePending;

  /// [security] Title of the swap Ledger modal when another background operation is already finishing the transaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction recovery in progress'**
  String get swapLedgerTitleRecovery;

  /// [security] Title of the swap Ledger recovery modal when the transaction was sent but could not be saved locally.
  ///
  /// In en, this message translates to:
  /// **'Transaction sent'**
  String get swapLedgerTitleSent;

  /// Swap or Pay review error: the user switched accounts after the quote was made, so the quote must be reviewed again.
  ///
  /// In en, this message translates to:
  /// **'Active account changed. Review the quote again before starting.'**
  String get swapNoticeAccountChanged;

  /// Heading of the list of networks affected by an incident.
  ///
  /// In en, this message translates to:
  /// **'Affected networks'**
  String get swapNoticeAffectedNetworks;

  /// Network list text meaning the notice applies to every chain.
  ///
  /// In en, this message translates to:
  /// **'All chains'**
  String get swapNoticeAllChains;

  /// [security] Swap or Pay deposit notice: the deposit was broadcast but the wallet failed to save it. Warns against sending again until the status is confirmed.
  ///
  /// In en, this message translates to:
  /// **'The transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.'**
  String get swapNoticeBroadcastNotStored;

  /// [security] Swap or Pay deposit notice: only part of a multi-transaction deposit was broadcast. Warns against sending again before checking.
  ///
  /// In en, this message translates to:
  /// **'Some deposit transactions may have reached the network. Check activity before trying again.'**
  String get swapNoticeBroadcastPartial;

  /// [security] Swap or Pay deposit notice: the deposit transaction was built but never reached the network. Warns against sending again before checking.
  ///
  /// In en, this message translates to:
  /// **'The deposit was created locally but could not be broadcast. Check activity before trying again.'**
  String get swapNoticeBroadcastPending;

  /// [security] Swap or Pay deposit notice: the deposit broadcast ended in a state the wallet cannot classify. Warns against sending again before checking.
  ///
  /// In en, this message translates to:
  /// **'The deposit status is uncertain. Check activity before trying again.'**
  String get swapNoticeBroadcastUncertain;

  /// [security] Swap or Pay deposit notice: the broadcast result is unknown because confirmation timed out. Warns against sending again before checking.
  ///
  /// In en, this message translates to:
  /// **'The transaction may have reached the network, but confirmation timed out. Check activity before trying again.'**
  String get swapNoticeBroadcastUnknown;

  /// Accessibility label of the close button on the NEAR Intents service notice.
  ///
  /// In en, this message translates to:
  /// **'Close service notice'**
  String get swapNoticeCloseLabel;

  /// [security] Swap or Pay error after sending: the deposit reached the network but the wallet lost its record of the swap. The user must copy the transaction hash to track the funds.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit was broadcast, but the saved swap intent was not found. Copy the transaction hash before leaving this screen.'**
  String get swapNoticeDepositIntentMissing;

  /// Service notice line with the expected end time of a maintenance window; {time} is a formatted local date and UTC offset.
  ///
  /// In en, this message translates to:
  /// **'Expected end: {time}'**
  String swapNoticeExpectedEnd(String time);

  /// Heading of the list of affected networks when the notice is maintenance only.
  ///
  /// In en, this message translates to:
  /// **'List of maintenance'**
  String get swapNoticeListOfMaintenance;

  /// First line of the service notice when scheduled maintenance is under way.
  ///
  /// In en, this message translates to:
  /// **'NEAR Intents is under maintenance.'**
  String get swapNoticeMaintenanceIntro;

  /// Title of the NEAR Intents service banner when only scheduled maintenance is reported.
  ///
  /// In en, this message translates to:
  /// **'Maintenance notice'**
  String get swapNoticeMaintenanceTitle;

  /// Service notice line naming the networks covered by one maintenance window; {networks} is a comma-separated list of chain names.
  ///
  /// In en, this message translates to:
  /// **'Maintenance window: {networks}'**
  String swapNoticeMaintenanceWindow(String networks);

  /// Button that dismisses the NEAR Intents service notice.
  ///
  /// In en, this message translates to:
  /// **'Ok'**
  String get swapNoticeOk;

  /// Service notice line shown in pay mode explaining that payments may fail.
  ///
  /// In en, this message translates to:
  /// **'Payments may not work right now.'**
  String get swapNoticePaymentsMayFail;

  /// Swap or Pay quote error: the wallet could not reserve a new receive address for the swap.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare a fresh wallet receive address. Retry after wallet sync or close older pending swaps before requesting a new quote.'**
  String get swapNoticeReceiveAddressUnavailable;

  /// Title of the NEAR Intents service banner when an incident affects swaps.
  ///
  /// In en, this message translates to:
  /// **'Service notice'**
  String get swapNoticeServiceTitle;

  /// Service notice line with the start time of a maintenance window; {time} is a formatted local date and UTC offset.
  ///
  /// In en, this message translates to:
  /// **'Start: {time}'**
  String swapNoticeStart(String time);

  /// Button that opens the NEAR Intents status web page.
  ///
  /// In en, this message translates to:
  /// **'NEAR Intents status page'**
  String get swapNoticeStatusPage;

  /// Service notice line shown in swap mode explaining that swaps may fail.
  ///
  /// In en, this message translates to:
  /// **'Swaps may not work right now.'**
  String get swapNoticeSwapsMayFail;

  /// Page title on the desktop swap screen.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get swapPageTitle;

  /// Toast after the ZEC deposit broadcast result is uncertain and the wallet is checking it.
  ///
  /// In en, this message translates to:
  /// **'Checking ZEC deposit'**
  String get swapPanelDepositChecking;

  /// Toast after the ZEC deposit for a swap was broadcast and its arrival is certain.
  ///
  /// In en, this message translates to:
  /// **'ZEC deposit sent'**
  String get swapPanelDepositSent;

  /// Body text under the load failure heading in the swap activity detail.
  ///
  /// In en, this message translates to:
  /// **'Return to Activity and select a saved swap.'**
  String get swapPanelLoadFailedBody;

  /// Heading shown when a saved swap cannot be loaded in the activity detail.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this swap. Try again or pull to refresh.'**
  String get swapPanelLoadFailedTitle;

  /// Subtitle under the receive amount in the swap status header; {recipient} is a contact name or shortened address.
  ///
  /// In en, this message translates to:
  /// **'To: {recipient}'**
  String swapPanelRecipientTo(String recipient);

  /// Row label for the ZEC amount a payment was converted from.
  ///
  /// In en, this message translates to:
  /// **'Converted from'**
  String get swapPayStatusConvertedFrom;

  /// Subtext under the recipient on the pay status screen when the address is not a saved contact.
  ///
  /// In en, this message translates to:
  /// **'New address'**
  String get swapPayStatusNewAddress;

  /// Row label for the original ZEC amount of a failed payment.
  ///
  /// In en, this message translates to:
  /// **'Source amount'**
  String get swapPayStatusSourceAmount;

  /// Accessibility label of the "Powered by" artwork in the NEAR Intents attribution.
  ///
  /// In en, this message translates to:
  /// **'Powered by'**
  String get swapPoweredByLabel;

  /// Swap and Pay review, value of the row that says how long the quote holds. {time} is a 24-hour local time such as 14:05.
  ///
  /// In en, this message translates to:
  /// **'Expires {time}'**
  String swapQuoteExpiresAt(String time);

  /// Swap and Pay review, value of the row that says how long the quote holds, when the provider gave no expiry time.
  ///
  /// In en, this message translates to:
  /// **'Quote expiry pending'**
  String get swapQuoteExpiryPending;

  /// Swap review, value of the exchange rate row when the provider quote has no usable rate yet.
  ///
  /// In en, this message translates to:
  /// **'Rate pending'**
  String get swapQuoteRatePending;

  /// Back link label on the review screen that returns to the Pay composer.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get swapReviewBackPay;

  /// Primary button on the mobile swap review that starts the swap.
  ///
  /// In en, this message translates to:
  /// **'Confirm & swap'**
  String get swapReviewConfirmAndSwap;

  /// Title and fallback button label on the desktop pay review screen.
  ///
  /// In en, this message translates to:
  /// **'Confirm payment'**
  String get swapReviewConfirmPaymentTitle;

  /// Primary button on the desktop swap review that starts the swap.
  ///
  /// In en, this message translates to:
  /// **'Confirm swap'**
  String get swapReviewConfirmSwap;

  /// Subtitle under the pay amount on the mobile swap review when the user pays from an external chain; {address} is a contact name or shortened address.
  ///
  /// In en, this message translates to:
  /// **'From: {address}'**
  String swapReviewFromAddress(String address);

  /// Warning on the swap review screen when the ZEC balance cannot cover the swap amount.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have enough ZEC for this swap. Try a smaller amount.'**
  String get swapReviewInsufficientZecSwap;

  /// Primary button on the pay review; {amount} is the formatted amount the recipient gets.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String swapReviewPayAmount(String amount);

  /// Notice on the review screens when the quote expired.
  ///
  /// In en, this message translates to:
  /// **'Quote expired. Review again for an updated rate.'**
  String get swapReviewQuoteExpired;

  /// Row label for how long the quote stays valid on the pay review summary.
  ///
  /// In en, this message translates to:
  /// **'Quote holds'**
  String get swapReviewQuoteHolds;

  /// Warning on the mobile swap review screen when the quote has expired or been replaced.
  ///
  /// In en, this message translates to:
  /// **'This quote is no longer active.'**
  String get swapReviewQuoteInactive;

  /// Primary button on the mobile swap review when the quote is no longer active.
  ///
  /// In en, this message translates to:
  /// **'Return to swap'**
  String get swapReviewReturnToSwap;

  /// Primary button on the swap review that fetches a new quote after the old one expired.
  ///
  /// In en, this message translates to:
  /// **'Review again'**
  String get swapReviewReviewAgain;

  /// Disabled primary button label on the swap review while the quote is being locked.
  ///
  /// In en, this message translates to:
  /// **'Locking quote'**
  String get swapReviewStartingLockingQuote;

  /// Disabled primary button label on the swap review while the ZEC deposit is being sent.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get swapReviewStartingSending;

  /// Subtitle under the receive amount on the mobile swap review when the user sends ZEC; {address} is a contact name or shortened address.
  ///
  /// In en, this message translates to:
  /// **'To: {address}'**
  String swapReviewToAddress(String address);

  /// Mobile Ledger signing screen title when the operation is a payment.
  ///
  /// In en, this message translates to:
  /// **'Sign payment'**
  String get swapSignPayment;

  /// Title of the mobile signing screens for the ZEC deposit of a swap.
  ///
  /// In en, this message translates to:
  /// **'Sign ZEC deposit'**
  String get swapSignZecDeposit;

  /// Label of the custom slippage input option in the slippage modal.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get swapSlippageCustom;

  /// Slippage modal explanation shown in pay mode: extra ZEC allowed when the quote moves.
  ///
  /// In en, this message translates to:
  /// **'Allows this much extra ZEC for quote movement before execution fails. Network fees are separate.'**
  String get swapSlippageDescriptionPay;

  /// Slippage modal explanation shown in swap mode: maximum rate change accepted.
  ///
  /// In en, this message translates to:
  /// **'Sets the maximum rate change you\'ll accept. Network fees are separate.'**
  String get swapSlippageDescriptionSwap;

  /// Validation error in the slippage modal when the custom value is outside 0.1 to 5 percent.
  ///
  /// In en, this message translates to:
  /// **'Slippage must be 0.1 - 5%'**
  String get swapSlippageRangeError;

  /// Title of the slippage settings modal and field label for the allowed price movement.
  ///
  /// In en, this message translates to:
  /// **'Slippage'**
  String get swapSlippageTitle;

  /// Status text on the mobile status screen when the operation needs user action.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get swapStatusBadgeNeedsAttention;

  /// Label of the details tab on the swap status screen.
  ///
  /// In en, this message translates to:
  /// **'Transaction details'**
  String get swapStatusDetailsTab;

  /// Row label next to the final swap status on the swap status screen.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get swapStatusRowLabel;

  /// Body text on the swap timeout screen asking the user to start a new swap.
  ///
  /// In en, this message translates to:
  /// **'Please, start another swap transaction.'**
  String get swapTimeoutBody;

  /// Headline on the swap timeout screen explaining the one-time deposit address has expired.
  ///
  /// In en, this message translates to:
  /// **'This deposit address is no longer valid'**
  String get swapTimeoutHeadline;

  /// Button on the swap timeout screen that returns to the swap composer.
  ///
  /// In en, this message translates to:
  /// **'Restart swap'**
  String get swapTimeoutRestart;

  /// Button label on the swap progress footer that opens the swap in the NEAR Intents explorer.
  ///
  /// In en, this message translates to:
  /// **'View on NEAR Intents'**
  String get swapViewOnNearIntents;

  /// Screen-reader sync status while Vizor re-checks the wallet.
  ///
  /// In en, this message translates to:
  /// **'Checking {percent} percent'**
  String syncCheckingPercentSemantics(String percent);

  /// Sync status while Vizor re-checks the wallet. {percent} is a whole number 0-99.
  ///
  /// In en, this message translates to:
  /// **'{percent}% checking'**
  String syncCheckingProgress(String percent);

  /// Sync status while Vizor waits for its Tor connection.
  ///
  /// In en, this message translates to:
  /// **'Connecting to Tor…'**
  String get syncConnectingToTor;

  /// Screen-reader sync status while Vizor waits for its Tor connection.
  ///
  /// In en, this message translates to:
  /// **'Connecting to Tor'**
  String get syncConnectingToTorSemantics;

  /// Sync failure reason: recovering from a chain reorganization failed.
  ///
  /// In en, this message translates to:
  /// **'Chain recovery'**
  String get syncErrorChainRecovery;

  /// Sync failure reason: received data could not be read.
  ///
  /// In en, this message translates to:
  /// **'Data error'**
  String get syncErrorData;

  /// Sync failure reason: the lightwalletd endpoint returned an error.
  ///
  /// In en, this message translates to:
  /// **'Endpoint error'**
  String get syncErrorEndpoint;

  /// Sync failure reason: the server could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get syncErrorNetwork;

  /// Sync failure reason: a private (PIR) status lookup failed.
  ///
  /// In en, this message translates to:
  /// **'Private lookup'**
  String get syncErrorPrivateLookup;

  /// Sync failure reason when the cause is unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get syncErrorUnknown;

  /// Sync failure reason: the wallet database failed.
  ///
  /// In en, this message translates to:
  /// **'Wallet data error'**
  String get syncErrorWalletData;

  /// Sync failure reason: the wallet database was busy.
  ///
  /// In en, this message translates to:
  /// **'Wallet data busy'**
  String get syncErrorWalletDataBusy;

  /// Sync status after a sync failed. {reason} is a short failure reason such as Network error.
  ///
  /// In en, this message translates to:
  /// **'Syncing failed. {reason}...'**
  String syncFailed(String reason);

  /// Screen-reader sync status after a sync failed.
  ///
  /// In en, this message translates to:
  /// **'Syncing failed. {reason}'**
  String syncFailedSemantics(String reason);

  /// Sync failure notice on Home: a chain reorganization happened during sync and the wallet is recovering.
  ///
  /// In en, this message translates to:
  /// **'The chain changed while syncing. We\'ll keep trying to recover.'**
  String get syncFailureChainRecovery;

  /// Sync failure notice on Home: the wallet database is locked and sync retries by itself.
  ///
  /// In en, this message translates to:
  /// **'Wallet data is busy. We\'ll try syncing again automatically.'**
  String get syncFailureDatabaseBusy;

  /// Sync failure notice on Home: the wallet database could not be read.
  ///
  /// In en, this message translates to:
  /// **'Wallet data could not be read. Restart the app and retry sync.'**
  String get syncFailureDatabaseFatal;

  /// Sync failure notice on Home: the configured lightwalletd endpoint is unreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the configured Zcash endpoint. Check your endpoint settings.'**
  String get syncFailureEndpoint;

  /// Sync failure notice on Home: the network connection dropped and sync retries by itself.
  ///
  /// In en, this message translates to:
  /// **'Network connection lost. We\'ll keep trying automatically.'**
  String get syncFailureNetwork;

  /// Sync failure notice on Home: data from the server could not be parsed.
  ///
  /// In en, this message translates to:
  /// **'Sync data could not be processed. Retry sync or check your endpoint.'**
  String get syncFailureParse;

  /// Sync failure notice on Home: experimental private queries could not determine a transaction's status and block syncing.
  ///
  /// In en, this message translates to:
  /// **'Private transaction lookup couldn\'t determine a transaction\'s status. Turn off experimental private queries in Settings to continue syncing.'**
  String get syncFailurePrivateStatus;

  /// Sync failure notice on Home: the Tor connection failed and the user can retry or turn Tor off.
  ///
  /// In en, this message translates to:
  /// **'Tor couldn\'t connect. Retry, or turn Tor off in Settings.'**
  String get syncFailureTor;

  /// Sync failure notice on Home: sync failed for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Sync failed. Retry sync to continue.'**
  String get syncFailureUnknown;

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

  /// Screen-reader sync status while the wallet syncs.
  ///
  /// In en, this message translates to:
  /// **'Syncing {percent} percent'**
  String syncSyncingPercentSemantics(String percent);

  /// Sync status while the wallet syncs. {percent} is a whole number 0-99.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Syncing...'**
  String syncSyncingProgress(String percent);

  /// Sync status after the Tor connection failed; sync is paused until the user acts.
  ///
  /// In en, this message translates to:
  /// **'Tor couldn\'t connect...'**
  String get syncTorFailed;

  /// Screen-reader sync status, and sync failure reason, when the Tor connection failed.
  ///
  /// In en, this message translates to:
  /// **'Tor couldn\'t connect'**
  String get syncTorFailedSemantics;

  /// Sync status, and screen-reader label, when the wallet is up to date. Shared by: lock, sync.
  ///
  /// In en, this message translates to:
  /// **'Vizor is synced'**
  String get syncVizorSynced;

  /// Error shown when this build of the app cannot operate on the wallet's transparent funds and the user must update Vizor.
  ///
  /// In en, this message translates to:
  /// **'This wallet needs a newer version of Vizor to use its transparent funds.'**
  String get transparentLedgerNeedsNewerBuild;

  /// Error shown when transparent funds cannot be used yet because private recovery of the transparent history has not finished.
  ///
  /// In en, this message translates to:
  /// **'Transparent funds are unavailable until private recovery completes.'**
  String get transparentRecoveryIncomplete;

  /// Tooltip on the fee row of transaction review and receipt screens.
  ///
  /// In en, this message translates to:
  /// **'Fee paid to the Zcash network to process this transaction.'**
  String get txFeeHelpTooltip;

  /// Body of the transaction fee info sheet.
  ///
  /// In en, this message translates to:
  /// **'The network fee is set by the Zcash protocol (ZIP 317) based on the transaction size. Vizor adds no extra fee.'**
  String get txFeeInfoDescription;

  /// Title of the transaction fee info sheet. Shared by: activity, swap, tx.
  ///
  /// In en, this message translates to:
  /// **'Tx fee'**
  String get txFeeInfoTitle;

  /// Message when installing a Vizor update failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the update. Try again.'**
  String get updateFailedMessage;

  /// Button that restarts Vizor to apply a downloaded update.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get updateRestart;

  /// Label of the bottom button that re-checks whether the account may vote.
  ///
  /// In en, this message translates to:
  /// **'Retry eligibility'**
  String get votingActionRetryEligibility;

  /// Button on a voting round card that shows the answers already submitted.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get votingActionReview;

  /// Button that opens the screen to review answers before submitting the vote.
  ///
  /// In en, this message translates to:
  /// **'Review answers'**
  String get votingActionReviewAnswers;

  /// Label of the bottom button of a voting round when voting is not available for this account.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get votingActionUnavailable;

  /// Button on a voting round card that opens the results of a closed round.
  ///
  /// In en, this message translates to:
  /// **'View results'**
  String get votingActionViewResults;

  /// Meta line of a voting round that is open when its end date is unknown.
  ///
  /// In en, this message translates to:
  /// **'Voting active'**
  String get votingActive;

  /// Notice on the voting round page when this account's funds were already used to vote in this round.
  ///
  /// In en, this message translates to:
  /// **'These funds were already used for this round. Voting cannot be restarted on this device.'**
  String get votingAlreadyUsedNotice;

  /// Accessibility label of the small spinner shown while the vote screen moves on to the next unanswered question.
  ///
  /// In en, this message translates to:
  /// **'Moving to the next unanswered question'**
  String get votingAutoAdvanceSemantics;

  /// Detail under the casting step while votes are being proved and cast.
  ///
  /// In en, this message translates to:
  /// **'Casting votes'**
  String get votingBallotCasting;

  /// Detail under the casting step while vote shares are delivered to the voting servers.
  ///
  /// In en, this message translates to:
  /// **'Delivering your responses'**
  String get votingBallotDelivering;

  /// Detail under the casting step while the ballot is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing your ballot'**
  String get votingBallotPreparing;

  /// Detail under the casting step while waiting for the votes to confirm on chain.
  ///
  /// In en, this message translates to:
  /// **'Waiting for chain confirmation'**
  String get votingBallotWaitingChain;

  /// Accessibility label of the Beta badge image next to the Vote title.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get votingBetaSemantics;

  /// Number of voting bundles one Keystone request signs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 voting bundle} other{{count} voting bundles}}'**
  String votingBundleCount(int count);

  /// Pager label for one bundle on the mobile Keystone signing screen; a bundle is a group of notes signed together.
  ///
  /// In en, this message translates to:
  /// **'Bundle {number} of {total}'**
  String votingBundleOf(int number, int total);

  /// Label of an answer option whose name is unknown; {number} is the option number.
  ///
  /// In en, this message translates to:
  /// **'Choice {number}'**
  String votingChoiceFallback(int number);

  /// Button or title for adding a custom voting config source URL.
  ///
  /// In en, this message translates to:
  /// **'Add custom source'**
  String get votingConfigAddCustomSource;

  /// Inline error under the voting config source URL field when the checksum after sha256: is not 64 lowercase hexadecimal characters.
  ///
  /// In en, this message translates to:
  /// **'The checksum must be 64 lowercase hex characters.'**
  String get votingConfigChecksumFormat;

  /// Inline error under the voting config source URL field when the checksum query key is percent-encoded. Keep checksum as written; it is the literal parameter name.
  ///
  /// In en, this message translates to:
  /// **'Write the checksum parameter name as checksum, without encoding.'**
  String get votingConfigChecksumKeyEncoded;

  /// Inline error under the voting config source URL field when the checksum value lacks the sha256: prefix. Keep sha256: as written.
  ///
  /// In en, this message translates to:
  /// **'The checksum must start with sha256:.'**
  String get votingConfigChecksumPrefix;

  /// Inline error under the voting config source URL field when checksum appears more than once. Keep checksum as written; it is the literal parameter name.
  ///
  /// In en, this message translates to:
  /// **'Include the checksum parameter only once.'**
  String get votingConfigChecksumRepeated;

  /// Inline error under the voting config source URL field when a checksum is required but missing. Keep checksum as written; it is the literal parameter name.
  ///
  /// In en, this message translates to:
  /// **'Add a checksum parameter to the URL.'**
  String get votingConfigChecksumRequired;

  /// Accessibility label of the close button of the voting config panel.
  ///
  /// In en, this message translates to:
  /// **'Close voting config settings'**
  String get votingConfigCloseSettings;

  /// Accessibility label of the button that copies a voting config source URL.
  ///
  /// In en, this message translates to:
  /// **'Copy source URL'**
  String get votingConfigCopyUrl;

  /// Name of the active voting config source when it is a URL the user added but did not save.
  ///
  /// In en, this message translates to:
  /// **'Custom source'**
  String get votingConfigCustomSource;

  /// Accessibility label of the delete button of a saved voting config source; {name} is the source's title.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}'**
  String votingConfigDeleteNamed(String name);

  /// Accessibility label of the button that deletes a saved voting config source.
  ///
  /// In en, this message translates to:
  /// **'Delete saved source'**
  String get votingConfigDeleteSaved;

  /// Validation error when the custom voting config source URL already exists.
  ///
  /// In en, this message translates to:
  /// **'This source URL is already added.'**
  String get votingConfigDuplicate;

  /// Title of the form for editing a custom voting config source.
  ///
  /// In en, this message translates to:
  /// **'Edit custom source'**
  String get votingConfigEditCustomSource;

  /// Accessibility label of the edit button of a saved voting config source; {name} is the source's title.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String votingConfigEditNamed(String name);

  /// Accessibility label of the button that edits a saved voting config source.
  ///
  /// In en, this message translates to:
  /// **'Edit saved source'**
  String get votingConfigEditSaved;

  /// Validation error on mobile when the title or URL of a custom voting config source is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a title and source URL.'**
  String get votingConfigEnterTitleAndUrl;

  /// Label of the URL field of a custom voting config source on desktop.
  ///
  /// In en, this message translates to:
  /// **'Static config URL'**
  String get votingConfigFieldStaticUrl;

  /// Label of the title field of a custom voting config source.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get votingConfigFieldTitle;

  /// Error shown when the custom voting config source could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting config from that source.'**
  String get votingConfigLoadFailed;

  /// Label of the URL field of a custom voting config source on mobile.
  ///
  /// In en, this message translates to:
  /// **'Source URL'**
  String get votingConfigMobileFieldUrl;

  /// Intro text in the mobile voting config sheet.
  ///
  /// In en, this message translates to:
  /// **'Choose where Vizor gets authenticated voting rounds.'**
  String get votingConfigMobileIntro;

  /// Button on the mobile voting config sheet that saves the custom source.
  ///
  /// In en, this message translates to:
  /// **'Save source'**
  String get votingConfigMobileSave;

  /// Explanation under the Show test rounds switch on mobile; [TEST] is a literal title marker.
  ///
  /// In en, this message translates to:
  /// **'Include authenticated rounds marked [TEST].'**
  String get votingConfigMobileTestRoundsHint;

  /// Title of the mobile bottom sheet for choosing the voting config source.
  ///
  /// In en, this message translates to:
  /// **'Vote config'**
  String get votingConfigMobileTitle;

  /// Error on mobile when saving the voting config source failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update voting config. Check the source and try again.'**
  String get votingConfigMobileUpdateFailed;

  /// Label of the save button while the voting config source choice is being saved.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get votingConfigSaving;

  /// Accessibility label of the settings button on the voting list that opens the voting configuration.
  ///
  /// In en, this message translates to:
  /// **'Voting config settings'**
  String get votingConfigSettings;

  /// Title and accessibility label of the switch that shows test voting rounds.
  ///
  /// In en, this message translates to:
  /// **'Show test rounds'**
  String get votingConfigShowTestRounds;

  /// Explanation under the Show test rounds switch on desktop; [TEST] is a literal title prefix.
  ///
  /// In en, this message translates to:
  /// **'Display authenticated rounds whose titles begin with [TEST].'**
  String get votingConfigShowTestRoundsHint;

  /// Heading above the list of voting config sources on mobile.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get votingConfigSources;

  /// Error shown when changing the Show test rounds setting failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the test round visibility setting.'**
  String get votingConfigTestVisibilityFailed;

  /// Validation error under the title field when adding a custom voting config source.
  ///
  /// In en, this message translates to:
  /// **'Title must be {max} characters or less.'**
  String votingConfigTitleTooLong(int max);

  /// Tooltip of the settings icon on the voting list that opens the voting configuration.
  ///
  /// In en, this message translates to:
  /// **'Voting config'**
  String get votingConfigTooltip;

  /// Error shown when saving the voting config source failed without a specific reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update voting config.'**
  String get votingConfigUpdateFailed;

  /// Toast shown after copying a voting config source URL.
  ///
  /// In en, this message translates to:
  /// **'Source URL copied.'**
  String get votingConfigUrlCopied;

  /// Inline error under the voting config source URL field when the URL has a # fragment.
  ///
  /// In en, this message translates to:
  /// **'The URL must not include a fragment (#…).'**
  String get votingConfigUrlHasFragment;

  /// Inline error under the voting config source URL field when the URL contains user info (user:password@).
  ///
  /// In en, this message translates to:
  /// **'The URL must not include a user name or password.'**
  String get votingConfigUrlHasUserInfo;

  /// Inline error under the voting config source URL field when the URL is not an HTTPS URL.
  ///
  /// In en, this message translates to:
  /// **'Use an HTTPS URL.'**
  String get votingConfigUrlNotHttps;

  /// Label of the save button while the custom source is being validated.
  ///
  /// In en, this message translates to:
  /// **'Validating...'**
  String get votingConfigValidating;

  /// Message on the voting confirmation screen while eligibility is checked.
  ///
  /// In en, this message translates to:
  /// **'Checking voting eligibility for this account.'**
  String get votingConfirmationCheckingEligibility;

  /// [security] Body of the voting confirmation screen after the vote was published; votes are final.
  ///
  /// In en, this message translates to:
  /// **'Your vote was successfully published and cannot be changed.'**
  String get votingConfirmationConfirmedBody;

  /// Title of the voting confirmation screen after the vote was published.
  ///
  /// In en, this message translates to:
  /// **'Submission confirmed!'**
  String get votingConfirmationConfirmedTitle;

  /// Message on the voting confirmation screen when eligibility could not be confirmed.
  ///
  /// In en, this message translates to:
  /// **'Voting eligibility has not been confirmed for this account.'**
  String get votingConfirmationEligibilityUnconfirmed;

  /// Title of the voting confirmation screen when the vote was not fully submitted.
  ///
  /// In en, this message translates to:
  /// **'Submission not complete'**
  String get votingConfirmationIncompleteTitle;

  /// Message on the voting confirmation screen when details could not be loaded; {error} is the reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load submission details: {error}'**
  String votingConfirmationLoadFailed(String error);

  /// Message on the voting confirmation screen when this account did not finish submitting its vote.
  ///
  /// In en, this message translates to:
  /// **'This account has not completed submission for this voting round.'**
  String get votingConfirmationNotCompleted;

  /// Error on the voting confirmation screen when refreshing the voting rounds list failed after Done was pressed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update voting rounds. Try again.'**
  String get votingConfirmationUpdateFailed;

  /// Shown on the voting confirmation screen while the voting rounds list refreshes after Done was pressed.
  ///
  /// In en, this message translates to:
  /// **'Updating voting rounds...'**
  String get votingConfirmationUpdatingRounds;

  /// Button that resumes an unfinished vote submission.
  ///
  /// In en, this message translates to:
  /// **'Continue voting'**
  String get votingContinueVoting;

  /// Time left in a voting round; zero means it ends today.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Ends today} =1{1 day left} other{{days} days left}}'**
  String votingDaysLeft(int days);

  /// Title of the error shown on the voting round page when the round could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting round'**
  String get votingDetailLoadFailedTitle;

  /// Body shown on the voting round page when the selected round does not exist.
  ///
  /// In en, this message translates to:
  /// **'The selected voting round could not be loaded.'**
  String get votingDetailUnavailableBody;

  /// Title shown on the voting round page when the selected round does not exist.
  ///
  /// In en, this message translates to:
  /// **'Voting round unavailable'**
  String get votingDetailUnavailableTitle;

  /// Meta line of an open voting round; {date} is the end date such as Jan 5, 2026.
  ///
  /// In en, this message translates to:
  /// **'Ends {date}'**
  String votingEnds(String date);

  /// Error shown when a vote submission to the voting chain was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Chain submission was cancelled.'**
  String get votingErrorChainCancelled;

  /// Error shown when a vote submission to the voting chain ended without producing a usable transaction.
  ///
  /// In en, this message translates to:
  /// **'Chain submission ended without a usable transaction.'**
  String get votingErrorChainNoUsableTransaction;

  /// Error shown when the wallet is still checking the outcome of an earlier vote submission to the voting chain.
  ///
  /// In en, this message translates to:
  /// **'Chain submission recovery is still pending.'**
  String get votingErrorChainRecoveryPending;

  /// Error shown when the voting chain rejected a submitted vote or delegation.
  ///
  /// In en, this message translates to:
  /// **'Chain submission was rejected.'**
  String get votingErrorChainRejected;

  /// Error shown when a vote submission may already be on the voting chain but its transaction hash is unknown; retrying could submit it twice.
  ///
  /// In en, this message translates to:
  /// **'Submission may have reached the chain, but no transaction hash was returned. Do not retry it.'**
  String get votingErrorChainSubmittedWithoutHash;

  /// Error shown when delegating voting power failed; {details} lists the failed bundles and their error text.
  ///
  /// In en, this message translates to:
  /// **'Delegation bundle processing failed: {details}'**
  String votingErrorDelegationFailed(String details);

  /// Error shown when votes cannot be cast because the key created during delegation is missing.
  ///
  /// In en, this message translates to:
  /// **'Voting hotkey is missing. Delegate this round before casting votes.'**
  String get votingErrorHotkeyMissing;

  /// Error shown when the voting round closed before a helper server confirmed receiving the user's vote share.
  ///
  /// In en, this message translates to:
  /// **'The voting round ended before a helper confirmed the immediate share. Check the voting status before retrying.'**
  String get votingErrorImmediateShareExpired;

  /// Error shown when Keystone vote signing is started for an account that is not a Keystone account.
  ///
  /// In en, this message translates to:
  /// **'Keystone voting is only available for Keystone accounts.'**
  String get votingErrorKeystoneAccountOnly;

  /// Error shown when Keystone vote signing is started for an account that is not a hardware wallet account.
  ///
  /// In en, this message translates to:
  /// **'Keystone voting is only available for hardware accounts.'**
  String get votingErrorKeystoneHardwareOnly;

  /// Error shown under the Keystone voting QR when a scanned signature is malformed.
  ///
  /// In en, this message translates to:
  /// **'Keystone returned an invalid voting signature. Scan the result for the QR shown here.'**
  String get votingErrorKeystoneInvalidSignature;

  /// Error shown under the Keystone voting QR when the scanned result contains no signatures.
  ///
  /// In en, this message translates to:
  /// **'Keystone returned no voting signatures. Scan the result again.'**
  String get votingErrorKeystoneNoSignatures;

  /// Error shown when a Keystone voting signature is scanned but no signing request is open.
  ///
  /// In en, this message translates to:
  /// **'No Keystone signing request is waiting for a signature.'**
  String get votingErrorKeystoneNoSigningRequest;

  /// Error shown when the QR code for signing a vote on Keystone could not be built; {reason} is the underlying error text.
  ///
  /// In en, this message translates to:
  /// **'Failed to prepare Keystone voting QR: {reason}'**
  String votingErrorKeystoneQrPrepareFailed(String reason);

  /// Error shown under the Keystone voting QR when the scanned result cannot be read as a response to it.
  ///
  /// In en, this message translates to:
  /// **'This Keystone result does not match the voting QR shown here. Scan the matching result and try again.'**
  String get votingErrorKeystoneResultMismatch;

  /// Error shown under the Keystone voting QR when the scanned signature differs from one already saved.
  ///
  /// In en, this message translates to:
  /// **'This Keystone result conflicts with a signature already saved for this voting request. Restart Keystone signing and scan the newly generated result.'**
  String get votingErrorKeystoneSignatureConflict;

  /// Error shown under the Keystone voting QR when the scanned signatures belong to a different request.
  ///
  /// In en, this message translates to:
  /// **'Keystone returned signatures that do not match this voting request. Scan the result for the QR shown here.'**
  String get votingErrorKeystoneSignatureMismatch;

  /// Error shown under the Keystone voting QR when the scanned signatures could not be stored.
  ///
  /// In en, this message translates to:
  /// **'Could not save the Keystone signatures. Scan the same Keystone result again.'**
  String get votingErrorKeystoneSignatureSaveFailed;

  /// Error shown when the user skips the remaining Keystone voting bundles before signing any.
  ///
  /// In en, this message translates to:
  /// **'Sign at least one Keystone bundle before skipping the rest.'**
  String get votingErrorKeystoneSkipNeedsSignature;

  /// Error shown when the user cancelled approving a vote on their Ledger.
  ///
  /// In en, this message translates to:
  /// **'Ledger voting approval was cancelled.'**
  String get votingErrorLedgerCancelled;

  /// Error shown when the Ledger is locked during voting; {instruction} is a sentence telling the user to open the Zcash app on the device.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Ledger. {instruction}'**
  String votingErrorLedgerLocked(String instruction);

  /// Error shown when a Ledger voting signature arrives but no bundle is waiting for approval.
  ///
  /// In en, this message translates to:
  /// **'No Ledger voting bundle is waiting for approval.'**
  String get votingErrorLedgerNoPendingBundle;

  /// Error shown when the user rejected the vote signature on their Ledger.
  ///
  /// In en, this message translates to:
  /// **'The vote signature was rejected on your Ledger. Retry to sign again.'**
  String get votingErrorLedgerRejected;

  /// Error shown when the Ledger signature differs from one already saved for the same voting bundle.
  ///
  /// In en, this message translates to:
  /// **'This Ledger signature conflicts with the signature already saved for this voting bundle.'**
  String get votingErrorLedgerSignatureConflict;

  /// Error shown when the Ledger voting signature could not be stored.
  ///
  /// In en, this message translates to:
  /// **'Could not save the Ledger voting signature. Retry this bundle.'**
  String get votingErrorLedgerSignatureSaveFailed;

  /// Error shown when the wrong app is open on the Ledger during voting; {instruction} is a sentence telling the user to open the Zcash app.
  ///
  /// In en, this message translates to:
  /// **'{instruction} Then retry.'**
  String votingErrorLedgerWrongApp(String instruction);

  /// Error shown when the account's eligible shielded balance is below the round's minimum; {amount} is a ZEC amount and {snapshot} names the snapshot block.
  ///
  /// In en, this message translates to:
  /// **'Voting requires at least one eligible shielded note bundle with {amount} at {snapshot}. Switch to an eligible account to vote.'**
  String votingErrorMinimumWeight(String amount, String snapshot);

  /// Reason shown in the mobile not-eligible dialog above the separate switch-account guidance, without a final period; {amount} is a ZEC amount and {snapshot} names the snapshot block.
  ///
  /// In en, this message translates to:
  /// **'Voting requires at least one eligible shielded note bundle with {amount} at {snapshot}'**
  String votingErrorMinimumWeightReason(String amount, String snapshot);

  /// Error shown on the voting status screen when a vote submission starts while no account is active.
  ///
  /// In en, this message translates to:
  /// **'No active account for voting session.'**
  String get votingErrorNoActiveAccount;

  /// Error shown when the account had no shielded funds at the snapshot; {snapshot} is a phrase naming the snapshot block.
  ///
  /// In en, this message translates to:
  /// **'This account is not eligible for this voting round. It had no eligible shielded funds at {snapshot}. Switch to an eligible account to vote.'**
  String votingErrorNoSpendableNotes(String snapshot);

  /// Reason shown in the mobile not-eligible dialog above the separate switch-account guidance, without a final period; {snapshot} is a phrase naming the snapshot block.
  ///
  /// In en, this message translates to:
  /// **'This account is not eligible for this voting round. It had no eligible shielded funds at {snapshot}'**
  String votingErrorNoSpendableNotesReason(String snapshot);

  /// Error shown when the user submits a ballot without choosing an answer to any question.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one vote before submitting.'**
  String get votingErrorNoVoteChosen;

  /// Error shown when the wallet could not choose a PIR server for the voting round.
  ///
  /// In en, this message translates to:
  /// **'Failed to resolve PIR endpoint.'**
  String get votingErrorPirEndpointResolveFailed;

  /// Error shown when delegation needs a PIR server but none has been selected yet.
  ///
  /// In en, this message translates to:
  /// **'PIR endpoint has not been resolved.'**
  String get votingErrorPirEndpointUnresolved;

  /// Error shown when a vote submission starts before the voting round's details have loaded.
  ///
  /// In en, this message translates to:
  /// **'Voting round details are not available yet. Retry in a moment.'**
  String get votingErrorRoundDetailsUnavailable;

  /// Error shown when a vote submission starts but the voting round's end time is not known yet.
  ///
  /// In en, this message translates to:
  /// **'Voting round end time is unavailable. Retry in a moment.'**
  String get votingErrorRoundEndTimeUnavailable;

  /// Generic error shown when a voting action failed without a more specific message.
  ///
  /// In en, this message translates to:
  /// **'Voting session action failed.'**
  String get votingErrorSessionFailed;

  /// Error shown when one delegation bundle still needs the hardware wallet's signature; {bundle} is the bundle number and {signer} is a hardware wallet name such as Keystone or Ledger.
  ///
  /// In en, this message translates to:
  /// **'Sign delegation bundle {bundle} with {signer} before submitting.'**
  String votingErrorSignBundleFirst(int bundle, String signer);

  /// Error shown when delegation is submitted before the hardware wallet signed it; {signer} is a hardware wallet name such as Keystone or Ledger.
  ///
  /// In en, this message translates to:
  /// **'Sign delegation bundles with {signer} before submitting.'**
  String votingErrorSignBundlesFirst(String signer);

  /// Error shown when hardware vote signing is started for an account of a different hardware wallet; {signer} is a hardware wallet name such as Keystone or Ledger.
  ///
  /// In en, this message translates to:
  /// **'{signer} voting is only available for matching hardware accounts.'**
  String votingErrorSignerAccountOnly(String signer);

  /// [security] Error shown when delegating voting power with a software account whose seed phrase cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Software delegation requires this account mnemonic. Unlock this account or switch to one with mnemonic access.'**
  String get votingErrorSoftwareMnemonicRequired;

  /// Error shown when casting votes failed; {details} lists the failed bundles and their error text.
  ///
  /// In en, this message translates to:
  /// **'Vote casting failed: {details}'**
  String votingErrorVoteCastingFailed(String details);

  /// Error shown when the wallet did not sync up to the voting round's snapshot block in time; {duration} is an elapsed time, {scanned} and {snapshot} are block heights.
  ///
  /// In en, this message translates to:
  /// **'Wallet sync did not reach this voting round snapshot within {duration}. Scanned block {scanned} of {snapshot}. Let wallet sync catch up and retry.'**
  String votingErrorWalletSyncTimeout(
    String duration,
    String scanned,
    String snapshot,
  );

  /// Label of the link button that opens the forum discussion of a voting round or proposal.
  ///
  /// In en, this message translates to:
  /// **'Forum discussion'**
  String get votingForumDiscussion;

  /// Title of the error shown on the voting pages when the wallet account could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load account'**
  String get votingGuardAccountLoadFailed;

  /// Title of the dialog explaining that the account cannot vote in this round.
  ///
  /// In en, this message translates to:
  /// **'Not eligible for this voting round'**
  String get votingIneligibleTitle;

  /// Dialog button that goes back to signing the remaining bundles on Keystone.
  ///
  /// In en, this message translates to:
  /// **'Keep signing'**
  String get votingKeepSigning;

  /// Dialog button that returns to the unanswered questions.
  ///
  /// In en, this message translates to:
  /// **'Keep voting'**
  String get votingKeepVoting;

  /// Label above the memo of one bundle on the Keystone signing panel.
  ///
  /// In en, this message translates to:
  /// **'Bundle {number} of {total} memo'**
  String votingKeystoneMemoLabel(int number, int total);

  /// Message on the Keystone signing panel when a new request QR for the next group of bundles is shown.
  ///
  /// In en, this message translates to:
  /// **'The next signing batch is ready'**
  String get votingKeystoneNextBatch;

  /// Tooltip of the button that shows the memo of the next bundle.
  ///
  /// In en, this message translates to:
  /// **'Next bundle memo'**
  String get votingKeystoneNextMemo;

  /// Caption under the Keystone request QR when a single approval signs all bundles.
  ///
  /// In en, this message translates to:
  /// **'One Keystone approval'**
  String get votingKeystoneOneApproval;

  /// Tooltip of the button that shows the memo of the previous bundle.
  ///
  /// In en, this message translates to:
  /// **'Previous bundle memo'**
  String get votingKeystonePreviousMemo;

  /// Caption under the Keystone request QR when it covers only part of the remaining bundles.
  ///
  /// In en, this message translates to:
  /// **'This QR signs {count} of {total} remaining bundles'**
  String votingKeystoneQrPartial(int count, int total);

  /// Instruction on the Keystone signing panel describing the two-way QR exchange.
  ///
  /// In en, this message translates to:
  /// **'Scan QR on this screen with Keystone. Then, scan the signed voting QR displayed on Keystone with this device\'s camera'**
  String get votingKeystoneScanInstruction;

  /// Button on the Keystone signing panel that opens the camera to scan the signed QR.
  ///
  /// In en, this message translates to:
  /// **'Scan signature'**
  String get votingKeystoneScanSignature;

  /// Heading of the Keystone signing panel; zero means the request is still being prepared.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Preparing voting signatures} =1{Sign 1 voting bundle} other{Sign {count} voting bundles}}'**
  String votingKeystoneSignLabel(int count);

  /// Error shown when the scanned QR is not the signed voting result.
  ///
  /// In en, this message translates to:
  /// **'Open the signed voting QR on Keystone, then scan again.'**
  String get votingKeystoneUnexpectedUr;

  /// [security] Notice on the Ledger panel: approving on the device authorizes the delegation, and the memo must be checked in Vizor because the device may not show it verbatim.
  ///
  /// In en, this message translates to:
  /// **'Approving on Ledger authorizes this voting delegation. Review the memo below in Vizor before continuing; the device may not display this memo verbatim.'**
  String get votingLedgerApprovalNotice;

  /// Body of the Ledger panel asking the user to approve opening the Zcash app on the device.
  ///
  /// In en, this message translates to:
  /// **'Approve the request to open the Zcash app on your Ledger.'**
  String get votingLedgerConfirmOpenBody;

  /// Title of the Ledger panel while the delegation is finished.
  ///
  /// In en, this message translates to:
  /// **'Finishing voting delegation'**
  String get votingLedgerFinishing;

  /// Heading of the desktop Ledger signing panel.
  ///
  /// In en, this message translates to:
  /// **'Voting delegation'**
  String get votingLedgerPanelTitle;

  /// Body of the Ledger panel while the request is prepared.
  ///
  /// In en, this message translates to:
  /// **'Please wait while Vizor prepares your request.'**
  String get votingLedgerPleaseWait;

  /// Title of the Ledger panel while the delegation request is prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing voting delegation'**
  String get votingLedgerPreparing;

  /// Fallback body of the Ledger panel when the device has a problem and no detail is known.
  ///
  /// In en, this message translates to:
  /// **'Reconnect your Ledger and try again.'**
  String get votingLedgerReconnect;

  /// Error on the mobile voting pages when the wallet account could not be loaded; {error} is the reason on a new line.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load account.\n{error}'**
  String votingMobileAccountLoadFailed(String error);

  /// Title in the sticky header of a mobile voting page.
  ///
  /// In en, this message translates to:
  /// **'Voting'**
  String get votingMobileHeaderTitle;

  /// Status on the mobile Keystone screen while the signature is verified.
  ///
  /// In en, this message translates to:
  /// **'Checking voting signature...'**
  String get votingMobileKeystoneChecking;

  /// Instruction on the mobile Keystone signing screen.
  ///
  /// In en, this message translates to:
  /// **'Scan the voting request with Keystone, approve it, then scan the signed result with this device.'**
  String get votingMobileKeystoneDescription;

  /// Title of the mobile Keystone signing screen when the signature could not be used.
  ///
  /// In en, this message translates to:
  /// **'Voting signature failed'**
  String get votingMobileKeystoneFailedTitle;

  /// Accessibility label of the button that shows the next bundle's memo.
  ///
  /// In en, this message translates to:
  /// **'Next voting bundle'**
  String get votingMobileKeystoneNextBundle;

  /// Accessibility label of the button that shows the previous bundle's memo.
  ///
  /// In en, this message translates to:
  /// **'Previous voting bundle'**
  String get votingMobileKeystonePreviousBundle;

  /// Status on the mobile Keystone screen while the scanned signature is read.
  ///
  /// In en, this message translates to:
  /// **'Reading voting signature...'**
  String get votingMobileKeystoneReading;

  /// Caption under the camera view on the mobile Keystone screen.
  ///
  /// In en, this message translates to:
  /// **'Scan the signed voting QR shown on Keystone'**
  String get votingMobileKeystoneScanCaption;

  /// Button on the mobile Keystone screen that submits with only the bundles signed so far.
  ///
  /// In en, this message translates to:
  /// **'Skip unsigned bundles'**
  String get votingMobileKeystoneSkipUnsigned;

  /// Title of the mobile screen that shows the QR for signing the vote on Keystone.
  ///
  /// In en, this message translates to:
  /// **'Sign vote with Keystone'**
  String get votingMobileKeystoneTitle;

  /// [security] Notice on the mobile submission screen telling the user to stay on it.
  ///
  /// In en, this message translates to:
  /// **'Don’t leave this window.'**
  String get votingMobileLeaveWarning;

  /// Accessibility label of the progress ring of the active submission step.
  ///
  /// In en, this message translates to:
  /// **'Active voting submission step progress'**
  String get votingMobileProgressSemantics;

  /// [security] Notice on the mobile submission screen that proofs take about a minute and closing may lose their progress.
  ///
  /// In en, this message translates to:
  /// **'Generating zero-knowledge proofs can take about 60 seconds, closing now may lose in-flight proof work.'**
  String get votingMobileProofNotice;

  /// Top-bar title of the mobile screen shown while the vote is submitted.
  ///
  /// In en, this message translates to:
  /// **'Submit vote'**
  String get votingMobileSubmitTitle;

  /// Body of the mobile screen shown after the vote was submitted.
  ///
  /// In en, this message translates to:
  /// **'Your vote has been submitted and can’t be changed.'**
  String get votingMobileSubmittedBody;

  /// Top-bar title of the mobile screen shown after the vote was submitted.
  ///
  /// In en, this message translates to:
  /// **'Vote submitted'**
  String get votingMobileSubmittedTitle;

  /// Title of the mobile screen while votes are being submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitting votes...'**
  String get votingMobileSubmittingTitle;

  /// Progress label when every question has an answer.
  ///
  /// In en, this message translates to:
  /// **'All questions answered'**
  String get votingNavAllAnswered;

  /// Progress label on the sticky action bar showing how many questions are answered.
  ///
  /// In en, this message translates to:
  /// **'{answered} / {total} answered'**
  String votingNavAnsweredProgress(int answered, int total);

  /// Hint in the questions sheet when every question is answered.
  ///
  /// In en, this message translates to:
  /// **'Your answers are ready to review.'**
  String get votingNavReadyToReview;

  /// Hint in the unanswered questions sheet.
  ///
  /// In en, this message translates to:
  /// **'Tap a question to jump to it.'**
  String get votingNavTapToJump;

  /// Progress label with the number of unanswered questions.
  ///
  /// In en, this message translates to:
  /// **'Unanswered · {count}'**
  String votingNavUnansweredCount(int count);

  /// Accessibility label of the menu listing the unanswered questions.
  ///
  /// In en, this message translates to:
  /// **'Unanswered questions'**
  String get votingNavUnansweredMenu;

  /// Body shown when a voting round has no proposals.
  ///
  /// In en, this message translates to:
  /// **'This voting round does not contain any proposals.'**
  String get votingNoProposalsBody;

  /// Title shown when a voting round has no proposals.
  ///
  /// In en, this message translates to:
  /// **'No proposals'**
  String get votingNoProposalsTitle;

  /// Shown in place of the voting power value when it is unknown.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get votingNotAvailable;

  /// Label shown when the account may not vote in the round; used on a button and as a badge.
  ///
  /// In en, this message translates to:
  /// **'Not eligible'**
  String get votingNotEligible;

  /// Trailing label of an answer option that can be picked.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get votingOptionChoose;

  /// Trailing label of the answer option the user picked.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get votingOptionSelected;

  /// Body shown on a voting round whose vote was started but not completed.
  ///
  /// In en, this message translates to:
  /// **'You have an unfinished vote for this round. Resume to complete the submission.'**
  String get votingPendingBody;

  /// Title shown on a voting round whose vote was started but not completed.
  ///
  /// In en, this message translates to:
  /// **'Vote in progress'**
  String get votingPendingTitle;

  /// Error shown when the PIR servers are already past the voting round's snapshot block.
  ///
  /// In en, this message translates to:
  /// **'Configured PIR endpoints are ahead of this voting round snapshot. Expected snapshot block {expected}; endpoints report {reported}.'**
  String votingPirAhead(String expected, String reported);

  /// Error shown when the PIR servers have not reached the voting round's snapshot block yet; PIR is a private information retrieval service.
  ///
  /// In en, this message translates to:
  /// **'Voting PIR data is not ready for this voting round yet. Expected snapshot block {expected}; PIR endpoints report {reported}. Retry once the PIR service catches up.'**
  String votingPirBehind(String expected, String reported);

  /// Error shown when no PIR server matches the voting round's snapshot block.
  ///
  /// In en, this message translates to:
  /// **'No PIR endpoint matched this voting round snapshot. Expected snapshot block {expected}.'**
  String votingPirNoMatch(String expected);

  /// Technical error detail shown when no PIR server matches the snapshot; {diagnostics} is a machine-written list per endpoint.
  ///
  /// In en, this message translates to:
  /// **'No PIR endpoint matched this voting round snapshot. Expected snapshot block {expected}. Diagnostics: {diagnostics}.'**
  String votingPirNoMatchDiagnostics(String expected, String diagnostics);

  /// Error shown when none of the configured PIR servers could be reached.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach any configured PIR endpoint. Check your network connection and retry.'**
  String get votingPirUnreachable;

  /// Label on a voting round card when this account's funds were already used to vote in this round.
  ///
  /// In en, this message translates to:
  /// **'Already used for this round'**
  String get votingPollAlreadyUsed;

  /// Closing date on a finished voting round card; {date} is a short date such as Jan 5.
  ///
  /// In en, this message translates to:
  /// **'Closed {date}'**
  String votingPollClosed(String date);

  /// Closing date on an open voting round card; {date} is a short date such as Jan 5.
  ///
  /// In en, this message translates to:
  /// **'Closes {date}'**
  String votingPollCloses(String date);

  /// Label on a voting round card when the account has no voting power in this round.
  ///
  /// In en, this message translates to:
  /// **'Not eligible for this round'**
  String get votingPollNotEligible;

  /// Start date on an upcoming voting round card; {date} is a short date such as Jan 5.
  ///
  /// In en, this message translates to:
  /// **'Starts {date}'**
  String votingPollStarts(String date);

  /// Body of the empty state on the voting list.
  ///
  /// In en, this message translates to:
  /// **'There are no token holder voting rounds to display yet.'**
  String get votingPollsEmptyBody;

  /// Title of the empty state on the voting list.
  ///
  /// In en, this message translates to:
  /// **'No voting rounds available'**
  String get votingPollsEmptyTitle;

  /// Title of the error shown on the voting list when the voting rounds could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting rounds'**
  String get votingPollsLoadFailedTitle;

  /// Meta line of a voting round showing the account's voting power; {amount} is a ZEC amount.
  ///
  /// In en, this message translates to:
  /// **'Voting power {amount}'**
  String votingPowerMeta(String amount);

  /// Message shown when the account's voting power could not be determined.
  ///
  /// In en, this message translates to:
  /// **'Voting power unavailable.'**
  String get votingPowerUnavailableSentence;

  /// Short note in the voting round summary when the account's voting power could not be determined.
  ///
  /// In en, this message translates to:
  /// **'Voting power unavailable'**
  String get votingPowerUnavailableTitle;

  /// Message shown while the wallet calculates how much voting power the account has.
  ///
  /// In en, this message translates to:
  /// **'Preparing voting power.'**
  String get votingPreparingPower;

  /// Meta line of a voting round while the voting power is being calculated.
  ///
  /// In en, this message translates to:
  /// **'Preparing voting power'**
  String get votingPreparingPowerMeta;

  /// [security] Note on the voting round page: a small part of the user's voting power is withheld so the submission cannot be linked to the user; {amount} is a ZEC amount.
  ///
  /// In en, this message translates to:
  /// **'{amount} is left out of this vote to keep your submission less identifiable.'**
  String votingPrivacyTrimNotice(String amount);

  /// Progress count under the proving step of voting submission; a bundle is a group of notes proved together.
  ///
  /// In en, this message translates to:
  /// **'{proved} of {total} bundles proved'**
  String votingProgressBundlesProved(int proved, int total);

  /// Detail under the proving step once all bundles are proved; {suffix} is empty or a dash followed by a count.
  ///
  /// In en, this message translates to:
  /// **'Finalizing delegation{suffix}'**
  String votingProgressFinalizingDelegation(String suffix);

  /// Detail under the proving step while a proof started earlier is reused; {suffix} is empty or a dash followed by a count.
  ///
  /// In en, this message translates to:
  /// **'Reusing an in-progress proof{suffix}'**
  String votingProgressReusingProof(String suffix);

  /// Detail under the proving step while waiting for the chain; {suffix} is empty or a dash followed by a proved-bundles count.
  ///
  /// In en, this message translates to:
  /// **'Waiting for submission and confirmation{suffix}'**
  String votingProgressWaitingConfirmation(String suffix);

  /// Label of the receipt row showing the account's voting power in ZEC.
  ///
  /// In en, this message translates to:
  /// **'Voting power'**
  String get votingReceiptPower;

  /// Number of bundles signed by this Keystone request out of those still unsigned.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} remaining bundles'**
  String votingRemainingBundles(int count, int total);

  /// Title of the voting results screen when the round has no title.
  ///
  /// In en, this message translates to:
  /// **'Voting results'**
  String get votingResultsFallbackTitle;

  /// Button that collapses a proposal's long description on the results screen.
  ///
  /// In en, this message translates to:
  /// **'Hide description'**
  String get votingResultsHideDescription;

  /// Error on the voting results screen when the tally could not be loaded; {error} is the reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load results: {error}'**
  String votingResultsLoadFailed(String error);

  /// Message on the voting results screen when the round has no proposals.
  ///
  /// In en, this message translates to:
  /// **'No proposals in this round.'**
  String get votingResultsNoProposals;

  /// Message on the voting results screen while the tally is not ready yet.
  ///
  /// In en, this message translates to:
  /// **'Results pending...'**
  String get votingResultsPending;

  /// Error on the voting results screen when the round details could not be loaded; {error} is the reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load voting round details: {error}'**
  String votingResultsRoundLoadFailed(String error);

  /// Button that expands a proposal's long description on the results screen.
  ///
  /// In en, this message translates to:
  /// **'Show description'**
  String get votingResultsShowDescription;

  /// Line on a proposal result with the total voting weight cast; {amount} is a ZEC amount.
  ///
  /// In en, this message translates to:
  /// **'Total: {amount}'**
  String votingResultsTotalAmount(String amount);

  /// Line on a proposal result naming the option the user voted for; {choice} is the option label from the vote data.
  ///
  /// In en, this message translates to:
  /// **'Voted: {choice}'**
  String votingResultsVotedFor(String choice);

  /// Label marking the winning option in a proposal result.
  ///
  /// In en, this message translates to:
  /// **'Winner'**
  String get votingResultsWinner;

  /// Label marking the option the user voted for in a proposal result.
  ///
  /// In en, this message translates to:
  /// **'Your vote'**
  String get votingResultsYourVote;

  /// Message on the review screen when no question has an answer yet.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one option before submitting.'**
  String get votingReviewChooseOne;

  /// Button on the review screen that submits the vote.
  ///
  /// In en, this message translates to:
  /// **'Confirm & submit'**
  String get votingReviewConfirmSubmit;

  /// Error shown on the vote review screen when it failed to load; {error} is the reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load review: {error}'**
  String votingReviewLoadFailed(String error);

  /// Status on the review screen of a question the user did not answer.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get votingReviewSkipped;

  /// Title of the screen where the user checks their answers before submitting the vote.
  ///
  /// In en, this message translates to:
  /// **'Review your answers'**
  String get votingReviewTitle;

  /// Instruction on the desktop screen that scans the signed voting QR.
  ///
  /// In en, this message translates to:
  /// **'Hold the Keystone QR code steady in front of your camera'**
  String get votingScanHold;

  /// Message on the desktop scan screen when no camera is available.
  ///
  /// In en, this message translates to:
  /// **'Keystone voting uses camera QR scanning only. Connect a camera and try again.'**
  String get votingScanNoCamera;

  /// Title of the desktop screen that scans the signed voting QR from Keystone.
  ///
  /// In en, this message translates to:
  /// **'Scan voting signature'**
  String get votingScanTitle;

  /// Body of the dialog offering to submit with only the signed bundles.
  ///
  /// In en, this message translates to:
  /// **'Vizor can submit now using only signatures already scanned from Keystone.'**
  String get votingSignedOnlyBody;

  /// Title of the dialog offering to submit the vote with only the bundles already signed on Keystone; a bundle is a group of notes signed together.
  ///
  /// In en, this message translates to:
  /// **'Use signed bundles only?'**
  String get votingSignedOnlyTitle;

  /// [security] Warning in the dialog that unsigned bundles are dropped and voting power is reduced.
  ///
  /// In en, this message translates to:
  /// **'Unsigned bundles are skipped, which lowers voting power for this voting round.'**
  String get votingSignedOnlyWarning;

  /// Button on the Keystone signing panel that skips the bundles still unsigned.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get votingSkip;

  /// Dialog button that submits the vote without the unsigned bundles.
  ///
  /// In en, this message translates to:
  /// **'Skip bundles'**
  String get votingSkipBundles;

  /// Body of the dialog asking whether to continue while some questions are unanswered.
  ///
  /// In en, this message translates to:
  /// **'You have not answered {skipped} of {total} questions. The review screen will mark them as skipped, and skipped questions will not be submitted.'**
  String votingSkipDialogBody(int skipped, int total);

  /// Title of the dialog asking whether to continue while some questions are unanswered.
  ///
  /// In en, this message translates to:
  /// **'Skip unanswered questions?'**
  String get votingSkipDialogTitle;

  /// Phrase naming the voting round's snapshot block; {height} is the formatted block number. Used inside eligibility error sentences.
  ///
  /// In en, this message translates to:
  /// **'snapshot block {height}'**
  String votingSnapshotBlock(String height);

  /// Phrase naming the voting round's snapshot block when its height is unknown; used inside eligibility error sentences.
  ///
  /// In en, this message translates to:
  /// **'the voting round snapshot block'**
  String get votingSnapshotUnknown;

  /// Body shown when the voting round needs a software account but a hardware account is active.
  ///
  /// In en, this message translates to:
  /// **'Token holder voting requires a software account. Switch to a software account to vote in this round.'**
  String get votingSoftwareRequiredBody;

  /// Title shown when the voting round needs a software account but a hardware account is active.
  ///
  /// In en, this message translates to:
  /// **'Software account required'**
  String get votingSoftwareRequiredTitle;

  /// Status badge of a voting round that is open for voting.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get votingStatusActive;

  /// [security] Body of the voting status screen warning not to close the window while proofs are generated.
  ///
  /// In en, this message translates to:
  /// **'Don\'t close the window. Generating zero-knowledge proofs can take a while; closing now may lose in-flight proof work.'**
  String get votingStatusBodyKeepOpen;

  /// Body of the voting status screen while Ledger approvals are pending.
  ///
  /// In en, this message translates to:
  /// **'Keep Vizor open. Follow the instructions below for each voting bundle.'**
  String get votingStatusBodyLedger;

  /// Status badge of a voting round that has closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get votingStatusClosed;

  /// Fallback error on the voting status screen when no specific error text exists.
  ///
  /// In en, this message translates to:
  /// **'Voting failed.'**
  String get votingStatusFailed;

  /// Generic error on the voting status screen when voting failed without a specific reason.
  ///
  /// In en, this message translates to:
  /// **'Voting could not continue for this account. Retry, or switch to an eligible account if this account cannot vote in this voting round.'**
  String get votingStatusGenericError;

  /// Status badge of a voting round that closed and whose results are being counted.
  ///
  /// In en, this message translates to:
  /// **'Tallying'**
  String get votingStatusTallying;

  /// Title of the desktop voting status screen while a Ledger approval is pending.
  ///
  /// In en, this message translates to:
  /// **'Voting with Ledger'**
  String get votingStatusTitleLedger;

  /// Title of the desktop voting status screen while votes are submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitting votes'**
  String get votingStatusTitleSubmitting;

  /// Status badge of a voting round in which this account already voted.
  ///
  /// In en, this message translates to:
  /// **'Voted'**
  String get votingStatusVoted;

  /// Step label of the voting progress list while votes are cast and vote shares are submitted.
  ///
  /// In en, this message translates to:
  /// **'Casting votes and submitting shares'**
  String get votingStepCasting;

  /// Step label of the voting progress list for the last step.
  ///
  /// In en, this message translates to:
  /// **'Finalizing submission'**
  String get votingStepFinalizing;

  /// Step label of the voting progress list while the zero-knowledge proof of voting authority is generated.
  ///
  /// In en, this message translates to:
  /// **'Proving voting authority'**
  String get votingStepProving;

  /// Step label of the voting progress list while signing on a Keystone.
  ///
  /// In en, this message translates to:
  /// **'Signing with Keystone'**
  String get votingStepSigningKeystone;

  /// Step label of the voting progress list while signing on a Ledger.
  ///
  /// In en, this message translates to:
  /// **'Signing with Ledger'**
  String get votingStepSigningLedger;

  /// [security] Toast shown when the user tries to remove an account or reset the wallet while a vote is still being submitted.
  ///
  /// In en, this message translates to:
  /// **'Vote submission is still running. Wait for it to finish before removing an account or resetting the wallet.'**
  String get votingSubmissionInProgress;

  /// Dialog button that opens the account switcher so the user can pick an eligible account.
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get votingSwitchAccount;

  /// Closing sentence of the eligibility error messages; the screen shows it separately and it must end those messages with identical wording.
  ///
  /// In en, this message translates to:
  /// **'Switch to an eligible account to vote.'**
  String get votingSwitchEligibleGuidance;

  /// Line in the wallet sync box showing how many blocks are left to sync.
  ///
  /// In en, this message translates to:
  /// **'{count} blocks remaining'**
  String votingSyncBlocksRemaining(int count);

  /// Part of the wallet sync detail line on the voting status screen; {height} is the latest block number.
  ///
  /// In en, this message translates to:
  /// **'chain tip {height}'**
  String votingSyncChainTip(int height);

  /// Part of the wallet sync detail line on the voting status screen; {height} is a block number.
  ///
  /// In en, this message translates to:
  /// **'Synced to block {height}'**
  String votingSyncSynced(int height);

  /// Body of the box shown while the wallet is still syncing up to the voting snapshot.
  ///
  /// In en, this message translates to:
  /// **'Your wallet is catching up to this voting round snapshot. Voting will continue automatically once the wallet has synced through the snapshot block.'**
  String get votingSyncWaitingBody;

  /// Names one failed delegation bundle with its reason inside the terminal delegation error.
  ///
  /// In en, this message translates to:
  /// **'bundle {number} ({reason})'**
  String votingTerminalBundle(int number, String reason);

  /// [security] Error when several delegation bundles can no longer continue; warns against retrying because the transactions may already be on chain.
  ///
  /// In en, this message translates to:
  /// **'Delegation for {bundles} cannot continue. Do not retry it; the transaction may already be on the chain.'**
  String votingTerminalMultiple(String bundles);

  /// Reason used inside the terminal delegation error when the bundle gave no failure detail.
  ///
  /// In en, this message translates to:
  /// **'it ended without confirming'**
  String get votingTerminalReasonDefault;

  /// [security] Error when one delegation bundle can no longer continue; warns against retrying because the transaction may already be on chain.
  ///
  /// In en, this message translates to:
  /// **'Delegation {bundle} cannot continue. Do not retry it; the transaction may already be on the chain.'**
  String votingTerminalSingle(String bundle);

  /// Fallback name of a voting round shown when the round has no title.
  ///
  /// In en, this message translates to:
  /// **'Token holder voting'**
  String get votingTokenHolderTitle;

  /// Button that collapses a long description.
  ///
  /// In en, this message translates to:
  /// **'View less'**
  String get votingViewLess;

  /// Button that expands a long description.
  ///
  /// In en, this message translates to:
  /// **'View more'**
  String get votingViewMore;

  /// Note that a submitted vote can no longer be changed.
  ///
  /// In en, this message translates to:
  /// **'Vote locked'**
  String get votingVoteLocked;

  /// Line under the title of a voting round the user already voted in; {date} is the voting date such as Jan 5, 2026.
  ///
  /// In en, this message translates to:
  /// **'Voted {date}'**
  String votingVotedOn(String date);

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

  /// Action in a list section header that clears the selection.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get walletLinkDeselectAll;

  /// [security] Subtitle of the desktop password prompt that explains why the password is needed before linking Vizor Mobile.
  ///
  /// In en, this message translates to:
  /// **'To link Vizor Mobile.'**
  String get walletLinkDesktopConfirmSubtitle;

  /// First sentence of the privacy note on the placeholder shown before the QR code appears; followed by a bold sentence.
  ///
  /// In en, this message translates to:
  /// **'The code is encrypted with a one-time key and expires after a minute.'**
  String get walletLinkDesktopEncryptedNotice;

  /// Bold second sentence of the privacy note on the QR placeholder.
  ///
  /// In en, this message translates to:
  /// **'Only your phone can decode it.'**
  String get walletLinkDesktopEncryptedStrong;

  /// Error on the desktop link screen when an account lacks the data needed to derive its keys.
  ///
  /// In en, this message translates to:
  /// **'Wallet account derivation metadata is not available.'**
  String get walletLinkDesktopErrorDerivationMissing;

  /// Error on the desktop link screen when the code expired before it could be displayed.
  ///
  /// In en, this message translates to:
  /// **'The mobile link expired before it could be shown.'**
  String get walletLinkDesktopErrorExpiredBeforeShown;

  /// Fallback message on the desktop link error screen when no specific reason is known.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the mobile link.'**
  String get walletLinkDesktopErrorFallback;

  /// Error on the desktop link screen when a hardware wallet account lacks its stored metadata.
  ///
  /// In en, this message translates to:
  /// **'Hardware wallet metadata is not available.'**
  String get walletLinkDesktopErrorHardwareMetadataMissing;

  /// [security] Error on the desktop link screen when the wallet secrets are not available because the wallet is locked.
  ///
  /// In en, this message translates to:
  /// **'Unlock this wallet before linking mobile.'**
  String get walletLinkDesktopErrorLocked;

  /// Error on the desktop link screen when the wallet has no accounts to link.
  ///
  /// In en, this message translates to:
  /// **'No wallet accounts are available to link.'**
  String get walletLinkDesktopErrorNoAccounts;

  /// Generic error on the desktop link screen when preparing the link failed.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the mobile link. Try again.'**
  String get walletLinkDesktopErrorPrepareFailed;

  /// Error on the desktop link screen when the linking server cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the linking server. Try again.'**
  String get walletLinkDesktopErrorServerUnreachable;

  /// Body of the expired-link screen on desktop.
  ///
  /// In en, this message translates to:
  /// **'For your security the link is only valid for a minute. Generate a fresh code and scan it again.'**
  String get walletLinkDesktopExpiredBody;

  /// Countdown under the QR code; {time} is the remaining time such as 0:45.
  ///
  /// In en, this message translates to:
  /// **'Expires in {time}'**
  String walletLinkDesktopExpiresIn(String time);

  /// Button on the expired-link screen that creates a new one-time code.
  ///
  /// In en, this message translates to:
  /// **'Generate new code'**
  String get walletLinkDesktopGenerateNewCode;

  /// Body text on the desktop link screen before a code is generated.
  ///
  /// In en, this message translates to:
  /// **'Connect this wallet to your Vizor mobile app by scanning a one-time QR code.'**
  String get walletLinkDesktopInitialBody;

  /// Body of the success screen when the number of imported items is unknown.
  ///
  /// In en, this message translates to:
  /// **'Vizor Mobile was linked to this wallet.'**
  String get walletLinkDesktopLinkedBody;

  /// Body of the success screen reporting how many accounts and contacts the phone imported.
  ///
  /// In en, this message translates to:
  /// **'{accountCount, plural, =1{1 account} other{{accountCount} accounts}} and {contactCount, plural, =1{1 contact} other{{contactCount} contacts}} were imported on mobile.'**
  String walletLinkDesktopLinkedCounts(int accountCount, int contactCount);

  /// Title of the success screen after the phone finished linking.
  ///
  /// In en, this message translates to:
  /// **'Vizor Mobile linked successfully'**
  String get walletLinkDesktopLinkedTitle;

  /// Status line under the QR code saying the single code is ready to be scanned.
  ///
  /// In en, this message translates to:
  /// **'1/1 Ready to scan...'**
  String get walletLinkDesktopReadyToScan;

  /// Button under the QR code that creates a fresh one-time code.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get walletLinkDesktopRegenerate;

  /// Instruction under the QR title; the arrows separate menu steps in the mobile app and 'Link Vizor Desktop' is a menu name.
  ///
  /// In en, this message translates to:
  /// **'Open Vizor on your phone → Add a wallet → Link Vizor Desktop'**
  String get walletLinkDesktopScanBody;

  /// Title above the one-time QR code on the desktop link screen.
  ///
  /// In en, this message translates to:
  /// **'Scan with Vizor mobile'**
  String get walletLinkDesktopScanTitle;

  /// Button on the desktop link screen that generates the one-time QR code.
  ///
  /// In en, this message translates to:
  /// **'Start linking'**
  String get walletLinkDesktopStartLinking;

  /// Title of the desktop screen that starts linking the desktop wallet to the Vizor mobile app.
  ///
  /// In en, this message translates to:
  /// **'Link Vizor Mobile'**
  String get walletLinkDesktopTitle;

  /// Title of the desktop link error screen.
  ///
  /// In en, this message translates to:
  /// **'Link unavailable'**
  String get walletLinkDesktopUnavailableTitle;

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

  /// Button on the contact selection screen that imports the selected contacts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Import 1 contact} other{Import {count} contacts}}'**
  String walletLinkImportContacts(int count);

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

  /// Toast shown when another wallet change, such as switching an account or toggling Private queries, is still running.
  ///
  /// In en, this message translates to:
  /// **'Finish the current wallet operation before starting another.'**
  String get walletMutationBusy;

  /// [security] Error when the device passcode check before a wallet reset failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify device ownership. Please try again.'**
  String get walletResetDeviceAuthFailed;

  /// Reason line in the operating system's device-authentication prompt when the user resets the wallet.
  ///
  /// In en, this message translates to:
  /// **'Confirm reset Vizor'**
  String get walletResetDeviceAuthReason;

  /// [security] Error when the user skipped the device passcode check before resetting the wallet.
  ///
  /// In en, this message translates to:
  /// **'Device authentication is required to reset Vizor.'**
  String get walletResetDeviceAuthRequired;

  /// Error when erasing the wallet failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset Vizor. Please try again.'**
  String get walletResetFailed;

  /// [security] Reset or account removal is refused while a gift card claim is in progress. Keep it to one short line.
  ///
  /// In en, this message translates to:
  /// **'A gift card is still being received. Wait for it to finish.'**
  String get walletResetGiftCardInFlight;

  /// [security] Warning on the locked reset screens while a gift card claim is in progress; reset is still allowed.
  ///
  /// In en, this message translates to:
  /// **'A gift card is still being received. Resetting loses it.'**
  String get walletResetGiftCardWarning;

  /// Error shown when the user starts a software update download that is no longer available.
  ///
  /// In en, this message translates to:
  /// **'This update is no longer ready to download. Check for updates again.'**
  String get windowsUpdateNotReady;

  /// Error shown when a software update cannot start because the updater has no Tor connection.
  ///
  /// In en, this message translates to:
  /// **'The software updater is not connected to Tor. Retry updates in Settings, or turn off Tor and try again.'**
  String get windowsUpdateTorRouteUnavailable;
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
