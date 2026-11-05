// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutBuiltByBody =>
      'We built Keplr, the wallet used by millions across Cosmos, Ethereum, and Bitcoin. Vizor is our take on what a Zcash wallet should feel like.';

  @override
  String get aboutBuiltByHeading => 'Built by the Keplr team';

  @override
  String get aboutLegalPlaceholderBody =>
      'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount.';

  @override
  String get aboutLegalPlaceholderHeading =>
      'From the team that brought you Keplr Wallet.';

  @override
  String aboutLinkSemantics(String label) {
    return '$label link';
  }

  @override
  String get aboutOpenGithub => 'Open Vizor GitHub';

  @override
  String get aboutOpenSourceBody =>
      'Vizor is Apache licensed. Your keys stay on your device.\nWe don\'t see your balances or your transactions.';

  @override
  String get aboutOpenSourceHeading => 'Open source, self-custodied';

  @override
  String get aboutOpenWebsite => 'Open Vizor website';

  @override
  String get aboutShieldedBody =>
      'Vizor is built around shielded transactions, where the sender, recipient, and amount stay private. Transparent Zcash works too, but private is the default.';

  @override
  String get aboutShieldedHeading => 'Designed for shielded Zcash';

  @override
  String get aboutTermsTitle => 'Terms of Usage';

  @override
  String get aboutTitle => 'About Vizor Wallet';

  @override
  String aboutVersionLabel(String version) {
    return 'Version: $version Public Beta';
  }

  @override
  String get aboutWebsite => 'Website';

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
  String get accountsTitle => 'Accounts';

  @override
  String get accountsUpdatePicture => 'Update picture';

  @override
  String get accountsViewSecretPhrase => 'View secret phrase';

  @override
  String get accountsViewViewingKey => 'View viewing key';

  @override
  String get activityAddressUnified => 'Unified address';

  @override
  String get activityBalanceFromOrchard => 'From Orchard balance';

  @override
  String get activityBalanceFromTransparent => 'From transparent balance';

  @override
  String get activityBalanceIronwood => 'Ironwood balance';

  @override
  String get activityBalanceOrchard => 'Orchard balance';

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
  String get activityEtaFunding => 'Est. 2–6 min';

  @override
  String get activityEtaNu7 => 'Est. under 1 min';

  @override
  String get activityEtaNu7Funding => 'Est. 1–2 min';

  @override
  String get activityEtaStandard => 'Est. 1–3 min';

  @override
  String get activityEtaTakingLonger => 'Taking longer';

  @override
  String get activityFeedEmpty => 'No activity yet';

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
  String get activityPayFromShielded => 'from shielded ZEC';

  @override
  String activityPayFromShieldedOnChain(String network) {
    return 'from shielded ZEC · $network';
  }

  @override
  String get activityPayIncomplete => 'Payment incomplete';

  @override
  String get activityPayPaid => 'Paid';

  @override
  String get activityPayPaying => 'Paying ...';

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
  String get activityReceiptNetChange => 'Net change';

  @override
  String get activityReceiptNetworkFee => 'Network fee';

  @override
  String get activityReceiptOutput => 'Output';

  @override
  String get activityReceiptRefreshFailed =>
      'Latest transaction status could not be refreshed.';

  @override
  String get activityReceiptStatus => 'Status';

  @override
  String get activityReceiptUnattributedFeeHelp =>
      'Total fee for this transaction. Your account\'s share of this fee is unknown.';

  @override
  String get activityReceiptUnknownFee => 'Unknown';

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
  String get activitySectionEarlier => 'Earlier';

  @override
  String get activitySectionThisWeek => 'This week';

  @override
  String get activitySenderShielded => 'Shielded sender';

  @override
  String get activitySenderUnknown => 'Unknown sender';

  @override
  String get activityStatusFailedFundsReturned => 'Failed, funds returned';

  @override
  String get activityStatusIncompleteDeposit => 'Incomplete deposit';

  @override
  String activitySwapAssetOnChain(String symbol, String chain) {
    return '$symbol on $chain';
  }

  @override
  String activitySwapDepositedAsset(String symbol) {
    return 'Deposited $symbol';
  }

  @override
  String activitySwapMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String activitySwapReceivedAsset(String symbol) {
    return 'Received $symbol';
  }

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
  String get activityTitleSendingVerb => 'Sending';

  @override
  String get activityTitleSent => 'Sent';

  @override
  String get activityTitleShielded => 'Shielded';

  @override
  String get activityTitleShieldingFailed => 'Shielding failed';

  @override
  String get activityTitleShieldingInProgress => 'Shielding in progress...';

  @override
  String get activityTitleShieldingVerb => 'Shielding';

  @override
  String get activityTitleTransaction => 'Transaction';

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
  String get addressBookClearAddress => 'Clear address';

  @override
  String get addressBookClearName => 'Clear name';

  @override
  String get addressBookClearSearch => 'Clear search';

  @override
  String addressBookContactActions(String label) {
    return '$label actions';
  }

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
  String get addressScanCloseScanner => 'Close scanner';

  @override
  String get addressScanDefaultCamera => 'Default camera';

  @override
  String get addressScanDeniedTitle => 'You\'ve denied Camera access';

  @override
  String get addressScanEnableWindowsAccess => 'Enable Windows camera access';

  @override
  String get addressScanGrantAccess => 'Grant access to your camera';

  @override
  String get addressScanLoadingCamera => 'Loading camera...';

  @override
  String get addressScanLoadingEllipsis => 'Loading...';

  @override
  String get addressScanNoCamera => 'No camera found';

  @override
  String get addressScanNoCameraOpened =>
      'No camera could be opened. Check that a camera is connected and not in use by another app.';

  @override
  String get addressScanOpenSettings => 'Open settings';

  @override
  String get addressScanTitle => 'Scan the address QR code';

  @override
  String get addressScanWindowsAccessHint =>
      'Turn on Camera access and Let desktop apps access your camera in Windows Settings.';

  @override
  String get addressScanZcashPrompt => 'Scan a Zcash QR code to continue';

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
  String get commonActionNeeded => 'Action needed';

  @override
  String get commonAddAMessage => 'Add a message';

  @override
  String get commonAddAccount => 'Add account';

  @override
  String get commonAddressCopied => 'Address copied';

  @override
  String commonAddressForChain(String chain) {
    return '$chain address';
  }

  @override
  String get commonAddressLabel => 'Address label';

  @override
  String get commonAmount => 'Amount';

  @override
  String get commonBack => 'Back';

  @override
  String commonBackTo(String destination) {
    return 'Back to $destination';
  }

  @override
  String get commonBackToWallet => 'Back to wallet';

  @override
  String get commonCameraDeniedTitle => 'You\'ve denied camera access';

  @override
  String get commonCameraRequestAgainHint =>
      'Request again, or enable manually\nin the System settings.';

  @override
  String get commonCameraRestrictedBody =>
      'Screen Time or device management\nis blocking the camera.';

  @override
  String get commonCameraRestrictedTitle => 'Camera access is restricted';

  @override
  String get commonCameraUnavailable => 'Camera unavailable';

  @override
  String get commonCameraUnavailableNow =>
      'The camera is unavailable right now.';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonCancelFailedRetry =>
      'Could not finish cancelling. Please try again.';

  @override
  String get commonCancellationFailed =>
      'Could not finish cancellation. Try again.';

  @override
  String get commonCancelling => 'Cancelling…';

  @override
  String get commonCannotBeUndone => 'This cannot be undone.';

  @override
  String get commonChainAndAddress => 'Chain & address';

  @override
  String get commonChangeContactPicture => 'Change contact picture';

  @override
  String get commonChecking => 'Checking...';

  @override
  String get commonCheckingEllipsis => 'Checking…';

  @override
  String get commonCheckingStatus => 'Checking status';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonClearContactLabel => 'Clear contact label';

  @override
  String get commonClearText => 'Clear text';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCloseMessage => 'Close message';

  @override
  String get commonCoinholderVoting => 'Coinholder voting';

  @override
  String get commonCompleted => 'Completed';

  @override
  String get commonContactLabelHint => 'Add label 1-20 characters';

  @override
  String get commonContacts => 'Contacts';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopyAddress => 'Copy address';

  @override
  String get commonCopyShieldedAddress => 'Copy shielded address';

  @override
  String get commonDismissNotification => 'Dismiss notification';

  @override
  String get commonDone => 'Done';

  @override
  String get commonDownload => 'Download';

  @override
  String get commonDurationOneHour => '1hr';

  @override
  String get commonDurationOneMinute => '1min';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonEnterAmountInUsd => 'Enter amount in USD';

  @override
  String get commonFailed => 'Failed';

  @override
  String get commonFeatureInProgress => 'This feature is still in progress.';

  @override
  String get commonFullAddress => 'Full address';

  @override
  String get commonGetSignature => 'Get signature';

  @override
  String get commonGoBack => 'Go back';

  @override
  String get commonGuaranteedMinimum => 'Guaranteed minimum';

  @override
  String get commonImporting => 'Importing...';

  @override
  String get commonInProgress => 'In progress';

  @override
  String get commonInformation => 'Information';

  @override
  String get commonJustNow => 'just now';

  @override
  String get commonKeepQrSteady => 'Keep the QR code steady and fully visible.';

  @override
  String get commonKeepScreenAwake => 'Keep screen awake';

  @override
  String get commonKeystoneAfterScan =>
      'After you scanned, click Get signature.';

  @override
  String get commonKeystoneScanSignatureResult =>
      'Open the signature result QR on Keystone, then scan again.';

  @override
  String get commonKeystoneScanTransaction =>
      'Use your Keystone wallet to scan this transaction QR code. Follow the steps on your device.';

  @override
  String get commonLedgerSigningFailed => 'Ledger signing failed';

  @override
  String get commonLoading => 'Loading';

  @override
  String get commonLoadingActivity => 'Loading activity';

  @override
  String get commonMemo => 'Memo';

  @override
  String get commonMessage => 'Message';

  @override
  String get commonMessageIsTooLong => 'Message is too long';

  @override
  String get commonNetworkConversionFees => 'Network + conversion fees';

  @override
  String get commonNoActiveAccount => 'No active account';

  @override
  String get commonNoActiveAccountSentence => 'No active account.';

  @override
  String get commonNotAvailableYet => 'Not available yet';

  @override
  String get commonNotEnoughZec => 'Not enough ZEC';

  @override
  String get commonOk => 'OK';

  @override
  String get commonPayInsufficientZec =>
      'You don\'t have enough ZEC for this payment. Try a smaller amount.';

  @override
  String get commonPaymentFailed => 'Payment failed';

  @override
  String get commonPaymentInProgress => 'Payment in progress';

  @override
  String get commonPaymentProgress => 'Payment progress';

  @override
  String get commonPaymentRefunded => 'Payment refunded';

  @override
  String get commonPaymentRequest => 'Payment request';

  @override
  String get commonPrivatelyFromShieldedBalance =>
      'Privately, from shielded balance';

  @override
  String get commonProvingParamsFailed =>
      'Required proving parameters could not be prepared.';

  @override
  String get commonQrNoAddress => 'QR code did not include an address.';

  @override
  String get commonQuit => 'Quit';

  @override
  String get commonRate => 'Rate';

  @override
  String get commonRecipientGets => 'Recipient gets';

  @override
  String get commonRefundFee => 'Refund fee';

  @override
  String get commonRefundTo => 'Refund to';

  @override
  String commonRefundToAddress(String address) {
    return 'Refund to: $address';
  }

  @override
  String get commonRefunded => 'Refunded';

  @override
  String get commonRefundedAmount => 'Refunded amount';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonRequestAgain => 'Request again';

  @override
  String get commonResetVizor => 'Reset Vizor';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRetrySaving => 'Retry saving';

  @override
  String get commonReturnHome => 'Return home';

  @override
  String get commonReviewAndFinish => 'Review & finish';

  @override
  String get commonReviewPayment => 'Review Payment';

  @override
  String get commonReviewQuote => 'Review quote';

  @override
  String get commonReviewSwap => 'Review swap';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSaveContact => 'Save contact';

  @override
  String get commonScanOriginalQr => 'Scan original QR';

  @override
  String get commonScanQrCode => 'Scan QR Code';

  @override
  String get commonSelectAccount => 'Select account';

  @override
  String get commonSelectContactPicture => 'Select contact picture';

  @override
  String get commonSelectRecipient => 'Select Recipient';

  @override
  String get commonSelectedContact => 'Selected contact';

  @override
  String get commonSendFailed => 'Send failed';

  @override
  String get commonSendZec => 'Send ZEC';

  @override
  String get commonSending => 'Sending...';

  @override
  String get commonSensitiveContentHidden => 'Sensitive content hidden';

  @override
  String get commonSentSuccessfully => 'Sent successfully';

  @override
  String get commonShieldedAddress => 'Shielded address';

  @override
  String get commonShieldedBalance => 'Shielded balance';

  @override
  String get commonShieldedSuccessfully => 'Shielded successfully';

  @override
  String get commonShielding => 'Shielding...';

  @override
  String get commonShowFullAddress => 'Show full address';

  @override
  String get commonSigningCancelledBeforeParams =>
      'Signing was cancelled before proving parameters were downloaded.';

  @override
  String get commonSigningExpired =>
      'Transaction expired before it could be signed.';

  @override
  String get commonSlippageTolerance => 'Slippage tolerance';

  @override
  String get commonSupportVizor => 'Support Vizor';

  @override
  String get commonSwapFailed => 'Swap failed';

  @override
  String get commonSwapFee => 'Swap fee';

  @override
  String get commonSwapProgress => 'Swap progress';

  @override
  String get commonSwapRefunded => 'Swap refunded';

  @override
  String commonSymbolRecipient(String symbol) {
    return '$symbol recipient';
  }

  @override
  String commonSymbolRefundAddress(String symbol) {
    return '$symbol refund address';
  }

  @override
  String get commonTimestamp => 'Timestamp';

  @override
  String get commonTo => 'To';

  @override
  String commonToAddressOnChain(String address, String chain) {
    return 'To: $address on $chain';
  }

  @override
  String get commonToggleFlashlight => 'Toggle flashlight';

  @override
  String get commonTransactionExpired => 'Transaction expired';

  @override
  String get commonTransactionHashCopied => 'Transaction hash copied';

  @override
  String get commonTransparentAddress => 'Transparent address';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonTxId => 'Tx ID';

  @override
  String get commonUnlockVizor => 'Unlock Vizor';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonUpdating => 'Updating...';

  @override
  String get commonWelcomeBack => 'Welcome Back';

  @override
  String get commonYouPay => 'You pay';

  @override
  String get commonYourePaying => 'You\'re paying';

  @override
  String get commonYoureReceiving => 'You\'re receiving';

  @override
  String get commonZcashAddress => 'Zcash address';

  @override
  String get donationDonatingTo => 'Donating to';

  @override
  String get donationEnterAmount => 'Enter your amount';

  @override
  String get donationPriceUnavailable => 'Price unavailable';

  @override
  String get donationReviewAmountTitle => 'Review Amount';

  @override
  String get donationSendingFrom => 'Sending from';

  @override
  String get donationSendingFromYour => 'Sending from your';

  @override
  String get donationSwitchCurrency => 'Switch between ZEC and USD';

  @override
  String get donationThanksTitle => 'Thank you for supporting Vizor';

  @override
  String get donationTotal => 'Total';

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
  String get homeShieldWaitingForPrivateRecovery =>
      'Private recovery is catching up with the latest block. Try again in a moment; your Keystone signature is kept.';

  @override
  String get homeShieldingBalance => 'Shielding your balance…';

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
  String get incomingLinkGiftBusy =>
      'Finish or cancel your current task to open this gift card.';

  @override
  String get incomingLinkGiftSetup =>
      'Finish account setup to open this gift card.';

  @override
  String get incomingLinkHomeBusy =>
      'Finish or cancel your task, then reopen the link.';

  @override
  String get incomingLinkHomeSetup =>
      'Finish account setup, then reopen the link.';

  @override
  String get incomingLinkPaymentBusy =>
      'Finish or cancel your current task to open this payment request.';

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
  String get keystoneAllowCamera => 'Allow camera';

  @override
  String get keystoneBatchCannotSignDeposit =>
      'This deposit uses inputs that Keystone batch signing cannot sign.';

  @override
  String get keystoneBatchCannotSignTx =>
      'This transaction uses inputs that Keystone batch signing cannot sign.';

  @override
  String get keystoneBatchTooManyInputsDeposit =>
      'This deposit uses too many inputs for Keystone batch signing. Try a smaller amount.';

  @override
  String get keystoneBatchTooManyInputsTx =>
      'This transaction uses too many inputs for Keystone batch signing. Try a smaller amount.';

  @override
  String get keystoneBirthdayInvalidHeight =>
      'That doesn\'t look like a valid block height.';

  @override
  String get keystoneBirthdaySubtitle =>
      'It helps us import your wallet faster.';

  @override
  String get keystoneCameraDefault => 'Default';

  @override
  String get keystoneCameraDeniedTitle => 'You\'ve denied the Camera access';

  @override
  String get keystoneCameraEnableBody =>
      'A camera is required to connect Keystone.\nYou can revert this in settings anytime later.';

  @override
  String get keystoneCameraEnableTitle => 'Enable camera access';

  @override
  String get keystoneCameraExternal => 'External';

  @override
  String get keystoneCameraFront => 'Front';

  @override
  String get keystoneCameraGiftBody =>
      'A camera is required to scan the gift card QR code.\nYou can revert this in settings anytime later.';

  @override
  String get keystoneCameraLabel => 'Camera';

  @override
  String keystoneCameraNameDefault(String name) {
    return '$name (Default)';
  }

  @override
  String get keystoneCameraNormal => 'Normal';

  @override
  String get keystoneCameraOffAllow =>
      'Camera access is off. Allow it in Settings to scan Keystone signatures.';

  @override
  String get keystoneCameraUnavailableBody =>
      'Keystone import uses camera QR scanning only.\nConnect a camera and try again.';

  @override
  String get keystoneCameraWide => 'Wide';

  @override
  String get keystoneCameraZoom => 'Zoom';

  @override
  String get keystoneConfirmSelection => 'Confirm selection';

  @override
  String get keystoneConfirmWithKeystone => 'Confirm with Keystone';

  @override
  String get keystoneDefaultCamera => 'Default camera';

  @override
  String get keystoneFirmwareBody =>
      'Make sure your Keystone is on the latest Cypherpunk firmware. ';

  @override
  String get keystoneFirmwareDownloadSemantics => 'Download Keystone firmware';

  @override
  String get keystoneFirmwareLinkLabel => 'link';

  @override
  String get keystoneFirmwareOpenPage => 'Open Keystone firmware page';

  @override
  String get keystoneFirmwareTitle => 'Check Keystone firmware';

  @override
  String get keystoneFirmwareUpdatePrefix =>
      'Update to the latest Keystone firmware at ';

  @override
  String get keystoneImReadyNow => 'I\'m ready now';

  @override
  String get keystoneLoadingCamera => 'Loading camera...';

  @override
  String get keystoneLoadingQrCode => 'Loading QR code ...';

  @override
  String get keystoneNextStep => 'Next step';

  @override
  String get keystoneNoCameraFound => 'No camera found';

  @override
  String get keystoneNoCameraOpened =>
      'No camera could be opened. Check that a camera is connected and not in use by another app.';

  @override
  String get keystoneOnVizor => 'On Vizor';

  @override
  String get keystoneOnYourKeystone => 'On your Keystone';

  @override
  String get keystoneOpenSettings => 'Open settings';

  @override
  String get keystoneOpenSignedQr =>
      'Open the signed transaction QR on Keystone, then scan again.';

  @override
  String get keystonePcztPrepareFailed =>
      'Keystone signing could not be prepared.';

  @override
  String get keystonePrepareSubtitle => 'Prepare your Keystone wallet';

  @override
  String get keystonePrepareToConnectTitle => 'Prepare to connect';

  @override
  String get keystonePreparingQr => 'Preparing QR';

  @override
  String get keystoneReadingQr => 'Reading QR...';

  @override
  String get keystoneReadingSignature => 'Reading signature...';

  @override
  String get keystoneScanCameraRequired =>
      'Keystone import uses camera QR scanning only. Connect a camera and try again.';

  @override
  String get keystoneScanCaption => 'Scan the Keystone account QR';

  @override
  String get keystoneScanCaptionConfirm =>
      'Scan the QR code on your Keystone to confirm';

  @override
  String get keystoneScanDecodeFailed =>
      'This QR code could not be decoded as a Keystone Zcash account.';

  @override
  String get keystoneScanHelpClose => 'Close scan help';

  @override
  String get keystoneScanIssuesTitle => 'Scanning issues?';

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
  String get keystoneScanPromptOnKeystone => 'on your Keystone,';

  @override
  String get keystoneScanPromptTap => 'Tap';

  @override
  String get keystoneScanPromptThenScan => 'then scan this QR code';

  @override
  String get keystoneScanReadingAccounts => 'Reading accounts...';

  @override
  String get keystoneScanWithKeystone => 'Scan with Keystone';

  @override
  String get keystoneSelectCamera => 'Select Camera';

  @override
  String get keystoneShowTransactionQr => 'Show transaction QR';

  @override
  String get keystoneSignatureQrNotDecoded =>
      'This QR code could not be decoded as a Keystone signature.';

  @override
  String get keystoneStepHowToConnect => 'How to Connect';

  @override
  String get keystoneStepOneOfTwo => 'Step 1/2';

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
  String get keystoneStepTwoOfTwo => 'Step 2/2';

  @override
  String get keystoneSubmittingTransaction => 'Submitting the transaction';

  @override
  String get keystoneTipContinuityCamera =>
      'On a Mac, you can use Continuity Camera to scan with your iPhone instead.';

  @override
  String get keystoneTipGiftFullScreen =>
      'Open the gift card QR code full screen on another device.';

  @override
  String get keystoneTipGiftMoveFurther =>
      'Move the QR code a few inches further from the camera so it can focus.';

  @override
  String get keystoneTipGlare =>
      'Make sure the room is well-lit and the QR code isn\'t reflecting glare.';

  @override
  String get keystoneTipMoveKeystoneFurther =>
      'Move your Keystone a few inches further from the camera so it can focus.';

  @override
  String get keystoneTipTapFullScreen =>
      'Tap the QR code on your Keystone to show it full screen. This is the easiest fix.';

  @override
  String get keystoneTroubleScanning => 'Trouble scanning?';

  @override
  String get keystoneTryAgainWithKeystone => 'Try again with Keystone';

  @override
  String get keystoneWindowsCameraBody =>
      'Turn on Camera access and Let desktop apps access your camera in Windows Settings.';

  @override
  String get keystoneWindowsCameraTitle => 'Enable Windows camera access';

  @override
  String languageSystemOption(String language) {
    return 'System ($language)';
  }

  @override
  String get ledgerAccountIndexFieldLabel => 'Ledger account index (0–100)';

  @override
  String get ledgerAccountIndexHint =>
      'Keep 0 unless you used a different index for this Ledger account.';

  @override
  String get ledgerAccountIndexLabel => 'Account index (0–100)';

  @override
  String get ledgerAccountIndexOutOfRange =>
      'Account index must be between 0 and 100.';

  @override
  String get ledgerAddAccountNote =>
      'View your balance and activity in Vizor. Transactions still need approval on Ledger.';

  @override
  String get ledgerAddAccountTitle => 'Add Ledger account';

  @override
  String get ledgerAdvancedOptions => 'Advanced options';

  @override
  String ledgerAppSemanticsLabel(String appName) {
    return '$appName app';
  }

  @override
  String get ledgerAppUpdateRequiredTitle => 'Ledger app update required';

  @override
  String get ledgerApproveShareViewingKey =>
      'Approve sharing your viewing key with Vizor.';

  @override
  String ledgerApproveShareViewingKeyForAccount(String number) {
    return 'Approve sharing the viewing key for Account #$number.';
  }

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
  String get ledgerBluetoothModelsList => 'Nano X, Flex, Stax, and Nano Gen5';

  @override
  String get ledgerBluetoothPermissionRequired =>
      'Bluetooth permission is required to find your Ledger. Allow it in Settings, then try again.';

  @override
  String get ledgerBtAccessAllowed =>
      'Permission is allowed. Try again when ready.';

  @override
  String get ledgerBtAccessBluetoothRequestable =>
      'Choose Allow permission to connect to your Ledger. If no prompt appears, open Settings.';

  @override
  String get ledgerBtAccessBluetoothSettings =>
      'Allow Bluetooth access for Vizor in your device settings.';

  @override
  String get ledgerBtAccessKindLocation => 'Location';

  @override
  String get ledgerBtAccessLocationRequestable =>
      'This Android version needs location permission to find your Ledger. Choose Allow permission, or open Settings if no prompt appears.';

  @override
  String get ledgerBtAccessLocationSettings =>
      'This Android version needs location permission to find your Ledger. Allow location access for Vizor in Settings.';

  @override
  String get ledgerBtAccessMacosSettings =>
      'Open System Settings > Privacy & Security > Bluetooth and allow access for Vizor.';

  @override
  String ledgerBtAccessRestricted(String kind) {
    return '$kind access is restricted by your device settings or administrator.';
  }

  @override
  String get ledgerBtAccessTurnOnBluetooth =>
      'Turn on Bluetooth, then check access again.';

  @override
  String get ledgerBtAccessTurnOnLocation =>
      'Turn on location services, then check access again.';

  @override
  String get ledgerBtCouldNotCheckAccess =>
      'Could not check access. Open Settings manually, then check again.';

  @override
  String get ledgerBtCouldNotOpenSettingsAllow =>
      'Could not open Settings. Open your device settings manually and allow access for Vizor.';

  @override
  String get ledgerBtCouldNotOpenSettingsRestricted =>
      'Could not open Settings. Open your device settings manually to review access for Vizor.';

  @override
  String get ledgerBtLabelAllowAccess => 'Allow access';

  @override
  String get ledgerBtLabelCheckAgain => 'Check again';

  @override
  String get ledgerBtLabelChecking => 'Checking access';

  @override
  String get ledgerBtLabelOpenSettings => 'Open settings';

  @override
  String get ledgerBtLabelReconnect => 'Reconnect';

  @override
  String get ledgerBtMsgBluetoothNeeded =>
      'Vizor needs Bluetooth access to connect to your Ledger.';

  @override
  String get ledgerBtMsgChecking =>
      'Checking whether Vizor can connect to your Ledger.';

  @override
  String get ledgerBtMsgLocationNeeded =>
      'This Android version needs location access to find your Ledger.';

  @override
  String get ledgerBtMsgReady =>
      'Turn on your Ledger and unlock it to continue.';

  @override
  String get ledgerBtRestrictedGeneric =>
      'Check Vizor’s Bluetooth access in Settings. Device restrictions or your administrator may prevent changes.';

  @override
  String get ledgerBtRestrictedLocation =>
      'Check location access for Vizor in Settings. Device restrictions or your administrator may prevent changes.';

  @override
  String get ledgerBtRestrictedMacos =>
      'Check Privacy & Security > Bluetooth in System Settings. This restriction may need to be changed by your administrator.';

  @override
  String get ledgerBtRestrictedNearby =>
      'Check Nearby devices access for Vizor in Settings. Device restrictions or your administrator may prevent changes.';

  @override
  String get ledgerBtSheetAllowAddAccount =>
      'Allow Bluetooth access for Vizor in your phone settings to add your account.';

  @override
  String get ledgerBtSheetAllowContinue =>
      'Allow Bluetooth access for Vizor in your phone settings to continue.';

  @override
  String get ledgerBtSheetAllowSigning =>
      'Allow Bluetooth access for Vizor in your phone settings to continue signing.';

  @override
  String get ledgerBtSheetReadyAddAccount =>
      'Bluetooth is available. Unlock your Ledger to add your account.';

  @override
  String get ledgerBtSheetReadyContinue =>
      'Bluetooth is available. Unlock your Ledger to continue.';

  @override
  String get ledgerBtSheetReadySigning =>
      'Bluetooth is available. Unlock your Ledger to continue signing.';

  @override
  String get ledgerBtSheetTurnOnAddAccount =>
      'Turn on Bluetooth on your phone to add your account.';

  @override
  String get ledgerBtSheetTurnOnContinue =>
      'Turn on Bluetooth on your phone to continue.';

  @override
  String get ledgerBtSheetTurnOnSigning =>
      'Turn on Bluetooth on your phone to continue signing.';

  @override
  String get ledgerBtTitleAllowBluetooth => 'Allow Bluetooth access';

  @override
  String get ledgerBtTitleAllowBluetoothSettings =>
      'Allow Bluetooth in Settings';

  @override
  String get ledgerBtTitleAllowLocation => 'Allow location access';

  @override
  String get ledgerBtTitleAllowLocationSettings => 'Allow location in Settings';

  @override
  String get ledgerBtTitleChecking => 'Checking Bluetooth access';

  @override
  String get ledgerBtTitleReady => 'Ready to reconnect';

  @override
  String get ledgerBtTitleRestricted => 'Access is restricted';

  @override
  String get ledgerBtTitleTurnOnBluetooth => 'Turn on Bluetooth';

  @override
  String get ledgerBtTitleTurnOnLocation => 'Turn on location services';

  @override
  String get ledgerButtonCheckingAccount => 'Checking account';

  @override
  String get ledgerButtonConnecting => 'Connecting';

  @override
  String get ledgerButtonSaving => 'Saving';

  @override
  String get ledgerButtonSearching => 'Searching';

  @override
  String get ledgerCancelFailed => 'Could not finish cancelling. Try again.';

  @override
  String get ledgerCancelShielding => 'Cancel shielding';

  @override
  String get ledgerCancellingRequest => 'Cancelling request';

  @override
  String get ledgerCancellingTheRequest => 'Cancelling the Ledger request…';

  @override
  String get ledgerCapabilityMainnetOnly =>
      'Ledger is currently supported only for Zcash mainnet.';

  @override
  String get ledgerCapabilityUnsupportedPlatform =>
      'Ledger is supported on Vizor for macOS, Windows, Linux, iOS, and Android.';

  @override
  String get ledgerChangedKeepOne =>
      'Your Ledger changed. Keep one Ledger connected and try again.';

  @override
  String get ledgerCheckingBluetoothAccess => 'Checking Bluetooth access…';

  @override
  String get ledgerCheckingUsb => 'Checking USB connection…';

  @override
  String get ledgerChooseAnother => 'Choose another Ledger';

  @override
  String get ledgerChooseConnection => 'Choose connection';

  @override
  String get ledgerChooseDevice => 'Choose a device to continue.';

  @override
  String get ledgerChooseLedgerForAccount =>
      'Choose the Ledger you want to use for this account.';

  @override
  String get ledgerCleanupFailed => 'Could not finish cleanup. Try again.';

  @override
  String get ledgerComeBackFindLedger =>
      'Keep your Ledger unlocked, then select Find Ledger below.';

  @override
  String get ledgerComeBackFindMyLedger =>
      'Keep your Ledger unlocked, then select “Find my Ledger” below.';

  @override
  String get ledgerComeBackReconnect => 'Come back and reconnect';

  @override
  String get ledgerCompletePairingOpenZcash =>
      'Complete pairing if prompted, then open the Zcash app and approve sharing the viewing key.';

  @override
  String get ledgerConfirmOpeningZcash => 'Confirm opening Zcash on Ledger.';

  @override
  String get ledgerConnectForAccount => 'Connect the Ledger for this account.';

  @override
  String get ledgerConnectSubtitle => 'Prepare your Ledger wallet.';

  @override
  String get ledgerConnectTitle => 'Connect Ledger';

  @override
  String get ledgerConnectUsbCable => 'Connect with a USB cable.';

  @override
  String ledgerConnectingTo(String device) {
    return 'Connecting to $device';
  }

  @override
  String get ledgerConnectionHelp => 'Connection help';

  @override
  String get ledgerContinueSigning => 'Continue signing';

  @override
  String get ledgerCouldNotConnect => 'Could not connect Ledger';

  @override
  String get ledgerCouldNotStopSearchTryAgain =>
      'Could not stop the search. Try again.';

  @override
  String get ledgerDifferentFromSaved => 'Different from saved connection';

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
  String ledgerFailureMsgAppUpdateRequired(String version) {
    return 'Update your Ledger and its Zcash app to $version or newer in Ledger Wallet.';
  }

  @override
  String get ledgerFailureMsgBusy =>
      'Your Ledger is busy. Try again in a moment.';

  @override
  String get ledgerFailureMsgCancelledTryAgain =>
      'Request cancelled. Try again when ready.';

  @override
  String get ledgerFailureMsgCheckOpenZcash =>
      'Check your Ledger and open the Zcash app, then try again.';

  @override
  String get ledgerFailureMsgDeclined =>
      'Declined on your Ledger. Try again when ready.';

  @override
  String get ledgerFailureMsgGiftCardRejected =>
      'Your Ledger couldn’t accept this request. Create a new gift card. Nothing was sent.';

  @override
  String get ledgerFailureMsgGiftCardTooLarge =>
      'Too large for your Ledger. Create a gift card with a smaller amount.';

  @override
  String get ledgerFailureMsgInstallZcash =>
      'Install the Zcash app with Ledger Wallet.';

  @override
  String get ledgerFailureMsgMemoHashUnsupported =>
      'Update the Ledger Zcash app to sign non-English memos';

  @override
  String get ledgerFailureMsgMigrationTooLarge =>
      'This migration step is too large for your Ledger to sign. Vizor can’t split it yet.';

  @override
  String get ledgerFailureMsgOpenZcash => 'Open the Zcash app on your Ledger.';

  @override
  String get ledgerFailureMsgOrchardChange =>
      'Ledger can\'t sign a transaction that keeps change in Orchard. Migrate your Orchard balance to Ironwood first.';

  @override
  String get ledgerFailureMsgPaymentTooLarge =>
      'Start a new payment. Don’t send a smaller amount to this address.';

  @override
  String get ledgerFailureMsgReconnectUnlock =>
      'Reconnect and unlock your Ledger.';

  @override
  String get ledgerFailureMsgRejectedNewRequest =>
      'Your Ledger couldn’t accept this request. Create a new one. Nothing was sent.';

  @override
  String get ledgerFailureMsgReopenZcash => 'Close and reopen the Zcash app.';

  @override
  String get ledgerFailureMsgSaplingRecipient =>
      'Your Ledger can’t send to a Sapling address. Create a new request.';

  @override
  String get ledgerFailureMsgSetPin =>
      'Set up a PIN on your Ledger, then try again.';

  @override
  String get ledgerFailureMsgShieldTooLarge =>
      'Too many inputs for your Ledger. Try again. Nothing was shielded.';

  @override
  String get ledgerFailureMsgSwapTooLarge =>
      'Start a new swap with a smaller amount. This one is discarded.';

  @override
  String get ledgerFailureMsgTooManyInputs =>
      'Too many inputs for your Ledger. Try a smaller amount.';

  @override
  String get ledgerFailureMsgUnexpected =>
      'Unexpected Ledger error. Reopen the Zcash app and try again.';

  @override
  String ledgerFailureMsgUnexpectedWithCode(String code) {
    return 'Unexpected Ledger error$code. Reopen the Zcash app and try again.';
  }

  @override
  String get ledgerFailureMsgUnlock => 'Unlock your Ledger, then try again.';

  @override
  String get ledgerFailureMsgUnsupportedTxType =>
      'Your Ledger can’t sign this transaction type. Create a new request.';

  @override
  String ledgerFailureMsgUpdateZcash(String version) {
    return 'Update the Zcash app to $version or newer.';
  }

  @override
  String get ledgerFailureMsgViewingKeyRejected =>
      'Your Ledger couldn’t accept this viewing-key request. Check the account number.';

  @override
  String get ledgerFailureMsgVoteRejected =>
      'Your Ledger couldn’t accept this vote request. Your vote was not signed.';

  @override
  String get ledgerFailureMsgVoteTooLarge =>
      'This vote is too large for your Ledger to sign.';

  @override
  String get ledgerFailureMsgWrongLedger =>
      'Connect the Ledger that holds this account.';

  @override
  String get ledgerFailureTitleBusy => 'Ledger is busy';

  @override
  String get ledgerFailureTitleCancelled => 'Request cancelled';

  @override
  String get ledgerFailureTitleError => 'Ledger error';

  @override
  String get ledgerFailureTitleFailed => 'Request failed';

  @override
  String get ledgerFailureTitleLocked => 'Ledger locked';

  @override
  String get ledgerFailureTitleNotReachable => 'Ledger not reachable';

  @override
  String get ledgerFailureTitleOpenZcash => 'Open the Zcash app';

  @override
  String get ledgerFailureTitlePinRequired => 'PIN required';

  @override
  String get ledgerFailureTitleRejected => 'Request not accepted';

  @override
  String get ledgerFailureTitleReopenZcash => 'Reopen the Zcash app';

  @override
  String get ledgerFailureTitleTooLarge => 'Request too large';

  @override
  String get ledgerFailureTitleUpdateZcash => 'Update the Zcash app';

  @override
  String get ledgerFailureTitleWrongLedger => 'Wrong Ledger';

  @override
  String get ledgerFailureTitleZcashMissing => 'Zcash app missing';

  @override
  String get ledgerFind => 'Find Ledger';

  @override
  String get ledgerFindMyLedger => 'Find my Ledger';

  @override
  String get ledgerFollowPromptsOnLedger => 'Follow the prompts on Ledger.';

  @override
  String get ledgerHelpChecksCloseOtherApps =>
      'Close other wallet apps and disconnect Ledger from other phones or computers.';

  @override
  String get ledgerHelpChecksHomeScreen =>
      'Leave Ledger on its home screen. Open the Zcash app when Vizor asks.';

  @override
  String get ledgerHelpChecksUnlockClose =>
      'Unlock Ledger, turn on Bluetooth, and keep it close to your phone.';

  @override
  String get ledgerHelpChooseModel => 'Choose your model';

  @override
  String get ledgerHelpFindInPhoneBluetooth =>
      'Find your Ledger in your phone’s Bluetooth settings.';

  @override
  String get ledgerHelpForgetAndroid =>
      'Bluetooth settings > the settings button next to your Ledger > Forget or Unpair';

  @override
  String get ledgerHelpForgetIos =>
      'Settings > Bluetooth > the info button next to your Ledger > Forget This Device';

  @override
  String get ledgerHelpKeepUnlockedHome =>
      'Keep Ledger unlocked with Bluetooth on, and leave it on its home screen.';

  @override
  String get ledgerHelpModelLabel => 'Ledger model';

  @override
  String get ledgerHelpNanoXConfirm =>
      'Confirm on Ledger and enter your PIN on the device.';

  @override
  String get ledgerHelpNanoXControls =>
      'Unlock Ledger. Hold both buttons to open its controls, then choose:';

  @override
  String get ledgerHelpNanoXMenuPath => 'Settings > Security > Reset pairings';

  @override
  String get ledgerHelpNanoXName =>
      'On your Nano X, hold both buttons for 2 seconds, then find Device Name.';

  @override
  String get ledgerHelpNextPhoneSettings => 'Next: phone settings';

  @override
  String get ledgerHelpNextSearchInVizor => 'Next: search in Vizor';

  @override
  String get ledgerHelpNextSearchTitle => 'Find your Ledger';

  @override
  String get ledgerHelpNotResetDevice =>
      'Use the Bluetooth pairing option, not Reset device. Your wallet and accounts stay unchanged.';

  @override
  String get ledgerHelpOpenBluetoothSettings => 'Open Bluetooth settings';

  @override
  String ledgerHelpOtherModelName(String model) {
    return 'On your $model, check Settings > Name.';
  }

  @override
  String get ledgerHelpRemovePairingOnLedger =>
      'Remove the saved pairing on Ledger, then remove it on your phone.';

  @override
  String get ledgerHelpRestartBothGuide =>
      'If it still does not appear, restart both devices and check Ledger’s official Bluetooth troubleshooting guide.';

  @override
  String get ledgerHelpSearchSelectOpenZcash =>
      'Search in Vizor and select your Ledger. Open the Zcash app when Vizor asks.';

  @override
  String get ledgerHelpSelectModelHint =>
      'Select your model to see its pairing removal instructions.';

  @override
  String get ledgerHelpShortIdName =>
      'If you haven’t named your Ledger, it may appear as a short ID, such as 01AB. Otherwise, look for the name you set.';

  @override
  String get ledgerHelpSkipIfNotListed =>
      'If Ledger is not listed, skip this step and continue.';

  @override
  String ledgerHelpStepBackInVizor(String step) {
    return 'Step $step of 3 · Back in Vizor';
  }

  @override
  String ledgerHelpStepOnLedger(String step) {
    return 'Step $step of 3 · On your Ledger';
  }

  @override
  String ledgerHelpStepOnPhone(String step) {
    return 'Step $step of 3 · On your phone';
  }

  @override
  String get ledgerHelpStillNotShowing => 'Still not showing?';

  @override
  String get ledgerHelpTouchControls =>
      'Unlock Ledger. From its home screen, tap the settings icon, then choose:';

  @override
  String get ledgerHelpTouchMenuPath => 'Bluetooth > Remove pairing';

  @override
  String get ledgerHelpTryRestart =>
      'Try restarting Ledger. If it stays missing, removing the saved Bluetooth pairing on both devices may help.';

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
  String get ledgerKeepItOpen => 'Keep it open on your Ledger.';

  @override
  String get ledgerKeepNearbyUnlocked =>
      'Keep your Ledger nearby and unlocked, with Bluetooth turned on.';

  @override
  String get ledgerKeepNearbyUnlockedShort =>
      'Keep your Ledger nearby and unlocked.';

  @override
  String get ledgerKeepZcashOpen => 'Keep Zcash open.';

  @override
  String get ledgerMacosBluetoothPrompt =>
      'macOS may ask for Bluetooth access. If prompted, allow access for Vizor.';

  @override
  String get ledgerMismatchChooseHolder =>
      'Choose the Ledger that holds this account. Your saved connection has not changed.';

  @override
  String get ledgerMismatchConnectHolder =>
      'Connect the Ledger that holds this account. Your saved connection hasn’t changed.';

  @override
  String get ledgerMobileAnotherRequestActive =>
      'Another Ledger request is still active. Complete or reject it on your Ledger, then try again.';

  @override
  String get ledgerMobileCheckBluetoothBelow =>
      'Check Bluetooth access below, then try connecting to your Ledger again.';

  @override
  String get ledgerMobileConnectionLost =>
      'The Bluetooth connection to your Ledger was lost or could not be established. Turn on and unlock your Ledger, keep it nearby, then try again.';

  @override
  String get ledgerMobilePairingInvalid =>
      'Your Bluetooth pairing is no longer valid. Forget this Ledger in your device’s Bluetooth settings, then reconnect.';

  @override
  String get ledgerMobilePairingNotCompleted =>
      'Bluetooth pairing was not completed. Reconnect your Ledger and approve the pairing request, then try again.';

  @override
  String get ledgerMobileRequestCancelled =>
      'The Ledger request was cancelled. Try again when ready.';

  @override
  String get ledgerMobileRequestRejected =>
      'The request was rejected on your Ledger. Try again when ready.';

  @override
  String get ledgerMobileTurnOnBluetooth =>
      'Turn on Bluetooth, then try again.';

  @override
  String get ledgerMobileTurnOnLocation =>
      'Turn on location services to find your Ledger on this Android version, then try again.';

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
  String ledgerOpenAppInstruction(String appName) {
    return 'Open the $appName app';
  }

  @override
  String ledgerOpenAppOnLedger(String appName) {
    return 'Open the $appName app on your Ledger.';
  }

  @override
  String get ledgerOpenBluetoothSettingsManually =>
      'Open Bluetooth settings manually to remove the old pairing.';

  @override
  String get ledgerOpenSettings => 'Open settings';

  @override
  String get ledgerOpenZcashThenTryAgain =>
      'Open the Zcash app, then try again.';

  @override
  String get ledgerOpeningConnectionHelp => 'Opening connection help…';

  @override
  String get ledgerPairingNoLongerRecognized =>
      'Your Ledger no longer recognizes this Bluetooth pairing.';

  @override
  String get ledgerPairingNoLongerRecognizedRemove =>
      'Your Ledger no longer recognizes this Bluetooth pairing. Remove the old pairing, then reconnect.';

  @override
  String ledgerProcedureStep(String step, String total) {
    return 'Step $step of $total';
  }

  @override
  String ledgerProcedureStepComplete(String step, String total) {
    return 'Step $step of $total, complete';
  }

  @override
  String get ledgerReadinessAppNotVerified =>
      'Vizor could not verify the Ledger Zcash app. Try again.';

  @override
  String get ledgerReadinessCouldNotPrepare =>
      'Vizor could not prepare the Ledger Zcash app. Try again.';

  @override
  String get ledgerReadinessOpenZcashApp =>
      'Open the Zcash app on your Ledger, then try again.';

  @override
  String get ledgerReadinessOperationCancelled =>
      'Ledger operation was cancelled.';

  @override
  String get ledgerReadinessReconnectUnlockTryAgain =>
      'Reconnect and unlock your Ledger, then try again.';

  @override
  String ledgerReadinessUpdateApp(String version) {
    return 'Update the Ledger Zcash app to version $version or newer.';
  }

  @override
  String get ledgerReadinessUsbPermission =>
      'Connect and unlock your Ledger over USB. If it is connected, install the Ledger udev rules on Linux, then unplug and reconnect it.';

  @override
  String get ledgerReadyContinueSigning =>
      'Your Ledger is ready. Continue signing when you’re ready.';

  @override
  String get ledgerReadyReviewOnLedger =>
      'Continue when you’re ready to review the transaction on your Ledger.';

  @override
  String get ledgerReconnectTitle => 'Reconnect Ledger';

  @override
  String get ledgerRemoveOldPairing => 'Remove the old pairing';

  @override
  String get ledgerRemovePairingIos =>
      'Open Settings > Bluetooth. If your Ledger is listed, tap its info button and forget the device.';

  @override
  String get ledgerRemovePairingMacos =>
      'Open System Settings > Bluetooth. If your Ledger is listed, remove its saved pairing.';

  @override
  String get ledgerRemovePairingOther =>
      'Open Bluetooth settings. If your Ledger is listed, remove its saved pairing.';

  @override
  String get ledgerResetBluetoothPairing => 'Reset Bluetooth pairing';

  @override
  String get ledgerReturningToOptions => 'Returning to connection options…';

  @override
  String get ledgerSavedFindAgain =>
      'This Ledger matches your account. Find it again to continue.';

  @override
  String get ledgerSavedMatchesFindAgain =>
      'This Ledger matches your account and is now saved. Find it again to continue.';

  @override
  String get ledgerSavingVerified =>
      'Your account matches. Saving the verified connection.';

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
  String get ledgerSigningApproveNextSeparately =>
      'You will approve the next transaction separately.';

  @override
  String get ledgerSigningApproveOrReject =>
      'Approve to sign, or reject to cancel.';

  @override
  String get ledgerSigningApproveToSign => 'Approve to sign.';

  @override
  String get ledgerSigningApproveToSignNext =>
      'Approve to sign.\n\nYou will approve the next transaction separately.';

  @override
  String get ledgerSigningApprovedFinishing =>
      'Approved on Ledger. Vizor is finishing the transaction.';

  @override
  String get ledgerSigningChangeConnection => 'Change connection';

  @override
  String get ledgerSigningCheckAmountRecipient =>
      'When prompted, check the amount and recipient on Ledger.';

  @override
  String get ledgerSigningCheckingZcashReady =>
      'Vizor is checking whether the Zcash app is ready.';

  @override
  String get ledgerSigningCloseSemantics => 'Close Ledger';

  @override
  String get ledgerSigningConfirmRequestReconnect =>
      'Confirm the request on your Ledger. Vizor will reconnect automatically.';

  @override
  String get ledgerSigningDeclined =>
      'Signing was declined on Ledger. Try again when you’re ready.';

  @override
  String get ledgerSigningFinishingRequest => 'Finishing the Ledger request.';

  @override
  String get ledgerSigningKeepLedgerConnected => 'Keep Ledger connected.';

  @override
  String get ledgerSigningKeepOpenWhileCancelling =>
      'Keep Vizor open while the Ledger request is cancelled.';

  @override
  String get ledgerSigningKeepVizorOpen => 'Keep Vizor open.';

  @override
  String get ledgerSigningKeepVizorOpenShort => 'Keep Vizor open';

  @override
  String get ledgerSigningMsgPreparing =>
      'Please wait while Vizor prepares your transaction.';

  @override
  String get ledgerSigningMsgReviewing =>
      'Review and approve when prompted on your Ledger.';

  @override
  String ledgerSigningMsgSending(String wait) {
    return '$wait Keep your Ledger connected.';
  }

  @override
  String get ledgerSigningSaving => 'Saving the signed transaction.';

  @override
  String get ledgerSigningStatusCheckingDevice => 'Checking device';

  @override
  String get ledgerSigningStatusOpeningZcash => 'Opening Zcash';

  @override
  String get ledgerSigningStatusPreparing => 'Preparing to sign';

  @override
  String get ledgerSigningStatusReview => 'Review on device';

  @override
  String get ledgerSigningStatusWait => 'Please wait';

  @override
  String get ledgerSigningStatusWaitingApproval => 'Waiting for your approval';

  @override
  String get ledgerSigningStepFinish => 'Finish transaction';

  @override
  String get ledgerSigningStepPrepare => 'Prepare transaction';

  @override
  String get ledgerSigningStepReview => 'Review on Ledger';

  @override
  String get ledgerSigningTitleChecking => 'Checking your Ledger';

  @override
  String get ledgerSigningTitleConfirmOnLedger => 'Confirm on your Ledger';

  @override
  String get ledgerSigningTitleConfirmOpening => 'Confirm opening Zcash';

  @override
  String get ledgerSigningTitleFinishing => 'Finishing transaction';

  @override
  String get ledgerSigningTitlePreparing => 'Preparing transaction';

  @override
  String get ledgerSigningTitleReviewing => 'Check your Ledger';

  @override
  String get ledgerSigningTitleSending => 'Processing with Ledger';

  @override
  String get ledgerSigningTitleSendingTx => 'Sending transaction';

  @override
  String get ledgerSigningTitleSign => 'Sign transaction';

  @override
  String ledgerSigningTransactionProgress(String current, String total) {
    return 'Transaction $current of $total';
  }

  @override
  String get ledgerSigningWaitInstruction =>
      'Ledger is preparing to sign. It may seem unresponsive for a few seconds.';

  @override
  String get ledgerStatusConnecting => 'Connecting…';

  @override
  String get ledgerStatusFollowPrompts => 'Follow the prompts on your Ledger';

  @override
  String get ledgerStatusOpeningBluetoothSettings =>
      'Opening Bluetooth settings…';

  @override
  String get ledgerStatusSavingConnection => 'Saving connection…';

  @override
  String get ledgerStatusSearchingNearby => 'Searching nearby…';

  @override
  String get ledgerStatusStillSearching => 'Still searching nearby…';

  @override
  String get ledgerStepApproveViewingKey => 'Approve viewing key';

  @override
  String ledgerStepOpenApp(String appName) {
    return 'Open $appName';
  }

  @override
  String get ledgerStepOpenZcash => 'Open Zcash';

  @override
  String get ledgerStopSearchFailedHelp =>
      'Could not stop the search. Try opening connection help again.';

  @override
  String get ledgerStoppingSearch => 'Stopping search';

  @override
  String get ledgerSupportedDevices => 'Supported devices';

  @override
  String get ledgerTitleConnectingToLedger => 'Connecting to your Ledger';

  @override
  String get ledgerTitleFindingLedger => 'Finding your Ledger';

  @override
  String get ledgerTitleLedgerConnected => 'Your Ledger is connected';

  @override
  String get ledgerTitleLedgerSaved => 'Ledger saved';

  @override
  String get ledgerTitleMismatch => 'This Ledger doesn’t match';

  @override
  String get ledgerTitlePairAgain => 'Pair your Ledger again';

  @override
  String get ledgerTitleSavingConnection => 'Saving your connection';

  @override
  String get ledgerTitleSelectYourLedger => 'Select your Ledger';

  @override
  String get ledgerTransportBluetooth => 'Bluetooth';

  @override
  String get ledgerTransportUsb => 'USB';

  @override
  String get ledgerUnlockBluetoothNearby =>
      'Unlock Ledger, turn on Bluetooth, and keep it nearby.';

  @override
  String get ledgerUnlockEnableBluetoothNearby =>
      'Unlock Ledger, enable Bluetooth and keep it nearby.';

  @override
  String get ledgerUnlockOpenZcashApprove =>
      'Unlock your Ledger and open the Zcash app. Approve opening it if prompted.';

  @override
  String get ledgerUnlockWithPin => 'Unlock with your PIN.';

  @override
  String get ledgerUsbApproveOpening =>
      'Approve opening the Zcash app on your Ledger.';

  @override
  String get ledgerUsbCheckCableOpenApp =>
      'Check the USB cable, unlock your Ledger, and open the Zcash app.';

  @override
  String get ledgerUsbConnectUnlockOpen =>
      'Connect your Ledger with a USB cable, unlock it, and open the Zcash app.';

  @override
  String get ledgerUsbConnection => 'USB connection';

  @override
  String get ledgerUsbCouldNotOpen =>
      'Vizor found your Ledger but could not open it. Close other wallet apps that use the Ledger, reconnect it, then try again.';

  @override
  String get ledgerUsbCouldNotStart =>
      'Vizor could not start USB access for your Ledger. Reconnect the device, then try again.';

  @override
  String ledgerUsbInterrupted(String instruction) {
    return 'The USB connection to your Ledger was interrupted. Reconnect and unlock your Ledger. $instruction';
  }

  @override
  String get ledgerUsbPermissionLinux =>
      'Vizor cannot access your Ledger over USB. Install Ledger\'s udev rules for Linux (github.com/LedgerHQ/udev-rules), then reconnect your Ledger and try again.';

  @override
  String get ledgerUsbPermissionOther =>
      'Vizor cannot access your Ledger over USB. Check USB device permissions, then reconnect and try again.';

  @override
  String get ledgerVerifyingNewDevice =>
      'Complete pairing if prompted, then approve sharing your viewing key.';

  @override
  String get ledgerVerifyingSavedDevice =>
      'Unlock Ledger and confirm opening Zcash if prompted.';

  @override
  String get ledgerVizorCheckingZcash => 'Vizor is checking the Zcash app.';

  @override
  String get ledgerWaitingForApproval => 'Waiting for approval…';

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
  String get lockSyncingMessage => 'Vizor is syncing';

  @override
  String get lockUnlockToContinue => 'Unlock to continue';

  @override
  String get lockUnlockToContinueBody => 'Unlock Vizor to continue';

  @override
  String get lockUnlockToContinuePausedBody => 'Unlock Vizor to continue.';

  @override
  String migrationAboutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '~$count minutes',
      one: '~1 minute',
    );
    return '$_temp0';
  }

  @override
  String get migrationAnalyzingBalance => 'Analyzing your balance...';

  @override
  String get migrationAnalyzingCaption =>
      'Vizor is working hard to find a perfect balance\nof safety, privacy, and speed for your migration';

  @override
  String get migrationAnalyzingFindingBatches => 'Finding private batches...';

  @override
  String get migrationAnalyzingPreparingPlan =>
      'Preparing your migration plan...';

  @override
  String get migrationAnalyzingSemanticsLabel =>
      'Preparing private migration plan';

  @override
  String get migrationAnnouncementBody =>
      'Ironwood is the latest Zcash shielded pool.\nIt\'s the first formally verified pool with\ncutting edge cryptography.';

  @override
  String get migrationAnnouncementReleaseNote => 'Official Release Note';

  @override
  String get migrationAnnouncementStart => 'Start Migration';

  @override
  String get migrationBackAbout => 'About Migration';

  @override
  String get migrationBackHome => 'Back home';

  @override
  String get migrationBackHowItWorks => 'How Migration Works';

  @override
  String get migrationBackOptions => 'Migration Options';

  @override
  String get migrationBatchBroadcasting => 'Broadcasting...';

  @override
  String migrationBatchCardTitle(String number, String count) {
    return 'Batch #$number ($count notes)';
  }

  @override
  String get migrationBatchConfirming => 'Confirming...';

  @override
  String migrationBlockHeight(String height) {
    return 'Block $height';
  }

  @override
  String migrationBlocksEstimate(String blocks) {
    return '~$blocks blocks';
  }

  @override
  String migrationBroadcastApproxInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '~in $count hrs',
      one: '~in 1 hr',
    );
    return '$_temp0';
  }

  @override
  String migrationBroadcastApproxInMinutes(int count) {
    return '~in $count min';
  }

  @override
  String get migrationBroadcastConfirmed => 'Confirmed';

  @override
  String get migrationBroadcastDueNow => 'Due now';

  @override
  String migrationBroadcastInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in $count hrs',
      one: 'in 1 hr',
    );
    return '$_temp0';
  }

  @override
  String migrationBroadcastInMinutes(int count) {
    return 'in $count min';
  }

  @override
  String get migrationBroadcastPending => 'Pending';

  @override
  String get migrationBroadcastSubmitted => 'Submitted';

  @override
  String get migrationCarouselPreparationLabel =>
      'Migration preparation information';

  @override
  String get migrationCarouselProgressLabel => 'Migration information';

  @override
  String get migrationCompleteBody =>
      'Migration completed successfully and you can\nspend your funds as usual.';

  @override
  String migrationCompleteTitle(String amount) {
    return 'Your\n$amount ZEC\nare on Ironwood!';
  }

  @override
  String get migrationConfirming => 'Confirming';

  @override
  String get migrationContinueMigration => 'Continue migration';

  @override
  String get migrationContinuing => 'Continuing...';

  @override
  String get migrationCtaStart => 'Migrate to Ironwood Pool';

  @override
  String get migrationCtaStopped => 'Migration stopped by network upgrade';

  @override
  String get migrationCurrentBatch => 'Current Batch';

  @override
  String migrationDurationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '~$count days',
      one: '~1 day',
    );
    return '$_temp0';
  }

  @override
  String migrationDurationHalfHours(String hours) {
    return '~$hours.5 hrs';
  }

  @override
  String migrationDurationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '~$count hrs',
      one: '~1 hr',
    );
    return '$_temp0';
  }

  @override
  String migrationDurationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '~$count mins',
      one: '~1 min',
    );
    return '$_temp0';
  }

  @override
  String get migrationErrorBroadcast =>
      'Couldn\'t broadcast the migration transaction. Try again.';

  @override
  String get migrationErrorContinue =>
      'Couldn\'t continue migration. Try again.';

  @override
  String get migrationErrorKeystonePrepare =>
      'Couldn\'t prepare Keystone signing.';

  @override
  String get migrationErrorLedgerExcluded =>
      'Ledger private migration is excluded because the current flow requires batched signing.';

  @override
  String get migrationErrorPlanChanged =>
      'The amount or fee changed. Review the updated details.';

  @override
  String get migrationErrorStart => 'Couldn\'t start migration. Try again.';

  @override
  String get migrationErrorUnlockBeforeContinue =>
      'Unlock Vizor before continuing migration.';

  @override
  String get migrationErrorUnlockBeforeStart =>
      'Unlock Vizor before starting migration.';

  @override
  String get migrationErrorWaitForSync =>
      'Wait for sync to finish, then try again.';

  @override
  String get migrationEstimateAfterSigning => 'After signing';

  @override
  String get migrationEstimateComplete => 'Complete';

  @override
  String migrationEstimateIn(String estimate) {
    return 'in $estimate';
  }

  @override
  String migrationEstimateInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in ~$count days',
      one: 'in ~1 day',
    );
    return '$_temp0';
  }

  @override
  String migrationEstimateInHours(String hours) {
    return 'in ~$hours hours';
  }

  @override
  String migrationEstimateInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in ~$count minutes',
      one: 'in ~1 minute',
    );
    return '$_temp0';
  }

  @override
  String get migrationEstimateInOneHour => 'in ~1 hour';

  @override
  String get migrationEstimatedArrivalTime => 'Estimated arrival time';

  @override
  String get migrationExpectKeepRunningBody =>
      'Your computer needs to be unlocked with Vizor running so we can send the next migration transaction';

  @override
  String get migrationExpectLongBody =>
      'Ironwood migrations can take anywhere from several hours up to a couple days depending on your migration amount.';

  @override
  String get migrationExpectLongTitle => 'Migrations can take a long time';

  @override
  String get migrationExpectSpendBody =>
      'Each confirmed Ironwood amount is available to spend while the rest of the migration continues.';

  @override
  String get migrationExpectSpendTitle => 'You can spend as funds arrive';

  @override
  String get migrationExpectTitle => 'What to expect';

  @override
  String get migrationExpectVpnBody =>
      'It’s recommended to run the migration behind a trustable VPN/network privacy layer';

  @override
  String get migrationExpectVpnTitle => 'Use VPN for an extra privacy';

  @override
  String get migrationFlowTitle => 'Ironwood Migration';

  @override
  String get migrationGoHome => 'Go home';

  @override
  String get migrationHowDelayedBody =>
      'Vizor slowly sends parts at staggered intervals across multiple batches to reduce traceability.';

  @override
  String get migrationHowDelayedTitle => 'Delayed and randomized migrations';

  @override
  String get migrationHowFrozenBody =>
      'A one-time migration to Ironwood is required to spend your existing shielded balance.';

  @override
  String get migrationHowFrozenTitle =>
      'Orchard (legacy shielded) balance is frozen';

  @override
  String get migrationHowPreparationBody =>
      'Vizor splits your total balance into many smaller notes (e.g. 0.1 ZEC / 1 ZEC / 5 ZEC) before migrating.';

  @override
  String get migrationHowPreparationTitle => 'Pre-migration preparations';

  @override
  String migrationHowStepLabel(String number) {
    return 'Step $number';
  }

  @override
  String migrationHowStepSemanticsCurrent(
    String number,
    String total,
    String title,
    String body,
  ) {
    return 'Migration step $number of $total. $title. $body';
  }

  @override
  String migrationHowStepSemanticsShow(String number, String total) {
    return 'Show migration step $number of $total';
  }

  @override
  String get migrationHowTitle => 'How the Migration Works';

  @override
  String get migrationImmediateAmount => 'Amount';

  @override
  String get migrationImmediateAuthoriseAnyway => 'Authorise anyway';

  @override
  String get migrationImmediateAuthorising => 'Authorising…';

  @override
  String get migrationImmediateAuthorisingSemantics => 'Authorising migration';

  @override
  String get migrationImmediateCalculating => 'Calculating…';

  @override
  String get migrationImmediateConsiderOther => 'Consider another option';

  @override
  String get migrationImmediateFees => 'Fees (estimate)';

  @override
  String get migrationImmediateNoBalance =>
      'No spendable Orchard balance is available for Immediate migration.';

  @override
  String get migrationImmediatePlanFailed =>
      'Couldn\'t calculate the Immediate migration plan. Sync and try again.';

  @override
  String get migrationImmediateRetryCalculation => 'Retry calculation';

  @override
  String get migrationImmediateReviewTitle => 'Review Migration Plan';

  @override
  String get migrationImmediateTradeoffEmphasis =>
      'easier to associate with your wallet.';

  @override
  String migrationImmediateTradeoffLead(String amount) {
    return 'Crosses in one visible step — your $amount and timing are ';
  }

  @override
  String get migrationImmediateTradeoffLedger =>
      '\nPrivate migration is not available for Ledger accounts.';

  @override
  String get migrationImmediateTradeoffPrivate =>
      '\nConsider choosing a Private Migration option.';

  @override
  String get migrationImmediateTradeoffTitle => 'Privacy trade-off';

  @override
  String get migrationImmediateUnavailable => 'Unavailable';

  @override
  String migrationInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '~in $count minutes',
      one: '~in 1 minute',
    );
    return '$_temp0';
  }

  @override
  String get migrationIntroAnnouncement => 'Official Announcement';

  @override
  String get migrationIntroBadge => 'Zcash Network Upgrade';

  @override
  String migrationIntroBody(String amount) {
    return 'Your $amount ZEC is currently in Orchard.\nTo keep using these funds for shielded payments, you will need to move them to Ironwood. You will review the migration plan before any funds move.';
  }

  @override
  String get migrationIntroTagline => 'A new shielded pool for Zcash.';

  @override
  String get migrationKeystoneAfterScanInstruction =>
      'After you scanned, click Get signature.';

  @override
  String get migrationKeystoneApplyingSignature =>
      'Applying the Keystone signature.';

  @override
  String get migrationKeystoneApplyingToPlan =>
      'Applying the Keystone signature to your migration plan.';

  @override
  String get migrationKeystoneBackToReview => 'Back to review';

  @override
  String get migrationKeystoneBackToStatus => 'Back to status';

  @override
  String get migrationKeystoneBeginSigning => 'Begin signing';

  @override
  String get migrationKeystoneCamera => 'Camera';

  @override
  String get migrationKeystoneCameraAccess =>
      'Allow camera access to scan the signed Keystone QR.';

  @override
  String get migrationKeystoneCameraOnly =>
      'Keystone migration signing uses camera QR scanning only. Connect a camera and try again.';

  @override
  String get migrationKeystoneCancelFailed =>
      'Could not cancel the signing request. Try again.';

  @override
  String get migrationKeystoneClickToEnlarge => 'Click QR to enlarge';

  @override
  String get migrationKeystoneConfirmTitle => 'Confirm Migration with Keystone';

  @override
  String get migrationKeystoneEnlargeQr => 'Enlarge Keystone request QR';

  @override
  String get migrationKeystoneEnlargedQr => 'Enlarged Keystone request QR';

  @override
  String get migrationKeystoneFirmwareUpdate =>
      'Update Keystone firmware to sign Ironwood migrations, then try again.';

  @override
  String get migrationKeystoneGetSignature => 'Get signature';

  @override
  String get migrationKeystoneKeepQrSteady =>
      'Keep the QR code steady and fully visible.';

  @override
  String get migrationKeystoneMobileTitle => 'Keystone migration';

  @override
  String get migrationKeystoneNotKeystone =>
      'Use a Keystone account to sign this migration.';

  @override
  String get migrationKeystoneOpenSignedQr =>
      'Open the signed migration QR on Keystone, then scan again.';

  @override
  String get migrationKeystonePlanBody =>
      'Each round uses one animated request QR and one signed response QR.';

  @override
  String get migrationKeystonePlanTitle => 'Keystone signing plan';

  @override
  String get migrationKeystonePrepareFailed =>
      'Keystone signing could not be prepared. Try again.';

  @override
  String get migrationKeystonePrepareWallet => 'Prepare your Keystone wallet';

  @override
  String get migrationKeystonePreparing => 'Preparing';

  @override
  String get migrationKeystonePreparingQr => 'Preparing QR codes...';

  @override
  String get migrationKeystoneProofFailed =>
      'Vizor could not prepare local proofs. Go back and prepare this request again.';

  @override
  String get migrationKeystoneProofWaiting =>
      'Signature captured. Vizor is still preparing local proofs. Keep this screen open.';

  @override
  String migrationKeystoneProofWaitingProgress(String ready, String total) {
    return 'Signature captured. Vizor is still preparing local proofs ($ready/$total). Keep this screen open.';
  }

  @override
  String get migrationKeystoneProofsPreparing => 'Preparing local proofs';

  @override
  String get migrationKeystoneProofsPreparingEllipsis =>
      'Preparing local proofs...';

  @override
  String migrationKeystoneProofsProgress(String ready, String total) {
    return 'Preparing local proofs $ready/$total';
  }

  @override
  String get migrationKeystoneQrBodyCombined =>
      'Scan this request with Keystone to sign the preparation transactions and migration batches together.';

  @override
  String get migrationKeystoneQrBodyImmediate =>
      'Scan the QR code with your Keystone wallet to confirm migration.';

  @override
  String get migrationKeystoneQrBodyRound =>
      'Scan this request QR with Keystone. Keystone will show a new signed QR when it finishes.';

  @override
  String get migrationKeystoneReadingSignature => 'Reading signature...';

  @override
  String get migrationKeystoneRequestCancelled =>
      'This signing request was cancelled. Prepare it again.';

  @override
  String get migrationKeystoneRequestExpired =>
      'This Keystone signing request expired. Prepare it again.';

  @override
  String get migrationKeystoneRequestQr => 'Request QR';

  @override
  String get migrationKeystoneRequestUnusable =>
      'This Keystone signing request can no longer be used. Prepare it again.';

  @override
  String migrationKeystoneRound(String current, String total) {
    return 'Round $current of $total';
  }

  @override
  String migrationKeystoneRoundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count QR signing rounds',
      one: '1 QR signing round',
    );
    return '$_temp0';
  }

  @override
  String get migrationKeystoneScanIssuesBody =>
      'There may be a newer version of Keystone Cypherpunk firmware available. Check if you have the latest version.';

  @override
  String get migrationKeystoneScanIssuesConfirm => 'Ok, I will check';

  @override
  String get migrationKeystoneScanIssuesTitle =>
      'Having issues with scanning the QR code?';

  @override
  String get migrationKeystoneScanNewQr =>
      'Scan the new signed QR shown on Keystone.';

  @override
  String get migrationKeystoneScanQrCode => 'Scan QR Code';

  @override
  String get migrationKeystoneScanRequest => 'Scan request with Keystone';

  @override
  String get migrationKeystoneScanSignature => 'Scan Keystone signature';

  @override
  String get migrationKeystoneScanSubtitle => 'Scan with your Keystone';

  @override
  String get migrationKeystoneSignBatch => 'Sign Ironwood batch';

  @override
  String get migrationKeystoneSignMigration => 'Sign migration';

  @override
  String get migrationKeystoneSignPrivateSplit => 'Sign private split';

  @override
  String get migrationKeystoneSignatureFailed =>
      'Keystone signature could not be applied.';

  @override
  String migrationKeystoneSignsAll(String transactions) {
    return 'Signs $transactions';
  }

  @override
  String migrationKeystoneSignsSome(String count, String transactions) {
    return 'Signs $count of $transactions';
  }

  @override
  String get migrationKeystoneToolbarReview => 'Review migration';

  @override
  String get migrationKeystoneToolbarStatus => 'Migration status';

  @override
  String migrationKeystoneTransactionTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions total',
      one: '1 transaction total',
    );
    return '$_temp0';
  }

  @override
  String migrationKeystoneTransactions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions',
      one: '1 transaction',
    );
    return '$_temp0';
  }

  @override
  String get migrationKeystoneTryAfterSync => 'Try again after sync finishes.';

  @override
  String get migrationKeystoneUnavailableTitle =>
      'Keystone signing unavailable';

  @override
  String get migrationKeystoneUnlockFirst =>
      'Unlock Vizor before signing migration.';

  @override
  String get migrationKeystoneWaitingForProofsLong =>
      'Signature captured. Vizor will continue when local proofs are ready.';

  @override
  String get migrationKeystoneWaitingForProofsShort =>
      'Signature captured. Waiting for local proofs.';

  @override
  String get migrationKeystoneWrongRound =>
      'This signed QR is from another round. Go back, scan the current request with Keystone, then scan its new signed QR.';

  @override
  String get migrationLedgerBroadcast =>
      'The migration transaction could not be broadcast.';

  @override
  String get migrationLedgerConnect =>
      'Connect and unlock your Ledger, then open the Zcash app.';

  @override
  String get migrationLedgerFailed =>
      'Ledger migration could not be completed.';

  @override
  String get migrationLedgerFailedTitle => 'Ledger migration failed';

  @override
  String get migrationLedgerPlanChanged =>
      'The amount or fee changed. Return and review the updated plan.';

  @override
  String get migrationLedgerProofs =>
      'Vizor could not finish preparing migration proofs.';

  @override
  String get migrationLedgerRejected =>
      'The migration transaction was rejected on your Ledger.';

  @override
  String get migrationLedgerTitle => 'Migrate with Ledger';

  @override
  String migrationLeftToTransfer(String amount) {
    return 'Left to transfer: $amount';
  }

  @override
  String get migrationManage => 'Manage';

  @override
  String get migrationManageCancelling => 'Cancelling...';

  @override
  String get migrationManageCannotCancel =>
      'This migration can no longer be cancelled.';

  @override
  String get migrationManageConfirm => 'Confirm';

  @override
  String get migrationManageImmediateBullet1 =>
      'Remaining split notes will be processed as an immediate migration, slightly increasing traceability';

  @override
  String get migrationManageImmediateBullet2 =>
      'Transactions already broadcast will not be reverted';

  @override
  String get migrationManageImmediateBullet3 =>
      'There’s no way to revert an immediate migration';

  @override
  String get migrationManageImmediateIntro =>
      'Process the remaining migration immediately.';

  @override
  String get migrationManageLoading => 'Loading...';

  @override
  String get migrationManageNoBalance =>
      'There is no remaining Orchard balance to migrate.';

  @override
  String get migrationManageStop => 'Stop Migration';

  @override
  String get migrationManageStopBody =>
      'This cancels the remaining scheduled migration transactions. You can re-start the migration from the home page.';

  @override
  String get migrationManageStopTitle => 'Are you sure you want to stop?';

  @override
  String get migrationManageStopping => 'Stopping...';

  @override
  String get migrationManageSwitchImmediate => 'Switch to Immediate';

  @override
  String get migrationManageTitle => 'Manage Migration';

  @override
  String get migrationManageUpdateFailed =>
      'The migration could not be updated. Please try again.';

  @override
  String get migrationMobileActionAllTransactions => 'All transactions';

  @override
  String migrationMobileActionBatch(int number) {
    return 'Batch #$number';
  }

  @override
  String get migrationMobileActionInProgress => 'Migration action in progress';

  @override
  String get migrationMobileActionNeedSignature =>
      'Transactions needing signature';

  @override
  String migrationMobileActionPrepareBatch(int number) {
    return 'Prepare batch #$number';
  }

  @override
  String migrationMobileActionPreparingBatch(int number) {
    return 'Preparing batch #$number...';
  }

  @override
  String get migrationMobileActionResign => 'Re-sign migration transactions';

  @override
  String get migrationMobileActionSign => 'Sign migration transactions';

  @override
  String migrationMobileActionSignBatch(int number) {
    return 'Sign batch #$number';
  }

  @override
  String get migrationMobileActionSubmitScheduled =>
      'Submit scheduled transaction';

  @override
  String get migrationMobileActionSubmittingScheduled =>
      'Submitting scheduled transaction...';

  @override
  String get migrationMobileAnnouncementBody =>
      'Zcash’s latest shielded pool, bringing cutting-edge cryptography and formal verification.\n\nYour shielded balance needs a one-time migration to Ironwood.';

  @override
  String get migrationMobileAnnouncementOfficial => 'Official announcement';

  @override
  String get migrationMobileAnnouncementUpgrade => 'Upgrade to Ironwood';

  @override
  String get migrationMobileAttentionContinueTitle => 'Continue your migration';

  @override
  String get migrationMobileAttentionLateTitle =>
      'A migration transaction needs attention';

  @override
  String get migrationMobileAttentionLater => 'I’ll visit later';

  @override
  String get migrationMobileAttentionOpen => 'Go to migration page';

  @override
  String get migrationMobileAttentionProofTitle =>
      'Your next migration batch is ready';

  @override
  String migrationMobileAttentionSignatureSheet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes are ready for your signature',
      one: '1 note is ready for your signature',
    );
    return '$_temp0';
  }

  @override
  String get migrationMobileAttentionStoppedTitle =>
      'Migration stopped by network upgrade';

  @override
  String get migrationMobileBackHome => 'Back home';

  @override
  String get migrationMobileBackToHome => 'Back to home';

  @override
  String get migrationMobileBannerInProgress => 'Migration in progress';

  @override
  String get migrationMobileBannerLate => 'Migration needs attention';

  @override
  String get migrationMobileBannerPreparing => 'Preparing migration';

  @override
  String get migrationMobileBannerProof => 'Next migration batch is ready';

  @override
  String migrationMobileBannerRemaining(String amount) {
    return '$amount ZEC still migrating';
  }

  @override
  String migrationMobileBannerSignature(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes are ready for signing',
      one: '1 note is ready for signing',
    );
    return '$_temp0';
  }

  @override
  String get migrationMobileBannerStart => 'Migrate to Ironwood';

  @override
  String get migrationMobileBannerStopped => 'Migration stopped';

  @override
  String get migrationMobileBannerWaiting => 'Waiting for confirmation...';

  @override
  String migrationMobileBatchProgress(int completed, int total) {
    return '$completed/$total Batch';
  }

  @override
  String get migrationMobileCanLeave => 'You can leave this screen.';

  @override
  String get migrationMobileCompleteBody =>
      'Migration went successfully and you can spend your funds as usual.';

  @override
  String migrationMobileCompleteHeading(String amount) {
    return 'Your\n$amount\nare on Ironwood!';
  }

  @override
  String get migrationMobileCompleteTitle => 'You’re all set!';

  @override
  String get migrationMobileContinueError =>
      'Couldn\'t continue migration. Try again.';

  @override
  String get migrationMobileContinueThisError =>
      'Couldn\'t continue this migration. Try again.';

  @override
  String get migrationMobileCredentialsRestore =>
      'Your migration credentials need to be restored before continuing.';

  @override
  String get migrationMobileErrorBroadcast =>
      'Couldn\'t broadcast the migration transaction. Try again.';

  @override
  String get migrationMobileErrorPlanChanged =>
      'The amount or fee changed. Review the updated details.';

  @override
  String get migrationMobileErrorStart =>
      'Couldn\'t start migration. Try again.';

  @override
  String get migrationMobileErrorSyncFirst =>
      'Wait for sync to finish, then try again.';

  @override
  String get migrationMobileErrorUnlock =>
      'Unlock Vizor before starting migration.';

  @override
  String get migrationMobileEstCompletion => 'Est. completion';

  @override
  String get migrationMobileFastConsiderOther => 'Consider another option';

  @override
  String get migrationMobileFastContinueAnyway => 'Continue anyway';

  @override
  String get migrationMobileFastDurationRow => 'Migration complete in';

  @override
  String get migrationMobileFastFeesRow => 'Fees (estimate)';

  @override
  String get migrationMobileFastNoBalance =>
      'No spendable Orchard balance is available for Immediate migration.';

  @override
  String get migrationMobileFastPlanCalculating => 'Calculating…';

  @override
  String get migrationMobileFastPlanError =>
      'Couldn\'t calculate the Immediate migration fee. Sync and try again.';

  @override
  String get migrationMobileFastPlanUnavailable => 'Unavailable';

  @override
  String get migrationMobileFastPrivacyBodyHighlight =>
      'easier to associate with your wallet';

  @override
  String migrationMobileFastPrivacyBodyLead(String amount) {
    return 'Crosses in one visible step — your $amount and timing are ';
  }

  @override
  String get migrationMobileFastPrivacyConsiderPrivate =>
      'Consider choosing a Private Migration option.';

  @override
  String get migrationMobileFastPrivacyLedger =>
      'Private migration is not available for Ledger accounts.';

  @override
  String get migrationMobileFastPrivacyTitle => 'Privacy trade-off';

  @override
  String get migrationMobileFastRetryCalculation => 'Retry calculation';

  @override
  String migrationMobileFastSubmittedBody(String amount) {
    return '$amount is on its way to Ironwood.';
  }

  @override
  String get migrationMobileFastSubmittedTitle => 'Migration submitted';

  @override
  String get migrationMobileFastTitle => 'Fast Migration';

  @override
  String get migrationMobileGoHome => 'Go home';

  @override
  String get migrationMobileHeroBadge => 'Migration';

  @override
  String get migrationMobileHeroIronwoodPool => 'Ironwood Pool';

  @override
  String get migrationMobileHeroLegacy => '(Legacy)';

  @override
  String get migrationMobileHeroOrchardPool => 'Orchard Pool';

  @override
  String get migrationMobileHowItWorksNavTitle => 'About';

  @override
  String get migrationMobileHowItWorksTitle => 'How Migration Works';

  @override
  String migrationMobileIntroBody(String amount) {
    return 'Your $amount ZEC is currently in Orchard. To keep using these funds for shielded payments, you\'ll need to move them to Ironwood. You\'ll review the migration plan before any funds move.';
  }

  @override
  String get migrationMobileIntroReleaseNote => 'Official release note';

  @override
  String get migrationMobileIntroTagline => 'A new shielded pool for Zcash.';

  @override
  String get migrationMobileIntroTitle => 'Zcash Network Update';

  @override
  String get migrationMobileKeepOpenUnlocked => 'Keep Vizor open & unlocked.';

  @override
  String get migrationMobileKeepRunning => 'But keep Vizor open & running.';

  @override
  String get migrationMobileKeystoneConfirmPrepSemantics =>
      'Confirm migration preparation with Keystone';

  @override
  String get migrationMobileKeystoneConfirmTitle =>
      'Confirm Migration with Keystone';

  @override
  String get migrationMobileKeystoneConfirmTransferSemantics =>
      'Confirm migration transfer with Keystone';

  @override
  String get migrationMobileKeystoneHelpPrompt =>
      'Tap QR on your Keystone,\nthen scan this QR code.';

  @override
  String get migrationMobileKeystoneHelpSemantics =>
      'Keystone QR scanning help';

  @override
  String get migrationMobileKeystoneLoadingQrSemantics => 'Loading QR code';

  @override
  String get migrationMobileKeystoneLoadingQrText => 'Loading QR code ...';

  @override
  String get migrationMobileKeystoneNextStep => 'Next step';

  @override
  String get migrationMobileKeystonePromptOnDevice => 'on your Keystone,';

  @override
  String get migrationMobileKeystonePromptTap => 'Tap';

  @override
  String get migrationMobileKeystonePromptThenScan => 'then scan this QR code';

  @override
  String get migrationMobileKeystoneReconnect =>
      'Reconnect or re-import your Keystone account to continue this migration.';

  @override
  String get migrationMobileKeystoneRequestQrSemantics =>
      'Keystone request QR code';

  @override
  String get migrationMobileKeystoneRequiredStatus =>
      'Keystone account required';

  @override
  String get migrationMobileKeystoneResignMessage =>
      'Sign the rebuilt migration transactions with Keystone to continue.';

  @override
  String get migrationMobileKeystoneScanCaption =>
      'Scan the QR code on your\nKeystone to confirm';

  @override
  String get migrationMobileKeystoneScanPrepSemantics =>
      'Scan the signed migration preparation from Keystone';

  @override
  String get migrationMobileKeystoneScanProgress => 'Scan progress';

  @override
  String get migrationMobileKeystoneScanTitle => 'Scan with Keystone';

  @override
  String get migrationMobileKeystoneScanTransferSemantics =>
      'Scan the signed migration transfer from Keystone';

  @override
  String get migrationMobileKeystoneShowTxQr => 'Show transaction QR';

  @override
  String get migrationMobileKeystoneStep1 => 'Step 1/2';

  @override
  String get migrationMobileKeystoneStep2 => 'Step 2/2';

  @override
  String get migrationMobileLeftToMigrate => 'Left to migrate';

  @override
  String get migrationMobileManageCheckError =>
      'Couldn\'t check the migration status. Please try again.';

  @override
  String get migrationMobileManageChecking => 'Checking migration status...';

  @override
  String get migrationMobileManageConfirm => 'Confirm';

  @override
  String get migrationMobileManageNoRevert =>
      'Transactions already broadcast will not be reverted.';

  @override
  String get migrationMobileManageRetryStatus => 'Retry status check';

  @override
  String get migrationMobileManageStopAction => 'Stop migration';

  @override
  String get migrationMobileManageStopBody =>
      'Stop the remaining migration. Funds already migrated will stay in Ironwood.';

  @override
  String get migrationMobileManageStopTitle => 'Stop migration?';

  @override
  String get migrationMobileManageStopping => 'Stopping...';

  @override
  String get migrationMobileManageSwitchAction => 'Switch to Fast';

  @override
  String get migrationMobileManageSwitchBody =>
      'Stop the private schedule and review a Fast migration for your remaining balance. Fast migration increases traceability and cannot be reversed once submitted.';

  @override
  String get migrationMobileManageSwitchTitle => 'Switch to Fast?';

  @override
  String get migrationMobileManageTitle => 'Manage migration';

  @override
  String get migrationMobileManageUnavailable =>
      'This migration is no longer available to manage.';

  @override
  String get migrationMobileManageUpdateError =>
      'The migration could not be updated. Please try again.';

  @override
  String get migrationMobileManageWaitingBroadcast =>
      'Waiting for any active broadcast to finish before stopping the remaining migration.';

  @override
  String get migrationMobileNextConfirmationsArriving =>
      'Confirmations are still arriving.\nYou can leave Vizor and check again later.';

  @override
  String migrationMobileNextExpectedIn(String timing) {
    return 'Next migration step expected in\n$timing.';
  }

  @override
  String get migrationMobileNextMigration => 'Next migration';

  @override
  String migrationMobileNextNotificationsOffBlock(int height, String timing) {
    return 'Notifications are disabled. Open Vizor after block $height ($timing) and approve the next migration batch.';
  }

  @override
  String get migrationMobileNextNotificationsOffNoTiming =>
      'Notifications are disabled. Open Vizor again when the timing is available and approve the next migration batch.';

  @override
  String get migrationMobileNextNotificationsOffOpen =>
      'Notifications are disabled. Open Vizor again to continue.';

  @override
  String get migrationMobileNextNotificationsOnLeave =>
      'Notifications are on. You can leave Vizor and check back later.';

  @override
  String get migrationMobileNextOnTheWay =>
      'Next migration step is on the way.';

  @override
  String get migrationMobileNextReadyAuto =>
      'The scheduled transaction is ready for automatic submission. Keep Vizor open.';

  @override
  String get migrationMobileNextStepReady =>
      'The next migration step is ready. Keep Vizor open to continue.';

  @override
  String migrationMobileNextTimingUntil(String timing) {
    return '$timing until the next migration step.\nNotifications are on; you can leave Vizor and check back later.';
  }

  @override
  String get migrationMobileNextTorDisclosure =>
      'While Vizor is closed, migration continues over a direct connection.';

  @override
  String get migrationMobileNotifyAllow => 'Allow notifications';

  @override
  String get migrationMobileNotifyBody =>
      'Some migration steps require approval. We’ll notify you when it’s time, so you can respond quickly and avoid unnecessary delays.';

  @override
  String get migrationMobileNotifyConfirmBody =>
      'Without notifications, you’ll need to remember to open Vizor regularly and approve the next migration step when it’s ready.';

  @override
  String get migrationMobileNotifyConfirmNote =>
      'Otherwise, your migration may take longer.';

  @override
  String get migrationMobileNotifyConfirmTitle =>
      'Continue without notifications?';

  @override
  String get migrationMobileNotifyContinueWithout =>
      'Continue without notifications';

  @override
  String get migrationMobileNotifyHeading => 'Keep your migration on schedule';

  @override
  String get migrationMobileNotifyStillOff =>
      'Notifications are still off. Allow them from Settings, or continue without notifications.';

  @override
  String get migrationMobileNotifyTitle => 'Enable notifications';

  @override
  String migrationMobileOptionImmediateBody(String estimate) {
    return 'Migrates your entire balance in one batch. Fast ($estimate) but less private.';
  }

  @override
  String get migrationMobileOptionImmediateTitle => 'Immediate';

  @override
  String get migrationMobileOptionPrivateBody =>
      'Splits transactions into multiple parts to minimize traceability but will take several hours to days.';

  @override
  String get migrationMobileOptionPrivateTitle => 'Private';

  @override
  String get migrationMobileOptionPrivateUnavailableAndroid =>
      'Not available on Android.';

  @override
  String get migrationMobileOptionPrivateUnavailableLedger =>
      'Not available for Ledger accounts.';

  @override
  String get migrationMobileOptionsNavTitle => 'How to Migrate';

  @override
  String get migrationMobileOptionsOpenError =>
      'Couldn\'t open migration preparation. Try again.';

  @override
  String get migrationMobileOptionsSubtitle =>
      'Choose between more privacy over time or a faster migration. You can review the details before anything moves.';

  @override
  String get migrationMobileOptionsSubtitleAndroid =>
      'Private migration is temporarily unavailable on Android. Choose immediate to continue.';

  @override
  String migrationMobileOptionsSubtitleAndroidRest(String amount) {
    return '$amount ZEC is still in Orchard. Private migration is temporarily unavailable on Android. Choose immediate to continue.';
  }

  @override
  String get migrationMobileOptionsSubtitleLedger =>
      'Private migration is not available for Ledger accounts. Choose Immediate to continue.';

  @override
  String migrationMobileOptionsSubtitleLedgerRest(String amount) {
    return '$amount ZEC is still in Orchard. Private migration is not available for Ledger accounts. Choose Immediate to continue.';
  }

  @override
  String migrationMobileOptionsSubtitleRest(String amount) {
    return '$amount ZEC is still in Orchard. Choose between more privacy over time or a faster migration.';
  }

  @override
  String get migrationMobileOptionsTitle => 'Choose How to Migrate';

  @override
  String get migrationMobileOptionsTitleRest => 'How to Move the Rest';

  @override
  String migrationMobilePartConfirming(int count, int target) {
    return 'Confirming · $count/$target';
  }

  @override
  String migrationMobilePartLabel(int number) {
    return 'Part $number';
  }

  @override
  String migrationMobilePartProgress(String part, int percent) {
    return '$part progress $percent%';
  }

  @override
  String get migrationMobilePartQueued => 'Queued';

  @override
  String get migrationMobilePartsPlaceholder =>
      'Migration parts will appear as transactions are prepared.';

  @override
  String get migrationMobilePrepAdvancing =>
      'Preparing the next transactions. Keep Vizor open.';

  @override
  String get migrationMobilePrepBackgroundTracking =>
      'Confirming in the background. You can close Vizor.';

  @override
  String get migrationMobilePrepBackgroundUnsupported =>
      'This device can’t confirm in the background. Keep Vizor open.';

  @override
  String get migrationMobilePrepContinue => 'Continue preparation';

  @override
  String get migrationMobilePrepContinueKeystone => 'Continue with Keystone';

  @override
  String get migrationMobilePrepDoneBody =>
      'Preparation is complete. Check your migration status for progress and any action needed.';

  @override
  String get migrationMobilePrepDoneTitle => 'Preparation is done';

  @override
  String get migrationMobilePrepDuration => 'Preparation will\ntake 10–20 min';

  @override
  String get migrationMobilePrepInfoOrganizing =>
      'We’re organizing your balance into common-sized parts. This makes your migration harder to link.';

  @override
  String get migrationMobilePrepInfoThenBegin =>
      'Once preparation finishes, your migration can begin.';

  @override
  String get migrationMobilePrepKeystoneSignature =>
      'Preparation needs another Keystone signature.';

  @override
  String get migrationMobilePrepNotificationsDisabled =>
      'Allow notifications to continue in the background, or keep Vizor open.';

  @override
  String get migrationMobilePrepPausedLeft =>
      'Preparation was paused because you left.';

  @override
  String get migrationMobilePrepSyncingWallet => 'Syncing your wallet…';

  @override
  String get migrationMobilePreparingBody =>
      'Preparing your balance for migration. This step usually takes 10-20 mins.';

  @override
  String get migrationMobilePreparingTitle => 'Preparing your migration';

  @override
  String get migrationMobileProcessChooseBody =>
      'Compare a privacy-optimized schedule with a faster migration.';

  @override
  String get migrationMobileProcessChooseTitle => 'Choose how you migrate';

  @override
  String get migrationMobileProcessMoveBody =>
      'Privacy-optimized migrations send parts at staggered times to reduce linkability.';

  @override
  String get migrationMobileProcessMoveTitle => 'Move to Ironwood';

  @override
  String get migrationMobileProcessPrepareBody =>
      'Vizor reorganizes your balance into common-sized parts before migration begins.';

  @override
  String get migrationMobileProcessPrepareTitle => 'Prepare your balance';

  @override
  String get migrationMobileProcessSpendBody =>
      'Each confirmed Ironwood amount is available to spend while the rest continues.';

  @override
  String get migrationMobileProcessSpendTitle => 'Spend as funds arrive';

  @override
  String get migrationMobileProgressAllClear =>
      'All clear. Migration is in progress';

  @override
  String migrationMobileProgressAllClearBatch(int number) {
    return 'All clear. Processing batch #$number';
  }

  @override
  String migrationMobileProgressBatchReady(int number) {
    return 'Batch #$number is ready.';
  }

  @override
  String get migrationMobileProgressConfirmations =>
      'Waiting for confirmations';

  @override
  String get migrationMobileProgressNextStep =>
      'Waiting for next migration step';

  @override
  String get migrationMobileProgressReadyNow => 'Ready now';

  @override
  String get migrationMobileProgressScheduledReady =>
      'Scheduled transaction ready';

  @override
  String get migrationMobileProgressSyncing => 'Syncing';

  @override
  String get migrationMobileProgressSyncingBody =>
      'Checking the latest confirmations and migration status.';

  @override
  String get migrationMobileProgressSyncingTitle =>
      'Syncing migration progress';

  @override
  String get migrationMobileProgressWaitingWindowBody =>
      'Preparation is complete, but we are waiting\nfor the next available signing window.\nWe’ll let you know when it’s time to take action.';

  @override
  String get migrationMobileProgressYourConfirmation =>
      'Waiting for your confirmation';

  @override
  String get migrationMobileRebuildAction => 'Rebuild';

  @override
  String get migrationMobileRebuildBody =>
      'Vizor will first check that the pending transactions were not sent. It will then rebuild the migration for only your remaining balance. Any confirmed transfers will stay unchanged.';

  @override
  String get migrationMobileRebuildTitle => 'Rebuild migration?';

  @override
  String get migrationMobileRecommended => 'Recommended';

  @override
  String get migrationMobileRecover => 'Recover';

  @override
  String get migrationMobileRecovering => 'Recovering...';

  @override
  String get migrationMobileRecoveryRequired => 'Migration recovery required.';

  @override
  String get migrationMobileResume => 'Resume';

  @override
  String get migrationMobileResuming => 'Resuming...';

  @override
  String get migrationMobileRetryAutomatically =>
      'Vizor will retry automatically.';

  @override
  String get migrationMobileRetrying => 'Retrying...';

  @override
  String get migrationMobileReviewPlanTitle => 'Review Migration Plan';

  @override
  String get migrationMobileSavedTxError =>
      'Two saved transactions couldn\'t be reopened.';

  @override
  String get migrationMobileScheduleCalculating => 'Calculating';

  @override
  String get migrationMobileScheduleChange => 'Change';

  @override
  String migrationMobileScheduleConfirming(int count, int target) {
    return 'Confirming $count/$target';
  }

  @override
  String get migrationMobileScheduleCurrentBlock => 'Current block';

  @override
  String get migrationMobileScheduleDueNow => 'Due now';

  @override
  String get migrationMobileScheduleDuration => 'Duration';

  @override
  String get migrationMobileScheduleLoading => 'Loading migration schedule';

  @override
  String get migrationMobileScheduleManage => 'Manage';

  @override
  String get migrationMobileScheduleMigrating => 'Migrating…';

  @override
  String get migrationMobileScheduleMigrationNote => 'Migration note';

  @override
  String get migrationMobileScheduleNextRound => 'Next round';

  @override
  String migrationMobileScheduleOf(int current, int total) {
    return '$current of $total';
  }

  @override
  String get migrationMobileScheduleOverdue => 'Overdue';

  @override
  String get migrationMobileSchedulePending => 'Schedule pending';

  @override
  String get migrationMobileSchedulePreparationProgress =>
      'Preparation progress';

  @override
  String get migrationMobileSchedulePreparationTitle => 'Preparation Schedule';

  @override
  String get migrationMobileSchedulePreparing => 'Preparing schedule';

  @override
  String get migrationMobileSchedulePreparingState => 'Preparing';

  @override
  String get migrationMobileScheduleReadyIn => 'Ready in';

  @override
  String get migrationMobileScheduleReadyToSign => 'Ready to sign';

  @override
  String get migrationMobileScheduleReturn => 'Return';

  @override
  String migrationMobileScheduleRound(int round) {
    return 'Round $round';
  }

  @override
  String get migrationMobileScheduleRoundsRemaining => 'Rounds remaining';

  @override
  String get migrationMobileScheduleScheduled => 'Scheduled';

  @override
  String get migrationMobileScheduleSpendable => 'Ironwood spendable';

  @override
  String migrationMobileScheduleSplitRound(int round) {
    return 'Split round $round';
  }

  @override
  String get migrationMobileScheduleTitle => 'Migration Schedule';

  @override
  String get migrationMobileScheduleUnavailableBody =>
      'Vizor couldn\'t load the latest schedule. Your saved migration state is unchanged.';

  @override
  String get migrationMobileScheduleUnavailableTitle =>
      'Migration schedule unavailable';

  @override
  String get migrationMobileScheduleWaitingMined => 'Waiting to be mined';

  @override
  String migrationMobileScheduleWindow(String height) {
    return 'Window #$height';
  }

  @override
  String get migrationMobileSpendableBalance => 'Currently spendable balance';

  @override
  String get migrationMobileStartErrorFallback =>
      'Try again when you are ready.';

  @override
  String get migrationMobileStartErrorTitle =>
      'Couldn\'t prepare your migration';

  @override
  String get migrationMobileStartLoadingBody =>
      'Vizor is preparing your migration. This may take a moment.';

  @override
  String get migrationMobileStartMessageOrganizing =>
      'Organizing migration batches...';

  @override
  String get migrationMobileStartMessagePlan =>
      'Preparing your migration plan...';

  @override
  String get migrationMobileStartMessagePreparing =>
      'Preparing your migration...';

  @override
  String get migrationMobileStartReadyBody =>
      'Continue to sign the preparation transactions and migration batches together with Keystone.';

  @override
  String get migrationMobileStartReadyTitle => 'Ready to sign';

  @override
  String migrationMobileStatusNotesCount(int count) {
    return '$count notes';
  }

  @override
  String get migrationMobileStatusNotesLead => 'Migration ';

  @override
  String get migrationMobileStatusTitle => 'Ironwood Migration';

  @override
  String get migrationMobileStoppedMoved => 'Moved to Ironwood';

  @override
  String get migrationMobileStoppedRemaining => 'Still in Orchard';

  @override
  String get migrationMobileSyncingProgress =>
      'Syncing the migration progress.';

  @override
  String get migrationMobileTimingUpdating => 'Timing is updating';

  @override
  String get migrationMobileViewSchedule => 'View schedule';

  @override
  String get migrationMobileWaitAutoStart =>
      'Migration will start automatically once note split is complete.';

  @override
  String migrationMobileWaitBlocks(int count, int target) {
    return '$count/$target blocks';
  }

  @override
  String get migrationMobileWaitConfirmation => 'Wait for confirmation';

  @override
  String get migrationMobileWaitKeystoneAgain =>
      'Another Keystone approval will be needed after these confirmations.';

  @override
  String get migrationMobileWaitLoopBatch => ' the batch of transactions';

  @override
  String get migrationMobileWaitLoopCaption =>
      'Repeat several times,\nwaiting could take 2–10\nhours';

  @override
  String get migrationMobileWaitLoopForWindow => ' for the window';

  @override
  String get migrationMobileWaitLoopSign => 'Sign';

  @override
  String get migrationMobileWaitLoopWait => 'Wait';

  @override
  String get migrationMobileWaitNoteSplit => 'Note Split';

  @override
  String get migrationMobileWaitSafeBlock =>
      'Waiting for a safe block to continue.';

  @override
  String migrationMobileWaitSplitInto(int count) {
    return 'Split Notes into $count Migration Parts';
  }

  @override
  String get migrationNextActionDetailAllNotesCompleted =>
      'All notes completed';

  @override
  String get migrationNextActionDetailAt => 'at';

  @override
  String get migrationNextActionDetailExpectedAt => 'Expected at';

  @override
  String get migrationNextActionDetailPreparing => 'Preparing migration';

  @override
  String get migrationNextActionDetailReadyToSign => 'Ready to sign';

  @override
  String get migrationNextActionDetailSendingNow => 'Sending now';

  @override
  String get migrationNextActionDetailWaitingForConfirmations =>
      'Waiting for confirmations';

  @override
  String get migrationNextActionDetailWaitingForSync =>
      'Waiting for wallet sync';

  @override
  String get migrationNextActionLabelAwaitingMining => 'Awaiting mining';

  @override
  String get migrationNextActionLabelComplete => 'Migration complete';

  @override
  String get migrationNextActionLabelFinalizing => 'Finalizing migration';

  @override
  String get migrationNextActionLabelNext => 'Next migration';

  @override
  String get migrationNextActionLabelNextWindow => 'Next migration window';

  @override
  String get migrationNextActionLabelOpeningWindow =>
      'Opening migration window';

  @override
  String get migrationNextActionLabelSending => 'Sending migration';

  @override
  String get migrationNextActionLabelWindowReady => 'Migration window ready';

  @override
  String get migrationNotScheduled => 'Not scheduled';

  @override
  String migrationNotesAwaitingConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes awaiting confirmation',
      one: '1 note awaiting confirmation',
    );
    return '$_temp0';
  }

  @override
  String migrationNotesBroadcast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes broadcast',
      one: '1 note broadcast',
    );
    return '$_temp0';
  }

  @override
  String migrationNotesRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes remaining',
      one: '1 note remaining',
    );
    return '$_temp0';
  }

  @override
  String get migrationOptionImmediate => 'Immediate';

  @override
  String get migrationOptionImmediateBody =>
      'Migrates your entire balance in one batch. Fast but less private.';

  @override
  String get migrationOptionPrivate => 'Private';

  @override
  String get migrationOptionPrivateBody =>
      'Splits transactions into multiple parts to minimize traceability, but will take longer.';

  @override
  String get migrationOptionPrivateLedger =>
      'Not available for Ledger accounts.';

  @override
  String get migrationOptionRecommended => 'Recommended';

  @override
  String get migrationOptionsBody =>
      'Choose between more privacy over time or a faster migration. You can review the details before anything moves.';

  @override
  String migrationOptionsBodyMoveRest(String amount) {
    return '$amount ZEC is still in Orchard. Choose between more privacy over time or a faster migration.';
  }

  @override
  String get migrationOptionsSelectReview => 'Select & review';

  @override
  String get migrationOptionsTitle => 'Choose how to migrate';

  @override
  String get migrationOptionsTitleMoveRest => 'How to move the rest';

  @override
  String get migrationOverallCalculatingTotal => 'Calculating total';

  @override
  String migrationOverallProgress(String completed, String total) {
    return '$completed of $total complete';
  }

  @override
  String migrationPlannedBatches(String count) {
    return '$count Planned batches';
  }

  @override
  String get migrationPoolIronwood => 'Ironwood Pool';

  @override
  String get migrationPoolLegacy => '(Legacy)';

  @override
  String get migrationPoolOrchard => 'Orchard Pool';

  @override
  String migrationPreparationConfirmations(String confirmed, String target) {
    return '$confirmed of $target confirmations';
  }

  @override
  String migrationPreparationSplitProgress(String current, String total) {
    return 'Preparing split $current of $total';
  }

  @override
  String migrationPreparationSplitStep(String current, String total) {
    return 'Split $current of $total';
  }

  @override
  String get migrationPreparationSplitTransactions =>
      'Preparing split transactions';

  @override
  String get migrationPreparationTipDelay =>
      'Once preparation finishes, your migration will begin automatically after a long intentional delay.';

  @override
  String get migrationPreparationTipOrganizing =>
      'We’re organizing your balance into common-sized parts. This makes your migration harder to link.';

  @override
  String get migrationPreparationTipRounds =>
      'We may have to do multiple rounds of note splitting depending on your balance.';

  @override
  String get migrationPreparingBatch => 'Preparing batch...';

  @override
  String get migrationPrivacyLockDescription =>
      'We auto-locked Vizor after 10 minutes of inactivity.';

  @override
  String get migrationPrivacyLockInProgress => 'Migration in progress';

  @override
  String migrationProgressTipBlockTime(String seconds) {
    return 'Each Zcash block takes about $seconds seconds to create, but timing can vary with network conditions.';
  }

  @override
  String get migrationProgressTipClose =>
      'You can close Vizor anytime. Migration will pause, and you can restart it when you return.';

  @override
  String get migrationProgressTipKeepRunning =>
      'Keep Vizor running and the migration will automatically run in the background.';

  @override
  String get migrationReadyNow => 'ready now';

  @override
  String get migrationRetryMigration => 'Retry migration';

  @override
  String get migrationRetrying => 'Retrying...';

  @override
  String get migrationReviewAmountToMigrate => 'Amount to migrate';

  @override
  String get migrationReviewAnalyzeErrorTitle =>
      'Couldn\'t analyze this balance';

  @override
  String get migrationReviewCompleteIn => 'Migration complete in';

  @override
  String get migrationReviewKeepRunningBody =>
      'Preparation continues while the app is minimized, then migration starts automatically.';

  @override
  String get migrationReviewKeepRunningTitle => 'Keep Vizor running';

  @override
  String get migrationReviewStart => 'Start migration';

  @override
  String get migrationReviewStarting => 'Starting…';

  @override
  String get migrationRingAllSplitsCompleted => 'All splits completed';

  @override
  String get migrationRingConfirmingSplit => 'Confirming split';

  @override
  String get migrationRingNextSplit => 'Next split';

  @override
  String get migrationRingPreparationComplete => 'Preparation complete';

  @override
  String get migrationRingPreparingSchedule => 'Preparing schedule';

  @override
  String get migrationRingScheduled => 'Scheduled';

  @override
  String get migrationRingSplitInProgress => 'Split in progress';

  @override
  String get migrationRingStatusCompleted => 'completed';

  @override
  String get migrationRingStatusConfirming => 'confirming';

  @override
  String get migrationRingStatusMigrating => 'migrating';

  @override
  String get migrationRingStatusNeedsInput => 'needs input';

  @override
  String get migrationRingStatusNotStarted => 'not started';

  @override
  String get migrationRingStatusPreparing => 'preparing';

  @override
  String get migrationRingStatusScheduled => 'scheduled';

  @override
  String get migrationRingWaitingForBlock => 'Waiting for block';

  @override
  String get migrationRingWaitingForPreviousSplit =>
      'Waiting for previous split';

  @override
  String get migrationRouteNotAvailable =>
      'Migration is not available for this account.';

  @override
  String get migrationRouteNotNeeded =>
      'Migration is not needed for this account.';

  @override
  String get migrationRouteStatusFailed => 'Couldn\'t verify migration status.';

  @override
  String get migrationRouteSyncFailed =>
      'Sync could not finish. Try again once Vizor is synced.';

  @override
  String get migrationScheduleBroadcasting => 'Broadcasting';

  @override
  String get migrationScheduleCalculating => 'Calculating';

  @override
  String migrationScheduleCompletedAtBlock(String height) {
    return 'Completed at block $height';
  }

  @override
  String migrationScheduleConfirmingProgress(String count, String target) {
    return 'Confirming $count/$target';
  }

  @override
  String get migrationScheduleCurrentRound => 'Current round';

  @override
  String migrationScheduleExpected(String height) {
    return 'Expected #$height';
  }

  @override
  String get migrationScheduleOutputChange => 'Stays in Orchard';

  @override
  String migrationScheduleOutputContinuation(String round) {
    return 'Used in round $round';
  }

  @override
  String get migrationScheduleOutputMigration => 'For migration';

  @override
  String get migrationSchedulePending => 'Schedule pending';

  @override
  String get migrationSchedulePreparing => 'Preparing';

  @override
  String get migrationScheduleReadyToMigrate => 'Ready to migrate';

  @override
  String get migrationScheduleRecalculating => 'Recalculating';

  @override
  String migrationScheduleRescheduled(String height) {
    return 'Rescheduled #$height';
  }

  @override
  String migrationScheduleRoundProgress(String current, String total) {
    return '$current of $total';
  }

  @override
  String migrationScheduleScheduledAt(String height) {
    return 'Scheduled #$height';
  }

  @override
  String migrationScheduleSemanticsAwaiting(String height) {
    return 'waiting for previous split, expected at block $height';
  }

  @override
  String migrationScheduleSemanticsBroadcast(String height) {
    return 'broadcast, waiting to be mined, projected completion at block $height';
  }

  @override
  String get migrationScheduleSemanticsCompleted => 'completed';

  @override
  String migrationScheduleSemanticsCompletedAt(String height) {
    return 'completed at block $height';
  }

  @override
  String get migrationScheduleSemanticsDue => 'due now';

  @override
  String get migrationScheduleSemanticsMigrating =>
      'broadcast, waiting to be mined';

  @override
  String migrationScheduleSemanticsNote(
    String number,
    String amount,
    String state,
  ) {
    return 'Note $number, $amount ZEC, $state.';
  }

  @override
  String migrationScheduleSemanticsNoteConfirming(String count, String target) {
    return 'confirming, $count of $target confirmations';
  }

  @override
  String migrationScheduleSemanticsNoteConfirmingMined(
    String count,
    String target,
    String height,
  ) {
    return 'confirming, $count of $target confirmations, mined at block $height';
  }

  @override
  String migrationScheduleSemanticsOutput(String amount, String destination) {
    return '$amount ZEC, $destination';
  }

  @override
  String get migrationScheduleSemanticsOutputChange => 'stays in Orchard';

  @override
  String migrationScheduleSemanticsOutputContinuation(String round) {
    return 'used in round $round';
  }

  @override
  String get migrationScheduleSemanticsOutputMigration => 'for migration';

  @override
  String migrationScheduleSemanticsOutputs(String outputs) {
    return 'Outputs: $outputs.';
  }

  @override
  String get migrationScheduleSemanticsPending => 'schedule pending';

  @override
  String get migrationScheduleSemanticsReadyToSign => 'ready to sign';

  @override
  String migrationScheduleSemanticsRescheduled(String from, String to) {
    return 'rescheduled from block $from to block $to';
  }

  @override
  String migrationScheduleSemanticsScheduled(String height) {
    return 'scheduled at block $height';
  }

  @override
  String migrationScheduleSemanticsSplit(
    String number,
    String amount,
    String state,
  ) {
    return 'Split $number, $amount ZEC, $state.';
  }

  @override
  String migrationScheduleSemanticsSplitConfirming(
    String count,
    String target,
    String height,
  ) {
    return 'confirming, $count of $target confirmations, projected completion at block $height';
  }

  @override
  String migrationScheduleSemanticsWaitingWindow(String height) {
    return 'waiting for window at block $height';
  }

  @override
  String migrationScheduleSplitRound(String number) {
    return 'Split round $number';
  }

  @override
  String get migrationScheduleTitle => 'Migration Schedule';

  @override
  String get migrationScheduleTitlePreparation => 'Preparation Schedule';

  @override
  String get migrationScheduleUnavailableBody =>
      'Vizor couldn\'t load the latest migration schedule. Your saved migration state is unchanged.';

  @override
  String get migrationScheduleUnavailableTitle =>
      'Migration schedule unavailable';

  @override
  String get migrationScheduleWaitingToBeMined => 'Waiting to be mined';

  @override
  String migrationScheduleWindow(String height) {
    return 'Window #$height';
  }

  @override
  String migrationSemanticsNote(String number, String amount, String status) {
    return 'Note $number: $amount ZEC, $status.';
  }

  @override
  String get migrationSemanticsNotesOrder =>
      'Migration notes in expected processing order.';

  @override
  String get migrationSemanticsPreparingNotes => 'Preparing migration notes.';

  @override
  String migrationSignBatch(String number) {
    return 'Sign Batch #$number';
  }

  @override
  String get migrationSignWithKeystone => 'Sign with Keystone';

  @override
  String get migrationStageFinish => 'Finish';

  @override
  String get migrationStageMigration => 'Migration';

  @override
  String get migrationStagePreparation => 'Preparation';

  @override
  String get migrationStatusAttentionBody =>
      'Vizor hit a recoverable migration error before completing the Ironwood transition.';

  @override
  String get migrationStatusAttentionFooter =>
      'No funds are lost. Retry migration after checking that Vizor is synced and online.';

  @override
  String get migrationStatusAttentionTitle => 'Migration Needs Attention';

  @override
  String get migrationStatusBroadcasted => 'Broadcasted';

  @override
  String get migrationStatusBroadcastingBody =>
      'Vizor is broadcasting the prepared Ironwood migration transaction.';

  @override
  String get migrationStatusBroadcastingButton => 'Broadcasting';

  @override
  String get migrationStatusCompleteBody =>
      'Your funds have moved into the Ironwood pool.';

  @override
  String get migrationStatusCompleteFooter =>
      'You can return home and continue using Vizor.';

  @override
  String get migrationStatusCompleteTitle => 'Migration Complete';

  @override
  String get migrationStatusConfirmingBody =>
      'The migration transaction was broadcast. Vizor is waiting for network confirmations.';

  @override
  String get migrationStatusDefaultBody =>
      'Vizor is tracking the current Ironwood migration state.';

  @override
  String get migrationStatusDefaultButton => 'Migration in progress';

  @override
  String get migrationStatusDefaultFooter =>
      'This state is visible for diagnostics while the migration flow is being connected.';

  @override
  String get migrationStatusDefaultTitle => 'Migration Status';

  @override
  String get migrationStatusLeaveFooter =>
      'You can leave this screen.\nBut keep Vizor open & running.';

  @override
  String get migrationStatusLedgerUnsupported =>
      'Ledger private migration is not supported because this flow requires batched signing.';

  @override
  String get migrationStatusMigratingTitle => 'Migrating...';

  @override
  String get migrationStatusPausedBody =>
      'The private migration is paused before the next action.';

  @override
  String get migrationStatusPausedButton => 'Paused';

  @override
  String get migrationStatusPausedFooter =>
      'No new transaction will be prepared until migration execution is resumed.';

  @override
  String get migrationStatusPausedTitle => 'Migration Paused';

  @override
  String get migrationStatusPendingBroadcasts => 'Pending broadcasts';

  @override
  String get migrationStatusPreparingBody =>
      'This usually takes around 30 minutes per split.';

  @override
  String get migrationStatusPreparingTitle => 'Preparing...';

  @override
  String get migrationStatusReadyBody =>
      'The private split is ready. The next step will prepare the Ironwood migration batch.';

  @override
  String get migrationStatusReadyFooter =>
      'Continue migration to prepare and broadcast the Ironwood transaction when it is due.';

  @override
  String get migrationStatusReadyTitle => 'Ready to Migrate';

  @override
  String get migrationStatusScheduledBody =>
      'Your migration transaction is prepared and waiting for its scheduled broadcast window.';

  @override
  String get migrationStatusScheduledFooter =>
      'When Vizor is open, scheduled broadcasts will be advanced by the migration worker.';

  @override
  String get migrationStatusScheduledTitle => 'Broadcast Scheduled';

  @override
  String get migrationStatusSplitProgress => 'Split progress';

  @override
  String get migrationStatusUnavailableBody =>
      'Vizor couldn\'t verify the current Ironwood migration state. No new migration will start until the status can be checked.';

  @override
  String get migrationStatusUnavailableHint =>
      'Return home and try again after sync refreshes. If a migration is already in progress, Vizor will continue from the saved state after it can be read.';

  @override
  String get migrationStatusUnavailableTitle => 'Migration status unavailable';

  @override
  String get migrationSummaryCurrentBlock => 'Current block';

  @override
  String get migrationSummaryEstCompletion => 'Est. completion';

  @override
  String get migrationSummaryLeftToMigrate => 'Left to migrate';

  @override
  String get migrationSummaryOverallProgress => 'Overall progress';

  @override
  String migrationTransactionOrdinal(String ordinal) {
    return 'Transaction $ordinal';
  }

  @override
  String migrationTransactionOrdinalOfTotal(String ordinal, String total) {
    return 'Transaction $ordinal of $total';
  }

  @override
  String get migrationUpgradeStopBody =>
      'Transfers signed before the upgrade can’t be sent after it. Your funds are safe.';

  @override
  String get migrationUpgradeStopMoveRemainingLabel => 'Move remaining balance';

  @override
  String get migrationUpgradeStopMovedLabel => 'Moved to Ironwood';

  @override
  String get migrationUpgradeStopRemainingLabel => 'Still in Orchard';

  @override
  String get migrationUpgradeStopRingMessage =>
      'Stopped by the\nnetwork upgrade';

  @override
  String get migrationView => 'View';

  @override
  String get migrationViewSchedule => 'View Schedule';

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
  String get onboardingAddressShieldedTitleMobile => 'Shielded Address';

  @override
  String get onboardingAddressTransparentDescription =>
      'Address starts with t, similar to Bitcoin, your address\' balance and transaction history are publicly visible.';

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
  String get payAddToContacts => 'Add to contacts';

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
  String get payAmountEstimated => 'Estimated:';

  @override
  String get payAmountEstimatedSpend => 'Estimated spend';

  @override
  String get payAmountPayingFrom => 'Paying from your';

  @override
  String get payAmountPayingIn => 'Paying in';

  @override
  String get payBackHome => 'Home';

  @override
  String get payFetchingQuote => 'Fetching quote';

  @override
  String get payNewAddressDetected => 'New address detected.';

  @override
  String get payNewAddressWarning =>
      'You haven\'t interacted with this address before.';

  @override
  String payRecentDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String payRecentHoursAgo(int hours) {
    return '${hours}h ago';
  }

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
  String get payReviewUnknownAddress => 'Unknown address';

  @override
  String get paySaveContactError => 'Couldn\'t save this contact. Try again.';

  @override
  String get paySaving => 'Saving';

  @override
  String get payScanBarrierDismiss => 'Dismiss';

  @override
  String get payScanCaption => 'Scan the recipient address QR code';

  @override
  String get payScanPermissionTitle => 'Scan the recipient address';

  @override
  String get payScanQrSubtitle => 'Scan an address using camera';

  @override
  String get payScanQrTitle => 'Scan a QR code';

  @override
  String get paySelectRecipient => 'Select recipient';

  @override
  String get payStepRecipient => 'Recipient';

  @override
  String get payStepReview => 'Review';

  @override
  String get paySubmittedFailedBody =>
      'The payment could not be submitted. Try again.';

  @override
  String get paySubmittedGoToActivity => 'Go to activity';

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
  String get paymentUriExpired =>
      'That request link timed out. Open it again to pay.';

  @override
  String get paymentUriMalformed =>
      'This request link isn\'t valid. Ask the sender for a new one.';

  @override
  String get paymentUriMigrationSendGate =>
      'Finish your Ironwood migration before opening request links.';

  @override
  String get paymentUriNoWallet =>
      'Set up or import a wallet before opening request links.';

  @override
  String get paymentUriOnboarding =>
      'Finish setting up your wallet before opening request links.';

  @override
  String get paymentUriReplaced =>
      'Only the newest request link was kept. Open the earlier one again to pay it.';

  @override
  String get paymentUriUnavailable =>
      'Vizor couldn\'t open this request link. Open it again once your wallet has loaded.';

  @override
  String get paymentUriUnsupported =>
      'This request link uses a feature Vizor doesn\'t support yet.';

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
  String get receiveAboutAddressType => 'About this address type';

  @override
  String get receiveAddressCouldNotLoad =>
      'Address couldn\'t be loaded. Try again.';

  @override
  String get receiveAddressLoadFailed =>
      'We couldn\'t load your address. Try again in a moment.';

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
  String get receiveRequestAmountDecimalsError => 'Enter up to 8 decimals';

  @override
  String get receiveRequestAmountFormatError => 'Enter an amount like 0.5';

  @override
  String get receiveRequestAmountSupplyError => 'Amount exceeds the ZEC supply';

  @override
  String receiveRequestButton(String ticker) {
    return 'Request $ticker';
  }

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
  String get sendAddressTypeTex => 'TEX address';

  @override
  String get sendAddressValidationFailed => 'Address validation failed';

  @override
  String get sendAmountCtaEnterAmount => 'Enter amount to continue';

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
  String get sendContactPickerEmpty => 'No Zcash contacts';

  @override
  String get sendContactPickerTitle => 'Contacts Zcash';

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
  String get sendKeystoneConfirmTitle => 'Confirm with Keystone';

  @override
  String get sendKeystonePrepareFailedGoBack =>
      'Keystone signing could not be prepared. Go back and try again.';

  @override
  String get sendKeystonePrepareFailedReturnToSend =>
      'Keystone signing could not be prepared. Return to Send and try again.';

  @override
  String get sendKeystonePreparing => 'Preparing';

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
  String get sendLedgerSignaturePreservedMessage =>
      'Your Ledger signature is preserved. Retry saving without approving another transaction.';

  @override
  String get sendLedgerSignedNeedsAttentionTitle =>
      'Signed transaction needs attention';

  @override
  String get sendLedgerSigningIncomplete =>
      'Ledger signing could not be completed. Check your device and try again.';

  @override
  String get sendLedgerSigningUnavailableTitle => 'Ledger signing unavailable';

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
  String get sendMemoWhitespaceOnly => 'Whitespace only';

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
  String get sendPaymentRequestCheckGeneric =>
      'Couldn\'t check this request — try again or edit the details';

  @override
  String get sendPaymentRequestCheckNetwork =>
      'Couldn\'t reach the network — check your connection and try again';

  @override
  String get sendPaymentRequestCheckNoAccount =>
      'No active account — choose one, then open this link again';

  @override
  String get sendPaymentRequestCheckNoAmount =>
      'This link doesn\'t ask for a payable amount — enter one to continue';

  @override
  String get sendPaymentRequestCheckUpgradeHold =>
      'Paused for the network upgrade. Try again in a few minutes.';

  @override
  String get sendPaymentRequestCheckUpgradeScheduleChanged =>
      'The network upgrade changed the migration timing. Review the plan and start again.';

  @override
  String get sendPaymentRequestClose => 'Close payment request';

  @override
  String get sendPaymentRequestConfirmWithSender =>
      'Confirm the details with the person who sent it.';

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
  String get sendRequestScanCheckFailed =>
      'Couldn\'t check this QR code. Try again.';

  @override
  String get sendRequestScanInvalidAddress =>
      'This QR code isn\'t a valid Zcash address.';

  @override
  String get sendRequestScanInvalidRequest =>
      'This QR code doesn\'t contain a valid payment request.';

  @override
  String get sendRequestScanNotRequest =>
      'This QR code isn\'t a Zcash address or payment request.';

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
  String get sendRequestScanUnavailable =>
      'Connect a camera, or go back and review the link details.';

  @override
  String get sendRequestScanWrongNetwork =>
      'This address belongs to a different network.';

  @override
  String get sendReviewAction => 'Review';

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
  String get sendReviewPreparing => 'Preparing...';

  @override
  String sendReviewRequestedAmount(String amount) {
    return 'Requested $amount';
  }

  @override
  String get sendReviewRequestedBy => 'Requested by';

  @override
  String get sendReviewTitle => 'Review send';

  @override
  String get sendSaplingDownloadBody =>
      'To create this private transaction, your wallet needs to download about 50MB of cryptographic parameters.';

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
  String get sendStatusMobileNothingSent =>
      'Nothing was sent, your funds haven\'t moved. Try again.';

  @override
  String get sendStatusMobilePendingDefault =>
      'Your transaction was created and will be submitted automatically. Check the Activity page before sending again.';

  @override
  String get sendStatusMobileQueued => 'Queued to send';

  @override
  String get sendStatusMobileReturnToSettings => 'Return to settings';

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
  String get sendStatusScanKeystoneTitle => 'Scan your Keystone QR Code';

  @override
  String get sendStatusTitleInProgress => 'Send in progress...';

  @override
  String get sendStepEnterAmount => 'Enter Amount';

  @override
  String get sendStepReviewDonation => 'Review donation';

  @override
  String get sendStepReviewSend => 'Review Send';

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
  String get settingsUpdateCurrentLabel => 'Current';

  @override
  String get settingsUpdateDownloadButton => 'Download update';

  @override
  String get settingsUpdateDownloadingButton => 'Downloading…';

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
  String get swapActionAddRecipientAddress => 'Add recipient address';

  @override
  String get swapActionAddRefundAddress => 'Add refund address';

  @override
  String get swapActionContinueToReview => 'Continue to review';

  @override
  String get swapActionGettingQuote => 'Getting quote';

  @override
  String swapActivityAddressBookRefund(String symbol) {
    return '$symbol refund';
  }

  @override
  String swapActivityDeadlineHours(int hours) {
    return '${hours}hrs';
  }

  @override
  String swapActivityDeadlineMinutes(int minutes) {
    return '${minutes}mins';
  }

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
  String get swapActivityDetailIncluded => 'Included';

  @override
  String get swapActivityDetailIncludedInRate => 'Included in shown rate';

  @override
  String get swapActivityDetailMissingDeposit => 'Missing deposit';

  @override
  String get swapActivityDetailRealizedSlippage => 'Realized slippage';

  @override
  String get swapActivityDetailRequiredDeposit => 'Required deposit';

  @override
  String swapActivityDetailSourceTxShielded(String symbol) {
    return '$symbol tx (shielded)';
  }

  @override
  String get swapActivityDetailTotalFees => 'Total fees';

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
  String get swapActivityPaymentComplete => 'Payment complete';

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
  String get swapActivityReceiveAssetFallback => 'receive asset';

  @override
  String get swapActivityRecipientReceived => 'Recipient received';

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
  String get swapActivityStatusAwaitingDeposit => 'Awaiting deposit';

  @override
  String get swapActivityStatusAwaitingExternalDeposit =>
      'Awaiting external deposit';

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
  String get swapActivitySwapInProgress => 'Swap in progress...';

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
  String get swapActivityYouReceived => 'You received';

  @override
  String swapAddressRecipientDescription(String symbol) {
    return 'Your $symbol will be delivered to this address.';
  }

  @override
  String get swapAddressRecipientFieldLabel => 'Recipient';

  @override
  String swapAddressRecipientTitle(String symbol) {
    return '$symbol recipient address';
  }

  @override
  String swapAddressRefundDescription(String symbol, String chain) {
    return 'If the swap fails or the rate moves, you\'ll be refunded in $symbol on $chain, minus the fee.';
  }

  @override
  String get swapAddressRememberRecipient =>
      'Remember this address for recipients';

  @override
  String get swapAddressRememberRefund => 'Remember this address for refunds';

  @override
  String get swapAssetSelectorEmpty => 'No tokens or chains found';

  @override
  String get swapAssetSelectorSearchHint => 'Search token or chain';

  @override
  String get swapAssetSelectorTitle => 'Select asset';

  @override
  String get swapComposerAddRecipientAddressEllipsis =>
      'Add recipient address...';

  @override
  String get swapComposerAddRefundAddressEllipsis => 'Add refund address...';

  @override
  String swapComposerMaxAmount(String amount) {
    return 'Max: $amount';
  }

  @override
  String get swapComposerYouReceive => 'You receive';

  @override
  String get swapContactAlreadyInAddressBook => 'Already in your address book';

  @override
  String get swapContactAlreadySaved => 'Already in your contacts';

  @override
  String get swapDepositAmountCopiedDesktop => 'Amount Copied';

  @override
  String get swapDepositAmountCopiedMobile => 'Amount copied';

  @override
  String get swapDepositAmountToDeposit => 'Amount to deposit';

  @override
  String get swapDepositChecking => 'Checking';

  @override
  String get swapDepositDoneDesktop => 'I\'ve deposited';

  @override
  String get swapDepositDoneMobile => 'I’ve deposited tokens';

  @override
  String swapDepositHoursMany(int count) {
    return '${count}hrs';
  }

  @override
  String get swapDepositMemoCopied => 'Memo copied';

  @override
  String swapDepositMinutesMany(int count) {
    return '${count}mins';
  }

  @override
  String get swapDepositOneTimeAddress => 'One-time address';

  @override
  String swapDepositSendOnly(String symbol, String chain) {
    return 'Send only $symbol on $chain';
  }

  @override
  String get swapDepositTimeoutBody =>
      'This deposit address is no longer valid.\nPlease, start another swap transaction.';

  @override
  String get swapDepositTitle => 'Deposit tokens';

  @override
  String get swapDepositWithin => 'Deposit within';

  @override
  String get swapDepositZecButton => 'Deposit ZEC';

  @override
  String get swapDismissBarrierLabel => 'Dismiss';

  @override
  String get swapFailureAmountPrecision =>
      'Amount has too many decimal places.\nUse fewer decimals and try again.';

  @override
  String get swapFailureAmountTooLowPay =>
      'Amount is too low for this payment.\nTry a larger amount.';

  @override
  String get swapFailureAmountTooLowSwap =>
      'Amount is too low for this swap.\nTry a larger amount.';

  @override
  String get swapFailureAssetUnavailable =>
      'This asset is not available for swap right now.\nChoose another asset or try again later.';

  @override
  String get swapFailureDepositNotIndexed =>
      'Deposit is not indexed yet.\nCheck again in a few minutes.';

  @override
  String get swapFailureDepositRejected =>
      'Deposit transaction was rejected.\nCheck the address, memo, and tx hash.';

  @override
  String get swapFailureDepositSubmitFailed =>
      'Deposit status could not be submitted.\nTry again later.';

  @override
  String get swapFailureNoQuote =>
      'No quote is available for this route or amount.\nAdjust the amount, slippage, or asset and try again.';

  @override
  String get swapFailureQuoteTimeout =>
      'Quote request timed out.\nCheck your connection and try again.';

  @override
  String get swapFailureQuoteUnavailable =>
      'Quote is unavailable right now.\nTry again later.';

  @override
  String get swapFailureQuoteUnverified =>
      'Quote response could not be verified.\nTry again later.';

  @override
  String get swapFailureRefreshFailed =>
      'Could not refresh swap status.\nTry again later.';

  @override
  String get swapFailureRequestTimeout =>
      'Request timed out.\nCheck your connection and try again.';

  @override
  String get swapFailureResponseUnverified =>
      'Swap response could not be verified.\nTry again later.';

  @override
  String get swapFailureRouteRejected =>
      'This route or address was rejected.\nEdit the details and request a new quote.';

  @override
  String get swapFailureServiceUnavailable =>
      'Swap service is temporarily unavailable.\nTry again later.';

  @override
  String get swapFailureStartFailed =>
      'Swap could not be started.\nTry again later.';

  @override
  String get swapFailureStatusAssetUnsupported =>
      'Swap status uses an unsupported asset pair.\nDo not resend funds. Try again later.';

  @override
  String get swapFailureStatusAutoRefresh =>
      'We couldn\'t refresh the latest status.\nWe\'ll keep trying and update this screen automatically.';

  @override
  String get swapFailureStillProcessing =>
      'Swap service is still processing.\nWait a moment and try again.';

  @override
  String get swapFailureTokensUnavailable =>
      'Swap tokens could not be loaded.\nTry again later.';

  @override
  String get swapFailureTorBlockedPay =>
      'Pay is unavailable over Tor because the service blocked this connection.\nTurn off Tor in Settings to pay.';

  @override
  String get swapFailureTorBlockedSwap =>
      'Swap is unavailable over Tor because the service blocked this connection.\nTurn off Tor in Settings to use swap.';

  @override
  String get swapFailureZecDepositFunding =>
      'Not enough spendable ZEC to cover this swap and its network fee.\nTry a smaller amount or use Max.';

  @override
  String get swapFailureZecDepositPreflight =>
      'ZEC deposit could not be prepared.\nCheck your balance and try again.';

  @override
  String get swapFailureZecDepositSendFailed =>
      'ZEC deposit could not be sent.\nTry again later.';

  @override
  String get swapKeystoneBroadcastFailed =>
      'Transaction could not be broadcast.';

  @override
  String get swapKeystoneBroadcastingTitle => 'Broadcasting ZEC deposit';

  @override
  String get swapKeystoneFailedTitle => 'Keystone signing failed';

  @override
  String get swapKeystoneFinalizing => 'Broadcasting ZEC deposit...';

  @override
  String get swapKeystoneIncomplete =>
      'ZEC deposit signing could not be completed.';

  @override
  String get swapKeystoneNoTex => 'Keystone does not support TEX sends yet.';

  @override
  String get swapKeystoneQrMismatch =>
      'This QR code does not match the current Keystone request.';

  @override
  String get swapKeystoneScanCaption =>
      'Scan the QR code on your Keystone to finish the ZEC deposit';

  @override
  String get swapKeystoneScanToSign => 'Scan to sign';

  @override
  String get swapKeystoneSignTitle => 'Sign ZEC deposit on Keystone';

  @override
  String get swapKeystoneStatusUncertain =>
      'The transaction status is uncertain. Refresh activity before trying again.';

  @override
  String get swapLedgerBackToActivity => 'Back to activity';

  @override
  String get swapLedgerBroadcastFailed =>
      'The ZEC deposit could not be broadcast.';

  @override
  String get swapLedgerDeclined =>
      'The ZEC deposit was rejected on your Ledger.';

  @override
  String get swapLedgerMessageBackground =>
      'Vizor is already finishing this transaction in the background.';

  @override
  String get swapLedgerMessageExpired =>
      'The transaction expired before it was sent. Vizor still needs to release its reserved funds.';

  @override
  String get swapLedgerMessageSentNotSaved =>
      'The transaction was sent, but Vizor could not finish saving it.';

  @override
  String get swapLedgerMessageUncertain =>
      'Vizor could not confirm whether the transaction was sent, and still needs to save its status.';

  @override
  String get swapLedgerRetryCleanup => 'Retry cleanup';

  @override
  String get swapLedgerSigningIncomplete =>
      'Ledger signing could not be completed.';

  @override
  String get swapLedgerStatusCleanup => 'Cleanup needed';

  @override
  String get swapLedgerStatusSaving => 'Saving transaction';

  @override
  String get swapLedgerStatusWait => 'Please wait';

  @override
  String get swapLedgerTitlePending => 'Transaction status pending';

  @override
  String get swapLedgerTitleRecovery => 'Transaction recovery in progress';

  @override
  String get swapLedgerTitleSent => 'Transaction sent';

  @override
  String get swapNoticeAccountChanged =>
      'Active account changed. Review the quote again before starting.';

  @override
  String get swapNoticeAffectedNetworks => 'Affected networks';

  @override
  String get swapNoticeAllChains => 'All chains';

  @override
  String get swapNoticeBroadcastNotStored =>
      'The transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';

  @override
  String get swapNoticeBroadcastPartial =>
      'Some deposit transactions may have reached the network. Check activity before trying again.';

  @override
  String get swapNoticeBroadcastPending =>
      'The deposit was created locally but could not be broadcast. Check activity before trying again.';

  @override
  String get swapNoticeBroadcastUncertain =>
      'The deposit status is uncertain. Check activity before trying again.';

  @override
  String get swapNoticeBroadcastUnknown =>
      'The transaction may have reached the network, but confirmation timed out. Check activity before trying again.';

  @override
  String get swapNoticeCloseLabel => 'Close service notice';

  @override
  String get swapNoticeDepositIntentMissing =>
      'ZEC deposit was broadcast, but the saved swap intent was not found. Copy the transaction hash before leaving this screen.';

  @override
  String swapNoticeExpectedEnd(String time) {
    return 'Expected end: $time';
  }

  @override
  String get swapNoticeListOfMaintenance => 'List of maintenance';

  @override
  String get swapNoticeMaintenanceIntro => 'NEAR Intents is under maintenance.';

  @override
  String get swapNoticeMaintenanceTitle => 'Maintenance notice';

  @override
  String swapNoticeMaintenanceWindow(String networks) {
    return 'Maintenance window: $networks';
  }

  @override
  String get swapNoticeOk => 'Ok';

  @override
  String get swapNoticePaymentsMayFail => 'Payments may not work right now.';

  @override
  String get swapNoticeReceiveAddressUnavailable =>
      'Could not prepare a fresh wallet receive address. Retry after wallet sync or close older pending swaps before requesting a new quote.';

  @override
  String get swapNoticeServiceTitle => 'Service notice';

  @override
  String swapNoticeStart(String time) {
    return 'Start: $time';
  }

  @override
  String get swapNoticeStatusPage => 'NEAR Intents status page';

  @override
  String get swapNoticeSwapsMayFail => 'Swaps may not work right now.';

  @override
  String get swapPageTitle => 'Swap';

  @override
  String get swapPanelDepositChecking => 'Checking ZEC deposit';

  @override
  String get swapPanelDepositSent => 'ZEC deposit sent';

  @override
  String get swapPanelLoadFailedBody =>
      'Return to Activity and select a saved swap.';

  @override
  String get swapPanelLoadFailedTitle =>
      'Couldn\'t load this swap. Try again or pull to refresh.';

  @override
  String swapPanelRecipientTo(String recipient) {
    return 'To: $recipient';
  }

  @override
  String get swapPayStatusConvertedFrom => 'Converted from';

  @override
  String get swapPayStatusNewAddress => 'New address';

  @override
  String get swapPayStatusSourceAmount => 'Source amount';

  @override
  String get swapPoweredByLabel => 'Powered by';

  @override
  String swapQuoteExpiresAt(String time) {
    return 'Expires $time';
  }

  @override
  String get swapQuoteExpiryPending => 'Quote expiry pending';

  @override
  String get swapQuoteRatePending => 'Rate pending';

  @override
  String get swapReviewBackPay => 'Pay';

  @override
  String get swapReviewConfirmAndSwap => 'Confirm & swap';

  @override
  String get swapReviewConfirmPaymentTitle => 'Confirm payment';

  @override
  String get swapReviewConfirmSwap => 'Confirm swap';

  @override
  String swapReviewFromAddress(String address) {
    return 'From: $address';
  }

  @override
  String get swapReviewInsufficientZecSwap =>
      'You don\'t have enough ZEC for this swap. Try a smaller amount.';

  @override
  String swapReviewPayAmount(String amount) {
    return 'Pay $amount';
  }

  @override
  String get swapReviewQuoteExpired =>
      'Quote expired. Review again for an updated rate.';

  @override
  String get swapReviewQuoteHolds => 'Quote holds';

  @override
  String get swapReviewQuoteInactive => 'This quote is no longer active.';

  @override
  String get swapReviewReturnToSwap => 'Return to swap';

  @override
  String get swapReviewReviewAgain => 'Review again';

  @override
  String get swapReviewStartingLockingQuote => 'Locking quote';

  @override
  String get swapReviewStartingPaying => 'Paying';

  @override
  String get swapReviewStartingSending => 'Sending';

  @override
  String swapReviewToAddress(String address) {
    return 'To: $address';
  }

  @override
  String get swapSignPayment => 'Sign payment';

  @override
  String get swapSignZecDeposit => 'Sign ZEC deposit';

  @override
  String get swapSlippageCustom => 'Custom';

  @override
  String get swapSlippageDescriptionPay =>
      'Allows this much extra ZEC for quote movement before execution fails. Network fees are separate.';

  @override
  String get swapSlippageDescriptionSwap =>
      'Sets the maximum rate change you\'ll accept. Network fees are separate.';

  @override
  String get swapSlippageRangeError => 'Slippage must be 0.1 - 5%';

  @override
  String get swapSlippageTitle => 'Slippage';

  @override
  String get swapStatusBadgeNeedsAttention => 'Needs attention';

  @override
  String get swapStatusDetailsTab => 'Transaction details';

  @override
  String get swapStatusRowLabel => 'Status';

  @override
  String get swapTimeoutBody => 'Please, start another swap transaction.';

  @override
  String get swapTimeoutHeadline => 'This deposit address is no longer valid';

  @override
  String get swapTimeoutRestart => 'Restart swap';

  @override
  String get swapTimeoutTitle => 'Time’s up';

  @override
  String get swapViewOnNearIntents => 'View on NEAR Intents';

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
  String get votingActionResume => 'Resume';

  @override
  String get votingActionRetryEligibility => 'Retry eligibility';

  @override
  String get votingActionReview => 'Review';

  @override
  String get votingActionReviewAnswers => 'Review answers';

  @override
  String get votingActionUnavailable => 'Unavailable';

  @override
  String get votingActionView => 'View';

  @override
  String get votingActionViewResults => 'View results';

  @override
  String get votingActive => 'Voting active';

  @override
  String get votingAlreadyUsedNotice =>
      'These funds were already used for this round. Voting cannot be restarted on this device.';

  @override
  String get votingAutoAdvanceSemantics =>
      'Moving to the next unanswered question';

  @override
  String get votingBallotCasting => 'Casting votes';

  @override
  String get votingBallotDelivering => 'Delivering your responses';

  @override
  String get votingBallotPreparing => 'Preparing your ballot';

  @override
  String get votingBallotWaitingChain => 'Waiting for chain confirmation';

  @override
  String get votingBetaSemantics => 'Beta';

  @override
  String votingBundleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voting bundles',
      one: '1 voting bundle',
    );
    return '$_temp0';
  }

  @override
  String votingBundleOf(int number, int total) {
    return 'Bundle $number of $total';
  }

  @override
  String get votingCheckAgain => 'Check again';

  @override
  String votingChoiceFallback(int number) {
    return 'Choice $number';
  }

  @override
  String get votingConfigAddCustomSource => 'Add custom source';

  @override
  String get votingConfigBadgeDefault => 'Default';

  @override
  String get votingConfigCloseSettings => 'Close voting config settings';

  @override
  String get votingConfigCopyUrl => 'Copy source URL';

  @override
  String get votingConfigCustomSource => 'Custom source';

  @override
  String votingConfigDeleteNamed(String name) {
    return 'Delete $name';
  }

  @override
  String get votingConfigDeleteSaved => 'Delete saved source';

  @override
  String get votingConfigDuplicate => 'This source URL is already added.';

  @override
  String get votingConfigEditCustomSource => 'Edit custom source';

  @override
  String votingConfigEditNamed(String name) {
    return 'Edit $name';
  }

  @override
  String get votingConfigEditSaved => 'Edit saved source';

  @override
  String get votingConfigEnterTitleAndUrl => 'Enter a title and source URL.';

  @override
  String get votingConfigFieldStaticUrl => 'Static config URL';

  @override
  String get votingConfigFieldTitle => 'Title';

  @override
  String get votingConfigLoadFailed =>
      'Couldn\'t load voting config from that source.';

  @override
  String get votingConfigMobileFieldUrl => 'Source URL';

  @override
  String get votingConfigMobileIntro =>
      'Choose where Vizor gets authenticated voting rounds.';

  @override
  String get votingConfigMobileSave => 'Save source';

  @override
  String get votingConfigMobileTestRoundsHint =>
      'Include authenticated rounds marked [TEST].';

  @override
  String get votingConfigMobileTitle => 'Vote config';

  @override
  String get votingConfigMobileUpdateFailed =>
      'Couldn\'t update voting config. Check the source and try again.';

  @override
  String get votingConfigSaving => 'Saving...';

  @override
  String get votingConfigSettings => 'Voting config settings';

  @override
  String get votingConfigShowTestRounds => 'Show test rounds';

  @override
  String get votingConfigShowTestRoundsHint =>
      'Display authenticated rounds whose titles begin with [TEST].';

  @override
  String get votingConfigSources => 'Sources';

  @override
  String get votingConfigTestVisibilityFailed =>
      'Couldn\'t update the test round visibility setting.';

  @override
  String votingConfigTitleTooLong(int max) {
    return 'Title must be $max characters or less.';
  }

  @override
  String get votingConfigTooltip => 'Voting config';

  @override
  String get votingConfigUpdateFailed => 'Couldn\'t update voting config.';

  @override
  String get votingConfigUrlCopied => 'Source URL copied.';

  @override
  String get votingConfigValidating => 'Validating...';

  @override
  String get votingConfirmationCheckingEligibility =>
      'Checking voting eligibility for this account.';

  @override
  String get votingConfirmationConfirmedBody =>
      'Your vote was successfully published and cannot be changed.';

  @override
  String get votingConfirmationConfirmedTitle => 'Submission confirmed!';

  @override
  String get votingConfirmationEligibilityUnconfirmed =>
      'Voting eligibility has not been confirmed for this account.';

  @override
  String get votingConfirmationIncompleteTitle => 'Submission not complete';

  @override
  String votingConfirmationLoadFailed(String error) {
    return 'Couldn\'t load submission details: $error';
  }

  @override
  String get votingConfirmationNotCompleted =>
      'This account has not completed submission for this voting round.';

  @override
  String get votingConfirmationUpdateFailed =>
      'Couldn\'t update voting rounds. Try again.';

  @override
  String get votingConfirmationUpdatingRounds => 'Updating voting rounds...';

  @override
  String get votingContinueToReview => 'Continue to review';

  @override
  String get votingContinueVoting => 'Continue voting';

  @override
  String votingDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
      zero: 'Ends today',
    );
    return '$_temp0';
  }

  @override
  String get votingDetailLoadFailedTitle => 'Couldn\'t load voting round';

  @override
  String get votingDetailUnavailableBody =>
      'The selected voting round could not be loaded.';

  @override
  String get votingDetailUnavailableTitle => 'Voting round unavailable';

  @override
  String votingEnds(String date) {
    return 'Ends $date';
  }

  @override
  String get votingErrorLedgerCancelled =>
      'Ledger voting approval was cancelled.';

  @override
  String votingErrorLedgerLocked(String instruction) {
    return 'Unlock your Ledger. $instruction';
  }

  @override
  String get votingErrorLedgerRejected =>
      'The vote signature was rejected on your Ledger. Retry to sign again.';

  @override
  String votingErrorLedgerWrongApp(String instruction) {
    return '$instruction Then retry.';
  }

  @override
  String votingErrorMinimumWeight(String amount, String snapshot) {
    return 'Voting requires at least one eligible shielded note bundle with $amount at $snapshot. Switch to an eligible account to vote.';
  }

  @override
  String votingErrorNoSpendableNotes(String snapshot) {
    return 'This account is not eligible for this voting round. It had no eligible shielded funds at $snapshot. Switch to an eligible account to vote.';
  }

  @override
  String get votingErrorSessionFailed => 'Voting session action failed.';

  @override
  String get votingForumDiscussion => 'Forum discussion';

  @override
  String get votingGuardAccountLoadFailed => 'Couldn\'t load account';

  @override
  String get votingIneligibleTitle => 'Not eligible for this voting round';

  @override
  String get votingKeepSigning => 'Keep signing';

  @override
  String get votingKeepVoting => 'Keep voting';

  @override
  String votingKeystoneMemoLabel(int number, int total) {
    return 'Bundle $number of $total memo';
  }

  @override
  String get votingKeystoneNextBatch => 'The next signing batch is ready';

  @override
  String get votingKeystoneNextMemo => 'Next bundle memo';

  @override
  String get votingKeystoneOneApproval => 'One Keystone approval';

  @override
  String get votingKeystonePreviousMemo => 'Previous bundle memo';

  @override
  String votingKeystoneQrPartial(int count, int total) {
    return 'This QR signs $count of $total remaining bundles';
  }

  @override
  String get votingKeystoneScanInstruction =>
      'Scan QR on this screen with Keystone. Then, scan the signed voting QR displayed on Keystone with this device\'s camera';

  @override
  String get votingKeystoneScanSignature => 'Scan signature';

  @override
  String votingKeystoneSignLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sign $count voting bundles',
      one: 'Sign 1 voting bundle',
      zero: 'Preparing voting signatures',
    );
    return '$_temp0';
  }

  @override
  String get votingKeystoneUnexpectedUr =>
      'Open the signed voting QR on Keystone, then scan again.';

  @override
  String get votingLedgerApprovalNotice =>
      'Approving on Ledger authorizes this voting delegation. Review the memo below in Vizor before continuing; the device may not display this memo verbatim.';

  @override
  String votingLedgerBundleOf(int number, int total) {
    return 'Bundle $number of $total';
  }

  @override
  String get votingLedgerChecking => 'Checking your Ledger';

  @override
  String get votingLedgerCheckingBody =>
      'Vizor is checking whether the Zcash app is ready.';

  @override
  String get votingLedgerConfirmOpen => 'Confirm opening Zcash';

  @override
  String get votingLedgerConfirmOpenBody =>
      'Approve the request to open the Zcash app on your Ledger.';

  @override
  String get votingLedgerFinishing => 'Finishing voting delegation';

  @override
  String get votingLedgerNeedsAttention => 'Ledger needs attention';

  @override
  String get votingLedgerPanelTitle => 'Voting delegation';

  @override
  String get votingLedgerPleaseWait =>
      'Please wait while Vizor prepares your request.';

  @override
  String get votingLedgerPreparing => 'Preparing voting delegation';

  @override
  String get votingLedgerReconnect => 'Reconnect your Ledger and try again.';

  @override
  String votingMobileAccountLoadFailed(String error) {
    return 'Couldn\'t load account.\n$error';
  }

  @override
  String get votingMobileGoHome => 'Go home';

  @override
  String get votingMobileHeaderTitle => 'Voting';

  @override
  String get votingMobileKeystoneChecking => 'Checking voting signature...';

  @override
  String get votingMobileKeystoneDescription =>
      'Scan the voting request with Keystone, approve it, then scan the signed result with this device.';

  @override
  String get votingMobileKeystoneFailedTitle => 'Voting signature failed';

  @override
  String get votingMobileKeystoneNextBundle => 'Next voting bundle';

  @override
  String get votingMobileKeystonePreviousBundle => 'Previous voting bundle';

  @override
  String get votingMobileKeystoneReading => 'Reading voting signature...';

  @override
  String get votingMobileKeystoneScanCaption =>
      'Scan the signed voting QR shown on Keystone';

  @override
  String get votingMobileKeystoneSkipUnsigned => 'Skip unsigned bundles';

  @override
  String get votingMobileKeystoneTitle => 'Sign vote with Keystone';

  @override
  String get votingMobileLeaveWarning => 'Don’t leave this window.';

  @override
  String get votingMobileProgressSemantics =>
      'Active voting submission step progress';

  @override
  String get votingMobileProofNotice =>
      'Generating zero-knowledge proofs can take about 60 seconds, closing now may lose in-flight proof work.';

  @override
  String get votingMobileSubmitTitle => 'Submit vote';

  @override
  String get votingMobileSubmittedBody =>
      'Your vote has been submitted and can’t be changed.';

  @override
  String get votingMobileSubmittedTitle => 'Vote submitted';

  @override
  String get votingMobileSubmittingTitle => 'Submitting votes...';

  @override
  String get votingNavAllAnswered => 'All questions answered';

  @override
  String votingNavAnsweredProgress(int answered, int total) {
    return '$answered / $total answered';
  }

  @override
  String get votingNavReadyToReview => 'Your answers are ready to review.';

  @override
  String get votingNavTapToJump => 'Tap a question to jump to it.';

  @override
  String votingNavUnansweredCount(int count) {
    return 'Unanswered · $count';
  }

  @override
  String get votingNavUnansweredMenu => 'Unanswered questions';

  @override
  String get votingNoProposalsBody =>
      'This voting round does not contain any proposals.';

  @override
  String get votingNoProposalsTitle => 'No proposals';

  @override
  String get votingNotAvailable => 'Not available';

  @override
  String get votingNotEligible => 'Not eligible';

  @override
  String get votingOptionChoose => 'Choose';

  @override
  String get votingOptionSelected => 'Selected';

  @override
  String get votingPendingBody =>
      'You have an unfinished vote for this round. Resume to complete the submission.';

  @override
  String get votingPendingTitle => 'Vote in progress';

  @override
  String votingPirAhead(String expected, String reported) {
    return 'Configured PIR endpoints are ahead of this voting round snapshot. Expected snapshot block $expected; endpoints report $reported.';
  }

  @override
  String votingPirBehind(String expected, String reported) {
    return 'Voting PIR data is not ready for this voting round yet. Expected snapshot block $expected; PIR endpoints report $reported. Retry once the PIR service catches up.';
  }

  @override
  String votingPirNoMatch(String expected) {
    return 'No PIR endpoint matched this voting round snapshot. Expected snapshot block $expected.';
  }

  @override
  String votingPirNoMatchDiagnostics(String expected, String diagnostics) {
    return 'No PIR endpoint matched this voting round snapshot. Expected snapshot block $expected. Diagnostics: $diagnostics.';
  }

  @override
  String get votingPirUnreachable =>
      'Couldn\'t reach any configured PIR endpoint. Check your network connection and retry.';

  @override
  String get votingPollAlreadyUsed => 'Already used for this round';

  @override
  String votingPollClosed(String date) {
    return 'Closed $date';
  }

  @override
  String votingPollCloses(String date) {
    return 'Closes $date';
  }

  @override
  String get votingPollNotEligible => 'Not eligible for this round';

  @override
  String votingPollStarts(String date) {
    return 'Starts $date';
  }

  @override
  String get votingPollsEmptyBody =>
      'There are no token holder voting rounds to display yet.';

  @override
  String get votingPollsEmptyTitle => 'No voting rounds available';

  @override
  String get votingPollsLoadFailedTitle => 'Couldn\'t load voting rounds';

  @override
  String votingPowerMeta(String amount) {
    return 'Voting power $amount';
  }

  @override
  String get votingPowerUnavailableSentence => 'Voting power unavailable.';

  @override
  String get votingPowerUnavailableTitle => 'Voting power unavailable';

  @override
  String get votingPreparingEllipsis => 'Preparing...';

  @override
  String get votingPreparingPower => 'Preparing voting power.';

  @override
  String get votingPreparingPowerMeta => 'Preparing voting power';

  @override
  String votingPrivacyTrimNotice(String amount) {
    return '$amount is left out of this vote to keep your submission less identifiable.';
  }

  @override
  String votingProgressBundlesProved(int proved, int total) {
    return '$proved of $total bundles proved';
  }

  @override
  String votingProgressFinalizingDelegation(String suffix) {
    return 'Finalizing delegation$suffix';
  }

  @override
  String votingProgressReusingProof(String suffix) {
    return 'Reusing an in-progress proof$suffix';
  }

  @override
  String get votingProgressUnknown => 'Unknown';

  @override
  String votingProgressWaitingConfirmation(String suffix) {
    return 'Waiting for submission and confirmation$suffix';
  }

  @override
  String get votingReceiptPower => 'Voting power';

  @override
  String get votingReceiptRound => 'Voting round';

  @override
  String votingRemainingBundles(int count, int total) {
    return '$count of $total remaining bundles';
  }

  @override
  String get votingResultsFallbackTitle => 'Voting results';

  @override
  String get votingResultsHeading => 'Results';

  @override
  String get votingResultsHideDescription => 'Hide description';

  @override
  String votingResultsLoadFailed(String error) {
    return 'Couldn\'t load results: $error';
  }

  @override
  String get votingResultsNoProposals => 'No proposals in this round.';

  @override
  String get votingResultsPending => 'Results pending...';

  @override
  String votingResultsRoundLoadFailed(String error) {
    return 'Couldn\'t load voting round details: $error';
  }

  @override
  String get votingResultsShowDescription => 'Show description';

  @override
  String get votingResultsTotal => 'Total';

  @override
  String votingResultsTotalAmount(String amount) {
    return 'Total: $amount';
  }

  @override
  String get votingResultsVoted => 'Voted';

  @override
  String votingResultsVotedFor(String choice) {
    return 'Voted: $choice';
  }

  @override
  String get votingResultsWinner => 'Winner';

  @override
  String get votingResultsYourVote => 'Your vote';

  @override
  String get votingReviewChooseOne =>
      'Choose at least one option before submitting.';

  @override
  String get votingReviewConfirmSubmit => 'Confirm & submit';

  @override
  String votingReviewLoadFailed(String error) {
    return 'Couldn\'t load review: $error';
  }

  @override
  String get votingReviewSkipped => 'Skipped';

  @override
  String get votingReviewTitle => 'Review your answers';

  @override
  String get votingScanHold =>
      'Hold the Keystone QR code steady in front of your camera';

  @override
  String get votingScanNoCamera =>
      'Keystone voting uses camera QR scanning only. Connect a camera and try again.';

  @override
  String get votingScanReading => 'Reading signature...';

  @override
  String get votingScanSteady => 'Keep the QR code steady and fully visible.';

  @override
  String get votingScanTitle => 'Scan voting signature';

  @override
  String get votingSignedOnlyBody =>
      'Vizor can submit now using only signatures already scanned from Keystone.';

  @override
  String get votingSignedOnlyTitle => 'Use signed bundles only?';

  @override
  String get votingSignedOnlyWarning =>
      'Unsigned bundles are skipped, which lowers voting power for this voting round.';

  @override
  String get votingSkip => 'Skip';

  @override
  String get votingSkipBundles => 'Skip bundles';

  @override
  String votingSkipDialogBody(int skipped, int total) {
    return 'You have not answered $skipped of $total questions. The review screen will mark them as skipped, and skipped questions will not be submitted.';
  }

  @override
  String get votingSkipDialogTitle => 'Skip unanswered questions?';

  @override
  String votingSnapshotBlock(String height) {
    return 'snapshot block $height';
  }

  @override
  String get votingSnapshotUnknown => 'the voting round snapshot block';

  @override
  String get votingSoftwareRequiredBody =>
      'Token holder voting requires a software account. Switch to a software account to vote in this round.';

  @override
  String get votingSoftwareRequiredTitle => 'Software account required';

  @override
  String get votingStatusActive => 'Active';

  @override
  String get votingStatusBodyKeepOpen =>
      'Don\'t close the window. Generating zero-knowledge proofs can take a while; closing now may lose in-flight proof work.';

  @override
  String get votingStatusBodyLedger =>
      'Keep Vizor open. Follow the instructions below for each voting bundle.';

  @override
  String get votingStatusClosed => 'Closed';

  @override
  String get votingStatusFailed => 'Voting failed.';

  @override
  String get votingStatusGenericError =>
      'Voting could not continue for this account. Retry, or switch to an eligible account if this account cannot vote in this voting round.';

  @override
  String get votingStatusTallying => 'Tallying';

  @override
  String get votingStatusTitleLedger => 'Voting with Ledger';

  @override
  String get votingStatusTitleSubmitting => 'Submitting votes';

  @override
  String get votingStatusVoted => 'Voted';

  @override
  String get votingStepCasting => 'Casting votes and submitting shares';

  @override
  String get votingStepFinalizing => 'Finalizing submission';

  @override
  String get votingStepProving => 'Proving voting authority';

  @override
  String get votingStepSigningKeystone => 'Signing with Keystone';

  @override
  String get votingStepSigningLedger => 'Signing with Ledger';

  @override
  String get votingSwitchAccount => 'Switch account';

  @override
  String get votingSwitchEligibleGuidance =>
      'Switch to an eligible account to vote.';

  @override
  String votingSyncBlocksRemaining(int count) {
    return '$count blocks remaining';
  }

  @override
  String votingSyncChainTip(int height) {
    return 'chain tip $height';
  }

  @override
  String votingSyncSynced(int height) {
    return 'Synced to block $height';
  }

  @override
  String get votingSyncWaitingBody =>
      'Your wallet is catching up to this voting round snapshot. Voting will continue automatically once the wallet has synced through the snapshot block.';

  @override
  String get votingSyncWaitingTitle => 'Waiting for wallet sync';

  @override
  String votingTerminalBundle(int number, String reason) {
    return 'bundle $number ($reason)';
  }

  @override
  String votingTerminalMultiple(String bundles) {
    return 'Delegation for $bundles cannot continue. Do not retry it; the transaction may already be on the chain.';
  }

  @override
  String get votingTerminalReasonDefault => 'it ended without confirming';

  @override
  String votingTerminalSingle(String bundle) {
    return 'Delegation $bundle cannot continue. Do not retry it; the transaction may already be on the chain.';
  }

  @override
  String get votingTokenHolderTitle => 'Token holder voting';

  @override
  String get votingViewLess => 'View less';

  @override
  String get votingViewMore => 'View more';

  @override
  String get votingVoteLocked => 'Vote locked';

  @override
  String votingVotedOn(String date) {
    return 'Voted $date';
  }

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
  String get walletLinkDesktopConfirmSubtitle => 'To link Vizor Mobile.';

  @override
  String get walletLinkDesktopEncryptedNotice =>
      'The code is encrypted with a one-time key and expires after a minute.';

  @override
  String get walletLinkDesktopEncryptedStrong =>
      'Only your phone can decode it.';

  @override
  String get walletLinkDesktopErrorDerivationMissing =>
      'Wallet account derivation metadata is not available.';

  @override
  String get walletLinkDesktopErrorExpiredBeforeShown =>
      'The mobile link expired before it could be shown.';

  @override
  String get walletLinkDesktopErrorFallback =>
      'Could not prepare the mobile link.';

  @override
  String get walletLinkDesktopErrorHardwareMetadataMissing =>
      'Hardware wallet metadata is not available.';

  @override
  String get walletLinkDesktopErrorLocked =>
      'Unlock this wallet before linking mobile.';

  @override
  String get walletLinkDesktopErrorNoAccounts =>
      'No wallet accounts are available to link.';

  @override
  String get walletLinkDesktopErrorPrepareFailed =>
      'Could not prepare the mobile link. Try again.';

  @override
  String get walletLinkDesktopErrorServerUnreachable =>
      'Could not reach the linking server. Try again.';

  @override
  String get walletLinkDesktopExpiredBody =>
      'For your security the link is only valid for a minute. Generate a fresh code and scan it again.';

  @override
  String get walletLinkDesktopExpiredTitle => 'Time’s up';

  @override
  String walletLinkDesktopExpiresIn(String time) {
    return 'Expires in $time';
  }

  @override
  String get walletLinkDesktopGenerateNewCode => 'Generate new code';

  @override
  String get walletLinkDesktopInitialBody =>
      'Connect this wallet to your Vizor mobile app by scanning a one-time QR code.';

  @override
  String get walletLinkDesktopLinkedBody =>
      'Vizor Mobile was linked to this wallet.';

  @override
  String walletLinkDesktopLinkedCounts(int accountCount, int contactCount) {
    String _temp0 = intl.Intl.pluralLogic(
      accountCount,
      locale: localeName,
      other: '$accountCount accounts',
      one: '1 account',
    );
    String _temp1 = intl.Intl.pluralLogic(
      contactCount,
      locale: localeName,
      other: '$contactCount contacts',
      one: '1 contact',
    );
    return '$_temp0 and $_temp1 were imported on mobile.';
  }

  @override
  String get walletLinkDesktopLinkedTitle => 'Vizor Mobile linked successfully';

  @override
  String get walletLinkDesktopPreparing => 'Preparing';

  @override
  String get walletLinkDesktopReadyToScan => '1/1 Ready to scan...';

  @override
  String get walletLinkDesktopRegenerate => 'Regenerate';

  @override
  String get walletLinkDesktopScanBody =>
      'Open Vizor on your phone → Add a wallet → Link Vizor Desktop';

  @override
  String get walletLinkDesktopScanTitle => 'Scan with Vizor mobile';

  @override
  String get walletLinkDesktopStartLinking => 'Start linking';

  @override
  String get walletLinkDesktopTitle => 'Link Vizor Mobile';

  @override
  String get walletLinkDesktopUnavailableTitle => 'Link unavailable';

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
