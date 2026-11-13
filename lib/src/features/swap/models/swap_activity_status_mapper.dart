import 'package:intl/intl.dart' show DateFormat;

import '../../../core/formatting/date_format.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/widgets/contact_name_inline.dart';
import '../domain/near_intents_explorer.dart';
import 'swap_address_book_helpers.dart';
import 'swap_address_formatting.dart';
import 'swap_deposit_broadcast_result.dart';
import 'swap_detail_tooltips.dart';
import 'swap_fiat_value_formatting.dart';
import 'swap_models.dart';
import 'swap_privacy_mask.dart';
import 'swap_status_presentation.dart';
import 'swap_token_amount_formatting.dart';
import '../../../core/l10n/l10n.dart';
import 'one_time_address_role.dart';

class SwapActivityAccountDetail {
  const SwapActivityAccountDetail({required this.name, this.profilePictureId});

  final String name;
  final String? profilePictureId;
}

enum PayActivityStatusPhase { inProgress, completed, failed, refunded }

/// Label of the paid amount on the Pay status header: past tense once the
/// payment completes, neutral when it did not reach the recipient.
String payActivityStatusAmountLabel(
  AppLocalizations l10n,
  PayActivityStatusPhase phase,
) => switch (phase) {
  PayActivityStatusPhase.completed => l10n.swapActivityYouPaid,
  PayActivityStatusPhase.failed ||
  PayActivityStatusPhase.refunded => l10n.commonAmount,
  PayActivityStatusPhase.inProgress => l10n.commonYourePaying,
};

/// Shared Pay status data backed by values whose meaning is known at the
/// activity boundary. Provider/app fees are deliberately not repurposed as the
/// Figma `Tx fee`; that value is injected only from a confirmed matching ZEC
/// deposit transaction in wallet history.
class PayActivityStatusPresentation {
  const PayActivityStatusPresentation({
    required this.phase,
    required this.timestampText,
    required this.txIdText,
    required this.convertedFromText,
    required this.transactionFeeText,
    this.refundAddress,
    this.refundedAmountText,
    this.refundFeeText,
    this.txIdUri,
  });

  final PayActivityStatusPhase phase;
  final String timestampText;
  final String txIdText;
  final Uri? txIdUri;
  final String convertedFromText;
  final String transactionFeeText;
  final String? refundAddress;
  final String? refundedAmountText;
  final String? refundFeeText;

  String title(AppLocalizations l10n) => switch (phase) {
    PayActivityStatusPhase.inProgress => l10n.swapActivityPayInProgressTitle,
    PayActivityStatusPhase.completed => l10n.swapActivityPaidSuccessfullyTitle,
    PayActivityStatusPhase.failed => l10n.commonPaymentFailed,
    PayActivityStatusPhase.refunded => l10n.commonPaymentRefunded,
  };

  String statusLabel(AppLocalizations l10n) => switch (phase) {
    PayActivityStatusPhase.inProgress => l10n.commonInProgress,
    PayActivityStatusPhase.completed => l10n.commonCompleted,
    PayActivityStatusPhase.failed => l10n.commonFailed,
    PayActivityStatusPhase.refunded => l10n.commonRefunded,
  };
}

class SwapActivityStatusPresentation {
  const SwapActivityStatusPresentation({
    required this.title,
    required this.payAsset,
    required this.receiveAsset,
    required this.payFiatText,
    required this.receiveFiatText,
    required this.payAmountText,
    required this.receiveAmountText,
    this.payLabel =
        "You're paying", // l10n-ignore: fixture default; the presenter always passes localized labels
    this.receiveLabel =
        "You're receiving", // l10n-ignore: fixture default; the presenter always passes localized labels
    this.payDetailText = '',
    this.payDetailCopyText,
    this.receiveDetailText = '',
    this.receiveDetailCopyText,
    this.statusLabel = '',
    required this.badgeKind,
    required this.progressIndex,
    required this.steps,
    required this.details,
    this.progressTabLabel =
        'Swap progress', // l10n-ignore: fixture default; the presenter always passes a localized label
    this.paymentMode = false,
    this.payStatus,
    this.explorerUri,
    required this.showTabs,
    this.oneTimeAddress,
  });

  final String title;
  final SwapAsset payAsset;
  final SwapAsset receiveAsset;
  final String payFiatText;
  final String receiveFiatText;
  final String payAmountText;
  final String receiveAmountText;
  final String payLabel;
  final String receiveLabel;

  /// Bottom line of the pay summary row: the fiat value, or for
  /// external→ZEC swaps the "Refund to: …" address line.
  final String payDetailText;

  /// Full address copied by the pay row's copy affordance, when the pay
  /// line shows the refund address.
  final String? payDetailCopyText;

  /// Bottom line of the receive summary row: the fiat value, or for
  /// ZEC→external swaps the "To: … on [SwapAsset.chainLabel]" address line.
  final String receiveDetailText;

  /// Full address copied by the receive row's copy affordance, when the
  /// receive line shows the recipient address.
  final String? receiveDetailCopyText;

  /// User-facing status label for the terminal Status row.
  final String statusLabel;
  final SwapStatusBadgeKind badgeKind;
  final int progressIndex;
  final List<SwapStatusStepData> steps;
  final List<SwapStatusDetailRowData> details;
  final String progressTabLabel;
  final bool paymentMode;
  final PayActivityStatusPresentation? payStatus;
  final Uri? explorerUri;
  final bool showTabs;

  /// Set when the swap's ZEC side uses a one-time address: the payout when
  /// receiving ZEC, the refund when sending it.
  final OneTimeAddressRole? oneTimeAddress;
}

