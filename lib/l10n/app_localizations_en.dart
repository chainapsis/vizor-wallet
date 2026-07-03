// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionSystem => 'System';

  @override
  String get settingsSectionMisc => 'Misc';

  @override
  String get settingsSectionDangerZone => 'Danger zone';

  @override
  String get settingsSecretPassphrase => 'Secret passphrase';

  @override
  String get settingsPassword => 'Password';

  @override
  String get settingsProfilePicture => 'Profile picture';

  @override
  String get settingsProfilePictureCustom => 'Custom';

  @override
  String get settingsAccountName => 'Account name';

  @override
  String get settingsContacts => 'Contacts';

  @override
  String get settingsEndpoint => 'Endpoint';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsAboutVizor => 'About Vizor';

  @override
  String get settingsUninstallVizor => 'Uninstall Vizor';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeSystemAuto => 'System (Auto)';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeUpdateError => 'Couldn\'t update theme.';

  @override
  String get settingsLanguageUpdateError => 'Couldn\'t update language.';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonUpdating => 'Updating...';

  @override
  String get settingsUpdateCurrent => 'Current';

  @override
  String get settingsUpdateAvailable => 'Available';

  @override
  String get settingsUpdateUnavailable => 'Unavailable';

  @override
  String get settingsUpdateChecking => 'Checking';

  @override
  String get settingsUpdateRestart => 'Restart';

  @override
  String get settingsUpdateApplying => 'Applying';

  @override
  String get settingsUpdateFailed => 'Failed';

  @override
  String get settingsUpdateUpToDate => 'Up to date';

  @override
  String get settingsUpdateCheck => 'Check';

  @override
  String get settingsUpdateActionCheck => 'Check for updates';

  @override
  String get settingsUpdateActionChecking => 'Checking...';

  @override
  String get settingsUpdateActionDownloading => 'Downloading...';

  @override
  String get settingsUpdateActionRestarting => 'Restarting...';

  @override
  String get settingsUpdateActionDownload => 'Download update';

  @override
  String get settingsUpdateActionRestartToUpdate => 'Restart to update';

  @override
  String get settingsUpdateActionTryAgain => 'Try again';

  @override
  String get settingsUpdateStatusWindowsOnly =>
      'Updates are available in the installed Windows app.';

  @override
  String get settingsUpdateStatusChecking => 'Checking for updates.';

  @override
  String get settingsUpdateStatusUpToDate => 'Vizor is up to date.';

  @override
  String settingsUpdateStatusAvailable(String version) {
    return 'Version $version is available.';
  }

  @override
  String settingsUpdateStatusDownloading(int progress) {
    return 'Downloading $progress%.';
  }

  @override
  String settingsUpdateStatusReady(String version) {
    return 'Version $version is ready.';
  }

  @override
  String get settingsUpdateStatusApplying => 'Restarting Vizor.';

  @override
  String get settingsUpdateStatusCheckFailed => 'Couldn\'t check for updates.';

  @override
  String get settingsUpdateStatusIdle => 'Ready to check for updates.';

  @override
  String get commonBack => 'Back';

  @override
  String get commonClose => 'Close';

  @override
  String get commonOk => 'OK';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonDone => 'Done';

  @override
  String get commonNext => 'Next';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get homeNoticePasswordRotationFailed =>
      'We couldn\'t verify the previous password change. Try again or restart Vizor.';

  @override
  String get navHome => 'Home';

  @override
  String get navSend => 'Send';

  @override
  String get navReceive => 'Receive';

  @override
  String get navSwap => 'Swap';

  @override
  String get navVote => 'Vote';

  @override
  String get navActivity => 'Activity';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navSignOut => 'Sign out';

  @override
  String get navAmount => 'Amount';

  @override
  String get navReview => 'Review';

  @override
  String get navStatus => 'Status';

  @override
  String get navTransaction => 'Transaction';

  @override
  String get navChangePassword => 'Change password';

  @override
  String get navConnectKeystone => 'Connect Keystone';

  @override
  String get navVotingRound => 'Voting round';

  @override
  String get navSubmitted => 'Submitted';

  @override
  String get navResults => 'Results';

  @override
  String get navImporting => 'Importing...';

  @override
  String get sidebarMyAccounts => 'My accounts';

  @override
  String get sidebarManage => 'Manage';

  @override
  String get sidebarShowBalance => 'Show balance';

  @override
  String get sidebarHideBalance => 'Hide balance';

  @override
  String get sidebarCopyShieldedAddress => 'Copy shielded address';

  @override
  String get toastCopied => 'Copied';

  @override
  String get toastAddressCopied => 'Address copied';

  @override
  String get toastAddressCopyFailed => 'Address couldn\'t be copied';

  @override
  String get toastShieldedAddressCopied => 'Shielded address copied';

  @override
  String syncStatusSyncingLabel(String pct) {
    return '$pct% Syncing...';
  }

  @override
  String syncStatusSyncingSemantics(String pct) {
    return 'Syncing $pct percent';
  }

  @override
  String syncStatusFailedLabel(String reason) {
    return 'Syncing failed. $reason...';
  }

  @override
  String syncStatusFailedSemantics(String reason) {
    return 'Syncing failed. $reason';
  }

  @override
  String get syncStatusSynced => 'Vizor is synced';

  @override
  String get syncFailureNetwork => 'Network error';

  @override
  String get syncFailureEndpoint => 'Endpoint error';

  @override
  String get syncFailureDatabaseBusy => 'Wallet data busy';

  @override
  String get syncFailureDatabaseFatal => 'Wallet data error';

  @override
  String get syncFailureChainRecovery => 'Chain recovery';

  @override
  String get syncFailureParse => 'Data error';

  @override
  String get syncFailureUnknown => 'Unknown error';

  @override
  String get syncUserMessageNetwork =>
      'Network connection lost. We\'ll keep trying automatically.';

  @override
  String get syncUserMessageEndpoint =>
      'Cannot reach the configured Zcash endpoint. Check your endpoint settings.';

  @override
  String get syncUserMessageDatabaseBusy =>
      'Wallet data is busy. We\'ll try syncing again automatically.';

  @override
  String get syncUserMessageDatabaseFatal =>
      'Wallet data could not be read. Restart the app and retry sync.';

  @override
  String get syncUserMessageChainRecovery =>
      'The chain changed while syncing. We\'ll keep trying to recover.';

  @override
  String get syncUserMessageParse =>
      'Sync data could not be processed. Retry sync or check your endpoint.';

  @override
  String get syncUserMessageUnknown => 'Sync failed. Retry sync to continue.';

  @override
  String get homeShieldNoActiveAccount => 'No active account.';

  @override
  String homeErrorGeneric(String details) {
    return 'Something went wrong. Try again in a moment.\n\nDetails: $details';
  }

  @override
  String homeTransparentBalanceLabel(String balance) {
    return 'Transparent: $balance';
  }

  @override
  String get homeShielding => 'Shielding...';

  @override
  String get homeShieldNow => 'Shield now';

  @override
  String homeImportingAccount(String name) {
    return 'Importing $name\nKeep Vizor open & running.';
  }

  @override
  String get homeImportingGeneric =>
      'It might take some time.\nKeep Vizor open & running.';

  @override
  String get homeShieldedBalance => 'Shielded balance';

  @override
  String get homeReceiveFirstZec => 'Receive your first ZEC';

  @override
  String get homeLoadingActivity => 'Loading activity...';

  @override
  String get homeNoActivity => 'No activity, yet...';

  @override
  String get homeFirstTxPrompt => 'How about running your first ZEC tx?';

  @override
  String get homeRecentActivity => 'Recent activity';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get shieldQueuedRetry => 'Shielding queued for retry. Check Activity.';

  @override
  String get homeShieldComplete => 'Shielding complete';

  @override
  String get shieldErrorNoPassphrase =>
      'Secret Passphrase isn\'t available for this account.';

  @override
  String get shieldErrorWaitForSync => 'Wait for sync to finish, then shield.';

  @override
  String get shieldErrorTooSmall =>
      'Transparent balance is too small to shield after fees.';

  @override
  String get shieldErrorBroadcast =>
      'Couldn\'t broadcast your shielding transaction. Try again.';

  @override
  String get shieldErrorGeneric => 'Couldn\'t shield your balance. Try again.';

  @override
  String get shieldTxBroadcastUnknown =>
      'The shield transaction may have reached the network, but confirmation timed out. Check activity before trying again.';

  @override
  String get shieldTxStorageFailed =>
      'The shield transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';

  @override
  String get shieldTxUncertain =>
      'The shield transaction status is uncertain. Check activity before trying again.';

  @override
  String get keystoneShieldParamsError =>
      'Required proving parameters could not be prepared.';

  @override
  String get keystoneShieldSignatureError =>
      'Keystone signature could not be applied.';

  @override
  String get keystoneShieldFinalizeError =>
      'Shield transaction could not be finalized.';

  @override
  String get keystoneShieldPrepareError =>
      'Keystone signing could not be prepared.';

  @override
  String get keystoneShieldQrDecodeError =>
      'This QR code could not be decoded as a Keystone signature.';

  @override
  String get keystoneShieldOpenSignedQr =>
      'Open the signed shield QR on Keystone, then scan again.';

  @override
  String get keystoneScanHoldSteady =>
      'Keep the QR code steady and fully visible.';

  @override
  String get keystoneToggleFlashlight => 'Toggle flashlight';

  @override
  String get keystoneCancelSigning => 'Cancel signing';

  @override
  String get keystoneShieldBroadcasting => 'Broadcasting shield tx';

  @override
  String get keystoneShieldTransparentBalance => 'Shield transparent balance';

  @override
  String get keystoneShieldKeepOpen =>
      'Keep Vizor open while the transaction is sent.';

  @override
  String get keystoneShieldScanInstructions =>
      'Use your Keystone wallet to scan this shielding QR code. Follow the steps on your device.';

  @override
  String get keystoneCameraDenied =>
      'Camera access is off. Allow it in Settings to scan Keystone signatures.';

  @override
  String get keystoneCameraUnavailable =>
      'The camera is unavailable right now.';

  @override
  String get keystoneReadingSignature => 'Reading signature...';

  @override
  String keystoneScanningProgress(int progress) {
    return 'Scanning... $progress%';
  }

  @override
  String get keystoneScanSignedQr => 'Scan the signed QR on your Keystone';

  @override
  String get keystoneBackToWallet => 'Back to wallet';

  @override
  String get keystoneShowQr => 'Show QR';

  @override
  String get keystoneBroadcastingEllipsis => 'Broadcasting...';

  @override
  String get keystoneNextStep => 'Next step';

  @override
  String get homeShield => 'Shield';

  @override
  String get homeFirstTxPromptWrapped =>
      'How about running your\nfirst ZEC tx?';

  @override
  String get homeHangTight =>
      'Hang tight ... It might take some time. Keep Vizor open & running.';

  @override
  String get receiveNoActiveAccount => 'No active account';

  @override
  String get receiveRenewShieldedError =>
      'We couldn\'t refresh your shielded address. Try again, or use your current one.';

  @override
  String receiveRenewShieldedErrorDetails(String details) {
    return 'We couldn\'t refresh your shielded address. Try again, or use your current one.\nDetails: $details';
  }

  @override
  String receiveTitle(String ticker) {
    return 'Receive $ticker';
  }

  @override
  String get receiveCopyTransparentAddress => 'Copy transparent address';

  @override
  String get receiveShareShieldedAddress => 'Share shielded address';

  @override
  String get receiveShareTransparentAddress => 'Share transparent address';

  @override
  String get receiveShielded => 'Shielded';

  @override
  String get receiveTransparent => 'Transparent';

  @override
  String get receiveQrUnavailable => 'QR unavailable';

  @override
  String get previewUsername => 'Username';

  @override
  String get aboutKeplrTeamHeading => 'Built by the Keplr team';

  @override
  String get aboutKeplrTeamBody =>
      'We built Keplr, the wallet used by millions across Cosmos, Ethereum, and Bitcoin. Vizor is our take on what a Zcash wallet should feel like.';

  @override
  String get aboutShieldedHeading => 'Designed for shielded Zcash';

  @override
  String get aboutShieldedBody =>
      'Vizor is built around shielded transactions, where the sender, recipient, and amount stay private. Transparent Zcash works too, but private is the default.';

  @override
  String get aboutOpenSourceHeading => 'Open source, self-custodied';

  @override
  String get aboutOpenSourceBody =>
      'Vizor is Apache licensed. Your keys stay on your device.\nWe don\'t see your balances or your transactions.';

  @override
  String get aboutLegalPlaceholderHeading =>
      'From the team that brought you Keplr Wallet.';

  @override
  String get aboutLegalPlaceholderBody =>
      'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount.';

  @override
  String get aboutTermsOfUsage => 'Terms of Usage';

  @override
  String get aboutPrivacyPolicy => 'Privacy Policy';

  @override
  String get aboutVizorWallet => 'About Vizor Wallet';

  @override
  String get aboutWelcome => 'Welcome';

  @override
  String get aboutOpenGithub => 'Open Vizor GitHub';

  @override
  String get aboutWebsite => 'Website';

  @override
  String get aboutOpenWebsite => 'Open Vizor website';

  @override
  String get activitySendFailed => 'Send failed';

  @override
  String get activitySending => 'Sending';

  @override
  String get activityReceiving => 'Receiving';

  @override
  String get activityReceived => 'Received';

  @override
  String get activitySent => 'Sent';

  @override
  String get activityShielded => 'Shielded';

  @override
  String get activityRefunded => 'Refunded';

  @override
  String get activityFailed => 'Failed';

  @override
  String get activityInProgress => 'In progress';

  @override
  String get activityCompleted => 'Completed';

  @override
  String get activityMixed => 'Mixed';

  @override
  String get activityEarlier => 'Earlier';

  @override
  String get activityJustNow => 'just now';

  @override
  String activityMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String get activityThisWeek => 'This week';

  @override
  String activityTodayAt(String time) {
    return 'Today, $time';
  }

  @override
  String activityYesterdayAt(String time) {
    return 'Yesterday, $time';
  }

  @override
  String activityDateAt(String date, String time) {
    return '$date, $time';
  }

  @override
  String get activityNoActiveAccount => 'No active account.';

  @override
  String get activityTxLoadError => 'Transaction could not be loaded.';

  @override
  String get activityTxRefreshError =>
      'Latest transaction status could not be refreshed.';

  @override
  String get activityTxHashCopied => 'Transaction hash copied';

  @override
  String get activityLoadingTx => 'Loading transaction…';

  @override
  String get activityLoadError => 'Activity could not be loaded.';

  @override
  String get activityTimestamp => 'Timestamp';

  @override
  String get activityTxId => 'Tx ID';

  @override
  String get activityFrom => 'From';

  @override
  String get activityTo => 'To';

  @override
  String get activityShowFullAddress => 'Show full address';

  @override
  String get activityFromTransparentBalance => 'From transparent balance';

  @override
  String get activityReceivingEllipsis => 'Receiving...';

  @override
  String get activitySendingEllipsis => 'Sending...';

  @override
  String get activitySentSuccessfully => 'Sent successfully';

  @override
  String get swapFailedTitle => 'Swap failed';

  @override
  String get swapReviewQuote => 'Review quote';

  @override
  String get shieldReceiptInProgress => 'Shielding in progress...';

  @override
  String get shieldReceiptCompleted => 'Shielded successfully';

  @override
  String get shieldReceiptFailed => 'Shielding failed';

  @override
  String get receiveReceiptInProgress => 'Receive in progress...';

  @override
  String get receiveReceiptCompleted => 'Received successfully';

  @override
  String get receiveReceiptFailed => 'Receive failed';

  @override
  String get receivedFeeTooltip =>
      'Network fee paid by the sender to process this transaction.';

  @override
  String get activityNetworkFee => 'Network fee';

  @override
  String get activityMessage => 'Message';

  @override
  String get activityFailedFundsReturned => 'Failed, funds returned';

  @override
  String sendTitle(String ticker) {
    return 'Send $ticker';
  }

  @override
  String get sendKeystoneNoTex => 'Keystone does not support TEX sends yet.';

  @override
  String get sendInsufficientBalance => 'Insufficient balance';

  @override
  String get sendInsufficientShieldedBalance => 'Insufficient shielded balance';

  @override
  String get sendInsufficientBalanceCoverFee =>
      'Insufficient balance to cover fee';

  @override
  String get sendInsufficientShieldedBalanceCoverFee =>
      'Insufficient shielded balance to cover fee';

  @override
  String get sendInsufficientBalanceIncludingFee =>
      'Insufficient balance including fee';

  @override
  String get sendInsufficientShieldedBalanceIncludingFee =>
      'Insufficient shielded balance including fee';

  @override
  String sendInsufficientBalanceWithFee(String fee) {
    return 'Insufficient balance (fee: $fee)';
  }

  @override
  String sendInsufficientShieldedBalanceWithFee(String fee) {
    return 'Insufficient shielded balance (fee: $fee)';
  }

  @override
  String get sendMessageTooLong => 'Message is too long';

  @override
  String get sendMessageShieldedOnly =>
      'Message is only available for shielded addresses';

  @override
  String get sendNoActiveAccount => 'No active account';

  @override
  String get sendEnterValidAddressForMax => 'Enter a valid address to use Max';

  @override
  String get sendMaxUnavailable => 'Max amount unavailable';

  @override
  String get sendInvalidAmount => 'Invalid amount';

  @override
  String get sendCalculatingMax => 'Calculating max amount';

  @override
  String get sendEnterValidAddress => 'Enter a valid address';

  @override
  String get sendInvalidAddress => 'Invalid address';

  @override
  String get sendAddressValidationFailed => 'Address validation failed';

  @override
  String get sendSendTo => 'Send to';

  @override
  String get sendZcashAddressHint => 'Zcash address';

  @override
  String get sendZcashAddressHintMobile => 'Zcash Address';

  @override
  String get sendAddMessageHint => 'Add a message';

  @override
  String get sendCloseMessage => 'Close message';

  @override
  String get sendContactsZcashTitle => 'Contacts Zcash';

  @override
  String get sendNoZcashContacts => 'No Zcash contacts';

  @override
  String get sendOpenContacts => 'Open contacts';

  @override
  String get sendSpendableTooltipTitle =>
      'Your spendable balance may be lower than your total balance.';

  @override
  String get sendSpendableTooltipBody =>
      'Funds need confirmations before they can be spent: 3 for change from your own wallet, 10 for funds received from others. Shielded notes also need to be fully scanned. They\'ll become available shortly.';

  @override
  String sendMaxLabel(String amount) {
    return 'Max: $amount';
  }

  @override
  String get sendUseMaxBalance => 'Use maximum spendable balance';

  @override
  String get sendSpendableInfo => 'Spendable balance info';

  @override
  String get sendAddMemo => 'Add a memo';

  @override
  String get sendEncryptedShieldedOnly =>
      'Encrypted, for shielded addresses only.';

  @override
  String get sendScanKeystoneQr => 'Scan your Keystone QR Code';

  @override
  String get keystoneSendQrDecodeError =>
      'This QR code could not be decoded as a Keystone transaction signature.';

  @override
  String get keystoneOpenSignedTxQr =>
      'Open the signed transaction QR on Keystone, then scan again.';

  @override
  String get keystoneScanQrTitle => 'Scan QR Code';

  @override
  String get keystoneHoldQrSteady =>
      'Hold the QR code steady in front of your camera';

  @override
  String get keystoneCameraOnly =>
      'Keystone signing uses camera QR scanning only. Connect a camera and try again.';

  @override
  String get sendSigningCancelledParams =>
      'Signing was cancelled before proving parameters were downloaded.';

  @override
  String get sendTxExpired => 'Transaction expired before it could be signed.';

  @override
  String get sendKeystonePrepareError =>
      'Keystone signing could not be prepared. Return to Send and try again.';

  @override
  String get sendKeystonePrepareErrorGoBack =>
      'Keystone signing could not be prepared. Go back and try again.';

  @override
  String get sendConfirmWithKeystone => 'Confirm with Keystone';

  @override
  String get sendConfirmAndSend => 'Confirm & send';

  @override
  String get sendConfirmAndSendMobile => 'Confirm & Send';

  @override
  String get sendScanWithKeystone => 'Scan with your Keystone';

  @override
  String get sendAfterScanGetSignature =>
      'After you scanned, click Get signature.';

  @override
  String get sendScanNowProofs =>
      'Scan now. Signature import unlocks after proofs are ready.';

  @override
  String get sendPreparing => 'Preparing';

  @override
  String get sendPreparingEllipsis => 'Preparing...';

  @override
  String get sendGetSignature => 'Get signature';

  @override
  String get sendNotEnoughZec => 'Not enough ZEC';

  @override
  String get sendFinishReview => 'Finish & review';

  @override
  String get sendEnterAmountToContinue => 'Enter amount to continue';

  @override
  String get sendEnterAddressToContinue => 'Enter address to continue';

  @override
  String get addressTex => 'TEX address';

  @override
  String get sendSelectRecipient => 'Select Recipient';

  @override
  String get sendEnterAmount => 'Enter Amount';

  @override
  String get sendReviewSend => 'Review Send';

  @override
  String get sendScanAQrCode => 'Scan a QR Code';

  @override
  String get sendScanAddressUsingCamera => 'Scan an address using camera';

  @override
  String sendContactCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contacts',
      one: '1 contact',
    );
    return '$_temp0';
  }

  @override
  String get sendPaste => 'Paste';

  @override
  String get sendClear => 'Clear';

  @override
  String get sendSendingTo => 'Sending to';

  @override
  String get sendMax => 'Max';

  @override
  String get sendEnterAmountInZec => 'Enter amount in ZEC';

  @override
  String get sendEnterAmountInUsd => 'Enter amount in USD';

  @override
  String get sendFullAddress => 'Full address';

  @override
  String get sendAddShortEncryptedMessage => 'Add short encrypted message';

  @override
  String get sendAboutTxFee => 'About the transaction fee';

  @override
  String get sendAddMemoTitle => 'Add Memo';

  @override
  String get sendOnlyRecipientCanRead => 'Only the recipient can read this';

  @override
  String get sendClearMemo => 'Clear memo';

  @override
  String get sendReviewTitle => 'Review send';

  @override
  String get sendCollapse => 'Collapse';

  @override
  String sendTexAddressLabel(String address) {
    return 'TEX - $address';
  }

  @override
  String get sendInProgressTitle => 'Send in progress...';

  @override
  String sendAmountToRecipient(String amount, String recipient) {
    return '$amount to $recipient';
  }

  @override
  String get sendConfirmTransaction => 'Confirm transaction';

  @override
  String get sendErrorInsufficientForAmountFee =>
      'Insufficient shielded balance to cover amount and fee.';

  @override
  String get sendErrorNetwork =>
      'Network error. Check your connection and try again.';

  @override
  String get sendErrorPartialBroadcast =>
      'Some parts of this transaction were sent. Open Activity to see what went through before you try again.';

  @override
  String get sendErrorBroadcastRejected =>
      'The network rejected this transaction. Try again.';

  @override
  String get sendErrorBroadcastRejectedLater =>
      'The network rejected this transaction. Try again later.';

  @override
  String get sendErrorExpiredTryAgain =>
      'Transaction expired before it could be sent. Try again.';

  @override
  String get sendErrorExpired => 'Transaction expired before it could be sent.';

  @override
  String get sendErrorGenericShort => 'Send failed. Try again.';

  @override
  String get sendErrorCheckStatus =>
      'Transaction couldn\'t be sent. Go back to your wallet and check the latest status.';

  @override
  String get saplingDownloadRequired => 'Download Required';

  @override
  String get saplingDownloadBody =>
      'To create this private transaction, your wallet needs to download about 50MB of cryptographic parameters.';

  @override
  String get saplingDownloadOnce =>
      'This happens once, then it\'s done.\nNetwork data charges may apply.';

  @override
  String get saplingDownload => 'Download';

  @override
  String get accountsAddAccount => 'Add account';

  @override
  String get accountsCurrent => 'Current';

  @override
  String get accountsOther => 'Other';

  @override
  String get accountsAccountActions => 'Account actions';

  @override
  String get accountsEditAccount => 'Edit account';

  @override
  String get accountsCopyAddress => 'Copy address';

  @override
  String get accountsSendZec => 'Send ZEC';

  @override
  String get accountsRemoveAccount => 'Remove account';

  @override
  String accountsOptionsFor(String name) {
    return 'Account options for $name';
  }

  @override
  String get accountsRemoveResetWarning =>
      'Removing this account will completely reset the Vizor app. This means deleting all accounts and requiring you to import accounts again.\nThis cannot be undone.';

  @override
  String get accountsRemoveWarning =>
      'Are you sure you want to remove this account? This action can\'t be reverted.\nYou will have to re-import your account.';

  @override
  String get accountsResetVizor => 'Reset Vizor';

  @override
  String get accountsCheckingSwaps =>
      'Checking this account for active swaps before removal.';

  @override
  String get accountsSwapCheckFailed =>
      'Couldn\'t check this account for active swaps. Try again before removing it.';

  @override
  String accountsActiveSwaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active swaps',
      one: '1 active swap',
    );
    return 'This account has $_temp0. Complete or remove them from swap activity before removing this account.';
  }

  @override
  String get accountsIncorrectPassword =>
      'Incorrect password. Please try again.';

  @override
  String get accountsEnterPassword => 'Enter your password';

  @override
  String get accountsCheckingPassword => 'Checking password...';

  @override
  String get accountsStoppingSync => 'Stopping sync...';

  @override
  String get accountsResetting => 'Resetting...';

  @override
  String get accountsRemoving => 'Removing account...';

  @override
  String get accountsChangeProfilePicture => 'Change profile picture';

  @override
  String get accountsSelectProfilePicture => 'Select profile picture';

  @override
  String get accountsClearAccountName => 'Clear account name';

  @override
  String get accountsSaveEdits => 'Save edits';

  @override
  String get accountsUpdatePicture => 'Update picture';

  @override
  String get accountsOtherAccounts => 'Other accounts';

  @override
  String get accountsManageAccounts => 'Manage accounts';

  @override
  String get accountsNameHint => '1-20 characters';

  @override
  String get accountsNameLengthMessage => 'Use up to 20 characters.';

  @override
  String get accountsUpdateError => 'Couldn\'t update account.';

  @override
  String get abSearch => 'Search';

  @override
  String get abSearchHint => 'Search for label or network';

  @override
  String get abEditContact => 'Edit contact';

  @override
  String get abRemoveContact => 'Remove contact';

  @override
  String get abNoContactsYet => 'No contacts yet';

  @override
  String get abAddFirstContact => 'Add your first contact to get started.';

  @override
  String get abNoContactsFound => 'No contacts were found';

  @override
  String get abModifySearch => 'Try to modify your search';

  @override
  String get abAddContact => 'Add contact';

  @override
  String get abAddressLabel => 'Address label';

  @override
  String get abAddLabelHint => 'Add label 1-20 characters';

  @override
  String get abAddress => 'Address';

  @override
  String get abAddAddressHint => 'Add address';

  @override
  String get abScanAddressQr => 'Scan address QR';

  @override
  String get abChangeContactPicture => 'Change contact picture';

  @override
  String get abChainAndAddress => 'Chain & address';

  @override
  String get abSelectNetwork => 'Select network';

  @override
  String get abSelectContactPicture => 'Select contact picture';

  @override
  String get abSearchNetworkHint => 'Search network';

  @override
  String get abNoNetworksFound => 'No networks found';

  @override
  String get abContactWillBeRemoved => 'This contact will be removed.';

  @override
  String abNamedContactWillBeRemoved(String name) {
    return '$name will be removed from your contacts.';
  }

  @override
  String get abLoadError =>
      'Couldn\'t load your contacts. Try again, or contact support if this keeps happening.';

  @override
  String get abSaveError => 'Couldn\'t save contact. Try again.';

  @override
  String get abRemoveError => 'Couldn\'t remove contact. Try again.';

  @override
  String get abNoContactsFoundShort => 'No contacts found';

  @override
  String get abSearchContacts => 'Search contacts';

  @override
  String get abCloseContacts => 'Close contacts';

  @override
  String get abClearSearch => 'Clear search';

  @override
  String get abQrNoAddress => 'QR code did not include an address.';

  @override
  String get abClearName => 'Clear name';

  @override
  String get abClearAddress => 'Clear address';

  @override
  String get abNetwork => 'Network';

  @override
  String get abName => 'Name';

  @override
  String get abAddNameHint => 'Add a name';

  @override
  String get abAddAnAddressHint => 'Add an address';

  @override
  String get abSaveContact => 'Save contact';

  @override
  String get abRemoveContactQuestion => 'Remove contact?';

  @override
  String get abNoPastTxEffect => 'This does not affect any past transactions.';

  @override
  String get abInvalidEvm => 'Invalid EVM address';

  @override
  String get abInvalidBitcoin => 'Invalid Bitcoin address';

  @override
  String get abInvalidSolana => 'Invalid Solana address';

  @override
  String get abInvalidZcash => 'Invalid Zcash address';

  @override
  String get abInvalidNear => 'Invalid NEAR address';

  @override
  String get abNearHint =>
      'NEAR accounts usually end in .near — double-check this address';

  @override
  String get abAddLabelError => 'Add a label';

  @override
  String get abLabelLength => 'Use 1-20 characters';

  @override
  String get abAddAddressError => 'Add an address';

  @override
  String abScanNetworkQr(String network) {
    return 'Scan $network QR code';
  }

  @override
  String get keystoneScanReadingQr => 'Reading QR...';

  @override
  String get cameraNoneFound => 'No camera found';

  @override
  String get cameraLoading => 'Loading camera...';

  @override
  String get cameraDefault => 'Default camera';

  @override
  String cameraDefaultSuffix(String name) {
    return '$name (Default)';
  }

  @override
  String get cameraOpenError =>
      'No camera could be opened. Check that a camera is connected and not in use by another app.';

  @override
  String get cameraDeniedWindowsTitle => 'Enable Windows camera access';

  @override
  String get cameraDeniedTitle => 'You\'ve denied the Camera access';

  @override
  String get cameraDeniedWindowsDesc =>
      'Turn on Camera access and Let desktop apps access your camera in Windows Settings.';

  @override
  String get cameraDeniedDesc =>
      'Request again, or enable manually\nin the System settings.';

  @override
  String get cameraAllow => 'Allow camera';

  @override
  String get cameraRequestAgain => 'Request again';

  @override
  String get cameraOpenSettings => 'Open settings';

  @override
  String get cameraEnableAccess => 'Enable camera access';

  @override
  String get cameraKeystoneRequired =>
      'A camera is required to connect Keystone.\nYou can revert this in settings anytime later.';

  @override
  String get cameraUnavailableTitle => 'Camera unavailable';

  @override
  String get troubleScanning => 'Trouble scanning?';

  @override
  String get troubleTipFullScreen =>
      'Tap the QR code on your Keystone to show it full screen. This is the easiest fix.';

  @override
  String get troubleTipDistance =>
      'Move your Keystone a few inches further from the camera so it can focus.';

  @override
  String get troubleTipLighting =>
      'Make sure the room is well-lit and the QR code isn\'t reflecting glare.';

  @override
  String get troubleTipContinuity =>
      'On a Mac, you can use Continuity Camera to scan with your iPhone instead.';

  @override
  String get cameraLabel => 'Camera';

  @override
  String get cameraSelect => 'Select Camera';

  @override
  String get cameraDetailDefault => 'Default';

  @override
  String get cameraDetailExternal => 'External';

  @override
  String get cameraDetailFront => 'Front';

  @override
  String get cameraDetailBack => 'Back';

  @override
  String get cameraDetailNormal => 'Normal';

  @override
  String get cameraDetailWide => 'Wide';

  @override
  String get cameraDetailZoom => 'Zoom';

  @override
  String get keystonePrepareWallet => 'Prepare your Keystone wallet';

  @override
  String get keystoneStepCheckFirmware => '1. Check Keystone firmware';

  @override
  String get keystoneStepPrepareConnect => '2. Prepare to connect';

  @override
  String get keystoneOnYourKeystone => 'On your Keystone';

  @override
  String get keystoneStepTapConnect =>
      'Tap ••• (top right), then Connect software wallet.';

  @override
  String get keystoneStepSelectVizor => 'Select Vizor (or ZODL)';

  @override
  String get keystoneOnVizor => 'On Vizor';

  @override
  String get keystoneStepScanDynamicQr =>
      'Scan the dynamic QR code on your Keystone.';

  @override
  String get keystoneFirmwareNote =>
      'Make sure your Keystone is on the latest Cypherpunk firmware. ';

  @override
  String get keystoneDownloadFirmware => 'Download Keystone firmware';

  @override
  String get keystoneNoZcashAccounts =>
      'No Zcash accounts were found on this Keystone QR.';

  @override
  String get keystoneAccountQrDecodeError =>
      'This QR code could not be decoded as a Keystone Zcash account.';

  @override
  String get keystoneOpenAccountQr =>
      'Open the Zcash account QR on Keystone, then scan again.';

  @override
  String get keystoneReadingAccounts => 'Reading accounts...';

  @override
  String get keystoneImportCameraOnly =>
      'Keystone import uses camera QR scanning only. Connect a camera and try again.';

  @override
  String get keystoneSelectAccount => 'Select account';

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
  String keystoneAccountFallback(int index) {
    return 'Account $index';
  }

  @override
  String get keystoneScanAccountQr => 'Scan the Keystone account QR';

  @override
  String get onbEstimatingHeight => 'Estimating height...';

  @override
  String get onbCheckingAccounts => 'Checking accounts...';

  @override
  String get onbPausingSync => 'Pausing sync...';

  @override
  String get onbImportingWallet => 'Importing wallet...';

  @override
  String get onbSelectMonth => 'Select month';

  @override
  String get onbSelectDate => 'Select date';

  @override
  String get onbBirthdayTitle => 'Around when did you create your wallet?';

  @override
  String get onbBirthdaySubtitle =>
      'An estimate is enough — sync starts\nfrom there.';

  @override
  String get onbDontRemember => 'I don’t remember';

  @override
  String get onbEnterMonth => 'Enter the month';

  @override
  String get onbEnterDate => 'Enter the date';

  @override
  String get onbEnterBlockHeight => 'Enter the block height';

  @override
  String get onbBlockHeight => 'Block height';

  @override
  String onbAtLeastHeight(String height) {
    return 'At least $height.';
  }

  @override
  String onbBetweenHeights(String min, String max) {
    return 'Between $min and $max.';
  }

  @override
  String get onbPickMonth => 'Pick a month';

  @override
  String get onbPickDate => 'Pick a date';

  @override
  String get onbEstimateFailed =>
      'Couldn\'t estimate a height for that date. Enter a block height instead.';

  @override
  String get scanZcashQrCaption => 'Scan a Zcash QR code to continue';

  @override
  String get scanAddressQrTitle => 'Scan the address QR code';

  @override
  String get scanNeedsCamera => 'QR scanning needs a camera on this device.';

  @override
  String get scanAddressNeedsCamera =>
      'Address QR scanning needs a camera on this device.';

  @override
  String get scanAddressRequiresCamera =>
      'Address QR scanning requires a camera on this device.';

  @override
  String get scanCloseScanner => 'Close scanner';

  @override
  String get scanLoadingEllipsis => 'Loading...';

  @override
  String get scanLoading => 'Loading';

  @override
  String get scanGrantCameraAccess => 'Grant access to your camera';

  @override
  String get scanQrNoAddress => 'QR code did not include an address.';

  @override
  String get scanCameraDeniedTitle => 'You\'ve denied camera access';

  @override
  String get keystoneLoadingQr => 'Loading the QR code ...';

  @override
  String get keystoneSignQrDecodeError =>
      'This QR code could not be decoded as a Keystone signature.';

  @override
  String get keystoneSignPrepareError =>
      'Keystone signing could not be prepared.';

  @override
  String get keystoneScanSignedKeystoneQr => 'Scan the signed Keystone QR';

  @override
  String get keystoneSignNeedsCamera =>
      'Keystone signing needs a camera on this device.';

  @override
  String get keystoneCloseSigning => 'Close Keystone signing';

  @override
  String get onbWelcomeToVizor => 'Welcome to Vizor';

  @override
  String get onbSelectMethod => 'Select the method you want.';

  @override
  String get onbCreateWallet => 'Create wallet';

  @override
  String get onbImportWallet => 'Import wallet';

  @override
  String get onbAgreePrefix => 'By using Vizor you agree to our ';

  @override
  String get onbTerms => 'Terms';

  @override
  String get onbPrivacy => 'Privacy';

  @override
  String get onbEndpointSettings => 'Endpoint settings';

  @override
  String get onbPrivateMoney => 'Private money.\nBy default';

  @override
  String get onbGetStarted => 'Get started\nwith Vizor';

  @override
  String get onbCreateAWallet => 'Create a wallet';

  @override
  String get onbImportAWallet => 'Import a wallet';

  @override
  String get onbIncorrectPassword => 'Incorrect password. Try again.';

  @override
  String get onbWelcomeBack => 'Welcome back';

  @override
  String get onbEnterPasswordToOpen => 'Enter your password to open Vizor.';

  @override
  String get onbEnterPassword => 'Enter password';

  @override
  String get onbUnlockVizor => 'Unlock Vizor';

  @override
  String get onbForgotPassword => 'Forgot password?';

  @override
  String onbResetAfterSeconds(int seconds) {
    return 'Reset after ${seconds}s...';
  }

  @override
  String get onbCannotBeUndone => 'This cannot be undone.';

  @override
  String get onbLostPassword => 'Lost password?';

  @override
  String get onbLostPasswordBodyPrefix =>
      'If you\'ve lost your password, the only way to recover\nyour account is to ';

  @override
  String get onbLostPasswordReset => 'completely reset Vizor app';

  @override
  String get onbLostPasswordBodyMiddle =>
      ', which\nmeans deleting all accounts and requiring you to\n';

  @override
  String get onbLostPasswordReimport => 'import accounts again';

  @override
  String get walletResetFailed => 'Couldn\'t reset Vizor. Please try again.';

  @override
  String get storageDbUpdateStillFailed =>
      'The wallet database update still failed.';

  @override
  String get storageStillUnavailable => 'Secure storage is still unavailable.';

  @override
  String get storageRetrying => 'Retrying';

  @override
  String get storageQuit => 'Quit';

  @override
  String get storageDbUpdateTitle => 'Unable to update wallet database';

  @override
  String get storageOpenFailedTitle => 'Unable to open Vizor';

  @override
  String get storageUnlockKeyring => 'Unlock your keyring';

  @override
  String get storageLockedTitle => 'Secure storage is locked';

  @override
  String get storageDbUpdateBody =>
      'Vizor needs to update the local wallet database before opening this version. Try again, or quit and restart Vizor.';

  @override
  String get storageStartupBody =>
      'Vizor could not load the local startup state. Try again, or quit and restart Vizor.';

  @override
  String get storageKeyringBody =>
      'Vizor needs access to the system keyring before it can open your wallet. Unlock the keyring, then try again.';

  @override
  String get storageSecureBody =>
      'Vizor needs access to secure storage before it can open your wallet. Unlock secure storage, then try again.';

  @override
  String get onbPasswordsDoNotMatch => 'Passwords do not match.';

  @override
  String get onbPasswordHint => 'Min. 8 characters and symbols';

  @override
  String get onbConfirmPassword => 'Confirm password';

  @override
  String get onbSetPassword => 'Set Password';

  @override
  String get onbSetPasswordSubtitle =>
      'Set password for signing in to Vizor wallet.';

  @override
  String get onbStopSyncing => 'Stop syncing...';

  @override
  String get onbSettingPassword => 'Setting password...';

  @override
  String get onbSetPasswordFinish => 'Set password & finish';

  @override
  String get onbSecretPassphrase => 'Secret Passphrase';

  @override
  String get onbMasterKeySubtitle => 'The master key to your wallet.';

  @override
  String get onbCreatingWallet => 'Creating wallet...';

  @override
  String get onbRevealPhrase => 'Reveal the phrase';

  @override
  String get onbAboutToSeePrefix => 'You are about to see your ';

  @override
  String get onbAboutToSeeSuffix => 'Secret Passphrase.';

  @override
  String get onbPhraseWarning =>
      'This phrase is the master key to your funds. Keep it safe, keep it secret. If you lose it, no one can help you recover your wallet. Not even us.';

  @override
  String get onbCopied => 'Copied';

  @override
  String get onbWelcomeStep => 'Welcome';

  @override
  String get onbShieldedWorld => 'The Shielded World';

  @override
  String get onbZecIntro =>
      'Zcash (ZEC) built around financial privacy & self-custody.';

  @override
  String get onbZecPrivacyBody =>
      'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the sender, recipient, and amount — verified by cryptography, not trust.';

  @override
  String get onbTellMeHow => 'Tell me how Zcash works';

  @override
  String get onbIKnowZcash => 'I know how to use Zcash';

  @override
  String get onbStepIntro => 'Intro to Zcash';

  @override
  String get onbStepAddressTypes => 'Address types';

  @override
  String get onbStepThingsToKnow => 'Things to know';

  @override
  String get onbZcashAddressTypes => 'Zcash Address Types';

  @override
  String get onbTwoAddressTypes =>
      'Zcash has two address types.\nOne for privacy, one for transparency.';

  @override
  String get onbAddressStartsWith => 'Address starts with ';

  @override
  String get onbShieldedAddressSuffix =>
      ' for legacy). Only you can see your account balance and transaction history.';

  @override
  String get onbShieldedAddressOr => ' (or ';

  @override
  String get onbTransparentAddressBody =>
      'Address starts with t, similar to Bitcoin, your address\' balance and transaction history are publicly visible.';

  @override
  String get onbThingsToKnow => 'Things to know';

  @override
  String get onbTimeToSync => 'Time to sync';

  @override
  String get onbTimeToSyncBody =>
      'Your wallet syncs directly with the Zcash network instead of relying on a server. This protects your privacy, but takes a moment. Your funds are safe while the app catches up.';

  @override
  String get onbKeepPrivacy => 'How to keep privacy';

  @override
  String get onbKeepPrivacyBody =>
      'Some exchanges can\'t send to shielded addresses. If you\'re withdrawing from an exchange, use your transparent address. You can shield your ZEC after it arrives.';

  @override
  String get keystoneSendScanInstructions =>
      'Use your Keystone wallet to scan this transaction QR code. Follow the steps on your device.';

  @override
  String get activityNoActivityYet => 'No activity yet';

  @override
  String get activityShieldedSender => 'Shielded sender';

  @override
  String get activityUnknownSender => 'Unknown sender';

  @override
  String get addressUnified => 'Unified address';

  @override
  String get addressZcash => 'Zcash address';

  @override
  String get receiveGenerateNewShielded => 'Generate new shielded address';

  @override
  String get receiveAboutAddressType => 'About this address type';

  @override
  String get receiveShieldedAddressTitle => 'Shielded address';

  @override
  String get receiveTransparentAddressTitle => 'Transparent address';

  @override
  String get receiveShieldedSubtitle => 'Strong privacy by default.';

  @override
  String get receiveTransparentSubtitle => 'Publicly visible';

  @override
  String get receiveShieldedInfoPrivacyTouch =>
      'Tx details — sender, receiver, and amount — are encrypted on-chain & hidden.';

  @override
  String get receiveShieldedInfoPrivacyPointer =>
      'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.';

  @override
  String get receiveShieldedInfoRenewTap =>
      'A new Zcash shielded address is generated only when you tap the renew button.';

  @override
  String get receiveShieldedInfoRenewClick =>
      'A new Zcash shielded address is generated only when you click the renew button.';

  @override
  String get receiveShieldedInfoDiversified =>
      'Each new address is a diversified address derived from the same key. They all receive to the same wallet.';

  @override
  String get receiveTransparentInfoPublicTouch =>
      'All tx details — sender, receiver, and amount — are publicly visible on-chain.';

  @override
  String get receiveTransparentInfoPublicPointer =>
      'All tx details - sender, receiver, and amount - are publicly visible on-chain.';

  @override
  String get receiveTransparentInfoExchanges =>
      'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.';

  @override
  String get receiveTransparentInfoRotation =>
      'After this address receives ZEC and Vizor syncs, your next transparent address will automatically change. Previous addresses still belong to this wallet.';

  @override
  String receiveTransparentInfoShieldGuide(String ticker) {
    return 'After receiving $ticker to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.';
  }

  @override
  String get inputClearText => 'Clear text';

  @override
  String backToLabel(String label) {
    return 'Back to $label';
  }

  @override
  String get txFeeHelpTooltip =>
      'Fee paid to the Zcash network to process this transaction.';

  @override
  String get txFeeSheetTitle => 'Tx fee';

  @override
  String get txFeeSheetBody =>
      'The network fee is set by the Zcash protocol (ZIP 317) based on the transaction size. Vizor adds no extra fee.';

  @override
  String get sheetNotAvailableTitle => 'Not available yet';

  @override
  String get sheetNotAvailableBody => 'This feature is still in progress.';

  @override
  String get onbStepWalletBirthdayHeight => 'Wallet Birthday Height';

  @override
  String get onbStepHowToConnect => 'How to Connect';

  @override
  String get onbStepScanQrCode => 'Scan QR Code';

  @override
  String get onbStepSelectAccount => 'Select Account';

  @override
  String get onbBirthdayMetadataError =>
      'Could not load wallet birthday metadata.';

  @override
  String get onbBirthdayEstimateError =>
      'Could not estimate the wallet birthday height.';

  @override
  String get onbImporting => 'Importing...';

  @override
  String get onbEstimating => 'Estimating...';

  @override
  String get onbCantRemember => 'I can’t remember';

  @override
  String get onbDateHint => 'mm/dd/yyyy';

  @override
  String get onbBlockHeightHint => 'Block height';

  @override
  String get onbUnknownHeightTitle => 'Import from the earliest height?';

  @override
  String get onbUnknownHeightBody =>
      'If you continue without a wallet birthday, Vizor will scan from the earliest supported shielded height. This is safe, but the first sync can take a very long time.';

  @override
  String get onbUnknownHeightHint =>
      'Choosing even an approximate date will be much faster.';

  @override
  String get onbContinueAnyway => 'Continue Anyway';

  @override
  String get onbGoBack => 'Go Back';

  @override
  String get onbErrorDuplicateAccount =>
      'This account is already in your wallet.';

  @override
  String get onbErrorDuplicateKeystoneAccount =>
      'This Keystone account is already in your wallet.';

  @override
  String get onbErrorCurrentBlockHeight =>
      'We need the current Zcash block height to create your wallet. Check your network connection and try again.';

  @override
  String get onbZecIntroMobile =>
      'Zcash (ZEC) built around financial\nprivacy & self-custody.';

  @override
  String get onbFewStepsAway =>
      'You\'re a few steps away from your first private wallet. Let\'s get you set up.';

  @override
  String get onbTwoAddressTypesMobile =>
      'Zcash has two addresses types.\nOne for Privacy, one for Transparency.';

  @override
  String get onbShieldedAddress => 'Shielded Address';

  @override
  String get onbTransparentAddress => 'Transparent Address';

  @override
  String get onbShieldedAddressBodyMobile =>
      'Address starts with u1 (or zs for legacy).\nOnly you can see your account balance and transaction history.';

  @override
  String get onbBeforeYouDiveIn => 'Before you dive in.';

  @override
  String get onbInvalidPassphraseWordCount =>
      'Enter a valid secret passphrase with 12, 15, 18, 21, or 24 words.';

  @override
  String get onbWelcomeAdventurer => 'Welcome, adventurer';

  @override
  String get onbImportByPassphrase =>
      'Import your wallet by entering your secret passphrase.';

  @override
  String get onbWordHint => 'Word';

  @override
  String onbPassphraseWordCountFound(int count) {
    return 'A secret passphrase has 12, 15, 18, 21, or 24 words — found $count.';
  }

  @override
  String get onbPassphraseInvalidOrder =>
      'These words are valid, but they do not form a valid secret passphrase. Check the order or replace any word that looks wrong.';

  @override
  String get onbPassphraseCheckFailed =>
      'That passphrase couldn\'t be checked. Try again.';

  @override
  String get onbImportWalletTitle => 'Import Wallet';

  @override
  String get onbImportWalletSubtitleMobile =>
      'Paste your Secret Passphrase or\nenter it manually word by word.';

  @override
  String get onbConfirmAndImport => 'Confirm & import';

  @override
  String get onbClearSecretPhrase => 'Clear secret phrase';

  @override
  String get onbPasteSecretPhrase => 'Paste secret phrase';

  @override
  String get onbEnterManually => 'Enter manually';

  @override
  String get onbEnterSecretPhraseManually => 'Enter secret phrase manually';

  @override
  String get onbClipboardEmpty => 'Clipboard is empty';

  @override
  String get onbClipboardReadFailed => 'Can\'t read clipboard data';

  @override
  String get onbUnlockBiometricReason => 'Unlock your wallet';

  @override
  String get onbIncorrectPasscode => 'Incorrect Passcode';

  @override
  String get onbWelcomeBackMobile => 'Welcome Back';

  @override
  String get onbOpeningWallet => 'Opening your wallet...';

  @override
  String get onbEnterPasscodeToOpen => 'Enter your passcode to open Vizor';

  @override
  String get onbMasterKeySubtitleMobile => 'The Master Key to your wallet.';

  @override
  String get onbRevealPhraseMobile => 'Reveal phrase';

  @override
  String get onbAboutToSeeMobile =>
      'You are about to see your\nSecret Passphrase.';

  @override
  String get keystoneConnectTitle => 'Connect Keystone';

  @override
  String get keystoneCheckFirmware => 'Check Keystone firmware';

  @override
  String get keystonePrepareToConnect => 'Prepare to connect';

  @override
  String get keystoneFirmwareBody =>
      'Make sure your Keystone is on the latest Cypherpunk firmware. ';

  @override
  String get keystoneLink => 'link';

  @override
  String get keystoneNoAccountsFound =>
      'No Zcash accounts were found on this Keystone QR.';

  @override
  String get keystoneConfirmSelection => 'Confirm selection';

  @override
  String get biometricFaceId => 'Face ID';

  @override
  String get biometricFingerprintInline => 'fingerprint';

  @override
  String get biometricBiometricsInline => 'biometrics';

  @override
  String get biometricFingerprintStandalone => 'Fingerprint';

  @override
  String get biometricBiometricsStandalone => 'Biometrics';

  @override
  String get biometricYourFingerprint => 'your fingerprint';

  @override
  String get biometricUnlockFeatureFace => 'Face ID unlock';

  @override
  String get biometricUnlockFeatureFingerprint => 'Fingerprint unlock';

  @override
  String get biometricUnlockFeatureNone => 'Biometric unlock';

  @override
  String get biometricUnlockFeatureInlineFingerprint => 'fingerprint unlock';

  @override
  String get biometricUnlockFeatureInlineNone => 'biometric unlock';

  @override
  String get biometricChangedFace => 'Face ID changed. Enter your passcode.';

  @override
  String get biometricChangedFingerprint =>
      'Fingerprint changed. Enter your passcode.';

  @override
  String get biometricChangedNone =>
      'Biometric unlock changed. Enter your passcode.';

  @override
  String biometricEnable(String method) {
    return 'Enable $method';
  }

  @override
  String biometricSignIn(String method) {
    return 'Sign in with $method';
  }

  @override
  String biometricFeatureOff(String feature) {
    return '$feature off';
  }

  @override
  String biometricFeatureOn(String feature) {
    return '$feature on';
  }

  @override
  String biometricSetUpFirst(String method) {
    return 'Set up $method in your device settings first.';
  }

  @override
  String biometricUpdateFailed(String feature) {
    return 'Couldn\'t update $feature.';
  }

  @override
  String biometricTurnOffTitle(String feature) {
    return 'Turn off $feature?';
  }

  @override
  String biometricTurnOffBody(String feature) {
    return 'You will use your passcode to unlock Vizor. You can turn $feature back on in settings anytime.';
  }

  @override
  String biometricEnableFailed(String method) {
    return 'Couldn\'t enable $method. You can try again in settings.';
  }

  @override
  String onbBiometricsTitle(String method) {
    return 'Unlock your wallet\nwith $method';
  }

  @override
  String get onbBiometricsSubtitle =>
      'This is an easy and fast way to sign in.\nYou can switch back to passcode anytime.';

  @override
  String get onbNotNow => 'Not now';

  @override
  String passcodeDigitLabel(int digit) {
    return 'Digit $digit';
  }

  @override
  String get passcodeHelpLabel => 'Passcode help';

  @override
  String get passcodeDeleteDigit => 'Delete digit';

  @override
  String get onbCopySecretPassphrase => 'Copy secret passphrase';

  @override
  String get onbPrivateMoneyMobile => 'Private Money.\nBy default';

  @override
  String get onbGetStartedShort => 'Get started';

  @override
  String get onbAnd => ' and ';

  @override
  String get onbOr => 'OR';

  @override
  String get keystoneSubmittingTransaction => 'Submitting the transaction';

  @override
  String get onbMonthHint => 'mm/yyyy';

  @override
  String get onbForgotPasscodeTitle => 'Forgot Passcode?';

  @override
  String get onbForgotPasscodeBody =>
      'If you can\'t remember your passcode, the only way to recover your account is to completely reset the Vizor app, which means deleting all accounts and requiring you to import accounts again.';

  @override
  String get onbContinueToReset => 'Continue to reset Vizor';

  @override
  String get onbResetVizor => 'Reset Vizor';

  @override
  String get onbAreYouSure => 'Are you sure?';

  @override
  String get onbCantBeUndone => 'This can\'t be undone.\n';

  @override
  String get onbProceedResponsibility => 'Proceed on your responsibility.';

  @override
  String get onbSettingUpWallet => 'Setting up your wallet...';

  @override
  String get onbReenterPasscode => 'Re-enter your passcode.';

  @override
  String get onbSixDigitsLength => '6 digits length';

  @override
  String get onbConfirmPasscode => 'Confirm Passcode';

  @override
  String get onbCreatePasscode => 'Create Passcode';

  @override
  String get onbAdditionalAccountsFound => 'Additional accounts found';

  @override
  String get onbChooseAdditionalAccounts =>
      'Choose the additional accounts to import.';

  @override
  String get onbImportAction => 'Import';

  @override
  String get onbBalanceLoading => 'Loading';

  @override
  String get onbTransparentLabel => 'Transparent';

  @override
  String get onbContinueAnywayLower => 'Continue anyway';

  @override
  String get onbGoBackLower => 'Go back';

  @override
  String onbWordNotInList(String word) {
    return '\'$word\' isn\'t in the passphrase word list.';
  }

  @override
  String onbStoppedAtWord(String word) {
    return 'Stopped at \'$word\' — it isn\'t in the passphrase word list.';
  }

  @override
  String get onbNextWord => 'Next word';

  @override
  String get onbEnterYourPassphrase => 'Enter your Secret Passphrase';

  @override
  String get onbAcceptWordCounts => 'Accept 12, 15, 18, 21 or 24 words';

  @override
  String get onbUndoLastWord => 'Undo last word';

  @override
  String get swapStatusAwaitingDeposit => 'Awaiting deposit';

  @override
  String get swapStatusAwaitingExternalDeposit => 'Awaiting external deposit';

  @override
  String get swapStatusDepositObserved => 'Deposit observed';

  @override
  String get swapStatusProcessing => 'Processing';

  @override
  String get swapStatusChecking => 'Checking status';

  @override
  String get swapStatusIncompleteDeposit => 'Incomplete deposit';

  @override
  String get swapStatusComplete => 'Complete';

  @override
  String get swapStatusRefunded => 'Refunded';

  @override
  String get swapStatusExpired => 'Expired';

  @override
  String get swapStatusFailed => 'Failed';

  @override
  String get swapTitleCompleted => 'Swap completed';

  @override
  String get swapTitleFailed => 'Swap failed';

  @override
  String get swapTitleInProgress => 'Swap in progress...';

  @override
  String swapToAddressOnChain(String address, String chain) {
    return 'To: $address on $chain';
  }

  @override
  String swapRefundToAddress(String address) {
    return 'Refund to: $address';
  }

  @override
  String get swapVerbSending => 'Sending';

  @override
  String get swapVerbDepositing => 'Depositing';

  @override
  String swapSymbolSent(String symbol) {
    return '$symbol sent';
  }

  @override
  String swapSymbolDeposited(String symbol) {
    return '$symbol Deposited';
  }

  @override
  String swapDeliverSymbol(String symbol) {
    return 'Deliver $symbol';
  }

  @override
  String swapSendSymbol(String symbol) {
    return 'Send $symbol';
  }

  @override
  String swapDepositSymbol(String symbol) {
    return 'Deposit $symbol';
  }

  @override
  String get swapLastCheckJustNow => 'Last check: just now';

  @override
  String swapLastCheckMinutesAgo(int minutes) {
    return 'Last check: ${minutes}m ago';
  }

  @override
  String get swapStepSourceDesc =>
      'Confirm waiting for the source chain and provider to recognise the deposit';

  @override
  String get swapStepDepositConfirmation => 'Deposit confirmation';

  @override
  String get swapStepDepositConfirmationActive => 'Deposit confirmation...';

  @override
  String get swapStepConfirmingDesc =>
      'Confirming the deposit before the swap route starts.';

  @override
  String get swapStepSwapTitle => 'Swap';

  @override
  String get swapStepSwapActive => 'Swap...';

  @override
  String get swapStepSwapDesc => 'The provider is executing the swap route.';

  @override
  String get swapStepDeliveryDesc =>
      'Delivering the output asset to the recipient address.';

  @override
  String get swapRealizedSlippageLabel => 'Realized slippage';

  @override
  String get swapNotReported => 'Not reported';

  @override
  String get swapTimestampLabel => 'Timestamp';

  @override
  String swapDepositTxLabel(String symbol) {
    return '$symbol deposit tx';
  }

  @override
  String swapRefundedToLabel(String symbol) {
    return '$symbol refunded to';
  }

  @override
  String get swapTotalFeesLabel => 'Total fees';

  @override
  String get swapIncluded => 'Included';

  @override
  String swapRecipientLabel(String symbol) {
    return '$symbol recipient';
  }

  @override
  String swapRefundAddressLabel(String symbol) {
    return '$symbol refund address';
  }

  @override
  String swapDepositToLabel(String symbol) {
    return 'Deposit $symbol to';
  }

  @override
  String get swapMemoLabel => 'Memo';

  @override
  String get swapSlippageToleranceLabel => 'Slippage tolerance';

  @override
  String get swapConfiguredQuote => 'Configured quote';

  @override
  String get swapGuaranteedMinimumLabel => 'Guaranteed minimum';

  @override
  String swapDeliveryTxLabel(String symbol) {
    return '$symbol delivery tx';
  }

  @override
  String get swapFeeLabel => 'Swap fee';

  @override
  String get swapIncludedInRate => 'Included in shown rate';

  @override
  String get swapTxIdLabel => 'Tx ID';

  @override
  String get swapMissingDepositLabel => 'Missing deposit';

  @override
  String get swapRequiredDepositLabel => 'Required deposit';

  @override
  String get swapDetectedDepositLabel => 'Detected deposit';

  @override
  String get swapDepositDeadlineRowLabel => 'Deposit deadline';

  @override
  String get swapRefundFeeLabel => 'Refund fee';

  @override
  String swapHoursShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}hrs',
      one: '1hr',
    );
    return '$_temp0';
  }

  @override
  String swapMinutesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '${count}mins',
      one: '1min',
    );
    return '$_temp0';
  }

  @override
  String swapSendFromSourceChain(String symbol) {
    return 'Send $symbol from source chain';
  }

  @override
  String swapDepositLabelShort(String symbol) {
    return '$symbol deposit';
  }

  @override
  String swapSourceDepositLabel(String symbol) {
    return '$symbol source deposit';
  }

  @override
  String swapDepositTxHashLabel(String symbol) {
    return '$symbol deposit tx hash';
  }

  @override
  String swapDepositTxHashHint(String symbol) {
    return '$symbol source-chain transaction hash';
  }

  @override
  String swapSubmitDeposit(String symbol) {
    return 'Submit $symbol deposit';
  }

  @override
  String get swapDoNotReuseAddress => 'Do not reuse this address';

  @override
  String swapMinReceiveTooltip(String symbol) {
    return 'The lowest amount of $symbol you\'ll get after slippage. You may get more, never less.';
  }

  @override
  String get swapGenericMinReceiveTooltip =>
      'The lowest amount you\'ll get after slippage. You may get more, never less.';

  @override
  String get swapFeeTooltipText =>
      'Covers our fee and the route providers\' costs to process this swap. Already included in the rate above.';

  @override
  String get swapStatusDetailTooltipText =>
      'Details are based on the latest swap record and provider status.';

  @override
  String get swapProgressTab => 'Swap progress';

  @override
  String get swapTransactionDetailsTab => 'Transaction details';

  @override
  String get swapStatusRowLabel => 'Status';

  @override
  String swapRefundsReturnedAs(String symbol, String chain) {
    return 'If the swap fails or the rate moves, you\'ll be refunded in $symbol on $chain, minus the fee.';
  }

  @override
  String get swapReviewSwap => 'Review swap';

  @override
  String get swapQuoteExpiredNotice =>
      'Quote expired. Review again for an updated rate.';

  @override
  String get swapYourePaying => 'You\'re paying';

  @override
  String get swapYoureReceiving => 'You\'re receiving';

  @override
  String get swapYouPaid => 'You paid';

  @override
  String get swapYouReceived => 'You received';

  @override
  String get swapVerbLockingQuote => 'Locking quote';

  @override
  String get swapReviewAgain => 'Review again';

  @override
  String get swapNotEnoughZec => 'Not enough ZEC';

  @override
  String get swapConfirmSwap => 'Confirm swap';

  @override
  String swapToShort(String address) {
    return 'To: $address';
  }

  @override
  String swapRecipientAddressTitle(String symbol) {
    return '$symbol recipient address';
  }

  @override
  String swapRefundAddressTitle(String symbol) {
    return '$symbol refund address';
  }

  @override
  String get swapRecipientFieldLabel => 'Recipient';

  @override
  String get swapRefundToFieldLabel => 'Refund to';

  @override
  String swapDeliveredToAddress(String symbol) {
    return 'Your $symbol will be delivered to this address.';
  }

  @override
  String get swapRememberRecipients => 'Remember this address for recipients';

  @override
  String get swapRememberRefunds => 'Remember this address for refunds';

  @override
  String get swapUpdateAction => 'Update';

  @override
  String get swapIveDepositedTokens => 'I’ve deposited tokens';

  @override
  String get swapIveDeposited => 'I\'ve deposited';

  @override
  String get swapDepositZec => 'Deposit ZEC';

  @override
  String get swapDepositTokensTitle => 'Deposit tokens';

  @override
  String get swapChecking => 'Checking';

  @override
  String get swapTimesUp => 'Time’s up';

  @override
  String get swapDepositExpiredBody =>
      'This deposit address is no longer valid.\nPlease, start another swap transaction.';

  @override
  String get swapRestartSwap => 'Restart swap';

  @override
  String get swapDepositWithin => 'Deposit within';

  @override
  String get swapAmountToDeposit => 'Amount to deposit';

  @override
  String get swapAmountLabel => 'Amount';

  @override
  String get swapAmountCopiedMobile => 'Amount copied';

  @override
  String get swapAmountCopiedDesktop => 'Amount Copied';

  @override
  String get swapOneTimeAddress => 'One-time address';

  @override
  String get swapMemoCopied => 'Memo copied';

  @override
  String get swapSigningCancelledBeforeParams =>
      'Signing was cancelled before proving parameters were downloaded.';

  @override
  String get swapTxStatusUncertain =>
      'The transaction status is uncertain. Refresh activity before trying again.';

  @override
  String get swapZecDepositAction => 'ZEC deposit';

  @override
  String swapBroadcastingAction(String action) {
    return 'Broadcasting $action';
  }

  @override
  String swapSignActionOnKeystone(String action) {
    return 'Sign $action on Keystone';
  }

  @override
  String get swapSubmittingTransaction => 'Submitting transaction';

  @override
  String get swapScanToSign => 'Scan to sign';

  @override
  String get swapAfterScannedClickGetSignature =>
      'After you scanned, click Get signature.';

  @override
  String get swapGetSignature => 'Get signature';

  @override
  String get swapBackToActivity => 'Back to activity';

  @override
  String get swapTxCouldNotBroadcast => 'Transaction could not be broadcast.';

  @override
  String get swapZecDepositSigningFailed =>
      'ZEC deposit signing could not be completed.';

  @override
  String get swapYouPay => 'You pay';

  @override
  String get swapYouReceive => 'You receive';

  @override
  String get swapZcashLabel => 'Zcash';

  @override
  String get swapAddRefundAddress => 'Add refund address...';

  @override
  String get swapAddRecipientAddress => 'Add recipient address...';

  @override
  String swapMaxAvailable(String amount) {
    return 'Max: $amount';
  }

  @override
  String get swapZecDepositSent => 'ZEC deposit sent';

  @override
  String get swapCheckingZecDeposit => 'Checking ZEC deposit';

  @override
  String swapToTruncated(String address) {
    return 'To: $address';
  }

  @override
  String get swapCouldntLoad =>
      'Couldn\'t load this swap. Try again or pull to refresh.';

  @override
  String get swapReturnToActivity =>
      'Return to Activity and select a saved swap.';

  @override
  String get swapSignZecDeposit => 'Sign ZEC deposit';

  @override
  String get swapKeystoneSigningFailed => 'Keystone signing failed';

  @override
  String get swapScanTxQrInstructions =>
      'Use your Keystone wallet to scan this transaction QR code. Follow the steps on your device.';

  @override
  String get swapBroadcastingZecDeposit => 'Broadcasting ZEC deposit...';

  @override
  String get swapAlreadyInContacts => 'Already in your contacts';

  @override
  String get swapAlreadyInAddressBook => 'Already in your address book';

  @override
  String get swapTitle => 'Swap';

  @override
  String get swapGettingQuote => 'Getting quote';

  @override
  String get swapAddRecipientAddressAction => 'Add recipient address';

  @override
  String get swapAddRefundAddressAction => 'Add refund address';

  @override
  String get swapContinueToReview => 'Continue to review';

  @override
  String get swapQrNoAddress => 'QR code did not include an address.';

  @override
  String get swapSelectAsset => 'Select asset';

  @override
  String get swapSearchTokenOrChain => 'Search token or chain';

  @override
  String get swapNoTokensFound => 'No tokens or chains found';

  @override
  String get swapSlippage => 'Slippage';

  @override
  String get swapSlippageRange => 'Slippage must be 0.1 - 5%';

  @override
  String get swapCustom => 'Custom';

  @override
  String get swapTimeoutInvalidAddress =>
      'This deposit address is no longer valid';

  @override
  String get swapTimeoutStartAnother =>
      'Please, start another swap transaction.';

  @override
  String get swapToPrefix => 'To';

  @override
  String get swapFromPrefix => 'From';

  @override
  String get swapConfirmAndSwap => 'Confirm & swap';

  @override
  String get swapPoweredBy => 'Powered by';

  @override
  String get swapErrAmountTooLow =>
      'Amount is too low for this swap.\nTry a larger amount.';

  @override
  String get swapErrAmountPrecision =>
      'Amount has too many decimal places.\nUse fewer decimals and try again.';

  @override
  String get swapErrInvalidRoute =>
      'This route or address was rejected.\nEdit the details and request a new quote.';

  @override
  String get swapErrNoQuote =>
      'No quote is available for this route or amount.\nAdjust the amount, slippage, or asset and try again.';

  @override
  String get swapErrZecDepositFunding =>
      'Not enough spendable ZEC to cover this swap and its network fee.\nTry a smaller amount or use Max.';

  @override
  String get swapErrWalletPreflight =>
      'ZEC deposit could not be prepared.\nCheck your balance and try again.';

  @override
  String get swapErrDepositNotFound =>
      'Deposit is not indexed yet.\nCheck again in a few minutes.';

  @override
  String get swapErrDepositRejected =>
      'Deposit transaction was rejected.\nCheck the address, memo, and tx hash.';

  @override
  String get swapErrUnsupportedPairNoResend =>
      'Swap status uses an unsupported asset pair.\nDo not resend funds. Try again later.';

  @override
  String get swapErrAssetUnavailable =>
      'This asset is not available for swap right now.\nChoose another asset or try again later.';

  @override
  String get swapErrServiceUnavailableNoResend =>
      'Swap service is temporarily unavailable.\nDo not resend funds. Try again later.';

  @override
  String get swapErrServiceUnavailable =>
      'Swap service is temporarily unavailable.\nTry again later.';

  @override
  String get swapErrQuoteTimeout =>
      'Quote request timed out.\nCheck your connection and try again.';

  @override
  String get swapErrTimeoutNoResend =>
      'Request timed out.\nDo not resend funds. Try again later.';

  @override
  String get swapErrTimeout =>
      'Request timed out.\nCheck your connection and try again.';

  @override
  String get swapErrProcessingNoResend =>
      'Swap service is still processing.\nDo not resend funds. Try again later.';

  @override
  String get swapErrProcessing =>
      'Swap service is still processing.\nWait a moment and try again.';

  @override
  String get swapErrQuoteUnverified =>
      'Quote response could not be verified.\nTry again later.';

  @override
  String get swapErrResponseUnverified =>
      'Swap response could not be verified.\nTry again later.';

  @override
  String get swapErrTokenList =>
      'Swap tokens could not be loaded.\nTry again later.';

  @override
  String get swapErrQuoteUnavailable =>
      'Quote is unavailable right now.\nTry again later.';

  @override
  String get swapErrStartFailed =>
      'Swap could not be started.\nTry again later.';

  @override
  String get swapErrRefreshFailed =>
      'Could not refresh swap status.\nTry again later.';

  @override
  String get swapErrSubmitDepositFailed =>
      'Deposit status could not be submitted.\nTry again later.';

  @override
  String get swapErrSendZecDepositFailed =>
      'ZEC deposit could not be sent.\nTry again later.';

  @override
  String get swapErrNoActiveAccount => 'No active account';

  @override
  String get swapErrInsufficientShieldedForFee =>
      'Insufficient shielded balance to cover fee';

  @override
  String get swapErrMaxUnavailable => 'Max amount unavailable';

  @override
  String get swapBadgeCompleted => 'Completed';

  @override
  String get swapBadgeNeedsAttention => 'Needs attention';

  @override
  String get swapBadgeInProgress => 'In progress';

  @override
  String get swapZcashAddress => 'Zcash address';

  @override
  String swapChainAddress(String chain) {
    return '$chain address';
  }

  @override
  String get swapFullAddress => 'Full address';

  @override
  String votingNotEligibleNoFunds(String snapshot) {
    return 'This account is not eligible for this voting round. It had no eligible shielded funds at $snapshot. Switch to an eligible account to vote.';
  }

  @override
  String votingRequiresMinimumBundle(String snapshot) {
    return 'Voting requires at least one eligible shielded note bundle with 0.125 ZEC at $snapshot. Switch to an eligible account to vote.';
  }

  @override
  String get votingSnapshotBlockFallback => 'the voting round snapshot block';

  @override
  String votingSnapshotBlock(String height) {
    return 'snapshot block $height';
  }

  @override
  String get votingSessionActionFailed => 'Voting session action failed.';

  @override
  String get votingTryAgain => 'Try again';

  @override
  String get votingNoRounds => 'No voting rounds available';

  @override
  String get votingNoRoundsBody =>
      'There are no token holder voting rounds to display yet.';

  @override
  String get votingVoteTitle => 'Vote';

  @override
  String get votingConfigTooltip => 'Voting config';

  @override
  String get votingConfigSemantics => 'Voting config settings';

  @override
  String get votingBeta => 'Beta';

  @override
  String get votingCloses => 'Closes';

  @override
  String get votingClosed => 'Closed';

  @override
  String votingClosesOn(String label, String date) {
    return '$label $date';
  }

  @override
  String votingStartsOn(String date) {
    return 'Starts $date';
  }

  @override
  String get votingStateInProgress => 'In progress';

  @override
  String get votingStateActive => 'Active';

  @override
  String get votingStateVoted => 'Voted';

  @override
  String get votingStateTallying => 'Tallying';

  @override
  String get votingResume => 'Resume';

  @override
  String get votingStartVoting => 'Start voting';

  @override
  String get votingReview => 'Review';

  @override
  String get votingViewResults => 'View results';

  @override
  String get votingRoundUnavailable => 'Voting round unavailable';

  @override
  String get votingRoundLoadFailed =>
      'The selected voting round could not be loaded.';

  @override
  String get votingTokenHolderVoting => 'Token holder voting';

  @override
  String get votingPowerUnavailable => 'Voting power unavailable.';

  @override
  String get votingPreparingPower => 'Preparing voting power.';

  @override
  String get votingNoProposals => 'No proposals';

  @override
  String get votingNoProposalsBody =>
      'This voting round does not contain any proposals.';

  @override
  String get votingRetryEligibility => 'Retry eligibility';

  @override
  String get votingNotEligible => 'Not eligible';

  @override
  String get votingReviewAnswers => 'Review answers';

  @override
  String get votingSkipUnanswered => 'Skip unanswered questions?';

  @override
  String votingSkipUnansweredBody(int skipped, int total) {
    return 'You have not answered $skipped of $total questions. The review screen will mark them as skipped, and skipped questions will not be submitted.';
  }

  @override
  String get votingContinueToReview => 'Continue to review';

  @override
  String get votingKeepVoting => 'Keep voting';

  @override
  String get votingNotEligibleRound => 'Not eligible for this voting round';

  @override
  String get votingActive => 'Voting active';

  @override
  String votingEndsOn(String date) {
    return 'Ends $date';
  }

  @override
  String get votingSkipped => 'Skipped';

  @override
  String get votingVoteInProgress => 'Vote in progress';

  @override
  String get votingUnfinishedVote =>
      'You have an unfinished vote for this round. Resume to complete the submission.';

  @override
  String get votingContinueVoting => 'Continue voting';

  @override
  String get votingForumDiscussion => 'Forum discussion';

  @override
  String votingChoiceLabel(String choice) {
    return 'Choice $choice';
  }

  @override
  String get votingSelected => 'Selected';

  @override
  String get votingChoose => 'Choose';

  @override
  String get votingViewLess => 'View less';

  @override
  String get votingViewMore => 'View more';

  @override
  String get votingReviewYourAnswers => 'Review your answers';

  @override
  String get votingChooseAtLeastOne =>
      'Choose at least one option before submitting.';

  @override
  String get votingConfirmSubmit => 'Confirm & submit';

  @override
  String get votingResults => 'Results';

  @override
  String get votingNoProposalsInRound => 'No proposals in this round.';

  @override
  String get votingResultsPending => 'Results pending...';

  @override
  String votingVotedLabel(String label) {
    return 'Voted: $label';
  }

  @override
  String votingTotalLabel(String amount) {
    return 'Total: $amount';
  }

  @override
  String get votingResultsTitle => 'Voting results';

  @override
  String get votingSubmissionNotComplete => 'Submission not complete';

  @override
  String get votingNotAvailable => 'Not available';

  @override
  String get votingNotSubmittedBody =>
      'This account has not completed submission for this voting round.';

  @override
  String get votingCheckingEligibility =>
      'Checking voting eligibility for this account.';

  @override
  String get votingEligibilityNotConfirmed =>
      'Voting eligibility has not been confirmed for this account.';

  @override
  String get votingSubmissionConfirmed => 'Submission confirmed!';

  @override
  String get votingSubmissionPublished =>
      'Your vote was successfully published and cannot be changed.';

  @override
  String get votingRoundLabel => 'Voting round';

  @override
  String get votingPowerLabel => 'Voting power';

  @override
  String get votingUpdatingRounds => 'Updating voting rounds...';

  @override
  String get votingGenericStatusError =>
      'Voting could not continue for this account. Retry, or switch to an eligible account if this account cannot vote in this voting round.';

  @override
  String votingPirNotReady(String expected, String highest) {
    return 'Voting PIR data is not ready for this voting round yet. Expected snapshot block $expected; PIR endpoints report $highest.';
  }

  @override
  String votingPirNoEndpoint(String expected) {
    return 'No PIR endpoint matched this voting round snapshot. Expected snapshot block $expected.';
  }

  @override
  String votingQuestionProgress(int current, int total) {
    return 'Question $current/$total';
  }

  @override
  String get votingUseSignedBundlesOnly => 'Use signed bundles only?';

  @override
  String get votingSignedBundlesBody =>
      'Vizor can submit now using only signatures already scanned from Keystone.';

  @override
  String get votingSignedBundlesWarning =>
      'Unsigned bundles are skipped, which lowers voting power for this voting round.';

  @override
  String get votingKeepSigning => 'Keep signing';

  @override
  String get votingSkipBundles => 'Skip bundles';

  @override
  String get votingSubmittingVotes => 'Submitting votes';

  @override
  String get votingSigningWithKeystone => 'Signing with Keystone';

  @override
  String get votingDelegatingAuthority => 'Delegating voting authority';

  @override
  String get votingCastingVotes => 'Casting votes and submitting shares';

  @override
  String get votingFinalizingSubmission => 'Finalizing submission';

  @override
  String get votingFailed => 'Voting failed.';

  @override
  String get votingClear => 'Clear';

  @override
  String votingSyncedToBlock(String height) {
    return 'Synced to block $height';
  }

  @override
  String votingSnapshotBlockPart(String height) {
    return 'snapshot block $height';
  }

  @override
  String votingChainTipPart(String height) {
    return 'chain tip $height';
  }

  @override
  String get votingWaitingForSync => 'Waiting for wallet sync';

  @override
  String get votingWaitingForSyncBody =>
      'Your wallet is catching up to this voting round snapshot. Voting will continue automatically once the wallet has synced through the snapshot block.';

  @override
  String votingBlocksRemaining(String count) {
    return '$count blocks remaining';
  }

  @override
  String votingSignBundle(int current, int total) {
    return 'Sign bundle $current of $total';
  }

  @override
  String get votingSkip => 'Skip';

  @override
  String get votingScanQrInstruction =>
      'Scan QR on this screen with Keystone. Then, scan the signed voting QR displayed on Keystone with this device\'s camera';

  @override
  String votingNowSigningBundle(int current, int total) {
    return 'Now signing bundle $current of $total';
  }

  @override
  String get votingScanSignature => 'Scan signature';

  @override
  String get votingSoftwareAccountRequired => 'Software account required';

  @override
  String get votingSoftwareAccountBody =>
      'Token holder voting requires a software account. Switch to a software account to vote in this round.';

  @override
  String get votingSignatureQrDecodeError =>
      'This QR code could not be decoded as a Keystone voting signature.';

  @override
  String get votingOpenSignedQr =>
      'Open the signed voting QR on Keystone, then scan again.';

  @override
  String get votingScanVotingSignature => 'Scan voting signature';

  @override
  String get votingHoldKeystoneQr =>
      'Hold the Keystone QR code steady in front of your camera';

  @override
  String get votingCameraOnly =>
      'Keystone voting uses camera QR scanning only. Connect a camera and try again.';

  @override
  String votingTitleTooLong(int max) {
    return 'Title must be $max characters or less.';
  }

  @override
  String get votingSourceAlreadyAdded => 'This source URL is already added.';

  @override
  String get votingCustomSource => 'Custom source';

  @override
  String get votingSaving => 'Saving...';

  @override
  String get votingAddCustomSource => 'Add custom source';

  @override
  String get votingCopySourceUrl => 'Copy source URL';

  @override
  String get votingSourceUrlCopied => 'Source URL copied.';

  @override
  String get votingEditSavedSource => 'Edit saved source';

  @override
  String get votingDeleteSavedSource => 'Delete saved source';

  @override
  String get votingEditCustomSource => 'Edit custom source';

  @override
  String get votingTitleField => 'Title';

  @override
  String get votingStaticConfigUrl => 'Static config URL';

  @override
  String get votingValidating => 'Validating...';

  @override
  String get votingDefault => 'Default';

  @override
  String get votingCloseConfigSettings => 'Close voting config settings';

  @override
  String get settingsAccountChangedReenterPassword =>
      'Active account changed. Enter your password again.';

  @override
  String get settingsNoActiveAccount => 'No active account is selected.';

  @override
  String get settingsSeedNotAvailableHardware =>
      'Secret passphrase is not available for hardware accounts.';

  @override
  String get settingsSeedNotAvailable =>
      'Secret passphrase is not available for this account.';

  @override
  String get settingsSeedConfirmSubtitle => 'To view the secret passphrase.';

  @override
  String get settingsSeedMasterKeyBody =>
      'This is the master key to your wallet.\nDon\'t share it with anyone.';

  @override
  String get settingsBirthdayDate => 'Birthday date';

  @override
  String get settingsBirthdayBlockHeight => 'Birthday block height';

  @override
  String get settingsSeedBiometricReason =>
      'Confirm access to your secret passphrase';

  @override
  String get settingsIncorrectPasscode => 'Incorrect passcode';

  @override
  String get settingsEnterPasscode => 'Enter Passcode';

  @override
  String get settingsConfirmYourAccess => 'Confirm your access';

  @override
  String get settingsSeedCopiedToast => 'Secret passphrase copied';

  @override
  String get settingsBirthdayDateCopied => 'Birthday date copied';

  @override
  String get settingsBirthdayHeightCopied => 'Birthday height copied';

  @override
  String settingsCopyLabel(String label) {
    return 'Copy $label';
  }

  @override
  String get settingsNoScreenshotsTitle =>
      'Don’t take screenshots of your Secret Passphrase';

  @override
  String get settingsScreenshotsNotReliable => 'Screenshots are not reliable';

  @override
  String get settingsNoScreenshotsBody =>
      '. Anyone who has access to your phone or your photo library will be able to see your Secret Passphrase. Write down your Phrase on a piece of paper instead.';

  @override
  String get settingsIUnderstand => 'I understand';

  @override
  String get settingsNewPasscodeMustDiffer =>
      'Your new passcode must be different.';

  @override
  String get settingsPasscodeRotationRecoveryFailed =>
      'We couldn\'t verify the previous passcode change. Keep your secret passphrase available before trying again.';

  @override
  String get settingsSetNewPasscode => 'Set New Passcode';

  @override
  String get settingsEnterCurrentPasswordAgain =>
      'Enter your current password again.';

  @override
  String get settingsKeepPassphraseAvailable =>
      'We couldn\'t verify the previous password change. Please keep your secret passphrase available before trying again.';

  @override
  String get settingsEnterCurrentPasswordFirst =>
      'Enter your current password first.';

  @override
  String get settingsUpdatePassword => 'Update password';

  @override
  String get settingsPasswordHintLong =>
      'Minimum 8 characters. Add numbers and symbols, or make it longer, for stronger security.';

  @override
  String get settingsConfirmPassword => 'Confirm password';

  @override
  String get settingsUpdatingPassword => 'Updating password...';

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsSecretPassphraseTitle => 'Secret Passphrase';

  @override
  String get settingsProfilePictureTitle => 'Profile Picture';

  @override
  String get settingsAccountNameTitle => 'Account Name';

  @override
  String get settingsSystemSection => 'System';

  @override
  String get settingsOn => 'On';

  @override
  String get settingsOff => 'Off';

  @override
  String get settingsPasscodeUpdated => 'Passcode updated';

  @override
  String get settingsTurnOff => 'Turn off';

  @override
  String settingsUninstallBody(String device) {
    return 'Vizor will delete wallet data and secure storage from $device.';
  }

  @override
  String get settingsThisMac => 'this Mac';

  @override
  String get settingsThisPc => 'this PC';

  @override
  String get settingsThisDevice => 'this device';

  @override
  String get settingsUninstallFinishMac =>
      'To finish uninstallation, remove the Vizor app from Applications.';

  @override
  String get settingsUninstallFinishWindows =>
      'To finish uninstallation, uninstall Vizor from Windows settings.';

  @override
  String get settingsUninstallFinishOther =>
      'To finish uninstallation, remove the Vizor app from this device.';

  @override
  String settingsActiveSwapsBlockUninstall(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This wallet has $count active swaps. Wait for them to complete before uninstalling.',
      one:
          'This wallet has 1 active swap. Wait for them to complete before uninstalling.',
    );
    return '$_temp0';
  }

  @override
  String get settingsCannotBeUndone => 'This cannot be undone.';

  @override
  String get settingsCheckingSwaps => 'Checking swaps...';

  @override
  String get settingsToUninstall => 'To uninstall Vizor.';

  @override
  String get settingsDataRemoved => 'Your data has been removed';

  @override
  String get settingsRemovingData => 'Removing data...';

  @override
  String get settingsCloseVizor => 'Close Vizor';

  @override
  String get settingsConfirmAccess => 'Confirm access';

  @override
  String get settingsYourPasswordHint => 'Your password...';

  @override
  String get endpointUpdating => 'Updating...';

  @override
  String get endpointCloseSettings => 'Close endpoint settings';

  @override
  String get endpointDefaultSuffix => '(Default)';

  @override
  String get endpointCurrentPrefix => 'Current: ';

  @override
  String get endpointCustomEndpointTitle => 'Custom Endpoint';

  @override
  String get endpointHostPortHint => '<hostname>:<port>';

  @override
  String get endpointSelectAnEndpoint => 'Select an endpoint.';

  @override
  String get endpointUpdated => 'Endpoint updated';

  @override
  String get endpointsTitle => 'Endpoints';

  @override
  String get endpointSelectFromList => 'Select from the list';

  @override
  String get endpointCustomEndpoint => 'Custom endpoint';

  @override
  String get endpointUpdateEndpoint => 'Update endpoint';

  @override
  String get endpointCustomiseEndpoint => 'Customise endpoint';

  @override
  String get endpointCustomizeEndpoint => 'Customize endpoint';

  @override
  String get endpointMisconfiguredNetwork =>
      'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash network.';

  @override
  String get endpointMisconfiguredBlockchain =>
      'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash blockchain.';

  @override
  String get endpointMisconfiguredNetworkNewline =>
      'If the endpoint is configured wrong, your wallet won\'t be able to sync with the Zcash network.\n';

  @override
  String endpointStaleBalanceWarning(String ticker) {
    return 'The wallet will show the balance from the last time it was successfully connected. It won\'t show any $ticker you recently received.';
  }

  @override
  String get abCopyAddress => 'Copy address';

  @override
  String get abSendZec => 'Send ZEC';

  @override
  String abContactActions(String name) {
    return '$name actions';
  }

  @override
  String get cameraDeniedShortTitle => 'You\'ve denied Camera access';

  @override
  String get homeImportingWallet => 'We\'re importing\nyour wallet...';

  @override
  String get homeImportingWalletMobile => 'We\'re importing your wallet...';

  @override
  String get profilePictureUpdateFailed => 'Couldn\'t update profile picture.';

  @override
  String get settingsRemoveDataFailed =>
      'Couldn\'t finish removing data. Please try again.';

  @override
  String get settingsSwapCheckFailed =>
      'Couldn\'t check for active swaps. Try again before uninstalling.';

  @override
  String get settingsPasswordCheckFailed =>
      'Couldn\'t check your password. Please try again.';

  @override
  String get endpointConnectFailed =>
      'Couldn\'t connect to that endpoint. Check the host and port.';

  @override
  String get settingsPasswordUpdateFailed =>
      'Couldn\'t update your password. Please try again.';

  @override
  String get settingsPasscodesDidntMatch =>
      'Passcodes didn\'t match. Try again.';

  @override
  String get settingsPasscodeCheckFailed =>
      'Couldn\'t check your passcode. Please try again.';

  @override
  String get settingsPasscodeUpdateFailed =>
      'Couldn\'t update your passcode. Please try again.';

  @override
  String get settingsAppResetFailed =>
      'Couldn\'t reset the app. Please try again.';

  @override
  String get settingsAccountSaveFailed => 'Couldn\'t save the account changes';

  @override
  String get settingsSeedLoadFailed =>
      'Couldn\'t load your secret passphrase. Please try again.';

  @override
  String get settingsPasscodeVerifyFailed =>
      'Couldn\'t verify the passcode. Try again.';

  @override
  String get votingRoundsLoadFailed => 'Couldn\'t load voting rounds';

  @override
  String get votingRoundLoadFailedTitle => 'Couldn\'t load voting round';

  @override
  String get votingConfigLoadFailed =>
      'Couldn\'t load voting config from that source.';

  @override
  String get votingConfigUpdateFailed => 'Couldn\'t update voting config.';

  @override
  String votingRoundDetailsLoadFailed(String error) {
    return 'Couldn\'t load voting round details: $error';
  }

  @override
  String get votingDontCloseWindow =>
      'Don\'t close the window. Generating zero-knowledge proofs can take a while; closing now may lose in-flight proof work.';

  @override
  String get votingPirUnreachable =>
      'Couldn\'t reach any configured PIR endpoint. Check your network and voting config, then try again.';

  @override
  String get swapNotEnoughZecBody =>
      'You don\'t have enough ZEC for this swap. Try a smaller amount.';

  @override
  String get receiveTransparentShieldGuideBody =>
      'After receiving ZEC to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.';

  @override
  String get accountsAddressCopyFailed => 'Address couldn\'t be copied';

  @override
  String get accountsAddressLoadFailed => 'Couldn\'t load the account address';

  @override
  String get accountsResetVizorFailed => 'Couldn\'t reset Vizor';

  @override
  String get accountsRemoveFailedShort => 'Couldn\'t remove the account';

  @override
  String get receiveAddressLoadFailedLong =>
      'We couldn\'t load your address. Try again in a moment.';

  @override
  String get receiveAddressLoadFailedShort =>
      'Address couldn\'t be loaded. Try again.';

  @override
  String get accountsResetVizorFailedDot => 'Couldn\'t reset Vizor.';

  @override
  String get accountsRemoveFailedDot => 'Couldn\'t remove account.';

  @override
  String get sendBroadcastRejectedRetrying =>
      'Transaction was created locally but didn\'t reach the network. The wallet will keep retrying until it expires. Don\'t send again unless this one expires.';

  @override
  String get sendQrNotZcash => 'This QR code isn\'t a Zcash address.';

  @override
  String get onbInvalidBlockHeight =>
      'That doesn\'t look like a valid block height.';

  @override
  String get onbNotLegitBlockHeight =>
      'Doesn\'t seem like a legit block height';

  @override
  String get onbUnlockFailed => 'Couldn\'t open your wallet. Please try again.';

  @override
  String get onbFewStepsAwayDesktop =>
      'You\'re a few steps away from your first private wallet.\nLet\'s get you set up.';

  @override
  String get receivePreviewShieldedPrivacy =>
      'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.';

  @override
  String get receivePreviewShieldedRenew =>
      'A new Zcash shielded address\ngenerated every time you open the\nreceive page or click renew button.';

  @override
  String get receivePreviewShieldedDiversified =>
      'Each new address is a diversified\naddress derived from the same key.\nThey all receive to the same wallet.';

  @override
  String passwordTooShort(int min) {
    return 'Password must be at least $min characters.';
  }

  @override
  String get passwordAsciiOnly =>
      'Use only English letters, numbers, and symbols.';

  @override
  String get passwordMustDiffer => 'Use a different password.';

  @override
  String get votingChooseAtLeastOneVote =>
      'Choose at least one vote before submitting.';

  @override
  String get votingVoteLocked => 'Vote locked';

  @override
  String votingVotedOn(String date) {
    return 'Voted $date';
  }

  @override
  String get votingPowerUnavailableShort => 'Voting power unavailable';

  @override
  String get votingPreparingPowerShort => 'Preparing voting power';

  @override
  String votingPowerMeta(String power) {
    return 'Voting power $power';
  }

  @override
  String get keystonePreparingQr => 'Preparing QR';

  @override
  String get keystoneImReadyNow => 'I\'m ready now';

  @override
  String swapChainAddressOrAccount(String chain) {
    return '$chain address or account';
  }

  @override
  String get swapNetworkErrorRetry =>
      'Network error while sending. Check your connection and try again — your signature is safe to reuse.';

  @override
  String get activitySwapped => 'Swapped';

  @override
  String get activitySwapFailed => 'Swap failed';

  @override
  String get activitySwapping => 'Swapping...';

  @override
  String activitySymbolRefunded(String symbol) {
    return '$symbol refunded';
  }

  @override
  String activityReceivedSymbol(String symbol) {
    return 'Received $symbol';
  }

  @override
  String activityDepositedSymbol(String symbol) {
    return 'Deposited $symbol';
  }

  @override
  String get legalTermsOfUse => 'Terms of Use';

  @override
  String updateTitleAvailableVersion(String version) {
    return 'Update $version available';
  }

  @override
  String get updateTitleDownloading => 'Downloading update';

  @override
  String get updateTitleReady => 'Update ready';

  @override
  String get updateTitleApplying => 'Restarting Vizor';

  @override
  String get updateTitleAvailable => 'Update available';

  @override
  String get updateBodyAvailable => 'Download now or keep working.';

  @override
  String updateBodyDownloading(int progress) {
    return '$progress% downloaded.';
  }

  @override
  String get updateBodyReady => 'Restart when you are ready.';

  @override
  String get updateBodyApplying => 'Applying after Vizor closes.';

  @override
  String get updateActionDownload => 'Download';

  @override
  String get updateActionRestart => 'Restart';

  @override
  String get updateActionDownloading => 'Downloading';

  @override
  String get updateActionRestarting => 'Restarting';

  @override
  String get updateActionUpdate => 'Update';

  @override
  String get updateActionLater => 'Later';

  @override
  String updateLinuxAvailable(String version) {
    return 'Vizor $version is available.';
  }

  @override
  String get updateViewRelease => 'View Release';

  @override
  String get endpointFailoverSwitched =>
      'Selected endpoint is unstable. Switched to fallback endpoint.';

  @override
  String get endpointFailoverRecovered =>
      'Selected endpoint recovered. Switched back.';

  @override
  String get activityIncompleteDeposit => 'Incomplete deposit';

  @override
  String get activityTimeout => 'Timeout';

  @override
  String get activityLoadErrorRetry =>
      'Couldn\'t load activity. Try again in a moment.';

  @override
  String get keystoneShieldSignTitle => 'Sign tx on your Keystone';

  @override
  String get keystoneShieldScanToSign => 'Scan the QR code to sign';

  @override
  String get keystoneShieldSubmitting => 'Submitting transaction';

  @override
  String get keystoneShieldReject => 'Reject';

  @override
  String get keystoneShieldBackToWallet => 'Back to Wallet';

  @override
  String get shieldErrorSyncFirst =>
      'Sync the wallet before shielding transparent balance.';

  @override
  String get shieldErrorBroadcastFailed =>
      'Shield transaction could not be broadcast.';

  @override
  String get shieldErrorRetry => 'Shield balance failed. Please try again.';

  @override
  String get shieldCancelledParamsDownload =>
      'Shielding was cancelled before proving parameters were downloaded.';

  @override
  String get scanCameraPermissionOff =>
      'Camera access is off. Allow it in Settings to scan addresses.';

  @override
  String swapQuoteChangedLower(String percent) {
    return 'Live quote is $percent% lower than the earlier estimate. Check the guaranteed minimum before you continue.';
  }

  @override
  String swapQuoteChangedHigher(String percent) {
    return 'Live quote is $percent% higher than the earlier estimate. Check the guaranteed minimum before you continue.';
  }

  @override
  String swapPickerRecipientsTitle(String symbol) {
    return '$symbol recipients';
  }

  @override
  String swapPickerRefundsTitle(String symbol) {
    return '$symbol refunds';
  }

  @override
  String swapPickerNoSavedRecipients(String symbol) {
    return 'No saved $symbol recipients';
  }

  @override
  String swapPickerNoSavedRefunds(String symbol) {
    return 'No saved $symbol refunds';
  }

  @override
  String get swapErrAccountChanged =>
      'Active account changed. Review the quote again before starting.';

  @override
  String get swapErrIntentMissing =>
      'ZEC deposit was broadcast, but the saved swap intent was not found. Copy the transaction hash before leaving this screen.';

  @override
  String get swapDepositPartialBroadcast =>
      'Some deposit transactions may have reached the network. Check activity before trying again.';

  @override
  String get swapDepositPendingBroadcast =>
      'The deposit was created locally but could not be broadcast. Check activity before trying again.';

  @override
  String get swapDepositBroadcastUnknown =>
      'The transaction may have reached the network, but confirmation timed out. Check activity before trying again.';

  @override
  String get swapDepositStorageFailed =>
      'The transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';

  @override
  String get swapDepositUncertain =>
      'The deposit status is uncertain. Check activity before trying again.';

  @override
  String get endpointRegionDefault => 'Default';

  @override
  String get endpointRegionAmericas => 'Americas';

  @override
  String get endpointRegionEurope => 'Europe';

  @override
  String get endpointRegionAsiaPacific => 'Asia Pacific';

  @override
  String get endpointRegionGlobal => 'Global';

  @override
  String get endpointRegionCommunity => 'Community';

  @override
  String get endpointRegionTestnet => 'Testnet';

  @override
  String get endpointRegionRegtest => 'Regtest';

  @override
  String get endpointErrEnter => 'Enter an endpoint.';

  @override
  String get endpointErrSpaces => 'Endpoint cannot contain spaces.';

  @override
  String get endpointErrHostPort => 'Enter a valid hostname and port.';

  @override
  String get endpointErrHttps => 'Use an https:// endpoint.';

  @override
  String get endpointErrPort =>
      'Include a valid port, for example us.zec.stardust.rest:443.';

  @override
  String get endpointLatencyChecking => 'Checking...';

  @override
  String get endpointLatencyUnavailable => 'Unavailable';

  @override
  String get endpointLatencyWrongNetwork => 'Wrong network';

  @override
  String aboutVersionLabel(String version) {
    return 'Version: $version Public Beta';
  }

  @override
  String get privacySensitiveContentHidden => 'Sensitive content hidden';

  @override
  String get sendUnknownShieldedAddress => 'Unknown shielded address';

  @override
  String get sendUnknownTransparentAddress => 'Unknown transparent address';

  @override
  String get accountsSendStartFailed => 'Send couldn\'t be started';

  @override
  String get abClearContactLabel => 'Clear contact label';

  @override
  String get abSaveContactFailed =>
      'Couldn\'t save the contact. Please try again.';

  @override
  String get abRemoveContactFailed =>
      'Couldn\'t remove the contact. Please try again.';

  @override
  String get abLoadContactsFailed => 'Couldn\'t load contacts. Try again.';

  @override
  String get sendTxCouldNotBeSent => 'Transaction couldn\'t be sent.';

  @override
  String get deviceAuthConfirmReset => 'Confirm reset Vizor';

  @override
  String get deviceAuthRequired =>
      'Device authentication is required to reset Vizor.';

  @override
  String get deviceAuthFailed =>
      'Couldn\'t verify device ownership. Please try again.';

  @override
  String get abPickerNoContacts => 'No contacts found';

  @override
  String get sendPartialBroadcast =>
      'Some transactions were broadcast and the rest will retry automatically. Check activity before sending again.';

  @override
  String get sendPendingBroadcastRetry =>
      'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.';

  @override
  String get sendBroadcastUnknown =>
      'The transaction may have reached the network, but confirmation timed out. Check activity before sending again.';

  @override
  String get sendBroadcastStorageFailed =>
      'The transaction reached the network, but Vizor could not store it locally. Do not send again until sync or an explorer confirms the latest status.';

  @override
  String get sendPcztRejected =>
      'Transaction was rejected by the network. Please try again later.';

  @override
  String get sendCancelledParamsDownload =>
      'Sending was cancelled before proving parameters were downloaded.';

  @override
  String get votingAccountLoadError => 'Couldn\'t load account';

  @override
  String get votingResultsFallbackTitle => 'Voting results';

  @override
  String votingLoadResultsError(String message) {
    return 'Couldn\'t load results: $message';
  }

  @override
  String votingLoadRoundDetailsError(String message) {
    return 'Couldn\'t load voting round details: $message';
  }

  @override
  String votingLoadReviewError(String message) {
    return 'Couldn\'t load review: $message';
  }

  @override
  String votingLoadSubmissionError(String message) {
    return 'Couldn\'t load submission details: $message';
  }

  @override
  String get votingRoundsRefreshError =>
      'Couldn\'t update voting rounds. Try again.';

  @override
  String get votingRecoveryDelegationPending =>
      'This vote has local progress, but delegation is not fully confirmed yet. The app should continue recovery before accepting another vote.';

  @override
  String get votingRecoveryCommitmentPending =>
      'This vote has been started, but its commitment transaction recovery data is not complete yet. Do not vote again from this account.';

  @override
  String get votingRecoverySharesPending =>
      'This vote was submitted, but some helper-server shares are still waiting for confirmation. Do not vote again from this account.';

  @override
  String get votingEndsToday => 'Ends today';

  @override
  String get votingOneDayLeft => '1 day left';

  @override
  String votingDaysLeft(int days) {
    return '$days days left';
  }

  @override
  String get mobileExitBackHint => 'Go back again to exit';
}
