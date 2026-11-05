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

  /// Label of the account name field or row.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountNameLabel;

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

  /// Status of a gift card receipt after the card was created.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get activityGiftStatusCreated;

  /// Status of a gift card receipt while the card is being created.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get activityGiftStatusCreating;

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

  /// Label of a row on a transaction receipt: the number of gift cards in a batch.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get activityReceiptCards;

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

  /// Label of a row on a transaction receipt: the total network fee of the transaction.
  ///
  /// In en, this message translates to:
  /// **'Network fee'**
  String get activityReceiptNetworkFee;

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

  /// Shown as the fee of a transaction whose fee the wallet has not recorded. An unknown fee is never zero.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get activityReceiptUnknownFee;

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

  /// Title of an activity row or receipt for an incoming transaction.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get activityTitleReceived;

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

  /// Fallback name of the camera in the desktop QR scanner footer.
  ///
  /// In en, this message translates to:
  /// **'Default camera'**
  String get addressScanDefaultCamera;

  /// Title in the desktop QR scanner when the camera permission was denied.
  ///
  /// In en, this message translates to:
  /// **'You\'ve denied Camera access'**
  String get addressScanDeniedTitle;

  /// Title in the desktop QR scanner when Windows blocks the camera.
  ///
  /// In en, this message translates to:
  /// **'Enable Windows camera access'**
  String get addressScanEnableWindowsAccess;

  /// Title of the desktop QR scanner while waiting for the camera permission.
  ///
  /// In en, this message translates to:
  /// **'Grant access to your camera'**
  String get addressScanGrantAccess;

  /// Footer label of the desktop QR scanner while cameras are being listed.
  ///
  /// In en, this message translates to:
  /// **'Loading camera...'**
  String get addressScanLoadingCamera;

  /// Label next to a spinner in the mobile QR scanner while the camera starts.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get addressScanLoadingEllipsis;

  /// Footer label of the desktop QR scanner when the device has no camera.
  ///
  /// In en, this message translates to:
  /// **'No camera found'**
  String get addressScanNoCamera;

  /// Description in the desktop QR scanner when the camera cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'No camera could be opened. Check that a camera is connected and not in use by another app.'**
  String get addressScanNoCameraOpened;

  /// Button that opens the system settings page for the camera permission.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get addressScanOpenSettings;

  /// Title of the QR scanner that reads an address.
  ///
  /// In en, this message translates to:
  /// **'Scan the address QR code'**
  String get addressScanTitle;

  /// Description telling the user which two switches to turn on in Windows Settings. Use the Windows setting names.
  ///
  /// In en, this message translates to:
  /// **'Turn on Camera access and Let desktop apps access your camera in Windows Settings.'**
  String get addressScanWindowsAccessHint;

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

  /// Back-link name of the voting results screen.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get appBackResults;

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

  /// Back-link name of a coinholder voting round screen.
  ///
  /// In en, this message translates to:
  /// **'Voting round'**
  String get appBackVotingRound;

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

  /// Label of a row on a transaction receipt: the transferred amount. Shared by: activity, app, pay, receive, send, swap.
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

  /// Status while Vizor checks something.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get commonChecking;

  /// Label of the primary button on the payment request card while the request is being checked. Shared by: send, settings.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get commonCheckingEllipsis;

  /// Subtitle of a pending activity row while the app checks the transaction status. Shared by: activity, swap.
  ///
  /// In en, this message translates to:
  /// **'Checking status'**
  String get commonCheckingStatus;

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

  /// Button label and accessibility label that copies the shielded address. Shared by: receive, sidebar.
  ///
  /// In en, this message translates to:
  /// **'Copy shielded address'**
  String get commonCopyShieldedAddress;

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

  /// Accessibility label of the toggle that switches the mobile Pay amount input to US dollars. Shared by: pay, receive.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in USD'**
  String get commonEnterAmountInUsd;

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

  /// [security] Primary button in the desktop Keystone modal that opens the scanner to read the signature QR code from the device. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'Get signature'**
  String get commonGetSignature;

  /// Button that returns to the previous screen.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get commonGoBack;

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

  /// Hint while scanning a QR code from a device screen. Shared by: common, pay.
  ///
  /// In en, this message translates to:
  /// **'Keep the QR code steady and fully visible.'**
  String get commonKeepQrSteady;

  /// Setting and button that keep the screen on while Vizor syncs.
  ///
  /// In en, this message translates to:
  /// **'Keep screen awake'**
  String get commonKeepScreenAwake;

  /// [security] Instruction in the desktop Keystone modal after proofs are ready. Shared by: send, swap.
  ///
  /// In en, this message translates to:
  /// **'After you scanned, click Get signature.'**
  String get commonKeystoneAfterScan;

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

  /// Label of a status detail row with the network and conversion fees of a payment in progress.
  ///
  /// In en, this message translates to:
  /// **'Network + conversion fees'**
  String get commonNetworkConversionFees;

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

  /// Error on the Pay recipient step when the quote costs more ZEC than is spendable. Shared by: pay, swap.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have enough ZEC for this payment. Try a smaller amount.'**
  String get commonPayInsufficientZec;

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

  /// Button that opens the camera to scan the requester's original payment request QR code.
  ///
  /// In en, this message translates to:
  /// **'Scan original QR'**
  String get commonScanOriginalQr;

  /// Title of a QR code scanning screen.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get commonScanQrCode;

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

  /// Label of a row on a transaction receipt: the transaction ID, tapping it opens a block explorer. Shared by: activity, send, swap.
  ///
  /// In en, this message translates to:
  /// **'Tx ID'**
  String get commonTxId;

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

  /// The Update button label while the change is being saved.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get commonUpdating;

  /// Title of the unlock screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get commonWelcomeBack;

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

  /// Two-line description under the camera unavailable title. Keep the line break; each line is shown on its own line without wrapping, so keep both lines short.
  ///
  /// In en, this message translates to:
  /// **'Keystone import uses camera QR scanning only.\nConnect a camera and try again.'**
  String get keystoneCameraUnavailableBody;

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

  /// Title of the Home sheet saying a Zcash network upgrade stopped the migration.
  ///
  /// In en, this message translates to:
  /// **'Migration stopped by network upgrade'**
  String get migrationMobileAttentionStoppedTitle;

  /// Default label of the secondary button that returns to Home from a mobile migration status screen.
  ///
  /// In en, this message translates to:
  /// **'Back home'**
  String get migrationMobileBackHome;

  /// Button on the migration progress screen that returns to Home.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get migrationMobileBackToHome;

  /// Text of the Home migration banner while the migration runs and no amount is known.
  ///
  /// In en, this message translates to:
  /// **'Migration in progress'**
  String get migrationMobileBannerInProgress;

  /// Text of the Home migration banner when a migration transaction is late.
  ///
  /// In en, this message translates to:
  /// **'Migration needs attention'**
  String get migrationMobileBannerLate;

  /// Text of the Home migration banner while the balance is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing migration'**
  String get migrationMobileBannerPreparing;

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

  /// Text of the Home banner that starts the Ironwood migration.
  ///
  /// In en, this message translates to:
  /// **'Migrate to Ironwood'**
  String get migrationMobileBannerStart;

  /// Text of the Home migration banner when the migration was stopped by a network upgrade.
  ///
  /// In en, this message translates to:
  /// **'Migration stopped'**
  String get migrationMobileBannerStopped;

  /// Text of the Home migration banner while waiting for network confirmations.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation...'**
  String get migrationMobileBannerWaiting;

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

  /// First line on the mobile migration progress screen when continuing the migration failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t continue migration. Try again.'**
  String get migrationMobileContinueError;

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

  /// Error shown on the mobile migration screens when the network rejected or failed to receive the migration transaction.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t broadcast the migration transaction. Try again.'**
  String get migrationMobileErrorBroadcast;

  /// Error shown on the mobile Immediate migration review when the amount or fee changed after the plan was calculated.
  ///
  /// In en, this message translates to:
  /// **'The amount or fee changed. Review the updated details.'**
  String get migrationMobileErrorPlanChanged;

  /// Generic error shown on the mobile migration screens when the migration could not start.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start migration. Try again.'**
  String get migrationMobileErrorStart;

  /// Error shown on the mobile migration screens when the migration could not start because the wallet is still syncing.
  ///
  /// In en, this message translates to:
  /// **'Wait for sync to finish, then try again.'**
  String get migrationMobileErrorSyncFirst;

  /// Error shown on the mobile migration screens when the wallet is locked and the migration could not start.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vizor before starting migration.'**
  String get migrationMobileErrorUnlock;

  /// Label of the row showing the estimated time the migration finishes.
  ///
  /// In en, this message translates to:
  /// **'Est. completion'**
  String get migrationMobileEstCompletion;

  /// Secondary button on the Immediate migration review that goes back to the option choice.
  ///
  /// In en, this message translates to:
  /// **'Consider another option'**
  String get migrationMobileFastConsiderOther;

  /// [security] Destructive button on the Immediate migration review that broadcasts the less private migration after the privacy warning.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get migrationMobileFastContinueAnyway;

  /// Label of the row showing how long the Immediate migration takes on the review screen.
  ///
  /// In en, this message translates to:
  /// **'Migration complete in'**
  String get migrationMobileFastDurationRow;

  /// Label of the row showing the estimated network fee on the Immediate migration review.
  ///
  /// In en, this message translates to:
  /// **'Fees (estimate)'**
  String get migrationMobileFastFeesRow;

  /// Error under the Immediate migration review when there is no spendable Orchard balance to migrate.
  ///
  /// In en, this message translates to:
  /// **'No spendable Orchard balance is available for Immediate migration.'**
  String get migrationMobileFastNoBalance;

  /// Placeholder value of the amount and fee rows on the Immediate migration review while the plan is being calculated.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get migrationMobileFastPlanCalculating;

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

  /// [security] Highlighted middle part of the sentence in the privacy warning card; it follows the lead part and ends the sentence.
  ///
  /// In en, this message translates to:
  /// **'easier to associate with your wallet'**
  String get migrationMobileFastPrivacyBodyHighlight;

  /// [security] First part of the sentence in the privacy warning card; it continues with the highlighted phrase. {amount} is the amount with the ZEC unit. Keep the trailing space.
  ///
  /// In en, this message translates to:
  /// **'Crosses in one visible step — your {amount} and timing are '**
  String migrationMobileFastPrivacyBodyLead(String amount);

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

  /// [security] Heading of the privacy warning card on the Immediate migration review.
  ///
  /// In en, this message translates to:
  /// **'Privacy trade-off'**
  String get migrationMobileFastPrivacyTitle;

  /// Ghost button on the Immediate migration review that recalculates the plan after a failure.
  ///
  /// In en, this message translates to:
  /// **'Retry calculation'**
  String get migrationMobileFastRetryCalculation;

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

  /// Button on the mobile migration progress screens that leaves the screen and goes to Home.
  ///
  /// In en, this message translates to:
  /// **'Go home'**
  String get migrationMobileGoHome;

  /// Badge text on the pool migration illustration at the top of the intro screen.
  ///
  /// In en, this message translates to:
  /// **'Migration'**
  String get migrationMobileHeroBadge;

  /// Label under the new pool in the migration illustration.
  ///
  /// In en, this message translates to:
  /// **'Ironwood Pool'**
  String get migrationMobileHeroIronwoodPool;

  /// Small label above Orchard Pool in the migration illustration, marking the old pool.
  ///
  /// In en, this message translates to:
  /// **'(Legacy)'**
  String get migrationMobileHeroLegacy;

  /// Label under the old pool in the migration illustration.
  ///
  /// In en, this message translates to:
  /// **'Orchard Pool'**
  String get migrationMobileHeroOrchardPool;

  /// Top bar title of the mobile screen that explains the migration steps.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get migrationMobileHowItWorksNavTitle;

  /// Title-case heading of the mobile screen that explains the steps of the Ironwood migration.
  ///
  /// In en, this message translates to:
  /// **'How Migration Works'**
  String get migrationMobileHowItWorksTitle;

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

  /// Tagline under the Ironwood wordmark on the first mobile migration screen.
  ///
  /// In en, this message translates to:
  /// **'A new shielded pool for Zcash.'**
  String get migrationMobileIntroTagline;

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

  /// [security] Title-case heading on the Keystone request screen while the QR code is still loading.
  ///
  /// In en, this message translates to:
  /// **'Confirm Migration with Keystone'**
  String get migrationMobileKeystoneConfirmTitle;

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

  /// Text under the placeholder while the Keystone request QR code is being built. Keep the space before the dots.
  ///
  /// In en, this message translates to:
  /// **'Loading QR code ...'**
  String get migrationMobileKeystoneLoadingQrText;

  /// Button on the Keystone request screen that moves on to scanning the signed result.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get migrationMobileKeystoneNextStep;

  /// Second fragment of the instruction on the Keystone request screen, shown after the QR icon.
  ///
  /// In en, this message translates to:
  /// **'on your Keystone,'**
  String get migrationMobileKeystonePromptOnDevice;

  /// First fragment of the instruction on the Keystone request screen: Tap [QR icon] on your Keystone, then scan this QR code. The icon is shown between this and the next fragment.
  ///
  /// In en, this message translates to:
  /// **'Tap'**
  String get migrationMobileKeystonePromptTap;

  /// Last fragment of the instruction on the Keystone request screen; the help button follows it.
  ///
  /// In en, this message translates to:
  /// **'then scan this QR code'**
  String get migrationMobileKeystonePromptThenScan;

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

  /// [security] Heading on the Keystone request screen once the QR code is ready; the user scans it with the device.
  ///
  /// In en, this message translates to:
  /// **'Scan with Keystone'**
  String get migrationMobileKeystoneScanTitle;

  /// [security] Screen reader label of the scanner screen for the signed migration transfer round.
  ///
  /// In en, this message translates to:
  /// **'Scan the signed migration transfer from Keystone'**
  String get migrationMobileKeystoneScanTransferSemantics;

  /// Label of the scanner control that goes back to the request QR code.
  ///
  /// In en, this message translates to:
  /// **'Show transaction QR'**
  String get migrationMobileKeystoneShowTxQr;

  /// Large step counter on the Keystone request screen of the migration signing: showing the request QR.
  ///
  /// In en, this message translates to:
  /// **'Step 1/2'**
  String get migrationMobileKeystoneStep1;

  /// Large step counter on the Keystone scan screen of the migration signing: scanning the signed result.
  ///
  /// In en, this message translates to:
  /// **'Step 2/2'**
  String get migrationMobileKeystoneStep2;

  /// Label of the row showing the amount that has not been migrated yet.
  ///
  /// In en, this message translates to:
  /// **'Left to migrate'**
  String get migrationMobileLeftToMigrate;

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

  /// Confirm button of the manage-migration dialog.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get migrationMobileManageConfirm;

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

  /// Label of the Confirm button of the manage-migration dialog while the migration is being stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopping...'**
  String get migrationMobileManageStopping;

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

  /// Error in the mobile manage-migration dialog when stopping or switching the migration failed.
  ///
  /// In en, this message translates to:
  /// **'The migration could not be updated. Please try again.'**
  String get migrationMobileManageUpdateError;

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

  /// Label above the amount of the next scheduled migration part inside the progress ring.
  ///
  /// In en, this message translates to:
  /// **'Next migration'**
  String get migrationMobileNextMigration;

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

  /// Title of the Immediate migration option card, which migrates everything in one batch.
  ///
  /// In en, this message translates to:
  /// **'Immediate'**
  String get migrationMobileOptionImmediateTitle;

  /// Body of the Private migration option card.
  ///
  /// In en, this message translates to:
  /// **'Splits transactions into multiple parts to minimize traceability but will take several hours to days.'**
  String get migrationMobileOptionPrivateBody;

  /// Title of the Private migration option card.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get migrationMobileOptionPrivateTitle;

  /// Body of the disabled Private migration option card on Android.
  ///
  /// In en, this message translates to:
  /// **'Not available on Android.'**
  String get migrationMobileOptionPrivateUnavailableAndroid;

  /// Body of the disabled Private migration option card for Ledger accounts.
  ///
  /// In en, this message translates to:
  /// **'Not available for Ledger accounts.'**
  String get migrationMobileOptionPrivateUnavailableLedger;

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

  /// Subtitle of the migration options screen explaining the two choices.
  ///
  /// In en, this message translates to:
  /// **'Choose between more privacy over time or a faster migration. You can review the details before anything moves.'**
  String get migrationMobileOptionsSubtitle;

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

  /// Subtitle of the migration options screen when part of the balance is already migrated. {amount} is the formatted remaining Orchard balance without the ZEC unit.
  ///
  /// In en, this message translates to:
  /// **'{amount} ZEC is still in Orchard. Choose between more privacy over time or a faster migration.'**
  String migrationMobileOptionsSubtitleRest(String amount);

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

  /// First line of the info card under the preparation ring. The apostrophe is curly.
  ///
  /// In en, this message translates to:
  /// **'We’re organizing your balance into common-sized parts. This makes your migration harder to link.'**
  String get migrationMobilePrepInfoOrganizing;

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

  /// Title and value text shown while the migration waits for network confirmations.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmations'**
  String get migrationMobileProgressConfirmations;

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

  /// Value of the estimated completion row while the migration progress is syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get migrationMobileProgressSyncing;

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

  /// Green badge on the recommended migration option card.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get migrationMobileRecommended;

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

  /// Button on the migration progress screen that resumes a paused migration.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get migrationMobileResume;

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

  /// Label of the action button on the migration progress screen while a retry runs.
  ///
  /// In en, this message translates to:
  /// **'Retrying...'**
  String get migrationMobileRetrying;

  /// Title-case heading of the mobile migration review screen.
  ///
  /// In en, this message translates to:
  /// **'Review Migration Plan'**
  String get migrationMobileReviewPlanTitle;

  /// Second line on the mobile migration progress screen explaining why recovery is required.
  ///
  /// In en, this message translates to:
  /// **'Two saved transactions couldn\'t be reopened.'**
  String get migrationMobileSavedTxError;

  /// Placeholder for the estimated duration or remaining rounds on the schedule screens while the chain height is not known yet.
  ///
  /// In en, this message translates to:
  /// **'Calculating'**
  String get migrationMobileScheduleCalculating;

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

  /// Label of the summary row showing the current block height.
  ///
  /// In en, this message translates to:
  /// **'Current block'**
  String get migrationMobileScheduleCurrentBlock;

  /// Status of a scheduled migration part whose block has just passed, within the grace period.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get migrationMobileScheduleDueNow;

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

  /// Ghost button on the migration schedule that opens the manage-migration dialog.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get migrationMobileScheduleManage;

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

  /// Value of the estimated completion row on the mobile migration progress screen while no schedule exists yet.
  ///
  /// In en, this message translates to:
  /// **'Schedule pending'**
  String get migrationMobileSchedulePending;

  /// Footer label on the preparation schedule screen for how many split transactions are done.
  ///
  /// In en, this message translates to:
  /// **'Preparation progress'**
  String get migrationMobileSchedulePreparationProgress;

  /// Title-case top bar title of the mobile schedule screen that lists the balance preparation (note split) rounds.
  ///
  /// In en, this message translates to:
  /// **'Preparation Schedule'**
  String get migrationMobileSchedulePreparationTitle;

  /// Message in the empty list area of the schedule screens while the schedule is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing schedule'**
  String get migrationMobileSchedulePreparing;

  /// Status of a migration part that is still being prepared and has no time estimate.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get migrationMobileSchedulePreparingState;

  /// Footer label on the preparation schedule screen for the time left until preparation is ready.
  ///
  /// In en, this message translates to:
  /// **'Ready in'**
  String get migrationMobileScheduleReadyIn;

  /// Status of a migration part that waits for the user to sign it on the schedule list.
  ///
  /// In en, this message translates to:
  /// **'Ready to sign'**
  String get migrationMobileScheduleReadyToSign;

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

  /// Status of a preparation transaction that is scheduled but not yet sent.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get migrationMobileScheduleScheduled;

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

  /// Title-case top bar title of the mobile schedule screen that lists the migration parts.
  ///
  /// In en, this message translates to:
  /// **'Migration Schedule'**
  String get migrationMobileScheduleTitle;

  /// Body of the error state of the migration schedule screen.
  ///
  /// In en, this message translates to:
  /// **'Vizor couldn\'t load the latest schedule. Your saved migration state is unchanged.'**
  String get migrationMobileScheduleUnavailableBody;

  /// Heading of the error state of the migration schedule screen.
  ///
  /// In en, this message translates to:
  /// **'Migration schedule unavailable'**
  String get migrationMobileScheduleUnavailableTitle;

  /// Status of a preparation transaction that was broadcast and waits to be included in a block.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be mined'**
  String get migrationMobileScheduleWaitingMined;

  /// Status of a migration part that waits for a signing window. {height} is a block height with thousands separators.
  ///
  /// In en, this message translates to:
  /// **'Window #{height}'**
  String migrationMobileScheduleWindow(String height);

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

  /// Third rotating loading message on the mobile private migration preparation screen.
  ///
  /// In en, this message translates to:
  /// **'Preparing your migration plan...'**
  String get migrationMobileStartMessagePlan;

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

  /// Heading shown when the Keystone signing request for the private migration is ready.
  ///
  /// In en, this message translates to:
  /// **'Ready to sign'**
  String get migrationMobileStartReadyTitle;

  /// Muted number of notes (migration parts) after the word Migration in the heading row of the progress screens.
  ///
  /// In en, this message translates to:
  /// **'{count} notes'**
  String migrationMobileStatusNotesCount(int count);

  /// Bold first words of the heading row above the migration parts; followed by the note count such as 3 notes. Keep the trailing space.
  ///
  /// In en, this message translates to:
  /// **'Migration '**
  String get migrationMobileStatusNotesLead;

  /// Title-case heading at the top of the mobile migration progress screens.
  ///
  /// In en, this message translates to:
  /// **'Ironwood Migration'**
  String get migrationMobileStatusTitle;

  /// Label of the row showing the amount already migrated after a network upgrade stopped the migration.
  ///
  /// In en, this message translates to:
  /// **'Moved to Ironwood'**
  String get migrationMobileStoppedMoved;

  /// Label of the row showing the amount still in Orchard after a network upgrade stopped the migration.
  ///
  /// In en, this message translates to:
  /// **'Still in Orchard'**
  String get migrationMobileStoppedRemaining;

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

  /// Second fragment of the bottom text on the animated loop; keep the leading space.
  ///
  /// In en, this message translates to:
  /// **' the batch of transactions'**
  String get migrationMobileWaitLoopBatch;

  /// Caption in the middle of the animated loop that explains the sign-and-wait cycle; the line breaks are intentional and the dash is an en dash.
  ///
  /// In en, this message translates to:
  /// **'Repeat several times,\nwaiting could take 2–10\nhours'**
  String get migrationMobileWaitLoopCaption;

  /// Second fragment of the top text on the animated loop; keep the leading space.
  ///
  /// In en, this message translates to:
  /// **' for the window'**
  String get migrationMobileWaitLoopForWindow;

  /// Highlighted first word of the bottom text on the animated loop; followed by the next fragment to read 'Sign the batch of transactions'.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get migrationMobileWaitLoopSign;

  /// Highlighted first word of the top text on the animated loop; followed by the next fragment to read 'Wait for the window'.
  ///
  /// In en, this message translates to:
  /// **'Wait'**
  String get migrationMobileWaitLoopWait;

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

  /// Subtitle on the desktop address types and things-to-know steps; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'Zcash has two address types.\nOne for privacy, one for transparency.'**
  String get onboardingAddressTypesSubtitle;

  /// Subtitle of the mobile address types step; two lines on purpose.
  ///
  /// In en, this message translates to:
  /// **'Zcash has two addresses types.\nOne for Privacy, one for Transparency.'**
  String get onboardingAddressTypesSubtitleMobile;

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

  /// Placeholder of the date field (month/day/year order).
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

  /// Placeholder of the iOS birthday field; shows the expected month/year order.
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

  /// Import method and screen title for connecting a Ledger device.
  ///
  /// In en, this message translates to:
  /// **'Connect Ledger'**
  String get onboardingConnectLedger;

  /// Confirm button of the desktop unknown-birthday dialog.
  ///
  /// In en, this message translates to:
  /// **'Continue Anyway'**
  String get onboardingContinueAnywayDesktop;

  /// Confirm button of the mobile unknown-birthday sheet.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get onboardingContinueAnywayMobile;

  /// Disabled primary button label while the new wallet is being created.
  ///
  /// In en, this message translates to:
  /// **'Creating wallet...'**
  String get onboardingCreatingWallet;

  /// Heading of the step where the user names the account and picks a profile picture; also the back label pointing to it.
  ///
  /// In en, this message translates to:
  /// **'Customise Account'**
  String get onboardingCustomiseAccount;

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

  /// Error on the network settings sheet when saving the custom endpoint failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the endpoint. Try again.'**
  String get onboardingNetworkSaveFailed;

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

  /// Onboarding step for naming the wallet and picking a picture.
  ///
  /// In en, this message translates to:
  /// **'Customise wallet'**
  String get onboardingStepCustomiseWallet;

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

  /// Accessibility label of the button that opens the QR scanner on the Pay recipient step.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get payRecipientScanQr;

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

  /// Label of the paying amount row on the Pay review step; also the disabled button label while the payment starts.
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

  /// Button label while the Pay add-contact card is saving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get paySaving;

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

  /// Button or label that opens the profile picture picker.
  ///
  /// In en, this message translates to:
  /// **'Change profile picture'**
  String get profilePictureChange;

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

  /// Inline error on the Receive screen: a summary line, then a technical details line. {details} is raw error text and is not translated.
  ///
  /// In en, this message translates to:
  /// **'{message}\nDetails: {details}'**
  String receiveErrorWithDetails(String message, String details);

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

  /// Button and accessibility label on the mobile payment request result that copies the request link.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get receiveRequestCopyLink;

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

  /// Title of the Receive screen. {ticker} is the currency ticker such as ZEC.
  ///
  /// In en, this message translates to:
  /// **'Receive {ticker}'**
  String receiveTitle(String ticker);

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

  /// Accessibility label of the control that switches the amount input to {currency}, such as ZEC or USD.
  ///
  /// In en, this message translates to:
  /// **'Enter amount in {currency}'**
  String sendEnterAmountInCurrency(String currency);

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

  /// [security] Title of the desktop Keystone signing modal and label of the review button for a Keystone account.
  ///
  /// In en, this message translates to:
  /// **'Confirm with Keystone'**
  String get sendKeystoneConfirmTitle;

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

  /// Disabled primary button label in the desktop Keystone modal while proofs are being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get sendKeystonePreparing;

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

  /// Label shown over the scanner while the signature QR code is being decoded.
  ///
  /// In en, this message translates to:
  /// **'Reading signature...'**
  String get sendKeystoneScanReading;

  /// [security] Subtitle of the desktop Keystone signing modal asking the user to scan the QR code with the device.
  ///
  /// In en, this message translates to:
  /// **'Scan with your Keystone'**
  String get sendKeystoneScanSubtitle;

  /// Caption under the camera view asking the user to scan the signature QR code shown on the Keystone to finish sending.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to finish sending'**
  String get sendKeystoneScanToFinish;

  /// Hint when the scanned QR code is of the wrong type; asks to open the signed transaction QR code on the Keystone device.
  ///
  /// In en, this message translates to:
  /// **'Open the signed transaction QR on Keystone, then scan again.'**
  String get sendKeystoneScanUnexpectedTransaction;

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

  /// Title of the failure panel when the Ledger device needs the user to act (unlock, open the app, reconnect).
  ///
  /// In en, this message translates to:
  /// **'Ledger needs attention'**
  String get sendLedgerNeedsAttentionTitle;

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

  /// Generic Ledger failure message asking the user to check the device and retry.
  ///
  /// In en, this message translates to:
  /// **'Ledger signing could not be completed. Check your device and try again.'**
  String get sendLedgerSigningIncomplete;

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

  /// Label of the primary button on the payment request card that reruns the check.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get sendPaymentRequestCheckAgain;

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

  /// Label of the primary button on the payment request card for a request without an amount.
  ///
  /// In en, this message translates to:
  /// **'Enter amount'**
  String get sendPaymentRequestEnterAmount;

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

  /// Troubleshooting tip suggesting Continuity Camera on a Mac.
  ///
  /// In en, this message translates to:
  /// **'On a Mac, you can use Continuity Camera to scan with your iPhone instead.'**
  String get sendRequestScanTipContinuity;

  /// Troubleshooting tip when the QR code cannot be scanned.
  ///
  /// In en, this message translates to:
  /// **'Move the QR code a few inches further from the camera so it can focus.'**
  String get sendRequestScanTipDistance;

  /// Troubleshooting tip when the QR code cannot be scanned.
  ///
  /// In en, this message translates to:
  /// **'Make sure the room is well-lit and the QR code isn\'t reflecting glare.'**
  String get sendRequestScanTipLight;

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

  /// Label of the review button while the transaction is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get sendReviewPreparing;

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

  /// Primary button label on the mobile swap screen that opens the review.
  ///
  /// In en, this message translates to:
  /// **'Continue to review'**
  String get swapActionContinueToReview;

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

  /// [security] Error in the swap Keystone signing overlay when the scanned signature QR belongs to another request.
  ///
  /// In en, this message translates to:
  /// **'This QR code does not match the current Keystone request.'**
  String get swapKeystoneQrMismatch;

  /// [security] Caption under the signature scanner on the mobile swap Keystone screen.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your Keystone to finish the ZEC deposit'**
  String get swapKeystoneScanCaption;

  /// [security] Subtitle of the swap Keystone signing overlay above the QR code.
  ///
  /// In en, this message translates to:
  /// **'Scan to sign'**
  String get swapKeystoneScanToSign;

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

  /// [security] Status chip in the swap Ledger modal while another operation finishes the transaction.
  ///
  /// In en, this message translates to:
  /// **'Please wait'**
  String get swapLedgerStatusWait;

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

  /// Accessibility label of the close button on the NEAR Intents service notice.
  ///
  /// In en, this message translates to:
  /// **'Close service notice'**
  String get swapNoticeCloseLabel;

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

  /// Disabled primary button label on the pay review while the payment is being started.
  ///
  /// In en, this message translates to:
  /// **'Paying'**
  String get swapReviewStartingPaying;

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

  /// Heading on the swap timeout screen shown when the quote deposit window has expired.
  ///
  /// In en, this message translates to:
  /// **'Time’s up'**
  String get swapTimeoutTitle;

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