SwapActivityStatusPresentation swapActivityStatusPresentationForIntent(
  AppLocalizations l10n,
  SwapState state,
  SwapIntent intent, {
  SwapActivityAccountDetail? accountDetail,
  Iterable<AddressBookContact> addressBookContacts = const [],
  BigInt? confirmedDepositFeeZatoshi,
  bool findingPayout = false,
  bool privacyModeEnabled = false,
}) {
  final sellAsset = swapActivitySellAsset(intent) ?? SwapAsset.zec;
  final receiveAsset = swapActivityReceiveAsset(intent) ?? SwapAsset.usdc;
  final sendsZec = intent.direction != SwapDirection.externalToZec;
  final payMode = intent.payMode && sendsZec;
  final payStatus = payMode
      ? _payActivityStatusPresentation(
          l10n,
          intent,
          confirmedDepositFeeZatoshi: confirmedDepositFeeZatoshi,
          privacyModeEnabled: privacyModeEnabled,
        )
      : null;
  final recipientAddress = intent.oneClickRecipient?.trim();
  final refundAddress = intent.oneClickRefundTo?.trim();
  final payFiatText = swapFiatTextForPrivacy(
    _swapActivityFiatTextForAsset(
      intent: intent,
      side: _SwapActivityAmountSide.sell,
      amountText: intent.sellAmount,
    ),
    privacyModeEnabled: privacyModeEnabled,
  );
  final receiveFiatText = swapFiatTextForPrivacy(
    _swapActivityFiatTextForAsset(
      intent: intent,
      side: _SwapActivityAmountSide.receive,
      amountText: intent.receiveEstimate,
    ),
    privacyModeEnabled: privacyModeEnabled,
  );

  // The summary's bottom lines: fiat on the ZEC side, the counterparty
  // address on the external side (recipient when sending ZEC, refund
  // address when depositing an external asset).
  var payDetailText = payFiatText;
  String? payDetailCopyText;
  var receiveDetailText = receiveFiatText;
  String? receiveDetailCopyText;
  if (sendsZec) {
    if (payMode) {
      payDetailText = l10n.commonPrivatelyFromShieldedBalance;
    }
    if (recipientAddress != null && recipientAddress.isNotEmpty) {
      receiveDetailText = l10n.commonToAddressOnChain(
        _headerAddressText(
          recipientAddress,
          asset: receiveAsset,
          contacts: addressBookContacts,
          contactId: intent.userExternalContactId,
        ),
        receiveAsset.chainLabel,
      );
      receiveDetailCopyText = recipientAddress;
    }
  } else {
    if (refundAddress != null && refundAddress.isNotEmpty) {
      payDetailText = l10n.commonRefundToAddress(
        _headerAddressText(
          refundAddress,
          asset: sellAsset,
          contacts: addressBookContacts,
          contactId: intent.userExternalContactId,
        ),
      );
      payDetailCopyText = refundAddress;
    }
  }

  // Until the wallet finds the payout, the swap reads as in progress.
  final labelStatus = findingPayout
      ? SwapIntentStatus.processing
      : intent.status;
  return SwapActivityStatusPresentation(
    oneTimeAddress: intent.privateAddress
        ? (sendsZec ? OneTimeAddressRole.refund : OneTimeAddressRole.payout)
        : null,
    // Keep the generic swap presentation stable. Pay surfaces consume the
    // dedicated [payStatus] contract instead of relabelling generic details.
    title: findingPayout
        ? l10n.swapActivitySwapInProgress
        : _swapActivityStatusTitle(l10n, intent),
    payAsset: sellAsset,
    receiveAsset: receiveAsset,
    payFiatText: payFiatText,
    receiveFiatText: receiveFiatText,
    payAmountText: swapAmountTextForPrivacy(
      intent.sellAmount,
      privacyModeEnabled: privacyModeEnabled,
    ),
    receiveAmountText: swapAmountTextForPrivacy(
      intent.receiveEstimate,
      privacyModeEnabled: privacyModeEnabled,
    ),
    payLabel: payMode
        ? _payIntentShowsPaidCopy(intent)
              ? l10n.swapActivityYouPaid
              : l10n.commonYouPay
        : _swapShowsTerminalFailureLabels(labelStatus)
        ? l10n.swapActivityDepositAmount
        : labelStatus == SwapIntentStatus.complete
        ? l10n.swapActivityYouPaid
        : l10n.commonYourePaying,
    receiveLabel: payMode
        ? switch (intent.status) {
            SwapIntentStatus.complete => l10n.swapActivityRecipientReceived,
            SwapIntentStatus.failed ||
            SwapIntentStatus.refunded ||
            SwapIntentStatus.expired ||
            SwapIntentStatus.incompleteDeposit => l10n.commonAmount,
            _ => l10n.commonRecipientGets,
          }
        : _swapShowsTerminalFailureLabels(labelStatus)
        ? l10n.swapActivityExpectedToReceive
        : labelStatus == SwapIntentStatus.complete
        ? l10n.swapActivityYouReceived
        : l10n.commonYoureReceiving,
    payDetailText: payDetailText,
    payDetailCopyText: payDetailCopyText,
    receiveDetailText: receiveDetailText,
    receiveDetailCopyText: receiveDetailCopyText,
    statusLabel: findingPayout
        ? l10n.swapFindingPayout
        : _swapActivityStatusLabel(l10n, intent.status),
    badgeKind: findingPayout
        ? SwapStatusBadgeKind.liveQuote
        : _swapActivityStatusBadgeKind(intent.status),
    progressIndex: _swapActivityStatusProgressIndex(intent),
    steps: _swapActivityProgressSteps(
      l10n,
      intent,
      findingPayout: findingPayout,
    ),
    details: _swapActivityStatusDetails(
      l10n,
      intent,
      addressBookContacts: addressBookContacts,
      privacyModeEnabled: privacyModeEnabled,
    ),
    progressTabLabel: payMode
        ? l10n.commonPaymentProgress
        : l10n.commonSwapProgress,
    paymentMode: payMode,
    payStatus: payStatus,
    explorerUri: swapActivityExplorerUri(intent),
    // Mobile keeps the shared progress tabs while reading its detail values
    // from [payStatus]; desktop renders its dedicated Pay status content.
    // A payout still being found keeps its steps, like any swap in progress.
    showTabs: findingPayout || !intent.status.isTerminal,
  );
}

bool _payIntentShowsPaidCopy(SwapIntent intent) {
  if (intent.hasProviderObservedDepositEvidence) return true;
  // A partial batch may only have mined its parent, without funding the deposit.
  if (intent.status == SwapIntentStatus.failed ||
      intent.broadcastStatus == SwapDepositBroadcastStatus.partialBroadcast) {
    return false;
  }
  return intent.hasConfirmedDepositEvidence;
}

