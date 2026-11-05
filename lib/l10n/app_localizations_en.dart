// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accountNameLabel => 'Account name';

  @override
  String get accountsActionsLabel => 'Account actions';

  @override
  String get accountsAddressLoadFailed => 'Couldn\'t load the account address';

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
  String get accountsRemovePasswordHint => 'Enter your password';

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
  String get accountsResetting => 'Resetting...';

  @override
  String get accountsSaveEdits => 'Save edits';

  @override
  String get accountsSaveFailed => 'Couldn\'t save the account changes';

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
  String get activityAddressShielded => 'Shielded address';

  @override
  String get activityAddressTransparent => 'Transparent address';

  @override
  String get activityAddressUnified => 'Unified address';

  @override
  String get activityAddressZcash => 'Zcash address';

  @override
  String get activityBalanceFromOrchard => 'From Orchard balance';

  @override
  String get activityBalanceFromTransparent => 'From transparent balance';

  @override
  String get activityBalanceIronwood => 'Ironwood balance';

  @override
  String get activityBalanceOrchard => 'Orchard balance';

  @override
  String get activityBalanceShielded => 'Shielded balance';

  @override
  String get activityDetailsLoadFailed => 'Failed — try again';

  @override
  String get activityDetailsLoadPublicly => 'Load publicly';

  @override
  String get activityDetailsLoadPubliclyLabel => 'Full details';

  @override
  String get activityDetailsLoading => 'Loading…';

  @override
  String get activityDetailsNotCovered => 'Not available in private mode';

  @override
  String get activityDetailsOmittedLabel => 'Not shown';

  @override
  String get activityDetailsOutputsLabel => 'Transaction outputs';

  @override
  String get activityDetailsOutputsUnattributed => 'Recipient not confirmed';

  @override
  String get activityDetailsUnavailable =>
      'Details unavailable — will update when the service is reachable';

  @override
  String get activityDetailsUnknownRecipient => 'Unknown recipient';

  @override
  String get activityFeedEmpty => 'No activity yet';

  @override
  String get activityFeedLoading => 'Loading activity';

  @override
  String get activityFeedRetry => 'Retry loading activity';

  @override
  String activityGiftBatchBreakdown(
    String cards,
    String fees,
    String feeLabel,
    String fee,
  ) {
    return 'Cards $cards ZEC · Redeem fees $fees ZEC · $feeLabel $fee';
  }

  @override
  String get activityGiftCreated => 'Created a gift card';

  @override
  String activityGiftCreatedMany(int count) {
    return 'Created $count gift cards';
  }

  @override
  String get activityGiftCreating => 'Creating a card';

  @override
  String activityGiftCreatingMany(int count) {
    return 'Creating $count cards';
  }

  @override
  String get activityGiftCreationFailed => 'Gift card creation failed';

  @override
  String get activityGiftGroupFailed => 'Gift card group failed';

  @override
  String get activityGiftRedeemed => 'Redeemed a gift card';

  @override
  String get activityGiftRedeeming => 'Redeeming a card';

  @override
  String get activityGiftRedemptionFailed => 'Gift card redemption failed';

  @override
  String get activityGiftStatusCreated => 'Created';

  @override
  String get activityGiftStatusCreating => 'Creating…';

  @override
  String get activityGiftStatusRedeemed => 'Redeemed';

  @override
  String get activityGiftStatusRedeeming => 'Redeeming…';

  @override
  String get activityGiftTotalPlanned => 'Planned total';

  @override
  String get activityGiftTotalSpent => 'Total spent';

  @override
  String get activityGiftTotalSubmitted => 'Submitted total';

  @override
  String get activityLoadFailedDesktop => 'Activity could not be loaded.';

  @override
  String get activityLoadFailedMobile =>
      'Couldn\'t load activity. Try again in a moment.';

  @override
  String get activityOmissionLaterOutputs => 'outputs after the second';

  @override
  String activityOmissionMoreOutputs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more outputs',
      one: '1 more output',
    );
    return '$_temp0';
  }

  @override
  String get activityOmissionOtherSenders => 'other sending addresses';

  @override
  String get activityOmissionOutputAddress => 'an output address';

  @override
  String get activityOmissionSender => 'the sending address';

  @override
  String get activityOmissionSharedFunding => 'inputs from other wallets';

  @override
  String get activityOmissionShieldedFunding =>
      'the shielded part of the funding';

  @override
  String get activityPayFailed => 'Payment failed';

  @override
  String get activityPayFromShielded => 'from shielded ZEC';

  @override
  String activityPayFromShieldedOnChain(String network) {
    return 'from shielded ZEC · $network';
  }

  @override
  String get activityPayInProgress => 'Payment in progress';

  @override
  String get activityPayIncomplete => 'Payment incomplete';

  @override
  String get activityPayPaid => 'Paid';

  @override
  String get activityPayPaying => 'Paying ...';

  @override
  String get activityPayRefunded => 'Payment refunded';

  @override
  String get activityPoolMixed => 'Mixed';

  @override
  String get activityPublicLookupBody =>
      'Vizor will ask the server for this one transaction to show what private lookups leave out.';

  @override
  String get activityPublicLookupTitle => 'Load details publicly?';

  @override
  String get activityPublicLookupWarning =>
      'The server learns that this wallet is interested in this transaction, and without Tor, your IP address.';

  @override
  String get activityReceiptAmount => 'Amount';

  @override
  String get activityReceiptAmountMigrated => 'Amount migrated';

  @override
  String get activityReceiptCardFee => 'Card fee';

  @override
  String get activityReceiptCards => 'Cards';

  @override
  String get activityReceiptDetails => 'Details';

  @override
  String get activityReceiptDetailsIncomplete => 'Details incomplete';

  @override
  String get activityReceiptDetailsIncompleteHelp =>
      'Some details of this transaction, such as its recipients, memos, or fee, are not known yet. The amount shown may change.';

  @override
  String get activityReceiptEstimatedNetworkFee => 'Estimated network fee';

  @override
  String get activityReceiptFrom => 'From';

  @override
  String get activityReceiptIncomplete => 'Incomplete';

  @override
  String get activityReceiptLoadFailed => 'Transaction could not be loaded.';

  @override
  String get activityReceiptLoading => 'Loading transaction…';

  @override
  String get activityReceiptMessage => 'Message';

  @override
  String get activityReceiptNetChange => 'Net change';

  @override
  String get activityReceiptNetworkFee => 'Network fee';

  @override
  String get activityReceiptNoAccount => 'No active account.';

  @override
  String get activityReceiptOutput => 'Output';

  @override
  String get activityReceiptRefreshFailed =>
      'Latest transaction status could not be refreshed.';

  @override
  String get activityReceiptShowFullAddress => 'Show full address';

  @override
  String get activityReceiptStatus => 'Status';

  @override
  String get activityReceiptTimestamp => 'Timestamp';

  @override
  String get activityReceiptTo => 'To';

  @override
  String get activityReceiptTxFee => 'Tx fee';

  @override
  String get activityReceiptTxId => 'Tx ID';

  @override
  String get activityReceiptUnattributedFeeHelp =>
      'Total fee for this transaction. Your account\'s share of this fee is unknown.';

  @override
  String get activityReceiptUnknownFee => 'Unknown';

  @override
  String get activityRowCheckingStatus => 'Checking status';

  @override
  String activityRowToday(String time) {
    return 'Today, $time';
  }

  @override
  String get activityRowWaitingForConnection => 'Waiting for connection';

  @override
  String activityRowYesterday(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get activityScreenTitle => 'Activity';

  @override
  String get activitySectionEarlier => 'Earlier';

  @override
  String get activitySectionThisWeek => 'This week';

  @override
  String get activitySenderShielded => 'Shielded sender';

  @override
  String get activitySenderUnknown => 'Unknown sender';

  @override
  String get activityStatusCompleted => 'Completed';

  @override
  String get activityStatusFailed => 'Failed';

  @override
  String get activityStatusFailedFundsReturned => 'Failed, funds returned';

  @override
  String get activityStatusInProgress => 'In progress';

  @override
  String get activityStatusIncompleteDeposit => 'Incomplete deposit';

  @override
  String get activityStatusRefunded => 'Refunded';

  @override
  String activitySwapAssetOnChain(String symbol, String chain) {
    return '$symbol on $chain';
  }

  @override
  String activitySwapDepositedAsset(String symbol) {
    return 'Deposited $symbol';
  }

  @override
  String get activitySwapFailed => 'Swap failed';

  @override
  String get activitySwapJustNow => 'just now';

  @override
  String activitySwapMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String activitySwapReceivedAsset(String symbol) {
    return 'Received $symbol';
  }

  @override
  String get activitySwapRefunded => 'Swap refunded';

  @override
  String get activitySwapReviewQuote => 'Review quote';

  @override
  String activitySwapStep(int current, int total) {
    return '$current/$total In progress';
  }

  @override
  String get activitySwapSwapped => 'Swapped';

  @override
  String get activitySwapSwapping => 'Swapping...';

  @override
  String get activitySwapTimeout => 'Timeout';

  @override
  String get activitySwapTitle => 'Swap';

  @override
  String get activityTitleMigrated => 'Migrated to Ironwood';

  @override
  String get activityTitleMigrating => 'Migrating to Ironwood...';

  @override
  String get activityTitleMigratingVerb => 'Migrating to Ironwood';

  @override
  String get activityTitleMigrationFailed => 'Migration failed';

  @override
  String get activityTitleReceiveFailed => 'Receive failed';

  @override
  String get activityTitleReceiveInProgress => 'Receive in progress...';

  @override
  String get activityTitleReceived => 'Received';

  @override
  String get activityTitleReceivedSuccessfully => 'Received successfully';

  @override
  String get activityTitleReceiving => 'Receiving...';

  @override
  String get activityTitleReceivingVerb => 'Receiving';

  @override
  String get activityTitleSendFailed => 'Send failed';

  @override
  String get activityTitleSending => 'Sending...';

  @override
  String get activityTitleSendingVerb => 'Sending';

  @override
  String get activityTitleSent => 'Sent';

  @override
  String get activityTitleSentSuccessfully => 'Sent successfully';

  @override
  String get activityTitleShielded => 'Shielded';

  @override
  String get activityTitleShieldedSuccessfully => 'Shielded successfully';

  @override
  String get activityTitleShielding => 'Shielding...';

  @override
  String get activityTitleShieldingFailed => 'Shielding failed';

  @override
  String get activityTitleShieldingInProgress => 'Shielding in progress...';

  @override
  String get activityTitleShieldingVerb => 'Shielding';

  @override
  String get activityTitleTransaction => 'Transaction';

  @override
  String get activityToastHashCopiedDesktop => 'Transaction hash copied';

  @override
  String get activityToastHashCopiedMobile => 'Transaction Hash Copied';

  @override
  String get addressBookAddContact => 'Add contact';

  @override
  String get addressBookAddressHintDesktop => 'Add address';

  @override
  String get addressBookAddressHintMobile => 'Add an address';

  @override
  String get addressBookAddressLabel => 'Address';

  @override
  String get addressBookAddressMissing => 'Add an address';

  @override
  String get addressBookChainAndAddress => 'Chain & address';

  @override
  String get addressBookChangePicture => 'Change contact picture';

  @override
  String get addressBookClearAddress => 'Clear address';

  @override
  String get addressBookClearLabel => 'Clear contact label';

  @override
  String get addressBookClearName => 'Clear name';

  @override
  String get addressBookClearSearch => 'Clear search';

  @override
  String addressBookContactActions(String label) {
    return '$label actions';
  }

  @override
  String get addressBookContactsTitle => 'Contacts';

  @override
  String get addressBookEditContact => 'Edit contact';

  @override
  String get addressBookEmptyBody => 'Add your first contact to get started.';

  @override
  String get addressBookEmptyTitle => 'No contacts yet';

  @override
  String get addressBookInvalidBitcoin => 'Invalid Bitcoin address';

  @override
  String get addressBookInvalidEvm => 'Invalid EVM address';

  @override
  String get addressBookInvalidNear => 'Invalid NEAR address';

  @override
  String get addressBookInvalidSolana => 'Invalid Solana address';

  @override
  String get addressBookInvalidZcash => 'Invalid Zcash address';

  @override
  String get addressBookLabelFieldLabel => 'Address label';

  @override
  String get addressBookLabelHint => 'Add label 1-20 characters';

  @override
  String get addressBookLabelLength => 'Use 1-20 characters';

  @override
  String get addressBookLabelMissing => 'Add a label';

  @override
  String get addressBookLoadFailed =>
      'Couldn\'t load your contacts. Try again, or contact support if this keeps happening.';

  @override
  String get addressBookNameHint => 'Add a name';

  @override
  String get addressBookNameLabel => 'Name';

  @override
  String get addressBookNearSuffixWarning =>
      'NEAR accounts usually end in .near — double-check this address';

  @override
  String get addressBookNetworkLabel => 'Network';

  @override
  String get addressBookNoNetworks => 'No networks found';

  @override
  String get addressBookNoResultsBody => 'Try to modify your search';

  @override
  String get addressBookNoResultsTitle => 'No contacts were found';

  @override
  String get addressBookPickerClose => 'Close contacts';

  @override
  String get addressBookPickerEmptyTitle => 'No contacts found';

  @override
  String get addressBookPickerLoadFailed =>
      'Couldn\'t load contacts. Try again.';

  @override
  String get addressBookPickerSearchHint => 'Search contacts';

  @override
  String get addressBookRemove => 'Remove';

  @override
  String addressBookRemoveBody(String label) {
    return '$label will be removed from your contacts.';
  }

  @override
  String get addressBookRemoveBodyUnknown => 'This contact will be removed.';

  @override
  String addressBookRemoveConfirmBody(String label) {
    return '\"$label\" will be removed from your contacts. This does not affect any past transactions.';
  }

  @override
  String get addressBookRemoveConfirmTitle => 'Remove contact?';

  @override
  String get addressBookRemoveContact => 'Remove contact';

  @override
  String get addressBookRemoveFailed => 'Couldn\'t remove contact. Try again.';

  @override
  String get addressBookRemoveFailedMobile =>
      'Couldn\'t remove the contact. Please try again.';

  @override
  String get addressBookSaveContact => 'Save contact';

  @override
  String get addressBookSaveFailed => 'Couldn\'t save contact. Try again.';

  @override
  String get addressBookSaveFailedMobile =>
      'Couldn\'t save the contact. Please try again.';

  @override
  String get addressBookScanAddressQr => 'Scan address QR';

  @override
  String addressBookScanQrTitle(String network) {
    return 'Scan $network QR code';
  }

  @override
  String get addressBookSearch => 'Search';

  @override
  String get addressBookSearchHint => 'Search for label or network';

  @override
  String get addressBookSearchNetwork => 'Search network';

  @override
  String get addressBookSelectNetwork => 'Select network';

  @override
  String get addressBookSelectPicture => 'Select contact picture';

  @override
  String get addressBookSelectedContact => 'Selected contact';

  @override
  String get addressBookSendZec => 'Send ZEC';

  @override
  String get addressScanAddressCameraNeeded =>
      'Address QR scanning needs a camera on this device.';

  @override
  String addressScanCameraDefaultSuffix(String name) {
    return '$name (Default)';
  }

  @override
  String get addressScanCameraNeeded =>
      'QR scanning needs a camera on this device.';

  @override
  String get addressScanCameraOff =>
      'Camera access is off. Allow it in Settings to scan addresses.';

  @override
  String get addressScanCameraRequired =>
      'Address QR scanning requires a camera on this device.';

  @override
  String get addressScanCameraRestricted =>
      'Screen Time or device management is blocking the camera on this device.';

  @override
  String get addressScanCameraUnavailable => 'Camera unavailable';

  @override
  String get addressScanCameraUnavailableNow =>
      'The camera is unavailable right now.';

  @override
  String get addressScanCloseScanner => 'Close scanner';

  @override
  String get addressScanDefaultCamera => 'Default camera';

  @override
  String get addressScanDeniedTitle => 'You\'ve denied Camera access';

  @override
  String get addressScanDeniedTitleMobile => 'You\'ve denied camera access';

  @override
  String get addressScanEnableWindowsAccess => 'Enable Windows camera access';

  @override
  String get addressScanGrantAccess => 'Grant access to your camera';

  @override
  String get addressScanLoading => 'Loading';

  @override
  String get addressScanLoadingCamera => 'Loading camera...';

  @override
  String get addressScanLoadingEllipsis => 'Loading...';

  @override
  String get addressScanNoAddress => 'QR code did not include an address.';

  @override
  String get addressScanNoCamera => 'No camera found';

  @override
  String get addressScanNoCameraOpened =>
      'No camera could be opened. Check that a camera is connected and not in use by another app.';

  @override
  String get addressScanOpenSettings => 'Open settings';

  @override
  String get addressScanRequestAgain => 'Request again';

  @override
  String get addressScanRequestAgainHint =>
      'Request again, or enable manually\nin the System settings.';

  @override
  String get addressScanRestrictedBody =>
      'Screen Time or device management\nis blocking the camera.';

  @override
  String get addressScanRestrictedTitle => 'Camera access is restricted';

  @override
  String get addressScanTitle => 'Scan the address QR code';

  @override
  String get addressScanToggleFlashlight => 'Toggle flashlight';

  @override
  String get addressScanWindowsAccessHint =>
      'Turn on Camera access and Let desktop apps access your camera in Windows Settings.';

  @override
  String get addressScanZcashPrompt => 'Scan a Zcash QR code to continue';

  @override
  String get appBackAmount => 'Amount';

  @override
  String get appBackContacts => 'Contacts';

  @override
  String get appBackDonation => 'Donation';

  @override
  String get appBackHardwareWallets => 'Hardware wallets';

  @override
  String get appBackImportMethods => 'Import methods';

  @override
  String get appBackReceive => 'Receive';

  @override
  String get appBackResults => 'Results';

  @override
  String get appBackReview => 'Review';

  @override
  String get appBackSend => 'Send';

  @override
  String get appBackStatus => 'Status';

  @override
  String get appBackSubmitted => 'Submitted';

  @override
  String get appBackTransaction => 'Transaction';

  @override
  String get appBackVotingRound => 'Voting round';

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
  String get appOpenFailedTitle => 'Unable to open Vizor';

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
  String get appUpdateFailedTitle => 'Update failed';

  @override
  String get appUpdateLater => 'Later';

  @override
  String get appUpdateReadyMessage => 'Restart when you are ready.';

  @override
  String get appUpdateReadyTitle => 'Update ready';

  @override
  String get appUpdateRestarting => 'Restarting';

  @override
  String get appUpdateRestartingTitle => 'Restarting Vizor';

  @override
  String get bip39PassphraseTitle => 'BIP39 Passphrase';

  @override
  String bip39PassphraseValue(String passphrase) {
    return 'BIP39 Passphrase: $passphrase';
  }

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
  String get commonAddAccount => 'Add account';

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
  String get commonCannotBeUndone => 'This cannot be undone.';

  @override
  String get commonChecking => 'Checking...';

  @override
  String get commonClearText => 'Clear text';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCoinholderVoting => 'Coinholder voting';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopyAddress => 'Copy address';

  @override
  String get commonDismissNotification => 'Dismiss notification';

  @override
  String get commonFeatureInProgress => 'This feature is still in progress.';

  @override
  String get commonGoBack => 'Go back';

  @override
  String get commonImporting => 'Importing...';

  @override
  String get commonInformation => 'Information';

  @override
  String get commonKeepQrSteady => 'Keep the QR code steady and fully visible.';

  @override
  String get commonKeepScreenAwake => 'Keep screen awake';

  @override
  String get commonNotAvailableYet => 'Not available yet';

  @override
  String get commonOk => 'OK';

  @override
  String get commonQuit => 'Quit';

  @override
  String get commonResetVizor => 'Reset Vizor';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonScanQrCode => 'Scan QR Code';

  @override
  String get commonSelectAccount => 'Select account';

  @override
  String get commonSensitiveContentHidden => 'Sensitive content hidden';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonUnlockVizor => 'Unlock Vizor';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonUpdating => 'Updating...';

  @override
  String get commonWelcomeBack => 'Welcome Back';

  @override
  String endpointCurrent(String endpoint) {
    return 'Current: $endpoint';
  }

  @override
  String get endpointCustom => 'Custom endpoint';

  @override
  String get endpointUpdate => 'Update endpoint';

  @override
  String get endpointUpdated => 'Endpoint updated';

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
  String get homeShieldErrorBroadcastFailed =>
      'Couldn\'t broadcast your shielding transaction. Try again.';

  @override
  String get homeShieldErrorCouldNotShield =>
      'Couldn\'t shield your balance. Try again.';

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
  String get homeShieldErrorSeedUnavailable =>
      'Secret Passphrase isn\'t available for this account.';

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
  String get homeShieldErrorWaitForSync =>
      'Wait for sync to finish, then shield.';

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
  String get homeShieldQueuedForRetry =>
      'Shielding queued for retry. Check Activity.';

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
  String get homeShieldWaitingForPrivateRecovery =>
      'Private recovery is catching up with the latest block. Try again in a moment; your Keystone signature is kept.';

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
  String homeTransparentLastKnown(String amount) {
    return '$amount (last known)';
  }

  @override
  String homeTransparentLastKnownStopped(String amount) {
    return '$amount (last known, recovery stopped)';
  }

  @override
  String get homeTransparentRecoveryStopped => 'Recovery stopped';

  @override
  String get homeTransparentStopLegacyDiscrepancy =>
      'Earlier public records don\'t match private recovery. Turning off Private queries discards privately recovered records and looks up transparent funds publicly.';

  @override
  String get homeTransparentStopOptOutUnfinished =>
      'Turning off Private queries didn\'t finish. Turn it off again in Settings to look up transparent funds publicly.';

  @override
  String get homeTransparentStopQuarantined =>
      'Private recovery found conflicting records for this account. Turning off Private queries discards privately recovered records and looks up transparent funds publicly.';

  @override
  String get homeTransparentStopStalled =>
      'Private recovery can\'t make progress for this account. Vizor will try again later.';

  @override
  String get homeTransparentStopWithdrawn =>
      'The private recovery service withdrew data for this account. Vizor will try again later.';

  @override
  String get homeTransparentUnavailable => 'Unavailable';

  @override
  String get homeVotingSemantics => 'Open coinholder voting';

  @override
  String get homeVotingSubtitle => 'Help to shape the network';

  @override
  String get keyringLockedBody =>
      'Vizor cannot access your system keyring. Unlock the keyring, then choose Retry. A system prompt may ask for your keyring password.';

  @override
  String get keyringNoResponse => 'The keyring did not respond. Try again.';

  @override
  String get keyringOpeningTitle => 'Opening Vizor';

  @override
  String get keyringPromptBody =>
      'Complete any system keyring prompt to continue in Vizor.';

  @override
  String get keyringRestartHint => 'Quit and restart Vizor to try again.';

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
  String get keystoneBirthdayInvalidHeight =>
      'That doesn\'t look like a valid block height.';

  @override
  String get keystoneBirthdaySubtitle =>
      'It helps us import your wallet faster.';

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
  String get keystoneCameraUnavailableBody =>
      'Keystone import uses camera QR scanning only.\nConnect a camera and try again.';

  @override
  String get keystoneCameraUnavailableTitle => 'Camera unavailable';

  @override
  String get keystoneConfirmSelection => 'Confirm selection';

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
  String get ledgerStepApproveViewingKey => 'Approve viewing key';

  @override
  String ledgerStepOpenApp(String appName) {
    return 'Open $appName';
  }

  @override
  String get ledgerStepOpenZcash => 'Open Zcash';

  @override
  String get ledgerStoppingSearch => 'Stopping search';

  @override
  String get ledgerSupportedDevices => 'Supported devices';

  @override
  String get ledgerTransportBluetooth => 'Bluetooth';

  @override
  String get ledgerTransportUsb => 'USB';

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
  String lockNavSyncing(int percent) {
    return '$percent% Syncing...';
  }

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
  String get networkSettingsTitle => 'Network settings';

  @override
  String get onboardingAdd => 'Add';

  @override
  String get onboardingAddBip39PassphraseOptional =>
      'Add BIP39 Passphrase (Optional)';

  @override
  String get onboardingAddBip39PassphraseSemantics => 'Add BIP39 passphrase';

  @override
  String get onboardingAddressShieldedBodyMobile =>
      'Address starts with u1 (or zs for legacy).\nOnly you can see your account balance and transaction history.';

  @override
  String onboardingAddressShieldedDescription(
    String unifiedPrefix,
    String legacyPrefix,
  ) {
    return 'Address starts with $unifiedPrefix (or $legacyPrefix for legacy). Only you can see your account balance and transaction history.';
  }

  @override
  String get onboardingAddressShieldedLabel => 'Shielded address';

  @override
  String get onboardingAddressShieldedTitleMobile => 'Shielded Address';

  @override
  String get onboardingAddressTransparentDescription =>
      'Address starts with t, similar to Bitcoin, your address\' balance and transaction history are publicly visible.';

  @override
  String get onboardingAddressTransparentLabel => 'Transparent address';

  @override
  String get onboardingAddressTransparentTitleMobile => 'Transparent Address';

  @override
  String get onboardingAddressTypesSubtitle =>
      'Zcash has two address types.\nOne for privacy, one for transparency.';

  @override
  String get onboardingAddressTypesSubtitleMobile =>
      'Zcash has two addresses types.\nOne for Privacy, one for Transparency.';

  @override
  String get onboardingAddressTypesTitle => 'Zcash Address Types';

  @override
  String onboardingBiometricEnableFailed(String method) {
    return 'Couldn\'t enable $method. You can try again in settings.';
  }

  @override
  String onboardingBiometricSetUpFirst(String method) {
    return 'Set up $method in your device settings first.';
  }

  @override
  String get onboardingBiometricSubtitle =>
      'This is an easy and fast way to sign in.\nYou can switch back to passcode anytime.';

  @override
  String onboardingBiometricTitle(String method) {
    return 'Unlock your wallet\nwith $method';
  }

  @override
  String get onboardingBip39PassphraseClear => 'Clear BIP39 passphrase';

  @override
  String get onboardingBip39PassphraseExplanation =>
      'Add an optional passphrase (“25th word”) to create/import a separate wallet from the same recovery phrase.';

  @override
  String get onboardingBip39PassphraseFieldLabel => 'BIP39 passphrase';

  @override
  String get onboardingBip39PassphraseHint => '1–100 characters';

  @override
  String get onboardingBip39PassphraseTitleOptional =>
      'BIP39 Passphrase (Optional)';

  @override
  String get onboardingBirthdayCantRemember => 'I can’t remember';

  @override
  String get onboardingBirthdayDateHint => 'mm/dd/yyyy';

  @override
  String get onboardingBirthdayDontRemember => 'I don’t remember';

  @override
  String get onboardingBirthdayEnterBlockHeight => 'Enter the block height';

  @override
  String get onboardingBirthdayEnterDate => 'Enter the date';

  @override
  String get onboardingBirthdayEnterMonth => 'Enter the month';

  @override
  String get onboardingBirthdayEstimateFailed =>
      'Could not estimate the wallet birthday height.';

  @override
  String onboardingBirthdayHeightAtLeast(String height) {
    return 'At least $height.';
  }

  @override
  String onboardingBirthdayHeightBetween(String min, String max) {
    return 'Between $min and $max.';
  }

  @override
  String get onboardingBirthdayInvalidHeight =>
      'Doesn\'t seem like a legit block height';

  @override
  String get onboardingBirthdayMetadataFailed =>
      'Could not load wallet birthday metadata.';

  @override
  String get onboardingBirthdayMobileEstimateFailed =>
      'Couldn\'t estimate a height for that date. Enter a block height instead.';

  @override
  String get onboardingBirthdayMonthHint => 'mm/yyyy';

  @override
  String get onboardingBirthdayPickDate => 'Pick a date';

  @override
  String get onboardingBirthdayPickMonth => 'Pick a month';

  @override
  String get onboardingBirthdaySelectDate => 'Select date';

  @override
  String get onboardingBirthdaySelectMonth => 'Select month';

  @override
  String get onboardingBirthdayStatusEstimating => 'Estimating height...';

  @override
  String get onboardingBirthdayStatusImporting => 'Importing wallet...';

  @override
  String get onboardingBirthdayStatusPausingSync => 'Pausing sync...';

  @override
  String get onboardingBirthdaySubtitleMobile =>
      'An estimate is enough — sync starts\nfrom there.';

  @override
  String get onboardingBirthdayTitle =>
      'Around when did you create your wallet?';

  @override
  String get onboardingBlockHeight => 'Block height';

  @override
  String get onboardingCheckingAccounts => 'Checking accounts...';

  @override
  String get onboardingClear => 'Clear';

  @override
  String get onboardingConnectHardwareSubtitleDesktop =>
      'Select your hardware wallet.';

  @override
  String get onboardingConnectHardwareSubtitleMobile =>
      'Select your hardware device.';

  @override
  String get onboardingConnectHardwareTitle => 'Connect\nHardware Wallet';

  @override
  String get onboardingConnectHardwareWallet => 'Connect hardware wallet';

  @override
  String get onboardingConnectKeystone => 'Connect Keystone';

  @override
  String get onboardingConnectLedger => 'Connect Ledger';

  @override
  String get onboardingContinueAnywayDesktop => 'Continue Anyway';

  @override
  String get onboardingContinueAnywayMobile => 'Continue anyway';

  @override
  String get onboardingCreatingWallet => 'Creating wallet...';

  @override
  String get onboardingCustomiseAccount => 'Customise Account';

  @override
  String get onboardingCustomiseAccountSubtitle =>
      'Add personality to your account by setting an account name and choosing a profile picture.';

  @override
  String get onboardingDiscoverySubtitle =>
      'Choose the additional accounts to import.';

  @override
  String get onboardingDiscoveryTitle => 'Additional accounts found';

  @override
  String get onboardingEdit => 'Edit';

  @override
  String get onboardingEditBip39Passphrase => 'Edit BIP39 passphrase';

  @override
  String get onboardingEnterPassword => 'Enter password';

  @override
  String get onboardingEstimating => 'Estimating...';

  @override
  String get onboardingFinishSetup => 'Finish setup';

  @override
  String get onboardingForgotPasscodeAreYouSure => 'Are you sure?';

  @override
  String get onboardingForgotPasscodeBody =>
      'If you can\'t remember your passcode, the only way to recover your account is to completely reset the Vizor app, which means deleting all accounts and requiring you to import accounts again. Unshared gift card links will be permanently lost.';

  @override
  String get onboardingForgotPasscodeCantBeUndone => 'This can\'t be undone.\n';

  @override
  String get onboardingForgotPasscodeContinueToReset =>
      'Continue to reset Vizor';

  @override
  String get onboardingForgotPasscodeProceed =>
      'Proceed on your responsibility.';

  @override
  String get onboardingForgotPasscodeTitle => 'Forgot Passcode?';

  @override
  String get onboardingForgotPasscodeUnbackedWarning =>
      'If you haven’t backed up an account’s secret passphrase, you can’t recover its funds after resetting Vizor.';

  @override
  String get onboardingForgotPassword => 'Forgot password?';

  @override
  String get onboardingGiftEducationClosing =>
      'Your wallet is ready. Learn how Zcash protects your privacy and which address to use.';

  @override
  String get onboardingGiftEducationSaveFailed =>
      'Unable to save your progress. Try again.';

  @override
  String get onboardingGoBackDesktop => 'Go Back';

  @override
  String get onboardingHardwareKeystoneOnly => 'Keystone wallet';

  @override
  String get onboardingHardwareLedgerOrKeystone => 'Ledger or Keystone wallet';

  @override
  String get onboardingIKnowHowToUseZcash => 'I know how to use Zcash';

  @override
  String get onboardingImport => 'Import';

  @override
  String get onboardingImportAcceptWordCounts =>
      'Accept 12, 15, 18, 21, or 24 words.';

  @override
  String get onboardingImportCheckFailedError =>
      'Couldn\'t check secret passphrase';

  @override
  String get onboardingImportClipboardEmpty => 'Clipboard is empty';

  @override
  String get onboardingImportClipboardReadError => 'Can\'t read the clipboard';

  @override
  String get onboardingImportEnterManuallySemantics =>
      'Enter secret passphrase manually';

  @override
  String get onboardingImportFromKeystone => 'Import from Keystone wallet';

  @override
  String get onboardingImportFromLedger => 'Import from Ledger wallet';

  @override
  String get onboardingImportInvalidPhraseError => 'Invalid secret passphrase';

  @override
  String get onboardingImportInvalidSecretPassphrase =>
      'Enter a valid secret passphrase with 12, 15, 18, 21, or 24 words.';

  @override
  String get onboardingImportManualCardSubtitle => 'Word by word.';

  @override
  String get onboardingImportManualCardTitle =>
      'Manually Enter\nSecret Passphrase';

  @override
  String get onboardingImportMethodSubtitle => 'Select the method you want.';

  @override
  String get onboardingImportMethodTitle => 'Import Account\nto Vizor';

  @override
  String get onboardingImportNoPhraseError => 'No secret passphrase found';

  @override
  String get onboardingImportPasteFromClipboard => 'Or paste from clipboard';

  @override
  String get onboardingImportPasteHelper =>
      'Accept 12, 15, 18, 21, or 24-word\nsecret passphrases';

  @override
  String get onboardingImportReadingClipboard => 'Reading clipboard data...';

  @override
  String get onboardingImportSecretPassphrase => 'Import secret passphrase';

  @override
  String get onboardingImportSecretPassphraseDescriptionDesktop =>
      'Vizor or any other Zcash wallet';

  @override
  String get onboardingImportSecretPassphraseDescriptionMobile =>
      'Vizor, ZODL, or any other wallet';

  @override
  String get onboardingImportWalletTitle => 'Import a Wallet';

  @override
  String get onboardingImportWalletTitleMobile => 'Import Wallet';

  @override
  String get onboardingIntroCard =>
      'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount — verified by cryptography, not trust.';

  @override
  String get onboardingIntroClosing =>
      'You\'re a few steps away from your first private wallet.\nLet\'s get you set up.';

  @override
  String get onboardingIntroClosingMobile =>
      'You\'re a few steps away from your first private wallet. Let\'s get you set up.';

  @override
  String get onboardingIntroSubtitle =>
      'Zcash (ZEC) built around financial privacy & self-custody.';

  @override
  String get onboardingIntroSubtitleMobile =>
      'Zcash (ZEC) built around financial\nprivacy & self-custody.';

  @override
  String get onboardingIntroTitle => 'The Shielded World';

  @override
  String get onboardingLinkVizorDesktop => 'Link Vizor Desktop';

  @override
  String get onboardingLinkVizorDesktopDescription =>
      'Scan & connect to Vizor Desktop';

  @override
  String get onboardingLoading => 'Loading';

  @override
  String onboardingLostPasswordBody(String resetAction, String importAction) {
    return 'If you\'ve lost your password, the only way to recover\nyour account is to $resetAction.\nThis deletes all accounts and unshared gift card links.\nYou will need to $importAction.';
  }

  @override
  String get onboardingLostPasswordImportAction => 'import accounts again';

  @override
  String get onboardingLostPasswordResetAction => 'completely reset Vizor app';

  @override
  String onboardingLostPasswordResetCountdown(int seconds) {
    return 'Reset after ${seconds}s...';
  }

  @override
  String get onboardingLostPasswordTitle => 'Lost password?';

  @override
  String get onboardingManualInvalidWord => 'Invalid secret passphrase word.';

  @override
  String get onboardingManualNextWord => 'Next word';

  @override
  String get onboardingManualReviewFinish => 'Review & finish';

  @override
  String onboardingManualStoppedAt(String word) {
    return 'Stopped at \'$word\' — it isn\'t in the passphrase word list.';
  }

  @override
  String get onboardingManualSubtitle => 'Accept 12, 15, 18, 21 or 24 words';

  @override
  String get onboardingManualTitle => 'Enter your Secret Passphrase';

  @override
  String get onboardingManualUndoLastWord => 'Undo last word';

  @override
  String get onboardingNetworkCheckingEndpoint => 'Checking endpoint…';

  @override
  String get onboardingNetworkEndpointHelper =>
      'Use a lightwalletd server for this wallet’s network.';

  @override
  String get onboardingNetworkSaveFailed =>
      'Couldn\'t save the endpoint. Try again.';

  @override
  String get onboardingNetworkVerifyFailed =>
      'Couldn\'t verify that endpoint. Check the address and try again.';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingNotNow => 'Not now';

  @override
  String get onboardingPasscodeCreateTitle => 'Create Passcode';

  @override
  String onboardingPasscodeDigitSemantics(int digit) {
    return 'Digit $digit';
  }

  @override
  String get onboardingPasscodeReEnter => 'Re-enter your passcode.';

  @override
  String get onboardingPasscodeSettingUp => 'Setting up your wallet...';

  @override
  String get onboardingRandomiseAccountPersona =>
      'Randomise account name and profile picture';

  @override
  String get onboardingRecoveringWallet => 'Recovering wallet...';

  @override
  String get onboardingResetAppFailed =>
      'Couldn\'t reset the app. Please try again.';

  @override
  String get onboardingResumeSetupFailed =>
      'Couldn\'t resume setup. Please try again.';

  @override
  String get onboardingRetrySetup => 'Retry setup';

  @override
  String get onboardingRetrying => 'Retrying';

  @override
  String get onboardingReviewClearSecretPassphrase => 'Clear secret passphrase';

  @override
  String get onboardingReviewConfirmContinue => 'Confirm & continue';

  @override
  String get onboardingReviewImportSubtitle =>
      'Review your secret passphrase\nbefore import starts.';

  @override
  String get onboardingReviewImportTitle => 'Review Import';

  @override
  String get onboardingSave => 'Save';

  @override
  String get onboardingSavingWallet => 'Saving wallet...';

  @override
  String get onboardingSecretPassphraseAboutToSee =>
      'You are about to see your Secret Passphrase.';

  @override
  String get onboardingSecretPassphraseAboutToSeeMobile =>
      'You are about to see your\nSecret Passphrase.';

  @override
  String get onboardingSecretPassphraseReveal => 'Reveal the phrase';

  @override
  String get onboardingSecretPassphraseRevealMobile => 'Reveal phrase';

  @override
  String get onboardingSecretPassphraseSubtitleDesktop =>
      'The master key to your wallet.';

  @override
  String get onboardingSecretPassphraseSubtitleMobile =>
      'The Master Key to your wallet.';

  @override
  String get onboardingSecretPassphraseWarning =>
      'This phrase is the master key to your funds. Keep it safe, keep it secret. If you lose it, no one can help you recover your wallet. Not even us.';

  @override
  String get onboardingSeedWordHint => 'Seed word';

  @override
  String get onboardingSetPasswordAndFinish => 'Set password & finish';

  @override
  String get onboardingSetPasswordPlaceholder =>
      'Min. 8 characters and symbols';

  @override
  String get onboardingSetPasswordSubtitle =>
      'Set password for signing in to Vizor wallet.';

  @override
  String get onboardingSettingPassword => 'Setting password...';

  @override
  String get onboardingSetupInterrupted =>
      'Setup interrupted. Retry to recover your wallet.';

  @override
  String get onboardingStepAddressTypes => 'Address types';

  @override
  String get onboardingStepCustomiseWallet => 'Customise wallet';

  @override
  String get onboardingStepImportContacts => 'Import contacts';

  @override
  String get onboardingStepIntroToZcash => 'Intro to Zcash';

  @override
  String get onboardingStepSetPassword => 'Set Password';

  @override
  String get onboardingStepWalletBirthdayHeight => 'Wallet Birthday Height';

  @override
  String get onboardingStopSyncing => 'Stop syncing...';

  @override
  String get onboardingStorageDbMigrationBody =>
      'Vizor needs to update the local wallet database before opening this version. Try again, or quit and restart Vizor.';

  @override
  String get onboardingStorageDbMigrationTitle =>
      'Unable to update wallet database';

  @override
  String get onboardingStorageKeyringLockedBody =>
      'Vizor needs access to the system keyring before it can open your wallet. Unlock the keyring, then try again.';

  @override
  String get onboardingStorageRetrySecureStorageFailed =>
      'Secure storage is still unavailable.';

  @override
  String get onboardingStorageRetryWalletDbFailed =>
      'The wallet database update still failed.';

  @override
  String get onboardingStorageSecureStorageLockedBody =>
      'Vizor needs access to secure storage before it can open your wallet. Unlock secure storage, then try again.';

  @override
  String get onboardingStorageSecureStorageLockedTitle =>
      'Secure storage is locked';

  @override
  String get onboardingStorageStartupFailureBody =>
      'Vizor could not load the local startup state. Try again, or quit and restart Vizor.';

  @override
  String get onboardingTellMeHowZcashWorks => 'Tell me how Zcash works';

  @override
  String get onboardingThingsKeepPrivacyBody =>
      'Some exchanges can\'t send to shielded addresses. If you\'re withdrawing from an exchange, use your transparent address. You can shield your ZEC after it arrives.';

  @override
  String get onboardingThingsKeepPrivacyTitle => 'How to keep privacy';

  @override
  String get onboardingThingsSubtitleMobile => 'Before you dive in.';

  @override
  String get onboardingThingsTimeToSyncBody =>
      'Your wallet syncs directly with the Zcash network instead of relying on a server. This protects your privacy, but takes a moment. Your funds are safe while the app catches up.';

  @override
  String get onboardingThingsTimeToSyncTitle => 'Time to sync';

  @override
  String get onboardingThingsToKnow => 'Things to know';

  @override
  String get onboardingUnknownHeightBody =>
      'If you continue without a wallet birthday, Vizor will scan from the earliest supported shielded height. This is safe, but the first sync can take a very long time.';

  @override
  String get onboardingUnknownHeightHint =>
      'Choosing even an approximate date will be much faster.';

  @override
  String get onboardingUnknownHeightTitle => 'Import from the earliest height?';

  @override
  String get onboardingUnlockBiometricReason => 'Unlock your wallet';

  @override
  String get onboardingUnlockDescription =>
      'Enter your password to open Vizor.';

  @override
  String get onboardingUnlockEnterPasscode =>
      'Enter your passcode to open Vizor';

  @override
  String get onboardingUnlockIncorrectPassword =>
      'Incorrect password. Try again.';

  @override
  String get onboardingUnlockOpenFailed =>
      'Couldn\'t open your wallet. Please try again.';

  @override
  String get onboardingUnlockOpening => 'Opening your wallet...';

  @override
  String get onboardingUnlockWelcomeBack => 'Welcome back';

  @override
  String get onboardingWelcome => 'Welcome';

  @override
  String get onboardingWelcomeActivateGiftCard => 'Activate gift card';

  @override
  String get onboardingWelcomeGetStarted => 'Get started';

  @override
  String get onboardingWelcomeImportWallet => 'Import wallet';

  @override
  String get passcodeConfirmTitle => 'Confirm Passcode';

  @override
  String get passcodeIncorrect => 'Incorrect Passcode';

  @override
  String get passcodeSixDigits => '6 digits length';

  @override
  String get passcodesDidNotMatch => 'Passcodes didn\'t match. Try again.';

  @override
  String get passwordCheckFailed =>
      'Couldn\'t check your password. Please try again.';

  @override
  String get passwordConfirmLabel => 'Confirm password';

  @override
  String get passwordIncorrect => 'Incorrect password. Please try again.';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match.';

  @override
  String get payAddLabelHint => 'Add label 1-20 characters';

  @override
  String get payAddToContacts => 'Add to contacts';

  @override
  String get payAddressLabel => 'Address label';

  @override
  String payAddressSemantics(String address) {
    return 'Address $address';
  }

  @override
  String get payAmountChooseAsset => 'Choose payment asset';

  @override
  String payAmountEnterIn(String symbol) {
    return 'Enter amount in $symbol';
  }

  @override
  String get payAmountEnterInUsd => 'Enter amount in USD';

  @override
  String get payAmountEstimated => 'Estimated:';

  @override
  String get payAmountEstimatedSpend => 'Estimated spend';

  @override
  String get payAmountPayingFrom => 'Paying from your';

  @override
  String get payAmountPayingIn => 'Paying in';

  @override
  String get payAmountShieldedBalance => 'Shielded balance';

  @override
  String get payBackHome => 'Home';

  @override
  String payChainAddressHint(String chain) {
    return '$chain address';
  }

  @override
  String get payChainAndAddress => 'Chain & address';

  @override
  String get payChangeContactPicture => 'Change contact picture';

  @override
  String get payClearContactLabel => 'Clear contact label';

  @override
  String get payContacts => 'Contacts';

  @override
  String get payFetchingQuote => 'Fetching quote';

  @override
  String get payInsufficientZec =>
      'You don\'t have enough ZEC for this payment. Try a smaller amount.';

  @override
  String get payNewAddressDetected => 'New address detected.';

  @override
  String get payNewAddressWarning =>
      'You haven\'t interacted with this address before.';

  @override
  String get payNotEnoughZec => 'Not enough ZEC';

  @override
  String payRecentDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String payRecentHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String get payRecentJustNow => 'just now';

  @override
  String payRecentMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String get payRecentlySent => 'Recently sent';

  @override
  String get payRecents => 'Recents';

  @override
  String get payRecipientAddressHint => 'Paste an address or scan QR code';

  @override
  String get payRecipientAddressLabel => 'Recipient address';

  @override
  String get payRecipientScanQr => 'Scan QR code';

  @override
  String get payRefreshingQuote => 'Refreshing quote';

  @override
  String get payReviewConfirmPay => 'Confirm & pay';

  @override
  String get payReviewConvertedAmount => 'Converted amount';

  @override
  String get payReviewFullAddress => 'Full address';

  @override
  String get payReviewPaying => 'Paying';

  @override
  String get payReviewQuoteExpired => 'Quote expired';

  @override
  String get payReviewQuoteExpiresIn => 'Quote expires in ';

  @override
  String get payReviewRefreshQuote => 'Refresh quote';

  @override
  String get payReviewRefreshTheQuote => 'Refresh the quote';

  @override
  String get payReviewReturnToPay => 'Return to pay';

  @override
  String get payReviewShowFullAddress => 'Show full address';

  @override
  String get payReviewTo => 'To';

  @override
  String get payReviewUnknownAddress => 'Unknown address';

  @override
  String get paySave => 'Save';

  @override
  String get paySaveContact => 'Save contact';

  @override
  String get paySaveContactError => 'Couldn\'t save this contact. Try again.';

  @override
  String get paySaving => 'Saving';

  @override
  String get payScanBarrierDismiss => 'Dismiss';

  @override
  String get payScanCaption => 'Scan the recipient address QR code';

  @override
  String get payScanNoAddress => 'QR code did not include an address.';

  @override
  String get payScanPermissionTitle => 'Scan the recipient address';

  @override
  String get payScanQrSubtitle => 'Scan an address using camera';

  @override
  String get payScanQrTitle => 'Scan a QR code';

  @override
  String get payScanSteadyHint => 'Keep the QR code steady and fully visible.';

  @override
  String get paySelectContactPicture => 'Select contact picture';

  @override
  String get paySelectRecipient => 'Select recipient';

  @override
  String get paySelectedContact => 'Selected contact';

  @override
  String get payStepAmount => 'Amount';

  @override
  String get payStepRecipient => 'Recipient';

  @override
  String get payStepReview => 'Review';

  @override
  String get paySubmittedDone => 'Done';

  @override
  String get paySubmittedFailedBody =>
      'The payment could not be submitted. Try again.';

  @override
  String get paySubmittedFailedTitle => 'Payment failed';

  @override
  String get paySubmittedGoToActivity => 'Go to activity';

  @override
  String get paySubmittedReturnHome => 'Return home';

  @override
  String get paySubmittedStatusUncertainNotice =>
      'The payment status is uncertain. Check Activity before trying again.';

  @override
  String get paySubmittedSubmittingBody =>
      'Submitting your payment to the network...';

  @override
  String get paySubmittedSubmittingTitle => 'Submitting payment...';

  @override
  String get paySubmittedSucceededBody =>
      'It will confirm on-chain shortly.\nTrack it in Activity.';

  @override
  String get paySubmittedSucceededTitle => 'Payment\nSubmitted';

  @override
  String get paySubmittedUnavailableNotice =>
      'We couldn\'t load this payment. Check Activity for its latest status.';

  @override
  String get paySubmittedUnavailableTitle => 'Payment unavailable';

  @override
  String get paySubmittedUncertainTitle => 'Payment status\nuncertain';

  @override
  String payTitleAmount(String symbol) {
    return 'Pay in $symbol';
  }

  @override
  String get payTitleRecipient => 'Select Recipient';

  @override
  String get payTitleReview => 'Review Payment';

  @override
  String get poolShielded => 'Shielded';

  @override
  String get poolTransparent => 'Transparent';

  @override
  String get profilePictureChange => 'Change profile picture';

  @override
  String get profilePictureSelect => 'Select profile picture';

  @override
  String get profilePictureUpdateFailed => 'Couldn\'t update profile picture.';

  @override
  String get receiptMessageLabel => 'Message';

  @override
  String get receiveAboutAddressType => 'About this address type';

  @override
  String get receiveAddressCouldNotLoad =>
      'Address couldn\'t be loaded. Try again.';

  @override
  String get receiveAddressLoadFailed =>
      'We couldn\'t load your address. Try again in a moment.';

  @override
  String get receiveCopyShieldedAddress => 'Copy shielded address';

  @override
  String get receiveCopyTransparentAddress => 'Copy transparent address';

  @override
  String receiveErrorWithDetails(String message, String details) {
    return '$message\nDetails: $details';
  }

  @override
  String get receiveGenerateNewShieldedAddress =>
      'Generate new shielded address';

  @override
  String get receiveInfoShieldedDiversified =>
      'Each new address is a diversified address derived from the same key. They all receive to the same wallet.';

  @override
  String get receiveInfoShieldedHiddenDesktop =>
      'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.';

  @override
  String get receiveInfoShieldedHiddenMobile =>
      'Tx details — sender, receiver, and amount — are encrypted on-chain & hidden.';

  @override
  String get receiveInfoShieldedRenewClick =>
      'A new Zcash shielded address is generated only when you click the renew button.';

  @override
  String get receiveInfoShieldedRenewTap =>
      'A new Zcash shielded address is generated only when you tap the renew button.';

  @override
  String get receiveInfoShieldedSubtitle => 'Strong privacy by default.';

  @override
  String get receiveInfoShieldedTitle => 'Shielded address';

  @override
  String get receiveInfoTransparentExchanges =>
      'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.';

  @override
  String get receiveInfoTransparentPublicDesktop =>
      'All tx details - sender, receiver, and amount - are publicly visible on-chain.';

  @override
  String get receiveInfoTransparentPublicMobile =>
      'All tx details — sender, receiver, and amount — are publicly visible on-chain.';

  @override
  String get receiveInfoTransparentRotates =>
      'After this address receives ZEC and Vizor syncs, your next transparent address will automatically change. Previous addresses still belong to this wallet.';

  @override
  String receiveInfoTransparentShieldFirst(String ticker) {
    return 'After receiving $ticker to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.';
  }

  @override
  String get receiveInfoTransparentSubtitle => 'Publicly visible';

  @override
  String get receiveInfoTransparentTitle => 'Transparent address';

  @override
  String get receiveNoActiveAccount => 'No active account';

  @override
  String get receiveQrSaveFailed =>
      'We couldn\'t save the QR image. Try another folder, or copy the request link instead.';

  @override
  String receiveQrSaved(String folder) {
    return 'QR image saved to $folder';
  }

  @override
  String get receiveQrUnavailable => 'QR unavailable';

  @override
  String get receiveRenewAddressError =>
      'We couldn\'t refresh your shielded address. Try again, or use your current one.';

  @override
  String get receiveRequestAddMessage => 'Add a message';

  @override
  String get receiveRequestAmountDecimalsError => 'Enter up to 8 decimals';

  @override
  String get receiveRequestAmountFormatError => 'Enter an amount like 0.5';

  @override
  String get receiveRequestAmountLabel => 'Amount';

  @override
  String get receiveRequestAmountSupplyError => 'Amount exceeds the ZEC supply';

  @override
  String receiveRequestButton(String ticker) {
    return 'Request $ticker';
  }

  @override
  String get receiveRequestCloseMessage => 'Close message';

  @override
  String get receiveRequestCloseRequest => 'Close request';

  @override
  String get receiveRequestCopyFailed =>
      'Couldn\'t copy the request link. Try sharing it instead.';

  @override
  String get receiveRequestCopyLink => 'Copy link';

  @override
  String get receiveRequestCopyRequestLink => 'Copy request link';

  @override
  String get receiveRequestCreate => 'Create request';

  @override
  String get receiveRequestEnterUsd => 'Enter amount in USD';

  @override
  String get receiveRequestEnterZec => 'Enter amount in ZEC';

  @override
  String get receiveRequestLinkCopied => 'Request link copied';

  @override
  String get receiveRequestMessageHelp =>
      'Shielded addresses only — anyone with this link can read it.';

  @override
  String get receiveRequestMessageHint =>
      'Anyone you send the link to can read this';

  @override
  String get receiveRequestMessageLabel => 'Message';

  @override
  String get receiveRequestMessageTooLong => 'Message is too long';

  @override
  String get receiveRequestSaveQr => 'Save QR image';

  @override
  String get receiveRequestShare => 'Share request';

  @override
  String get receiveRequestShareFailed =>
      'Couldn\'t share this request. Copy the link instead.';

  @override
  String get receiveRequestZecButton => 'Request ZEC';

  @override
  String get receiveShareAddress => 'Share address';

  @override
  String get receiveShareFailed =>
      'Couldn\'t share this address. Copy it instead.';

  @override
  String get receiveShareShieldedAddress => 'Share shielded address';

  @override
  String get receiveShareTransparentAddress => 'Share transparent address';

  @override
  String receiveTitle(String ticker) {
    return 'Receive $ticker';
  }

  @override
  String get secretPassphraseCopy => 'Copy secret passphrase';

  @override
  String get secretPassphraseTitle => 'Secret Passphrase';

  @override
  String get sendAddMemo => 'Add a memo';

  @override
  String get sendAddressTypeShielded => 'Shielded address';

  @override
  String get sendAddressTypeTex => 'TEX address';

  @override
  String get sendAddressTypeTransparent => 'Transparent address';

  @override
  String get sendAddressValidationFailed => 'Address validation failed';

  @override
  String get sendAmountCtaEnterAmount => 'Enter amount to continue';

  @override
  String get sendAmountCtaReviewAndFinish => 'Review & finish';

  @override
  String get sendAmountLabel => 'Amount';

  @override
  String get sendBroadcastCancelledBeforeParams =>
      'Sending was cancelled before proving parameters were downloaded.';

  @override
  String get sendBroadcastDependentIncomplete =>
      'The first transaction was accepted, but the dependent transaction did not complete. Check Activity before sending again.';

  @override
  String get sendBroadcastFirstUnknown =>
      'The first transaction is stored locally and may have reached the network, but confirmation timed out. Check Activity before sending again.';

  @override
  String get sendBroadcastHardwareExpired =>
      'The hardware signing request expired before broadcast. Return to your wallet, wait for sync, then review the payment and try again.';

  @override
  String get sendBroadcastIncomplete =>
      'The transaction broadcast did not complete. Check Activity before sending again.';

  @override
  String get sendBroadcastLedgerFirstUnknown =>
      'The first transaction may have reached the network, but confirmation timed out. Check Activity before sending again.';

  @override
  String get sendBroadcastLedgerNotStored =>
      'The transaction reached the network, but Vizor could not store it locally. Do not send again until sync or an explorer confirms the latest status.';

  @override
  String get sendBroadcastLedgerRejected =>
      'Transaction was rejected by the network. Please try again later.';

  @override
  String get sendBroadcastLocalRetry =>
      'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.';

  @override
  String get sendBroadcastMnemonicMissing =>
      'Mnemonic not found for the proposal account.';

  @override
  String get sendBroadcastPartial =>
      'Some transactions were broadcast and the rest will retry automatically. Check activity before sending again.';

  @override
  String get sendBroadcastProofParamsRequired =>
      'Proof parameters are required to retry this signed transaction.';

  @override
  String get sendBroadcastRejectedLocal =>
      'Transaction was created locally but didn\'t reach the network. The wallet will keep retrying until it expires. Don\'t send again unless this one expires.';

  @override
  String get sendBroadcastTrackingFailed =>
      'The transaction reached the network, but local tracking failed. Check Activity or an explorer before sending again.';

  @override
  String get sendCalculatingMax => 'Calculating max amount';

  @override
  String get sendClearAction => 'Clear';

  @override
  String get sendCloseMessageField => 'Close message';

  @override
  String get sendContactPickerEmpty => 'No Zcash contacts';

  @override
  String get sendContactPickerTitle => 'Contacts Zcash';

  @override
  String get sendContactsLink => 'Contacts';

  @override
  String get sendDonationAddressTitle => 'Vizor donation address';

  @override
  String get sendEnterAddressToContinue => 'Enter address to continue';

  @override
  String sendEnterAmountInCurrency(String currency) {
    return 'Enter amount in $currency';
  }

  @override
  String get sendEnterValidAddress => 'Enter a valid address';

  @override
  String get sendErrorCouldNotBeSent =>
      'Transaction couldn\'t be sent. Go back to your wallet and check the latest status.';

  @override
  String get sendErrorDonationFailed => 'Donation failed. Try again.';

  @override
  String get sendErrorExpiredBeforeSent =>
      'Transaction expired before it could be sent.';

  @override
  String get sendErrorExpiredTryAgain =>
      'Transaction expired before it could be sent. Try again.';

  @override
  String get sendErrorInsufficientShielded =>
      'Insufficient shielded balance to cover amount and fee.';

  @override
  String get sendErrorNetwork =>
      'Network error. Check your connection and try again.';

  @override
  String get sendErrorPartiallySent =>
      'Some parts of this transaction were sent. Open Activity to see what went through before you try again.';

  @override
  String get sendErrorRejectedTryAgain =>
      'The network rejected this transaction. Try again.';

  @override
  String get sendErrorRejectedTryLater =>
      'The network rejected this transaction. Try again later.';

  @override
  String get sendErrorSendFailed => 'Send failed. Try again.';

  @override
  String get sendErrorSyncFinishing =>
      'Finishing wallet sync. Try again shortly.';

  @override
  String get sendFeeAboutSemantics => 'About the transaction fee';

  @override
  String get sendFeeUnavailableTryAgain => 'Fee unavailable. Try again.';

  @override
  String get sendFeeUpdatedAfterSync =>
      'Fee updated after sync. Review and confirm again.';

  @override
  String get sendFinishingSync => 'Finishing wallet sync.';

  @override
  String get sendInsufficientBalanceIncludingFeeShielded =>
      'Insufficient shielded balance including fee';

  @override
  String get sendInsufficientBalanceIncludingFeeTex =>
      'Insufficient balance including fee';

  @override
  String get sendInsufficientBalanceSentenceShielded =>
      'Insufficient shielded balance.';

  @override
  String get sendInsufficientBalanceSentenceTex => 'Insufficient balance.';

  @override
  String get sendInsufficientBalanceShielded => 'Insufficient shielded balance';

  @override
  String get sendInsufficientBalanceTex => 'Insufficient balance';

  @override
  String get sendInsufficientBalanceToCoverFeeShielded =>
      'Insufficient shielded balance to cover fee';

  @override
  String get sendInsufficientBalanceToCoverFeeTex =>
      'Insufficient balance to cover fee';

  @override
  String sendInsufficientBalanceWithFeeShielded(String fee) {
    return 'Insufficient shielded balance (fee: $fee)';
  }

  @override
  String sendInsufficientBalanceWithFeeTex(String fee) {
    return 'Insufficient balance (fee: $fee)';
  }

  @override
  String get sendInvalidAddress => 'Invalid address';

  @override
  String get sendInvalidAmount => 'Invalid amount';

  @override
  String get sendKeystoneAfterScan => 'After you scanned, click Get signature.';

  @override
  String get sendKeystoneConfirmTitle => 'Confirm with Keystone';

  @override
  String get sendKeystoneExpired =>
      'Transaction expired before it could be signed.';

  @override
  String get sendKeystoneGetSignature => 'Get signature';

  @override
  String get sendKeystonePrepareFailedGoBack =>
      'Keystone signing could not be prepared. Go back and try again.';

  @override
  String get sendKeystonePrepareFailedReturnToSend =>
      'Keystone signing could not be prepared. Return to Send and try again.';

  @override
  String get sendKeystonePreparing => 'Preparing';

  @override
  String get sendKeystoneProvingCancelled =>
      'Signing was cancelled before proving parameters were downloaded.';

  @override
  String get sendKeystoneProvingParamsFailed =>
      'Required proving parameters could not be prepared.';

  @override
  String get sendKeystoneQrMismatch =>
      'This QR code does not match the current Keystone signing request.';

  @override
  String get sendKeystoneScanCameraOnly =>
      'Keystone signing uses camera QR scanning only. Connect a camera and try again.';

  @override
  String get sendKeystoneScanDecodeFailed =>
      'This QR code could not be decoded as a Keystone transaction signature.';

  @override
  String get sendKeystoneScanHoldSteady =>
      'Hold the QR code steady in front of your camera';

  @override
  String get sendKeystoneScanNow =>
      'Scan now. Signature import unlocks after proofs are ready.';

  @override
  String get sendKeystoneScanReading => 'Reading signature...';

  @override
  String get sendKeystoneScanSubtitle => 'Scan with your Keystone';

  @override
  String get sendKeystoneScanToFinish =>
      'Scan the QR code on your Keystone to finish sending';

  @override
  String get sendKeystoneScanTransactionInstruction =>
      'Use your Keystone wallet to scan this transaction QR code. Follow the steps on your device.';

  @override
  String get sendKeystoneScanUnexpectedSignature =>
      'Open the signature result QR on Keystone, then scan again.';

  @override
  String get sendKeystoneScanUnexpectedTransaction =>
      'Open the signed transaction QR on Keystone, then scan again.';

  @override
  String sendKeystoneTexTwoApprovals(int index) {
    return 'This TEX send requires two Keystone approvals. Scan transaction $index of 2.';
  }

  @override
  String sendKeystoneTransactionOfTwo(int index) {
    return 'Transaction $index of 2';
  }

  @override
  String sendLedgerConnectAndUnlock(String instruction) {
    return 'Connect and unlock your Ledger. $instruction';
  }

  @override
  String get sendLedgerCouldNotFinishTitle => 'Could not finish transaction';

  @override
  String get sendLedgerCouldNotPrepare =>
      'Vizor could not prepare the transaction. Try again.';

  @override
  String get sendLedgerCouldNotSaveTitle => 'Could not save signed transaction';

  @override
  String get sendLedgerCouldNotVerifySaved =>
      'Vizor could not verify the saved transaction. Do not sign or send it again.';

  @override
  String get sendLedgerCreateNewTransaction => 'Create new transaction';

  @override
  String get sendLedgerExpiredMessage =>
      'This transaction can no longer be signed. Create and review a new transaction.';

  @override
  String get sendLedgerExpiredTitle => 'Transaction expired';

  @override
  String get sendLedgerKeepOpenRetry =>
      'Keep Vizor open and try again. No new Ledger approval needed.';

  @override
  String get sendLedgerKeepOpenRetrySaving =>
      'Keep Vizor open and retry saving. No new Ledger approval needed.';

  @override
  String get sendLedgerNeedsAttentionTitle => 'Ledger needs attention';

  @override
  String get sendLedgerRejectedOnDevice =>
      'The transaction was rejected on your Ledger.';

  @override
  String get sendLedgerRetrySaving => 'Retry saving';

  @override
  String get sendLedgerSignaturePreservedMessage =>
      'Your Ledger signature is preserved. Retry saving without approving another transaction.';

  @override
  String get sendLedgerSignedNeedsAttentionTitle =>
      'Signed transaction needs attention';

  @override
  String get sendLedgerSigningFailedTitle => 'Ledger signing failed';

  @override
  String get sendLedgerSigningIncomplete =>
      'Ledger signing could not be completed. Check your device and try again.';

  @override
  String get sendLedgerSigningUnavailableTitle => 'Ledger signing unavailable';

  @override
  String get sendLedgerStatusActionNeeded => 'Action needed';

  @override
  String get sendLedgerStatusNewTransactionRequired =>
      'New transaction required';

  @override
  String get sendLedgerStatusRecoveryRequired => 'Recovery required';

  @override
  String get sendLedgerStatusSignaturePreserved => 'Signature preserved';

  @override
  String get sendLedgerStatusUnsupportedTransaction =>
      'Unsupported transaction';

  @override
  String sendLoadError(String error) {
    return 'Something went wrong. Try again in a moment.\n\nDetails: $error';
  }

  @override
  String get sendMaxButton => 'Max';

  @override
  String get sendMaxNeedsAddress => 'Enter a valid address to use Max';

  @override
  String get sendMaxUnavailable => 'Max amount unavailable';

  @override
  String get sendMemoAddShortEncrypted => 'Add short encrypted message';

  @override
  String get sendMemoClear => 'Clear memo';

  @override
  String get sendMemoCollapse => 'Collapse';

  @override
  String get sendMemoEncryptedHint => 'Encrypted, for shielded addresses only.';

  @override
  String get sendMemoRecipientOnly => 'Only the recipient can read this';

  @override
  String get sendMemoSheetAdd => 'Add Memo';

  @override
  String get sendMemoShieldedOnly =>
      'Message is only available for shielded addresses';

  @override
  String get sendMemoTooLong => 'Message is too long';

  @override
  String get sendMemoWhitespaceOnly => 'Whitespace only';

  @override
  String get sendMessageHint => 'Add a message';

  @override
  String get sendMessageLabel => 'Message';

  @override
  String get sendNoActiveAccount => 'No active account';

  @override
  String get sendNotEnoughZec => 'Not enough ZEC';

  @override
  String get sendOpenContacts => 'Open contacts';

  @override
  String get sendPasteAction => 'Paste';

  @override
  String get sendPaymentRequestAmountNotSpecified => 'Amount not specified';

  @override
  String get sendPaymentRequestCheckAgain => 'Check again';

  @override
  String get sendPaymentRequestCheckBeforePayBody =>
      'Other apps can change the address or amount in a request link.';

  @override
  String get sendPaymentRequestCheckBeforePayTitle => 'Check before you pay';

  @override
  String get sendPaymentRequestCheckFailed => 'Couldn\'t check this request';

  @override
  String get sendPaymentRequestChecking => 'Checking…';

  @override
  String get sendPaymentRequestClose => 'Close payment request';

  @override
  String get sendPaymentRequestConfirmWithSender =>
      'Confirm the details with the person who sent it.';

  @override
  String get sendPaymentRequestEdit => 'Edit';

  @override
  String get sendPaymentRequestEnterAmount => 'Enter amount';

  @override
  String get sendPaymentRequestHideFullAddress => 'Hide full recipient address';

  @override
  String get sendPaymentRequestHidePaymentDetails => 'Hide payment details';

  @override
  String get sendPaymentRequestHideRequesterInfo =>
      'Hide requester information';

  @override
  String sendPaymentRequestHideRequesterInfoFor(String name) {
    return 'Hide requester information for $name';
  }

  @override
  String get sendPaymentRequestInsufficientFunds =>
      'Not enough ZEC for this amount and the network fee';

  @override
  String sendPaymentRequestInsufficientFundsWithSpendable(String spendable) {
    return 'Not enough ZEC for this amount and the network fee ($spendable available)';
  }

  @override
  String get sendPaymentRequestInvalidAddress =>
      'Recipient address doesn\'t look right';

  @override
  String get sendPaymentRequestLinkDifferentAddress =>
      'The link had a different address';

  @override
  String get sendPaymentRequestLinkDifferentAmount =>
      'The link had a different amount';

  @override
  String get sendPaymentRequestLinkDifferentDetails =>
      'The link had different details';

  @override
  String get sendPaymentRequestLinkDifferentMemo =>
      'The link had a different memo';

  @override
  String get sendPaymentRequestMatchesLink => 'Matches the link';

  @override
  String get sendPaymentRequestMemoIncluded => 'Memo included';

  @override
  String get sendPaymentRequestMemoIncludedHint =>
      'Memo included. View the transaction memo.';

  @override
  String get sendPaymentRequestNameDisclaimer =>
      'This name comes from the request. It doesn\'t confirm who owns the receiving address.';

  @override
  String get sendPaymentRequestNameSuppliedInRequest =>
      'Name supplied in the request.';

  @override
  String get sendPaymentRequestNoteFromRequester => 'Note from requester';

  @override
  String get sendPaymentRequestPaymentDetails => 'Payment details';

  @override
  String get sendPaymentRequestRecipient => 'Recipient';

  @override
  String get sendPaymentRequestReplacedNotice => 'Replaced an earlier link';

  @override
  String get sendPaymentRequestRequestFrom => 'Request from';

  @override
  String get sendPaymentRequestReviewLinkDetails => 'Review link details';

  @override
  String get sendPaymentRequestReviewPayment => 'Review payment';

  @override
  String get sendPaymentRequestScanOriginalHint =>
      'Scan the original QR code directly in Vizor.';

  @override
  String get sendPaymentRequestScanOriginalQr => 'Scan original QR';

  @override
  String get sendPaymentRequestShowFullAddress => 'Show full recipient address';

  @override
  String get sendPaymentRequestShowRequesterInfo =>
      'Show requester information';

  @override
  String sendPaymentRequestShowRequesterInfoFor(String name) {
    return 'Show requester information for $name';
  }

  @override
  String get sendPaymentRequestSyncStalled =>
      'Still syncing — check again when the wallet is up to date';

  @override
  String get sendPaymentRequestSyncing =>
      'Wallet is still syncing — this will update when it finishes';

  @override
  String get sendPaymentRequestTitle => 'Payment request';

  @override
  String get sendPaymentRequestTransactionMemo => 'Transaction memo';

  @override
  String sendPaymentRequestUnavailableLabel(String label) {
    return '$label, unavailable';
  }

  @override
  String sendPaymentRequestUnavailableWithReason(String label, String reason) {
    return '$label, unavailable. $reason';
  }

  @override
  String get sendPaymentRequestUsingQrInstead =>
      'Using the QR instead — the link may have been changed.';

  @override
  String get sendPaymentRequestViewNote => 'View note';

  @override
  String get sendPaymentRequestYourAccount => 'Your account';

  @override
  String get sendQrScannerOpenFailed =>
      'Couldn\'t open the QR scanner. Try again.';

  @override
  String get sendRecentsSection => 'Recents';

  @override
  String get sendRecipientHint => 'Address or request link';

  @override
  String get sendRecipientLabel => 'Send to';

  @override
  String get sendRecipientUnreadableRequestLink =>
      'This request link couldn\'t be read';

  @override
  String get sendRecipientWrongNetwork =>
      'This address is for a different Zcash network';

  @override
  String get sendRequestScanBackLabel => 'Payment request';

  @override
  String get sendRequestScanCheckFailed =>
      'Couldn\'t check this QR code. Try again.';

  @override
  String get sendRequestScanPermission =>
      'A camera is required to scan the payment request QR code.\nYou can change camera access in settings at any time.';

  @override
  String get sendRequestScanSubtitle =>
      'Show the requester’s original QR code to your camera';

  @override
  String get sendRequestScanTipContinuity =>
      'On a Mac, you can use Continuity Camera to scan with your iPhone instead.';

  @override
  String get sendRequestScanTipDistance =>
      'Move the QR code a few inches further from the camera so it can focus.';

  @override
  String get sendRequestScanTipLight =>
      'Make sure the room is well-lit and the QR code isn\'t reflecting glare.';

  @override
  String get sendRequestScanTipOriginal =>
      'Open the requester’s original QR code full screen on another device.';

  @override
  String get sendRequestScanTitle => 'Scan original QR';

  @override
  String get sendRequestScanUnavailable =>
      'Connect a camera, or go back and review the link details.';

  @override
  String get sendReviewAction => 'Review';

  @override
  String get sendReviewBackSupportVizor => 'Support Vizor';

  @override
  String get sendReviewCalculatingFee => 'Calculating fee...';

  @override
  String get sendReviewConfirmAndSend => 'Confirm & send';

  @override
  String get sendReviewConfirmAndSendMobile => 'Confirm & Send';

  @override
  String get sendReviewConfirmDonation => 'Confirm donation';

  @override
  String get sendReviewConfirmWithLedger => 'Confirm with Ledger';

  @override
  String get sendReviewFeeUnavailable => 'Fee unavailable';

  @override
  String get sendReviewFinishingSyncButton => 'Finishing wallet sync...';

  @override
  String get sendReviewFullAddress => 'Full address';

  @override
  String get sendReviewPaymentTitle => 'Review Payment';

  @override
  String get sendReviewPreparing => 'Preparing...';

  @override
  String sendReviewRequestedAmount(String amount) {
    return 'Requested $amount';
  }

  @override
  String get sendReviewRequestedBy => 'Requested by';

  @override
  String get sendReviewShowFullAddress => 'Show full address';

  @override
  String get sendReviewTitle => 'Review send';

  @override
  String get sendReviewTo => 'To';

  @override
  String get sendSaplingDownloadBody =>
      'To create this private transaction, your wallet needs to download about 50MB of cryptographic parameters.';

  @override
  String get sendSaplingDownloadButton => 'Download';

  @override
  String get sendSaplingDownloadNote =>
      'This happens once, then it\'s done.\nNetwork data charges may apply.';

  @override
  String get sendSaplingDownloadTitle => 'Download Required';

  @override
  String get sendScanDowngradePastedMalformedRequest =>
      'Pasted the address only — the payment request couldn\'t be read';

  @override
  String get sendScanDowngradePastedMultipleRecipients =>
      'Pasted the first recipient only — this request asks for more than one';

  @override
  String get sendScanDowngradePastedUnsupportedMemo =>
      'Pasted the address only — the request\'s message couldn\'t be read';

  @override
  String get sendScanDowngradeScannedMalformedRequest =>
      'Scanned the address only — the payment request couldn\'t be read';

  @override
  String get sendScanDowngradeScannedMultipleRecipients =>
      'Scanned the first recipient only — this request asks for more than one';

  @override
  String get sendScanDowngradeScannedUnsupportedMemo =>
      'Scanned the address only — the request\'s message couldn\'t be read';

  @override
  String get sendScanNotZcashAddress => 'This QR code isn\'t a Zcash address.';

  @override
  String get sendScanQrSubtitle => 'Scan an address or payment request';

  @override
  String get sendScanQrTitle => 'Scan a QR Code';

  @override
  String get sendSendingToLabel => 'Sending to';

  @override
  String get sendSignCancelFailed =>
      'Could not finish cancelling. Please try again.';

  @override
  String get sendSignCancelling => 'Cancelling…';

  @override
  String get sendSignConfirmTransaction => 'Confirm transaction';

  @override
  String sendSignConfirmTransactionOfTwo(int index) {
    return 'Confirm transaction $index of 2';
  }

  @override
  String get sendSpendableInfoLabel => 'Spendable balance info';

  @override
  String get sendSpendableTooltipBody =>
      'Funds need confirmations before they can be spent: 3 for change from your own wallet, 6 for funds received from others. Shielded notes also need to be fully scanned. They\'ll become available shortly.';

  @override
  String get sendSpendableTooltipTitle =>
      'Your spendable balance may be lower than your total balance.';

  @override
  String get sendStatusBackToWallet => 'Back to wallet';

  @override
  String get sendStatusDonationFailed => 'Donation failed';

  @override
  String get sendStatusDonationInProgress => 'Donation in progress...';

  @override
  String sendStatusFailureSummary(String amount, String recipient) {
    return '$amount to $recipient';
  }

  @override
  String get sendStatusMobileConfirmSoon =>
      'It will confirm on-chain shortly. Track it in Activity.';

  @override
  String get sendStatusMobileDonationQueued => 'Donation queued';

  @override
  String get sendStatusMobileDonationSupport =>
      'Your support keeps Vizor going.';

  @override
  String get sendStatusMobileDonationThanks =>
      'Thank you for\nsupporting Vizor';

  @override
  String get sendStatusMobileDone => 'Done';

  @override
  String get sendStatusMobileNothingSent =>
      'Nothing was sent, your funds haven\'t moved. Try again.';

  @override
  String get sendStatusMobilePendingDefault =>
      'Your transaction was created and will be submitted automatically. Check the Activity page before sending again.';

  @override
  String get sendStatusMobileQueued => 'Queued to send';

  @override
  String get sendStatusMobileReturnHome => 'Return home';

  @override
  String get sendStatusMobileReturnToSettings => 'Return to settings';

  @override
  String get sendStatusMobileSending => 'Sending...';

  @override
  String get sendStatusMobileSendingDonation => 'Sending donation...';

  @override
  String get sendStatusMobileSent => 'Sent!';

  @override
  String get sendStatusMobileSubmitting =>
      'Submitting your transaction to the network...';

  @override
  String get sendStatusRetryAfterSync =>
      'Wait for wallet sync, then retry this signed transaction.';

  @override
  String get sendStatusRowStatus => 'Status';

  @override
  String get sendStatusRowTimestamp => 'Timestamp';

  @override
  String get sendStatusRowTxId => 'Tx ID';

  @override
  String get sendStatusScanKeystoneTitle => 'Scan your Keystone QR Code';

  @override
  String get sendStatusTitleCompleted => 'Sent successfully';

  @override
  String get sendStatusTitleFailed => 'Send failed';

  @override
  String get sendStatusTitleInProgress => 'Send in progress...';

  @override
  String get sendStatusTxHashCopied => 'Transaction hash copied';

  @override
  String get sendStatusValueCompleted => 'Completed';

  @override
  String get sendStatusValueFailed => 'Failed';

  @override
  String get sendStatusValueInProgress => 'In progress';

  @override
  String get sendStepEnterAmount => 'Enter Amount';

  @override
  String get sendStepReviewDonation => 'Review donation';

  @override
  String get sendStepReviewSend => 'Review Send';

  @override
  String get sendStepSelectRecipient => 'Select Recipient';

  @override
  String sendTitle(String currency) {
    return 'Send $currency';
  }

  @override
  String get sendUseMax => 'Use Max';

  @override
  String sendUseMaxSemantics(String spendable) {
    return 'Use maximum spendable balance, $spendable available';
  }

  @override
  String get sendUseMaxSemanticsShort => 'Use maximum spendable balance';

  @override
  String sendVerifyAddressPreviousTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count previous transactions',
      one: '1 previous transaction',
    );
    return '$_temp0';
  }

  @override
  String get sendZcashAddress => 'Zcash address';

  @override
  String get settingsAccountChangedPasscode =>
      'Selected account changed. Enter your passcode again.';

  @override
  String get settingsAccountChangedPassword =>
      'Selected account changed. Enter your password again.';

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
  String get settingsBirthdayBlockHeight => 'Birthday block height';

  @override
  String get settingsBirthdayDate => 'Birthday date';

  @override
  String get settingsBirthdayDateCopied => 'Birthday date copied';

  @override
  String get settingsBirthdayHeightCopied => 'Birthday height copied';

  @override
  String get settingsConfirmAccessSubtitle => 'Confirm your access';

  @override
  String get settingsConfirmAccessTitle => 'Confirm access';

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
  String get settingsEndpointCurrentPrefix => 'Current: ';

  @override
  String get settingsEndpointCustomise => 'Customise endpoint';

  @override
  String get settingsEndpointCustomize => 'Customize endpoint';

  @override
  String get settingsEndpointDefaultMarker => '(Default)';

  @override
  String get settingsEndpointSelectFromList => 'Select from the list';

  @override
  String get settingsEndpointTitle => 'Endpoint';

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
  String get settingsKeepAwakeDescription =>
      'Prevents your phone from sleeping so sync can finish faster. The app still locks after 1 minute of inactivity.';

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
  String get settingsPasswordHint => 'Your password...';

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
  String get settingsPrivateQueriesTurnOffDisclosure =>
      'The server receives every transparent address of every account and the IDs of transactions private recovery found. It can link them to each other and, without Tor, to your IP address.';

  @override
  String get settingsPrivateQueriesTurnOffTitle => 'Turn off private queries?';

  @override
  String get settingsProfilePictureCustom => 'Custom';

  @override
  String get settingsRowAboutVizor => 'About Vizor';

  @override
  String get settingsRowAccountNameMobile => 'Account Name';

  @override
  String get settingsRowAddressBook => 'Address book';

  @override
  String get settingsRowChangePasscode => 'Change passcode';

  @override
  String get settingsRowChangePassword => 'Change password';

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
  String get settingsTurnOffConfirm => 'Turn off';

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
  String swapActivityAddressBookRecipient(String symbol) {
    return '$symbol recipient';
  }

  @override
  String swapActivityAddressBookRefund(String symbol) {
    return '$symbol refund';
  }

  @override
  String get swapActivityAmount => 'Amount';

  @override
  String swapActivityDeadlineHours(int hours) {
    return '${hours}hrs';
  }

  @override
  String swapActivityDeadlineMinutes(int minutes) {
    return '${minutes}mins';
  }

  @override
  String get swapActivityDeadlineOneHour => '1hr';

  @override
  String get swapActivityDeadlineOneMinute => '1min';

  @override
  String get swapActivityDepositAmount => 'Deposit amount';

  @override
  String get swapActivityDepositAssetFallback => 'deposit asset';

  @override
  String swapActivityDepositInstructionDepositLabel(String symbol) {
    return '$symbol deposit';
  }

  @override
  String get swapActivityDepositInstructionReuseWarning =>
      'Do not reuse this address';

  @override
  String swapActivityDepositInstructionSendFromSource(String symbol) {
    return 'Send $symbol from source chain';
  }

  @override
  String swapActivityDepositInstructionSourceDepositLabel(String symbol) {
    return '$symbol source deposit';
  }

  @override
  String swapActivityDepositInstructionSubmit(String symbol) {
    return 'Submit $symbol deposit';
  }

  @override
  String swapActivityDepositInstructionTxHashHint(String symbol) {
    return '$symbol source-chain transaction hash';
  }

  @override
  String swapActivityDepositInstructionTxHashLabel(String symbol) {
    return '$symbol deposit tx hash';
  }

  @override
  String get swapActivityDetailConfiguredQuote => 'Configured quote';

  @override
  String swapActivityDetailDeliveryTx(String symbol) {
    return '$symbol delivery tx';
  }

  @override
  String get swapActivityDetailDepositDeadline => 'Deposit deadline';

  @override
  String swapActivityDetailDepositTo(String symbol) {
    return 'Deposit $symbol to';
  }

  @override
  String swapActivityDetailDepositTx(String symbol) {
    return '$symbol deposit tx';
  }

  @override
  String get swapActivityDetailDetectedDeposit => 'Detected deposit';

  @override
  String get swapActivityDetailFees => 'Fees';

  @override
  String get swapActivityDetailGuaranteedMinimum => 'Guaranteed minimum';

  @override
  String get swapActivityDetailIncluded => 'Included';

  @override
  String get swapActivityDetailIncludedInRate => 'Included in shown rate';

  @override
  String get swapActivityDetailMemo => 'Memo';

  @override
  String get swapActivityDetailMissingDeposit => 'Missing deposit';

  @override
  String get swapActivityDetailNetworkConversionFees =>
      'Network + conversion fees';

  @override
  String get swapActivityDetailRate => 'Rate';

  @override
  String get swapActivityDetailRealizedSlippage => 'Realized slippage';

  @override
  String swapActivityDetailRecipient(String symbol) {
    return '$symbol recipient';
  }

  @override
  String swapActivityDetailRefundAddress(String symbol) {
    return '$symbol refund address';
  }

  @override
  String get swapActivityDetailRefundFee => 'Refund fee';

  @override
  String get swapActivityDetailRefundTo => 'Refund to';

  @override
  String get swapActivityDetailRefundedAmount => 'Refunded amount';

  @override
  String get swapActivityDetailRequiredDeposit => 'Required deposit';

  @override
  String get swapActivityDetailSlippageTolerance => 'Slippage tolerance';

  @override
  String swapActivityDetailSourceTxShielded(String symbol) {
    return '$symbol tx (shielded)';
  }

  @override
  String get swapActivityDetailSwapFee => 'Swap fee';

  @override
  String get swapActivityDetailTimestamp => 'Timestamp';

  @override
  String get swapActivityDetailTotalFees => 'Total fees';

  @override
  String get swapActivityDetailTxId => 'Tx ID';

  @override
  String get swapActivityExpectedToReceive => 'Expected to receive';

  @override
  String get swapActivityIncompleteDeposit => 'Incomplete deposit';

  @override
  String get swapActivityIncompletePayment => 'Incomplete payment';

  @override
  String get swapActivityLastCheckJustNow => 'Last check: just now';

  @override
  String swapActivityLastCheckMinutesAgo(int minutes) {
    return 'Last check: ${minutes}m ago';
  }

  @override
  String get swapActivityNotReported => 'Not reported';

  @override
  String get swapActivityPaidSuccessfullyTitle => 'Paid successfully';

  @override
  String get swapActivityPayInProgressTitle => 'Pay in progress...';

  @override
  String get swapActivityPayStatusCompleted => 'Completed';

  @override
  String get swapActivityPayStatusFailed => 'Failed';

  @override
  String get swapActivityPayStatusInProgress => 'In progress';

  @override
  String get swapActivityPayStatusRefunded => 'Refunded';

  @override
  String get swapActivityPaymentComplete => 'Payment complete';

  @override
  String get swapActivityPaymentFailed => 'Payment failed';

  @override
  String get swapActivityPaymentInProgress => 'Payment in progress';

  @override
  String get swapActivityPaymentProgressTab => 'Payment progress';

  @override
  String get swapActivityPaymentRefunded => 'Payment refunded';

  @override
  String swapActivityPickerNoRecipients(String symbol) {
    return 'No saved $symbol recipients';
  }

  @override
  String swapActivityPickerNoRefunds(String symbol) {
    return 'No saved $symbol refunds';
  }

  @override
  String swapActivityPickerRecipientsTitle(String symbol) {
    return '$symbol recipients';
  }

  @override
  String swapActivityPickerRefundsTitle(String symbol) {
    return '$symbol refunds';
  }

  @override
  String get swapActivityPrivatelyFromShielded =>
      'Privately, from shielded balance';

  @override
  String get swapActivityReceiveAssetFallback => 'receive asset';

  @override
  String get swapActivityRecipientGets => 'Recipient gets';

  @override
  String get swapActivityRecipientReceived => 'Recipient received';

  @override
  String swapActivityRefundToAddress(String address) {
    return 'Refund to: $address';
  }

  @override
  String swapActivityStateAddressHint(String chain) {
    return '$chain address';
  }

  @override
  String swapActivityStateAddressOrAccountHint(String chain) {
    return '$chain address or account';
  }

  @override
  String swapActivityStateAssetUnsupported(String symbol, String chain) {
    return '$symbol on $chain is not currently supported.';
  }

  @override
  String swapActivityStateDecimalPlaces(String symbol, int decimals) {
    return '$symbol supports up to $decimals decimal places.';
  }

  @override
  String get swapActivityStateDestination => 'Destination';

  @override
  String swapActivityStateQuoteHigher(String percent) {
    return 'Live quote is $percent% higher than the earlier estimate. Check the guaranteed minimum before you continue.';
  }

  @override
  String swapActivityStateQuoteLower(String percent) {
    return 'Live quote is $percent% lower than the earlier estimate. Check the guaranteed minimum before you continue.';
  }

  @override
  String swapActivityStateQuoteUsesDifferentSell(
    String liveAmount,
    String estimateAmount,
    String symbol,
  ) {
    return 'Live quote uses $liveAmount $symbol instead of $estimateAmount $symbol. Check the guaranteed minimum before you continue.';
  }

  @override
  String swapActivityStateRefundAddressLabel(String symbol) {
    return '$symbol refund address';
  }

  @override
  String get swapActivityStatusAwaitingDeposit => 'Awaiting deposit';

  @override
  String get swapActivityStatusAwaitingExternalDeposit =>
      'Awaiting external deposit';

  @override
  String get swapActivityStatusCheckingStatus => 'Checking status';

  @override
  String get swapActivityStatusComplete => 'Complete';

  @override
  String get swapActivityStatusDepositObserved => 'Deposit observed';

  @override
  String get swapActivityStatusExpired => 'Expired';

  @override
  String get swapActivityStatusProcessing => 'Processing';

  @override
  String get swapActivityStepConvert => 'Convert';

  @override
  String get swapActivityStepConvertDescription =>
      'Converting the shielded spend into the payment asset.';

  @override
  String get swapActivityStepConverting => 'Converting...';

  @override
  String swapActivityStepDeliver(String symbol) {
    return 'Deliver $symbol';
  }

  @override
  String swapActivityStepDeliverActive(String symbol) {
    return 'Deliver $symbol...';
  }

  @override
  String get swapActivityStepDeliverPayDescription =>
      'Delivering the payment to the recipient address.';

  @override
  String get swapActivityStepDeliverSwapDescription =>
      'Delivering the output asset to the recipient address.';

  @override
  String swapActivityStepDelivering(String symbol) {
    return 'Delivering $symbol...';
  }

  @override
  String swapActivityStepDeposit(String symbol) {
    return 'Deposit $symbol';
  }

  @override
  String get swapActivityStepDepositConfirmation => 'Deposit confirmation';

  @override
  String get swapActivityStepDepositConfirmationActive =>
      'Deposit confirmation...';

  @override
  String get swapActivityStepDepositConfirmationDescription =>
      'Confirming the deposit before the swap route starts.';

  @override
  String swapActivityStepDeposited(String symbol) {
    return '$symbol Deposited';
  }

  @override
  String swapActivityStepDepositing(String symbol) {
    return 'Depositing $symbol...';
  }

  @override
  String get swapActivityStepRecipientReceives => 'Recipient receives';

  @override
  String swapActivityStepRecipientReceivesAsset(String symbol) {
    return 'Recipient receives $symbol...';
  }

  @override
  String get swapActivityStepRecipientReceivesDescription =>
      'Confirming the recipient-side payment.';

  @override
  String swapActivityStepSend(String symbol) {
    return 'Send $symbol';
  }

  @override
  String swapActivityStepSendActive(String symbol) {
    return 'Send $symbol...';
  }

  @override
  String swapActivityStepSending(String symbol) {
    return 'Sending $symbol...';
  }

  @override
  String swapActivityStepSent(String symbol) {
    return '$symbol sent';
  }

  @override
  String get swapActivityStepSourceDescription =>
      'Confirm waiting for the source chain and provider to recognise the deposit';

  @override
  String swapActivityStepSpend(String symbol) {
    return 'Spend $symbol';
  }

  @override
  String get swapActivityStepSpendDescription =>
      'Spending from shielded balance.';

  @override
  String swapActivityStepSpending(String symbol) {
    return 'Spending $symbol...';
  }

  @override
  String swapActivityStepSpent(String symbol) {
    return '$symbol spent';
  }

  @override
  String get swapActivityStepSwap => 'Swap';

  @override
  String get swapActivityStepSwapActive => 'Swap...';

  @override
  String get swapActivityStepSwapDescription =>
      'The provider is executing the swap route.';

  @override
  String get swapActivitySwapCompleted => 'Swap completed';

  @override
  String get swapActivitySwapFailed => 'Swap failed';

  @override
  String get swapActivitySwapInProgress => 'Swap in progress...';

  @override
  String get swapActivitySwapProgressTab => 'Swap progress';

  @override
  String get swapActivitySwapRefunded => 'Swap refunded';

  @override
  String swapActivityToAddressOnChain(String address, String chain) {
    return 'To: $address on $chain';
  }

  @override
  String get swapActivityTooltipFees =>
      'Covers our fee and the route providers\' costs to process this swap. Already included in the rate above.';

  @override
  String swapActivityTooltipMinimumReceive(String symbol) {
    return 'The lowest amount of $symbol you\'ll get after slippage. You may get more, never less.';
  }

  @override
  String get swapActivityTooltipMinimumReceiveGeneric =>
      'The lowest amount you\'ll get after slippage. You may get more, never less.';

  @override
  String get swapActivityTooltipPriceProtection =>
      'How much of the received amount your slippage tolerance protects. The swap is refunded if the rate moves past this.';

  @override
  String get swapActivityTooltipStatusDetail =>
      'Details are based on the latest swap record and provider status.';

  @override
  String get swapActivityYouPaid => 'You paid';

  @override
  String get swapActivityYouPay => 'You pay';

  @override
  String get swapActivityYouReceived => 'You received';

  @override
  String get swapActivityYourePaying => 'You\'re paying';

  @override
  String get swapActivityYoureReceiving => 'You\'re receiving';

  @override
  String syncCheckingPercentSemantics(String percent) {
    return 'Checking $percent percent';
  }

  @override
  String syncCheckingProgress(String percent) {
    return '$percent% checking';
  }

  @override
  String get syncConnectingToTor => 'Connecting to Tor…';

  @override
  String get syncConnectingToTorSemantics => 'Connecting to Tor';

  @override
  String get syncErrorChainRecovery => 'Chain recovery';

  @override
  String get syncErrorData => 'Data error';

  @override
  String get syncErrorEndpoint => 'Endpoint error';

  @override
  String get syncErrorNetwork => 'Network error';

  @override
  String get syncErrorPrivateLookup => 'Private lookup';

  @override
  String get syncErrorUnknown => 'Unknown error';

  @override
  String get syncErrorWalletData => 'Wallet data error';

  @override
  String get syncErrorWalletDataBusy => 'Wallet data busy';

  @override
  String syncFailed(String reason) {
    return 'Syncing failed. $reason...';
  }

  @override
  String syncFailedSemantics(String reason) {
    return 'Syncing failed. $reason';
  }

  @override
  String get syncSynced => 'Synced';

  @override
  String syncSyncedAtBlock(String height) {
    return 'Synced at block $height';
  }

  @override
  String syncSyncingPercentSemantics(String percent) {
    return 'Syncing $percent percent';
  }

  @override
  String syncSyncingProgress(String percent) {
    return '$percent% Syncing...';
  }

  @override
  String get syncTorFailed => 'Tor couldn\'t connect...';

  @override
  String get syncTorFailedSemantics => 'Tor couldn\'t connect';

  @override
  String get syncVizorSynced => 'Vizor is synced';

  @override
  String get txFeeHelpTooltip =>
      'Fee paid to the Zcash network to process this transaction.';

  @override
  String get txFeeInfoDescription =>
      'The network fee is set by the Zcash protocol (ZIP 317) based on the transaction size. Vizor adds no extra fee.';

  @override
  String get txFeeInfoTitle => 'Tx fee';

  @override
  String get updateFailedMessage => 'Couldn\'t complete the update. Try again.';

  @override
  String get updateRestart => 'Restart';

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