PayActivityStatusPresentation? _payActivityStatusPresentation(
  AppLocalizations l10n,
  SwapIntent intent, {
  BigInt? confirmedDepositFeeZatoshi,
  required bool privacyModeEnabled,
}) {
  final phase = payActivityStatusPhaseFor(intent.status);
  if (phase == null) return null;
  String amount(String text) =>
      swapAmountTextForPrivacy(text, privacyModeEnabled: privacyModeEnabled);
  final refundedAmountText =
      phase == PayActivityStatusPhase.refunded &&
          intent.providerRefundInfo?.hasRecordedRefund == true
      ? intent.providerRefundInfo!.refundedAmountText
      : null;
  final refundFeeText = phase == PayActivityStatusPhase.refunded
      ? intent.providerRefundInfo?.recordedRefundFeeText
      : null;

  final timestamp = phase != PayActivityStatusPhase.inProgress
      ? intent.completedAt ?? intent.updatedAt ?? intent.createdAt
      : intent.createdAt ?? intent.updatedAt;
  final explorerId = _firstNonEmpty([
    intent.depositAddress,
    intent.nearIntentHash,
    intent.depositTxHash,
    intent.originChainTxHash,
  ]);

  return PayActivityStatusPresentation(
    phase: phase,
    timestampText: timestamp == null
        ? l10n.swapActivityNotReported
        : formatDayMonthTime(timestamp, l10n.localeName),
    txIdText: explorerId == null
        ? l10n.swapActivityNotReported
        : compactSwapAddress(
            explorerId,
            maxLength: 19,
            prefixLength: 8,
            suffixLength: 8,
            separator: '...',
          ),
    txIdUri: swapActivityExplorerUri(intent),
    convertedFromText: amount(intent.sellAmount),
    transactionFeeText:
        confirmedDepositFeeZatoshi != null &&
            confirmedDepositFeeZatoshi > BigInt.zero
        ? amount(
            ZecAmount.fromZatoshi(confirmedDepositFeeZatoshi).fee.toString(),
          )
        : l10n.swapActivityNotReported,
    refundAddress:
        phase == PayActivityStatusPhase.failed ||
            phase == PayActivityStatusPhase.refunded
        ? intent.oneClickRefundTo?.trim()
        : null,
    refundedAmountText: refundedAmountText == null
        ? null
        : amount(refundedAmountText),
    refundFeeText: refundFeeText == null ? null : amount(refundFeeText),
  );
}

/// Failed and refunded swaps label the quote instead of implying delivery.
bool _swapShowsTerminalFailureLabels(SwapIntentStatus status) =>
    status == SwapIntentStatus.failed || status == SwapIntentStatus.refunded;

PayActivityStatusPhase? payActivityStatusPhaseFor(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => PayActivityStatusPhase.completed,
    SwapIntentStatus.failed => PayActivityStatusPhase.failed,
    SwapIntentStatus.refunded => PayActivityStatusPhase.refunded,
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.providerStatusUnknown => PayActivityStatusPhase.inProgress,
    SwapIntentStatus.incompleteDeposit || SwapIntentStatus.expired => null,
  };
}

String _swapActivityStatusLabel(
  AppLocalizations l10n,
  SwapIntentStatus status,
) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit => l10n.swapActivityStatusAwaitingDeposit,
    SwapIntentStatus.awaitingExternalDeposit =>
      l10n.swapActivityStatusAwaitingExternalDeposit,
    SwapIntentStatus.depositObserved => l10n.swapActivityStatusDepositObserved,
    SwapIntentStatus.processing => l10n.swapActivityStatusProcessing,
    SwapIntentStatus.providerStatusUnknown => l10n.commonCheckingStatus,
    SwapIntentStatus.incompleteDeposit => l10n.swapActivityIncompleteDeposit,
    SwapIntentStatus.complete => l10n.swapActivityStatusComplete,
    SwapIntentStatus.refunded => l10n.commonRefunded,
    SwapIntentStatus.expired => l10n.swapActivityStatusExpired,
    SwapIntentStatus.failed => l10n.commonFailed,
  };
}

String _swapActivityStatusTitle(AppLocalizations l10n, SwapIntent intent) {
  if (intent.payMode && intent.direction == SwapDirection.zecToExternal) {
    return switch (intent.status) {
      SwapIntentStatus.complete => l10n.swapActivityPaymentComplete,
      SwapIntentStatus.incompleteDeposit => l10n.swapActivityIncompletePayment,
      SwapIntentStatus.refunded => l10n.commonPaymentRefunded,
      SwapIntentStatus.failed ||
      SwapIntentStatus.expired => l10n.commonPaymentFailed,
      _ => l10n.commonPaymentInProgress,
    };
  }
  return switch (intent.status) {
    SwapIntentStatus.complete => l10n.swapActivitySwapCompleted,
    SwapIntentStatus.incompleteDeposit => l10n.swapActivityIncompleteDeposit,
    SwapIntentStatus.refunded => l10n.commonSwapRefunded,
    SwapIntentStatus.failed => l10n.commonSwapFailed,
    _ => l10n.swapActivitySwapInProgress,
  };
}

SwapStatusBadgeKind _swapActivityStatusBadgeKind(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => SwapStatusBadgeKind.completed,
    SwapIntentStatus.refunded => SwapStatusBadgeKind.refunded,
    SwapIntentStatus.incompleteDeposit => SwapStatusBadgeKind.warning,
    SwapIntentStatus.failed ||
    SwapIntentStatus.expired => SwapStatusBadgeKind.failed,
    _ => SwapStatusBadgeKind.liveQuote,
  };
}

int _swapActivityStatusProgressIndex(SwapIntent intent) {
  final hasDepositTx = intent.depositTxHash?.trim().isNotEmpty ?? false;
  final depositSent = hasDepositTx || intent.depositClaimedAt != null;
  return switch (intent.status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => depositSent ? 1 : 0,
    SwapIntentStatus.depositObserved => 1,
    SwapIntentStatus.processing ||
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.incompleteDeposit => 2,
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => 3,
  };
}

List<SwapStatusStepData> _swapActivityProgressSteps(
  AppLocalizations l10n,
  SwapIntent intent, {
  bool findingPayout = false,
}) {
  final sourceSymbol = swapActivityPairSymbol(l10n, intent.pair, 0);
  final receiveSymbol = swapActivityPairSymbol(l10n, intent.pair, 1);
  if (intent.payMode && intent.direction == SwapDirection.zecToExternal) {
    final lastCheckedLabel = _swapActivityLastRelativeStatusCheckedLabel(
      l10n,
      intent.lastStatusCheckedAt,
    );
    return [
      SwapStatusStepData(
        title: l10n.swapActivityStepSpend(sourceSymbol),
        state: SwapStatusStepState.pending,
        completeTitle: l10n.swapActivityStepSpent(sourceSymbol),
        activeTitle: l10n.swapActivityStepSpending(sourceSymbol),
        pendingTitle: l10n.swapActivityStepSpend(sourceSymbol),
        lastCheckedLabel: lastCheckedLabel,
        description: l10n.swapActivityStepSpendDescription,
      ),
      SwapStatusStepData(
        title: l10n.swapActivityStepConvert,
        state: SwapStatusStepState.pending,
        activeTitle: l10n.swapActivityStepConverting,
        lastCheckedLabel: lastCheckedLabel,
        description: l10n.swapActivityStepConvertDescription,
      ),
      SwapStatusStepData(
        title: l10n.swapActivityStepDeliver(receiveSymbol),
        state: SwapStatusStepState.pending,
        activeTitle: l10n.swapActivityStepDelivering(receiveSymbol),
        lastCheckedLabel: lastCheckedLabel,
        description: l10n.swapActivityStepDeliverPayDescription,
      ),
      SwapStatusStepData(
        title: l10n.swapActivityStepRecipientReceives,
        state: SwapStatusStepState.pending,
        activeTitle: l10n.swapActivityStepRecipientReceivesAsset(receiveSymbol),
        lastCheckedLabel: lastCheckedLabel,
        description: l10n.swapActivityStepRecipientReceivesDescription,
      ),
    ];
  }
  final sendsZecToExternal = intent.direction == SwapDirection.zecToExternal;
  final sourceActive = sendsZecToExternal
      ? l10n.swapActivityStepSending(sourceSymbol)
      : l10n.swapActivityStepDepositing(sourceSymbol);
  final sourceDone = sendsZecToExternal
      ? l10n.swapActivityStepSent(sourceSymbol)
      : l10n.swapActivityStepDeposited(sourceSymbol);
  final deliveryTitle = sendsZecToExternal
      ? l10n.swapActivityStepDeliver(receiveSymbol)
      : l10n.swapActivityStepSend(receiveSymbol);
  final deliveryActive = sendsZecToExternal
      ? l10n.swapActivityStepDeliverActive(receiveSymbol)
      : l10n.swapActivityStepSendActive(receiveSymbol);

  final lastCheckedLabel = _swapActivityLastRelativeStatusCheckedLabel(
    l10n,
    intent.lastStatusCheckedAt,
  );

  return [
    SwapStatusStepData(
      title: sourceSymbol,
      state: SwapStatusStepState.pending,
      completeTitle: sourceDone,
      activeTitle: sourceActive,
      pendingTitle: sendsZecToExternal
          ? l10n.swapActivityStepSend(sourceSymbol)
          : l10n.swapActivityStepDeposit(sourceSymbol),
      lastCheckedLabel: lastCheckedLabel,
      description: l10n.swapActivityStepSourceDescription,
    ),
    SwapStatusStepData(
      title: l10n.swapActivityStepDepositConfirmation,
      state: SwapStatusStepState.pending,
      activeTitle: l10n.swapActivityStepDepositConfirmationActive,
      lastCheckedLabel: lastCheckedLabel,
      description: l10n.swapActivityStepDepositConfirmationDescription,
    ),
    SwapStatusStepData(
      title: l10n.swapActivityStepSwap,
      state: SwapStatusStepState.pending,
      kind: SwapStatusStepKind.swap,
      activeTitle: l10n.swapActivityStepSwapActive,
      lastCheckedLabel: lastCheckedLabel,
      description: l10n.swapActivityStepSwapDescription,
    ),
    if (findingPayout)
      SwapStatusStepData(
        title: deliveryTitle,
        state: SwapStatusStepState.pending,
        kind: SwapStatusStepKind.walletDelivery,
        activeTitle: l10n.swapFindingPayout,
        description: l10n.swapActivityStepFindingPayoutDescription,
      )
    else
      SwapStatusStepData(
        title: deliveryTitle,
        state: SwapStatusStepState.pending,
        kind: sendsZecToExternal
            ? SwapStatusStepKind.other
            : SwapStatusStepKind.walletDelivery,
        activeTitle: deliveryActive,
        lastCheckedLabel: lastCheckedLabel,
        description: l10n.swapActivityStepDeliverSwapDescription,
      ),
  ];
}

List<SwapStatusDetailRowData> _swapActivityStatusDetails(
  AppLocalizations l10n,
  SwapIntent intent, {
  required Iterable<AddressBookContact> addressBookContacts,
  required bool privacyModeEnabled,
}) {
  String amount(String text) =>
      swapAmountTextForPrivacy(text, privacyModeEnabled: privacyModeEnabled);
  final sourceSymbol = swapActivityPairSymbol(l10n, intent.pair, 0);
  final receiveSymbol = swapActivityPairSymbol(l10n, intent.pair, 1);
  final sourceAsset = swapActivitySellAsset(intent);
  final receiveAsset = swapActivityReceiveAsset(intent);
  final refundAddress = intent.oneClickRefundTo?.trim();
  final recipientAddress = intent.oneClickRecipient?.trim();
  final depositAddress = intent.depositAddress?.trim();
  final localDepositTxHash = intent.depositTxHash?.trim();
  final originChainTxHash = intent.originChainTxHash?.trim();
  final destinationChainTxHash = intent.destinationChainTxHash?.trim();
  final depositTxHash = _firstNonEmpty([localDepositTxHash, originChainTxHash]);
  // Keep the provider lookup separate from the copyable source-chain tx hash.
  final txIdRow = _swapActivityTxIdRow(l10n, intent);
  final terminal = intent.status.isTerminal;
  final failed =
      intent.status == SwapIntentStatus.failed ||
      intent.status == SwapIntentStatus.refunded ||
      intent.status == SwapIntentStatus.expired;
  final sendsZec = intent.direction != SwapDirection.externalToZec;
  final payMode = intent.payMode && sendsZec;
  final sourceTxLabel = payMode
      ? l10n.swapActivityDetailSourceTxShielded(sourceSymbol)
      : l10n.swapActivityDetailDepositTx(sourceSymbol);
  final feesLabel = payMode
      ? l10n.swapActivityDetailFees
      : l10n.swapActivityDetailTotalFees;
  final recordedRefundFee = _recordedRefundFeeText(intent.providerRefundInfo);
  final payRateText = payMode
      ? _swapActivityPayRateText(intent, receiveAsset)
      : null;

  if (payMode) {
    return _swapActivityPayDetails(
      l10n,
      intent,
      sourceSymbol: sourceSymbol,
      receiveSymbol: receiveSymbol,
      depositTxHash: depositTxHash,
      destinationChainTxHash: destinationChainTxHash,
      payRateText: payRateText,
      failed: failed,
      refundAddress: refundAddress,
      sourceAsset: sourceAsset,
      addressBookContacts: addressBookContacts,
      privacyModeEnabled: privacyModeEnabled,
    );
  }

  if (terminal) {
    // Terminal surfaces date the swap by its settlement time, falling back
    // to the start time for records persisted before completion tracking.
    final timestamp = _swapActivityTimestampLabel(
      l10n,
      intent.completedAt ?? intent.createdAt,
    );
    final explorerUri = swapActivityExplorerUri(intent);
    return [
      if (!failed && !payMode)
        SwapStatusDetailRowData(
          label: l10n.swapActivityDetailRealizedSlippage,
          value: intent.realisedSlippageText ?? l10n.swapActivityNotReported,
        ),
      if (timestamp != null)
        SwapStatusDetailRowData(
          label: l10n.commonTimestamp,
          kind: SwapStatusDetailKind.timestamp,
          value: timestamp,
        ),
      if (payRateText != null)
        SwapStatusDetailRowData(label: l10n.commonRate, value: payRateText),
      if (depositTxHash != null && depositTxHash.isNotEmpty)
        SwapStatusDetailRowData(
          label: sourceTxLabel,
          kind: SwapStatusDetailKind.sourceTx,
          value: compactSwapAddress(depositTxHash),
          copyable: true,
          copyText: depositTxHash,
          linkUri: explorerUri,
        ),
      if (payMode &&
          destinationChainTxHash != null &&
          destinationChainTxHash.isNotEmpty)
        SwapStatusDetailRowData(
          label: l10n.swapActivityDetailDeliveryTx(receiveSymbol),
          kind: SwapStatusDetailKind.deliveryTx,
          value: compactSwapAddress(destinationChainTxHash),
          copyable: true,
          copyText: destinationChainTxHash,
        ),
      if (failed &&
          refundAddress != null &&
          refundAddress.isNotEmpty &&
          // Desktop headers carry the refund address only for external
          // deposits, so ZEC-sourced refunds keep the detail row.
          (sendsZec ||
              intent.status != SwapIntentStatus.refunded ||
              kAppFormFactor == AppFormFactor.mobile))
        ..._addressDetailRows(
          label: l10n.commonRefundTo,
          kind: SwapStatusDetailKind.refundTo,
          address: refundAddress,
          asset: sourceAsset,
          addressBookContacts: addressBookContacts,
          contactId: sendsZec ? null : intent.userExternalContactId,
        ),
      ?txIdRow,
      if (failed && intent.providerRefundInfo?.hasRecordedRefund == true)
        SwapStatusDetailRowData(
          label: l10n.commonRefundedAmount,
          kind: SwapStatusDetailKind.refundedAmount,
          value: amount(intent.providerRefundInfo!.refundedAmountText!),
        ),
      if (failed && recordedRefundFee != null)
        SwapStatusDetailRowData(
          label: l10n.commonRefundFee,
          kind: SwapStatusDetailKind.refundFee,
          value: amount(recordedRefundFee),
        ),
      if (!failed)
        SwapStatusDetailRowData(
          label: feesLabel,
          kind: payMode
              ? SwapStatusDetailKind.other
              : SwapStatusDetailKind.totalFees,
          value: swapDetailValueText(
            l10n,
            amount(
              intent.totalFeesText ??
                  intent.swapFeeText ??
                  intent.providerRefundInfo?.refundFeeText ??
                  l10n.swapActivityDetailIncluded,
            ),
          ),
          help: true,
          helpTooltip: swapTotalFeesTooltip(l10n),
        ),
    ];
  }

  if (intent.status == SwapIntentStatus.incompleteDeposit) {
    return _swapActivityIncompleteDepositDetails(
      l10n,
      intent,
      sourceSymbol: sourceSymbol,
      receiveSymbol: receiveSymbol,
      depositAddress: depositAddress,
      depositMemo: intent.depositMemo?.trim(),
      refundAddress: refundAddress,
      recipientAddress: recipientAddress,
      depositTxHash: depositTxHash,
      sendsZec: sendsZec,
      userExternalContactId: intent.userExternalContactId,
      addressBookContacts: addressBookContacts,
      privacyModeEnabled: privacyModeEnabled,
    );
  }

  // In-flight surfaces date the swap by when it was started; updatedAt
  // changes on every poll and would make the row jitter.
  final timestamp = _swapActivityTimestampLabel(l10n, intent.createdAt);
  final depositMemo = intent.depositMemo?.trim();
  return [
    if (sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.commonSymbolRecipient(receiveSymbol),
        kind: SwapStatusDetailKind.recipient,
        address: recipientAddress,
        asset: receiveAsset,
        addressBookContacts: addressBookContacts,
        contactId: intent.userExternalContactId,
      ),
    if (!sendsZec && refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.commonSymbolRefundAddress(sourceSymbol),
        kind: SwapStatusDetailKind.refundAddress,
        address: refundAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
        contactId: intent.userExternalContactId,
      ),
    if (depositAddress != null && depositAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapActivityDetailDepositTo(sourceSymbol),
        kind: SwapStatusDetailKind.depositAddress,
        address: depositAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
    // externalToZec deposits the user sends manually: keep a required memo
    // reachable after the optimistic claim hides the deposit page (memo/tag
    // deposits cannot complete without it).
    if (!sendsZec && depositMemo != null && depositMemo.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.commonMemo,
        kind: SwapStatusDetailKind.memo,
        value: depositMemo,
        copyable: true,
        copyText: depositMemo,
      ),
    if (!payMode)
      SwapStatusDetailRowData(
        label: l10n.commonSlippageTolerance,
        kind: SwapStatusDetailKind.slippageTolerance,
        value: swapDetailValueText(
          l10n,
          intent.slippageToleranceText ??
              l10n.swapActivityDetailConfiguredQuote,
        ),
      ),
    if (!payMode)
      SwapStatusDetailRowData(
        label: l10n.commonGuaranteedMinimum,
        kind: SwapStatusDetailKind.guaranteedMinimum,
        value: swapDetailValueText(
          l10n,
          amount(intent.minimumReceiveText ?? intent.receiveEstimate),
        ),
        help: true,
        helpTooltip: swapMinimumReceiveTooltip(l10n, receiveSymbol),
      ),
    if (timestamp != null)
      SwapStatusDetailRowData(
        label: l10n.commonTimestamp,
        kind: SwapStatusDetailKind.timestamp,
        value: timestamp,
      ),
    if (payRateText != null)
      SwapStatusDetailRowData(label: l10n.commonRate, value: payRateText),
    ?txIdRow,
    if (sendsZec && refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.commonSymbolRefundAddress(sourceSymbol),
        kind: SwapStatusDetailKind.refundAddress,
        address: refundAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (!sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.commonSymbolRecipient(receiveSymbol),
        kind: SwapStatusDetailKind.recipient,
        address: recipientAddress,
        asset: receiveAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (depositTxHash != null && depositTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: sourceTxLabel,
        kind: SwapStatusDetailKind.sourceTx,
        value: compactSwapAddress(depositTxHash),
        copyable: true,
        copyText: depositTxHash,
      ),
    if (destinationChainTxHash != null && destinationChainTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapActivityDetailDeliveryTx(receiveSymbol),
        kind: SwapStatusDetailKind.deliveryTx,
        value: compactSwapAddress(destinationChainTxHash),
        copyable: true,
        copyText: destinationChainTxHash,
      ),
    SwapStatusDetailRowData(
      label: l10n.commonSwapFee,
      kind: SwapStatusDetailKind.swapFee,
      value: swapDetailValueText(
        l10n,
        amount(intent.swapFeeText ?? l10n.swapActivityDetailIncludedInRate),
      ),
      help: true,
      helpTooltip: swapFeeTooltip(l10n),
    ),
  ];
}

List<SwapStatusDetailRowData> _swapActivityPayDetails(
  AppLocalizations l10n,
  SwapIntent intent, {
  required String sourceSymbol,
  required String receiveSymbol,
  required String? depositTxHash,
  required String? destinationChainTxHash,
  required String? payRateText,
  required bool failed,
  required String? refundAddress,
  required SwapAsset? sourceAsset,
  required Iterable<AddressBookContact> addressBookContacts,
  required bool privacyModeEnabled,
}) {
  String amount(String text) =>
      swapAmountTextForPrivacy(text, privacyModeEnabled: privacyModeEnabled);
  final terminal = intent.status.isTerminal;
  final paid = _payIntentShowsPaidCopy(intent);
  final feeText = _firstNonEmpty([
    intent.totalFeesText,
    intent.swapFeeText,
    intent.providerRefundInfo?.refundFeeText,
  ]);
  final recordedRefundFee = _recordedRefundFeeText(intent.providerRefundInfo);
  return [
    if (!failed)
      SwapStatusDetailRowData(
        label: paid ? l10n.swapActivityYouPaid : l10n.commonYouPay,
        value: amount(intent.sellAmount),
      ),
    if (!failed && payRateText != null)
      SwapStatusDetailRowData(label: l10n.commonRate, value: payRateText),
    if (!failed && feeText != null)
      SwapStatusDetailRowData(
        label: terminal
            ? l10n.swapActivityDetailFees
            : l10n.commonNetworkConversionFees,
        value: swapDetailValueText(l10n, amount(feeText)),
        help: true,
        helpTooltip: terminal
            ? swapTotalFeesTooltip(l10n)
            : swapFeeTooltip(l10n),
      ),
    if (failed && intent.providerRefundInfo?.hasRecordedRefund == true)
      SwapStatusDetailRowData(
        label: l10n.commonRefundedAmount,
        kind: SwapStatusDetailKind.refundedAmount,
        value: amount(intent.providerRefundInfo!.refundedAmountText!),
      ),
    if (failed && recordedRefundFee != null)
      SwapStatusDetailRowData(
        label: l10n.commonRefundFee,
        kind: SwapStatusDetailKind.refundFee,
        value: amount(recordedRefundFee),
      ),
    ?_swapActivityTxIdRow(l10n, intent),
    if (depositTxHash != null && depositTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapActivityDetailSourceTxShielded(sourceSymbol),
        kind: SwapStatusDetailKind.sourceTx,
        value: compactSwapAddress(depositTxHash),
        copyable: true,
        copyText: depositTxHash,
      ),
    if (destinationChainTxHash != null && destinationChainTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapActivityDetailDeliveryTx(receiveSymbol),
        kind: SwapStatusDetailKind.deliveryTx,
        value: compactSwapAddress(destinationChainTxHash),
        copyable: true,
        copyText: destinationChainTxHash,
      ),
    if (failed && refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.commonRefundTo,
        kind: SwapStatusDetailKind.refundTo,
        address: refundAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
  ];
}

String? _recordedRefundFeeText(SwapProviderRefundInfo? info) {
  if (info?.hasRecordedRefund != true) return null;
  return _firstNonEmpty([info?.recordedRefundFeeText]);
}

Uri? swapActivityExplorerUri(SwapIntent intent) => nearIntentsExplorerUri(
  depositAddress: intent.depositAddress,
  nearIntentHash: intent.nearIntentHash,
  depositTxHash: _firstNonEmpty([
    intent.depositTxHash,
    intent.originChainTxHash,
  ]),
);

SwapStatusDetailRowData? _swapActivityTxIdRow(
  AppLocalizations l10n,
  SwapIntent intent,
) {
  final txId = _firstNonEmpty([
    intent.depositAddress,
    intent.nearIntentHash,
    intent.depositTxHash,
    intent.originChainTxHash,
  ]);
  if (txId == null || txId.isEmpty) return null;

  final linkUri = swapActivityExplorerUri(intent);
  if (linkUri == null) return null;

  return SwapStatusDetailRowData(
    label: l10n.commonTxId,
    kind: SwapStatusDetailKind.txId,
    value: compactSwapAddress(txId),
    linkUri: linkUri,
  );
}

List<SwapStatusDetailRowData> _swapActivityIncompleteDepositDetails(
  AppLocalizations l10n,
  SwapIntent intent, {
  required String sourceSymbol,
  required String receiveSymbol,
  required String? depositAddress,
  required String? depositMemo,
  required String? refundAddress,
  required String? recipientAddress,
  required String? depositTxHash,
  required bool sendsZec,
  required String? userExternalContactId,
  required Iterable<AddressBookContact> addressBookContacts,
  required bool privacyModeEnabled,
}) {
  String amount(String text) =>
      swapAmountTextForPrivacy(text, privacyModeEnabled: privacyModeEnabled);
  final sourceAsset = swapActivitySellAsset(intent);
  final receiveAsset = swapActivityReceiveAsset(intent);
  final providerInfo = intent.providerRefundInfo;
  final requiredDepositText =
      _firstNonEmpty([providerInfo?.minimumDepositText, intent.sellAmount]) ??
      intent.sellAmount;
  final missingDepositText = sourceAsset == null
      ? null
      : _swapActivityMissingDepositText(
          sourceAsset: sourceAsset,
          requiredDepositText: requiredDepositText,
          depositedAmountText: providerInfo?.depositedAmountText,
        );
  final deadlineText = _swapActivityTimestampLabel(
    l10n,
    intent.depositDeadline,
  );

  return [
    if (missingDepositText != null)
      SwapStatusDetailRowData(
        label: l10n.swapActivityDetailMissingDeposit,
        kind: SwapStatusDetailKind.missingDeposit,
        value: amount(missingDepositText),
      ),
    if (depositMemo != null && depositMemo.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.commonMemo,
        kind: SwapStatusDetailKind.memo,
        value: depositMemo,
        copyable: true,
        copyText: depositMemo,
      ),
    if (depositAddress != null && depositAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapActivityDetailDepositTo(sourceSymbol),
        kind: SwapStatusDetailKind.depositAddress,
        address: depositAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
    SwapStatusDetailRowData(
      label: l10n.swapActivityDetailRequiredDeposit,
      kind: SwapStatusDetailKind.requiredDeposit,
      value: amount(requiredDepositText),
    ),
    if (providerInfo?.depositedAmountText != null)
      SwapStatusDetailRowData(
        label: l10n.swapActivityDetailDetectedDeposit,
        kind: SwapStatusDetailKind.detectedDeposit,
        value: amount(providerInfo!.depositedAmountText!),
      ),
    if (deadlineText != null)
      SwapStatusDetailRowData(
        label: l10n.swapActivityDetailDepositDeadline,
        kind: SwapStatusDetailKind.depositDeadline,
        value: deadlineText,
      ),
    if (providerInfo?.refundFeeText != null)
      SwapStatusDetailRowData(
        label: l10n.commonRefundFee,
        kind: SwapStatusDetailKind.refundFee,
        value: amount(providerInfo!.refundFeeText!),
      ),
    if (refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.commonSymbolRefundAddress(sourceSymbol),
        kind: SwapStatusDetailKind.refundAddress,
        address: refundAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
        contactId: sendsZec ? null : userExternalContactId,
      ),
    if (!sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.commonSymbolRecipient(receiveSymbol),
        kind: SwapStatusDetailKind.recipient,
        address: recipientAddress,
        asset: receiveAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (depositTxHash != null && depositTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapActivityDetailDepositTx(sourceSymbol),
        kind: SwapStatusDetailKind.sourceTx,
        value: compactSwapAddress(depositTxHash),
        copyable: true,
        copyText: depositTxHash,
      ),
    ?_swapActivityTxIdRow(l10n, intent),
  ];
}

/// Header address text: `"Rowan (0x0cd7ad0 ... 0727181)"` when the address
/// matches a saved contact, plain compact address otherwise.
String _headerAddressText(
  String address, {
  required SwapAsset? asset,
  required Iterable<AddressBookContact> contacts,
  String? contactId,
}) {
  final label = addressBookContactForSwapAsset(
    contacts: contacts,
    asset: asset,
    address: address,
    contactId: contactId,
  )?.label.trim();
  final compact = compactSwapAddress(address);
  if (label == null || label.isEmpty) return compact;
  return contactAddressDisplayText(label: label, compactAddress: compact);
}

List<SwapStatusDetailRowData> _addressDetailRows({
  required String label,
  required SwapStatusDetailKind kind,
  required String address,
  required SwapAsset? asset,
  required Iterable<AddressBookContact> addressBookContacts,
  String? contactId,
}) {
  final addressBookLabel = addressBookContactForSwapAsset(
    contacts: addressBookContacts,
    asset: asset,
    address: address,
    contactId: contactId,
  )?.label.trim();
  final addressNetwork = addressBookLabel == null || asset == null
      ? null
      : AddressBookNetwork.tryFromChainTicker(asset.chainTicker);
  // Matched rows share the address line with the network chip, so use a tighter
  // compaction (keeps the 0x prefix and the last 5 chars, no spaced ellipsis).
  final value = addressBookLabel == null
      ? compactSwapAddress(address)
      : compactSwapAddress(
          address,
          prefixLength: 7,
          suffixLength: 5,
          separator: '…',
        );
  return [
    SwapStatusDetailRowData(
      label: label,
      kind: kind,
      value: value,
      copyable: true,
      copyText: address,
      addressBookLabel: addressBookLabel,
      addressNetwork: addressNetwork,
    ),
  ];
}

SwapAsset? swapActivitySellAsset(SwapIntent intent) {
  final direction = intent.direction;
  final externalAsset = intent.externalAsset;
  if (direction == null || externalAsset == null) {
    return _swapActivityAssetFromPair(intent.pair, 0);
  }
  return direction.fromAsset(externalAsset);
}

SwapAsset? swapActivityReceiveAsset(SwapIntent intent) {
  final direction = intent.direction;
  final externalAsset = intent.externalAsset;
  if (direction == null || externalAsset == null) {
    return _swapActivityAssetFromPair(intent.pair, 1);
  }
  return direction.toAsset(externalAsset);
}

SwapAsset? _swapActivityAssetFromPair(String pair, int index) {
  final parts = pair.split('->');
  if (index < 0 || index >= parts.length) return null;
  final tokens = parts[index].trim().split(RegExp(r'\s+'));
  final symbol = tokens.isEmpty ? '' : tokens.first;
  if (symbol.isEmpty) return null;
  return SwapAsset.byName(symbol.toLowerCase());
}

String swapActivityPairSymbol(AppLocalizations l10n, String pair, int index) {
  final parts = pair.split(' -> ');
  if (parts.length > index && parts[index].trim().isNotEmpty) {
    return parts[index].trim();
  }
  return index == 0
      ? l10n.swapActivityDepositAssetFallback
      : l10n.swapActivityReceiveAssetFallback;
}

String _swapActivityFiatTextForAsset({
  required SwapIntent intent,
  required _SwapActivityAmountSide side,
  required String amountText,
}) {
  final amount = _numericAmount(amountText);
  if (amount == null || amount <= 0) return r'$--';
  final fiatValueBasis = intent.fiatValueBasis;
  if (fiatValueBasis == null) return r'$--';
  final capturedValue = switch (side) {
    _SwapActivityAmountSide.sell => fiatValueBasis.sellUsdValue(amount),
    _SwapActivityAmountSide.receive => fiatValueBasis.receiveUsdValue(amount),
  };
  return capturedValue == null
      ? r'$--'
      : swapFormatCompactFiatValue(capturedValue);
}

enum _SwapActivityAmountSide { sell, receive }

String? swapDepositDeadlineLabel(AppLocalizations l10n, SwapIntent intent) {
  final deadline = intent.depositDeadline;
  if (deadline == null) return null;
  final remaining = deadline.difference(DateTime.now());
  if (remaining.isNegative) return '00:00';
  if (remaining.inHours >= 1) {
    final hours = (remaining.inSeconds / Duration.secondsPerHour).ceil();
    return hours == 1
        ? l10n.commonDurationOneHour
        : l10n.swapActivityDeadlineHours(hours);
  }
  if (remaining.inMinutes >= 15) {
    final minutes = remaining.inMinutes;
    return minutes == 1
        ? l10n.commonDurationOneMinute
        : l10n.swapActivityDeadlineMinutes(minutes);
  }
  final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String? _swapActivityLastRelativeStatusCheckedLabel(
  AppLocalizations l10n,
  DateTime? checkedAt,
) {
  if (checkedAt == null) return null;
  final elapsed = DateTime.now().difference(checkedAt.toLocal());
  if (elapsed.inMinutes <= 0) return l10n.swapActivityLastCheckJustNow;
  return l10n.swapActivityLastCheckMinutesAgo(elapsed.inMinutes);
}

String? _swapActivityTimestampLabel(
  AppLocalizations l10n,
  DateTime? timestamp,
) {
  if (timestamp == null) return null;
  return DateFormat.yMMMd(l10n.localeName).add_Hm().format(timestamp.toLocal());
}

class SwapActivityDepositInstruction {
  const SwapActivityDepositInstruction({
    required this.sendLabel,
    required this.depositSymbol,
    required this.depositAddressLabel,
    required this.address,
    required this.txHashLabel,
    required this.txHashHint,
    required this.submitLabel,
    this.memo,
    this.qr,
  });

  /// The instructions for funding `intent`, or null while it has none to show,
  /// including while its wallet start is pending (see
  /// [SwapIntent.startPending]).
  static SwapActivityDepositInstruction? fromIntent(
    AppLocalizations l10n,
    SwapIntent intent,
  ) {
    if (intent.startPending) return null;
    final direction = intent.direction;
    final externalAsset = intent.externalAsset;
    final depositAddress = intent.depositAddress;
    if (direction == null || externalAsset == null || depositAddress == null) {
      return null;
    }

    final depositSymbol = direction.fromSymbol(externalAsset);
    final depositAddressLabel = direction.sendsZec
        ? l10n.swapActivityDepositInstructionDepositLabel(depositSymbol)
        : l10n.swapActivityDepositInstructionSourceDepositLabel(depositSymbol);

    return SwapActivityDepositInstruction(
      sendLabel: direction.sendsZec
          ? l10n.swapActivityStepSend(depositSymbol)
          : l10n.swapActivityDepositInstructionSendFromSource(depositSymbol),
      depositSymbol: depositSymbol,
      depositAddressLabel: depositAddressLabel,
      address: depositAddress,
      memo: intent.depositMemo,
      txHashLabel: l10n.swapActivityDepositInstructionTxHashLabel(
        depositSymbol,
      ),
      txHashHint: l10n.swapActivityDepositInstructionTxHashHint(depositSymbol),
      submitLabel: l10n.swapActivityDepositInstructionSubmit(depositSymbol),
      qr: direction.sendsZec
          ? null
          : SwapActivityDepositQrInstruction(
              railLabel: externalAsset.railLabel,
              reuseWarning: l10n.swapActivityDepositInstructionReuseWarning,
            ),
    );
  }

  final String sendLabel;
  final String depositSymbol;
  final String depositAddressLabel;
  final String address;
  final String? memo;
  final String txHashLabel;
  final String txHashHint;
  final String submitLabel;
  final SwapActivityDepositQrInstruction? qr;
}

class SwapActivityDepositQrInstruction {
  const SwapActivityDepositQrInstruction({
    required this.railLabel,
    required this.reuseWarning,
  });

  final String railLabel;
  final String reuseWarning;
}

bool canRefreshSwapIntentStatus(SwapIntentStatus status) {
  return status != SwapIntentStatus.complete;
}

bool _hasDepositInstruction(SwapIntent intent) =>
    intent.direction != null &&
    intent.externalAsset != null &&
    intent.depositAddress != null;

bool swapActivityShowsExternalDepositPage(SwapIntent intent) {
  return intent.direction == SwapDirection.externalToZec &&
      intent.status == SwapIntentStatus.awaitingExternalDeposit &&
      intent.depositClaimedAt == null &&
      _hasDepositInstruction(intent);
}

bool swapActivityShowsHardwareZecDepositPage(
  SwapIntent intent, {
  required bool intentIsHardware,
}) {
  return intentIsHardware &&
      intent.direction == SwapDirection.zecToExternal &&
      intent.status == SwapIntentStatus.awaitingDeposit &&
      !(intent.depositTxHash?.trim().isNotEmpty ?? false) &&
      _hasDepositInstruction(intent);
}

bool swapActivityShowsDepositPage(
  SwapIntent intent, {
  required bool intentIsHardware,
}) {
  if (intent.status == SwapIntentStatus.expired) return true;
  return swapActivityShowsExternalDepositPage(intent) ||
      swapActivityShowsHardwareZecDepositPage(
        intent,
        intentIsHardware: intentIsHardware,
      );
}

String? _swapActivityMissingDepositText({
  required SwapAsset sourceAsset,
  required String requiredDepositText,
  required String? depositedAmountText,
}) {
  final requiredAmount = _numericAmount(requiredDepositText);
  final depositedAmount = _numericAmount(depositedAmountText ?? '');
  if (requiredAmount == null || depositedAmount == null) return null;
  final missingAmount = requiredAmount - depositedAmount;
  if (!missingAmount.isFinite || missingAmount <= 0) return null;
  return '${swapPreciseAmountText(sourceAsset, missingAmount)} ' // l10n-ignore: amount format
      '${sourceAsset.symbol}';
}

String? _swapActivityPayRateText(SwapIntent intent, SwapAsset? receiveAsset) {
  if (receiveAsset == null) return null;
  final sellAmount = _numericAmount(intent.sellAmount);
  final receiveAmount = _numericAmount(intent.receiveEstimate);
  if (sellAmount == null || receiveAmount == null || sellAmount <= 0) {
    return null;
  }
  final rate = receiveAmount / sellAmount;
  if (!rate.isFinite || rate <= 0) return null;
  return '1 ZEC = ${swapPreciseAmountText(receiveAsset, rate)} ' // l10n-ignore: amount format
      '${receiveAsset.symbol}';
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

double? _numericAmount(String amountText) {
  final raw = amountText.split(RegExp(r'\s+')).first.replaceAll(',', '').trim();
  final amount = double.tryParse(raw);
  return amount == null || !amount.isFinite ? null : amount;
}
