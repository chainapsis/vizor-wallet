import '../../../core/config/fiat_currencies.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/widgets/contact_name_inline.dart';
import '../domain/near_intents_explorer.dart';
import 'swap_address_book_helpers.dart';
import 'swap_address_formatting.dart';
import 'swap_detail_tooltips.dart';
import 'swap_models.dart';
import 'swap_status_presentation.dart';
import 'swap_token_amount_formatting.dart';

class SwapActivityAccountDetail {
  const SwapActivityAccountDetail({required this.name, this.profilePictureId});

  final String name;
  final String? profilePictureId;
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
    this.payDetailText = '',
    this.payDetailCopyText,
    this.receiveDetailText = '',
    this.receiveDetailCopyText,
    this.statusLabel = '',
    required this.badgeKind,
    required this.progressIndex,
    required this.steps,
    required this.details,
    required this.showTabs,
  });

  final String title;
  final SwapAsset payAsset;
  final SwapAsset receiveAsset;
  final String payFiatText;
  final String receiveFiatText;
  final String payAmountText;
  final String receiveAmountText;

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
  final bool showTabs;
}

SwapActivityStatusPresentation swapActivityStatusPresentationForIntent(
  SwapState state,
  SwapIntent intent, {
  SwapActivityAccountDetail? accountDetail,
  Iterable<AddressBookContact> addressBookContacts = const [],
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  final sellAsset = swapActivitySellAsset(intent) ?? SwapAsset.zec;
  final receiveAsset = swapActivityReceiveAsset(intent) ?? SwapAsset.usdc;
  final sendsZec = intent.direction != SwapDirection.externalToZec;
  final recipientAddress = intent.oneClickRecipient?.trim();
  final refundAddress = intent.oneClickRefundTo?.trim();
  final payFiatText = _swapActivityFiatTextForAsset(
    intent: intent,
    side: _SwapActivityAmountSide.sell,
    amountText: intent.sellAmount,
    fiatDisplay: fiatDisplay,
  );
  final receiveFiatText = _swapActivityFiatTextForAsset(
    intent: intent,
    side: _SwapActivityAmountSide.receive,
    amountText: intent.receiveEstimate,
    fiatDisplay: fiatDisplay,
  );

  // The summary's bottom lines: fiat on the ZEC side, the counterparty
  // address on the external side (recipient when sending ZEC, refund
  // address when depositing an external asset).
  var payDetailText = payFiatText;
  String? payDetailCopyText;
  var receiveDetailText = receiveFiatText;
  String? receiveDetailCopyText;
  if (sendsZec) {
    if (recipientAddress != null && recipientAddress.isNotEmpty) {
      receiveDetailText =
          'To: ${_headerAddressText(recipientAddress, asset: receiveAsset, contacts: addressBookContacts)} '
          'on ${receiveAsset.chainLabel}';
      receiveDetailCopyText = recipientAddress;
    }
  } else {
    if (refundAddress != null && refundAddress.isNotEmpty) {
      payDetailText =
          'Refund to: ${_headerAddressText(refundAddress, asset: sellAsset, contacts: addressBookContacts)}';
      payDetailCopyText = refundAddress;
    }
  }

  return SwapActivityStatusPresentation(
    title: _swapActivityStatusTitle(intent),
    payAsset: sellAsset,
    receiveAsset: receiveAsset,
    payFiatText: payFiatText,
    receiveFiatText: receiveFiatText,
    payAmountText: intent.sellAmount,
    receiveAmountText: intent.receiveEstimate,
    payDetailText: payDetailText,
    payDetailCopyText: payDetailCopyText,
    receiveDetailText: receiveDetailText,
    receiveDetailCopyText: receiveDetailCopyText,
    statusLabel: intent.status.label,
    badgeKind: _swapActivityStatusBadgeKind(intent.status),
    progressIndex: _swapActivityStatusProgressIndex(intent),
    steps: _swapActivityProgressSteps(intent),
    details: _swapActivityStatusDetails(
      intent,
      addressBookContacts: addressBookContacts,
    ),
    showTabs: !intent.status.isTerminal,
  );
}

String _swapActivityStatusTitle(SwapIntent intent) {
  return switch (intent.status) {
    SwapIntentStatus.complete => 'Swap completed',
    SwapIntentStatus.incompleteDeposit => 'Incomplete deposit',
    SwapIntentStatus.failed || SwapIntentStatus.refunded => 'Swap failed',
    _ => 'Swap in progress...',
  };
}

SwapStatusBadgeKind _swapActivityStatusBadgeKind(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => SwapStatusBadgeKind.completed,
    SwapIntentStatus.incompleteDeposit => SwapStatusBadgeKind.warning,
    SwapIntentStatus.failed ||
    SwapIntentStatus.refunded ||
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

List<SwapStatusStepData> _swapActivityProgressSteps(SwapIntent intent) {
  final sourceSymbol = swapActivityPairSymbol(intent.pair, 0);
  final receiveSymbol = swapActivityPairSymbol(intent.pair, 1);
  final sourceVerb = intent.direction == SwapDirection.zecToExternal
      ? 'Sending'
      : 'Depositing';
  final sourceDone = intent.direction == SwapDirection.zecToExternal
      ? '$sourceSymbol sent'
      : '$sourceSymbol Deposited';
  final deliveryTitle = intent.direction == SwapDirection.zecToExternal
      ? 'Deliver $receiveSymbol'
      : 'Send $receiveSymbol';

  final lastCheckedLabel =
      _swapActivityLastRelativeStatusCheckedLabel(intent.lastStatusCheckedAt) ??
      'Last check: just now';

  return [
    SwapStatusStepData(
      title: sourceSymbol,
      state: SwapStatusStepState.pending,
      completeTitle: sourceDone,
      activeTitle: '$sourceVerb $sourceSymbol...',
      pendingTitle: intent.direction == SwapDirection.zecToExternal
          ? 'Send $sourceSymbol'
          : 'Deposit $sourceSymbol',
      lastCheckedLabel: lastCheckedLabel,
      description:
          'Confirm waiting for the source chain and provider to recognise the deposit',
    ),
    SwapStatusStepData(
      title: 'Deposit confirmation',
      state: SwapStatusStepState.pending,
      activeTitle: 'Deposit confirmation...',
      lastCheckedLabel: lastCheckedLabel,
      description: 'Confirming the deposit before the swap route starts.',
    ),
    SwapStatusStepData(
      title: 'Swap',
      state: SwapStatusStepState.pending,
      activeTitle: 'Swap...',
      lastCheckedLabel: lastCheckedLabel,
      description: 'The provider is executing the swap route.',
    ),
    SwapStatusStepData(
      title: deliveryTitle,
      state: SwapStatusStepState.pending,
      activeTitle: '$deliveryTitle...',
      lastCheckedLabel: lastCheckedLabel,
      description: 'Delivering the output asset to the recipient address.',
    ),
  ];
}

List<SwapStatusDetailRowData> _swapActivityStatusDetails(
  SwapIntent intent, {
  required Iterable<AddressBookContact> addressBookContacts,
}) {
  final sourceSymbol = swapActivityPairSymbol(intent.pair, 0);
  final receiveSymbol = swapActivityPairSymbol(intent.pair, 1);
  final sourceAsset = swapActivitySellAsset(intent);
  final receiveAsset = swapActivityReceiveAsset(intent);
  final refundAddress = intent.oneClickRefundTo?.trim();
  final recipientAddress = intent.oneClickRecipient?.trim();
  final depositAddress = intent.depositAddress?.trim();
  final localDepositTxHash = intent.depositTxHash?.trim();
  final originChainTxHash = intent.originChainTxHash?.trim();
  final destinationChainTxHash = intent.destinationChainTxHash?.trim();
  final depositTxHash = _firstNonEmpty([localDepositTxHash, originChainTxHash]);
  // The Tx ID detail row is a mobile-only addition; desktop keeps the
  // original detail set (the standalone "<symbol> deposit tx" row).
  final txIdRow = kAppFormFactor == AppFormFactor.mobile
      ? _swapActivityTxIdRow(
          intent: intent,
          depositTxHash: depositTxHash,
          depositAddress: depositAddress,
        )
      : null;
  final terminal = intent.status.isTerminal;
  final failed =
      _swapActivityStatusBadgeKind(intent.status) == SwapStatusBadgeKind.failed;
  final sendsZec = intent.direction != SwapDirection.externalToZec;

  if (terminal) {
    // Terminal surfaces date the swap by its settlement time, falling back
    // to the start time for records persisted before completion tracking.
    final timestamp = _swapActivityTimestampLabel(
      intent.completedAt ?? intent.createdAt,
    );
    final explorerUri = nearIntentsExplorerUri(
      nearIntentHash: intent.nearIntentHash,
      depositTxHash: depositTxHash,
      depositAddress: depositAddress,
    );
    return [
      if (!failed)
        SwapStatusDetailRowData(
          label: 'Realized slippage',
          value: intent.realisedSlippageText ?? 'Not reported',
        ),
      if (timestamp != null)
        SwapStatusDetailRowData(label: 'Timestamp', value: timestamp),
      if (depositTxHash != null && depositTxHash.isNotEmpty)
        SwapStatusDetailRowData(
          label: '$sourceSymbol deposit tx',
          value: compactSwapAddress(depositTxHash),
          copyable: true,
          copyText: depositTxHash,
          linkUri: explorerUri,
        ),
      if (failed && refundAddress != null && refundAddress.isNotEmpty)
        ..._addressDetailRows(
          label: '$sourceSymbol refunded to',
          address: refundAddress,
          asset: sourceAsset,
          addressBookContacts: addressBookContacts,
        ),
      ?txIdRow,
      SwapStatusDetailRowData(
        label: 'Total fees',
        value:
            intent.totalFeesText ??
            intent.swapFeeText ??
            intent.providerRefundInfo?.refundFeeText ??
            'Included',
        help: true,
        helpTooltip: swapTotalFeesTooltip,
      ),
    ];
  }

  if (intent.status == SwapIntentStatus.incompleteDeposit) {
    return _swapActivityIncompleteDepositDetails(
      intent,
      sourceSymbol: sourceSymbol,
      receiveSymbol: receiveSymbol,
      depositAddress: depositAddress,
      depositMemo: intent.depositMemo?.trim(),
      refundAddress: refundAddress,
      recipientAddress: recipientAddress,
      depositTxHash: depositTxHash,
      sendsZec: sendsZec,
      addressBookContacts: addressBookContacts,
    );
  }

  // In-flight surfaces date the swap by when it was started; updatedAt
  // changes on every poll and would make the row jitter.
  final timestamp = _swapActivityTimestampLabel(intent.createdAt);
  final depositMemo = intent.depositMemo?.trim();
  return [
    if (sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: '$receiveSymbol recipient',
        address: recipientAddress,
        asset: receiveAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (!sendsZec && refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: '$sourceSymbol refund address',
        address: refundAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (depositAddress != null && depositAddress.isNotEmpty)
      ..._addressDetailRows(
        label: 'Deposit $sourceSymbol to',
        address: depositAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
    // externalToZec deposits the user sends manually: keep a required memo
    // reachable after the optimistic claim hides the deposit page (memo/tag
    // deposits cannot complete without it).
    if (!sendsZec && depositMemo != null && depositMemo.isNotEmpty)
      SwapStatusDetailRowData(
        label: 'Memo',
        value: depositMemo,
        copyable: true,
        copyText: depositMemo,
      ),
    SwapStatusDetailRowData(
      label: 'Slippage tolerance',
      value: intent.slippageToleranceText ?? 'Configured quote',
    ),
    SwapStatusDetailRowData(
      label: 'Guaranteed minimum',
      value: intent.minimumReceiveText ?? intent.receiveEstimate,
      help: true,
      helpTooltip: swapMinimumReceiveTooltip(receiveSymbol),
    ),
    if (timestamp != null)
      SwapStatusDetailRowData(label: 'Timestamp', value: timestamp),
    ?txIdRow,
    if (sendsZec && refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: '$sourceSymbol refund address',
        address: refundAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (!sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: '$receiveSymbol recipient',
        address: recipientAddress,
        asset: receiveAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (depositTxHash != null && depositTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$sourceSymbol deposit tx',
        value: compactSwapAddress(depositTxHash),
        copyable: true,
        copyText: depositTxHash,
      ),
    if (destinationChainTxHash != null && destinationChainTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$receiveSymbol delivery tx',
        value: compactSwapAddress(destinationChainTxHash),
        copyable: true,
        copyText: destinationChainTxHash,
      ),
    SwapStatusDetailRowData(
      label: 'Swap fee',
      value: intent.swapFeeText ?? 'Included in shown rate',
      help: true,
      helpTooltip: swapFeeTooltip,
    ),
  ];
}

SwapStatusDetailRowData? _swapActivityTxIdRow({
  required SwapIntent intent,
  required String? depositTxHash,
  required String? depositAddress,
}) {
  final hasExplorerSource =
      (intent.nearIntentHash?.trim().isNotEmpty ?? false) ||
      (depositTxHash?.trim().isNotEmpty ?? false);
  if (!hasExplorerSource) return null;

  final txId = _firstNonEmpty([
    depositAddress,
    intent.nearIntentHash?.trim(),
    depositTxHash,
  ]);
  if (txId == null || txId.isEmpty) return null;

  final linkUri = nearIntentsExplorerUri(
    nearIntentHash: intent.nearIntentHash,
    depositTxHash: depositTxHash,
    depositAddress: depositAddress,
  );
  if (linkUri == null) return null;

  return SwapStatusDetailRowData(
    label: 'Tx ID',
    value: compactSwapAddress(txId),
    linkUri: linkUri,
  );
}

List<SwapStatusDetailRowData> _swapActivityIncompleteDepositDetails(
  SwapIntent intent, {
  required String sourceSymbol,
  required String receiveSymbol,
  required String? depositAddress,
  required String? depositMemo,
  required String? refundAddress,
  required String? recipientAddress,
  required String? depositTxHash,
  required bool sendsZec,
  required Iterable<AddressBookContact> addressBookContacts,
}) {
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
  final deadlineText = _swapActivityTimestampLabel(intent.depositDeadline);

  return [
    if (missingDepositText != null)
      SwapStatusDetailRowData(
        label: 'Missing deposit',
        value: missingDepositText,
      ),
    if (depositMemo != null && depositMemo.isNotEmpty)
      SwapStatusDetailRowData(
        label: 'Memo',
        value: depositMemo,
        copyable: true,
        copyText: depositMemo,
      ),
    if (depositAddress != null && depositAddress.isNotEmpty)
      ..._addressDetailRows(
        label: 'Deposit $sourceSymbol to',
        address: depositAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
    SwapStatusDetailRowData(
      label: 'Required deposit',
      value: requiredDepositText,
    ),
    if (providerInfo?.depositedAmountText != null)
      SwapStatusDetailRowData(
        label: 'Detected deposit',
        value: providerInfo!.depositedAmountText!,
      ),
    if (deadlineText != null)
      SwapStatusDetailRowData(label: 'Deposit deadline', value: deadlineText),
    if (providerInfo?.refundFeeText != null)
      SwapStatusDetailRowData(
        label: 'Refund fee',
        value: providerInfo!.refundFeeText!,
      ),
    if (refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: '$sourceSymbol refund address',
        address: refundAddress,
        asset: sourceAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (!sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: '$receiveSymbol recipient',
        address: recipientAddress,
        asset: receiveAsset,
        addressBookContacts: addressBookContacts,
      ),
    if (depositTxHash != null && depositTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$sourceSymbol deposit tx',
        value: compactSwapAddress(depositTxHash),
        copyable: true,
        copyText: depositTxHash,
      ),
  ];
}

/// Header address text: `"Rowan (0x0cd7ad0 ... 0727181)"` when the address
/// matches a saved contact, plain compact address otherwise.
String _headerAddressText(
  String address, {
  required SwapAsset? asset,
  required Iterable<AddressBookContact> contacts,
}) {
  final label = addressBookContactForSwapAsset(
    contacts: contacts,
    asset: asset,
    address: address,
  )?.label.trim();
  final compact = compactSwapAddress(address);
  if (label == null || label.isEmpty) return compact;
  return contactAddressDisplayText(label: label, compactAddress: compact);
}

List<SwapStatusDetailRowData> _addressDetailRows({
  required String label,
  required String address,
  required SwapAsset? asset,
  required Iterable<AddressBookContact> addressBookContacts,
}) {
  final addressBookLabel = addressBookContactForSwapAsset(
    contacts: addressBookContacts,
    asset: asset,
    address: address,
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

String swapActivityPairSymbol(String pair, int index) {
  final parts = pair.split(' -> ');
  if (parts.length > index && parts[index].trim().isNotEmpty) {
    return parts[index].trim();
  }
  return index == 0 ? 'deposit asset' : 'receive asset';
}

/// The persisted basis is USD captured at swap time; non-USD display uses
/// the *current* implied FX rate, so historical rows re-price as FX moves.
/// This is deliberate (display-only conversion, nothing persisted changes) —
/// capturing per-currency values at swap time would require storing them.
String _swapActivityFiatTextForAsset({
  required SwapIntent intent,
  required _SwapActivityAmountSide side,
  required String amountText,
  required FiatDisplay fiatDisplay,
}) {
  final amount = _numericAmount(amountText);
  if (amount == null || amount <= 0) return fiatDisplay.placeholderText;
  final fiatValueBasis = intent.fiatValueBasis;
  if (fiatValueBasis == null) return fiatDisplay.placeholderText;
  final capturedValue = switch (side) {
    _SwapActivityAmountSide.sell => fiatValueBasis.sellUsdValue(amount),
    _SwapActivityAmountSide.receive => fiatValueBasis.receiveUsdValue(amount),
  };
  return capturedValue == null
      ? fiatDisplay.placeholderText
      : fiatDisplay.formatCompactUsdValue(capturedValue);
}

enum _SwapActivityAmountSide { sell, receive }

String? swapDepositDeadlineLabel(SwapIntent intent) {
  final deadline = intent.depositDeadline;
  if (deadline == null) return null;
  final remaining = deadline.difference(DateTime.now());
  if (remaining.isNegative) return '00:00';
  if (remaining.inHours >= 1) {
    final hours = (remaining.inSeconds / Duration.secondsPerHour).ceil();
    return hours == 1 ? '1hr' : '${hours}hrs';
  }
  if (remaining.inMinutes >= 15) {
    final minutes = remaining.inMinutes;
    return minutes == 1 ? '1min' : '${minutes}mins';
  }
  final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String? _swapActivityLastRelativeStatusCheckedLabel(DateTime? checkedAt) {
  if (checkedAt == null) return null;
  final elapsed = DateTime.now().difference(checkedAt.toLocal());
  if (elapsed.inMinutes <= 0) return 'Last check: just now';
  return 'Last check: ${elapsed.inMinutes}m ago';
}

String? _swapActivityTimestampLabel(DateTime? timestamp) {
  if (timestamp == null) return null;
  final local = timestamp.toLocal();
  final month = _monthNames[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month ${local.day}, ${local.year} $hour:$minute';
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

  static SwapActivityDepositInstruction? fromIntent(SwapIntent intent) {
    final direction = intent.direction;
    final externalAsset = intent.externalAsset;
    final depositAddress = intent.depositAddress;
    if (direction == null || externalAsset == null || depositAddress == null) {
      return null;
    }

    final depositSymbol = direction.fromSymbol(externalAsset);
    final depositAddressLabel = direction.sendsZec
        ? '$depositSymbol deposit'
        : '$depositSymbol source deposit';

    return SwapActivityDepositInstruction(
      sendLabel: direction.sendsZec
          ? 'Send $depositSymbol'
          : 'Send $depositSymbol from source chain',
      depositSymbol: depositSymbol,
      depositAddressLabel: depositAddressLabel,
      address: depositAddress,
      memo: intent.depositMemo,
      txHashLabel: '$depositSymbol deposit tx hash',
      txHashHint: '$depositSymbol source-chain transaction hash',
      submitLabel: 'Submit $depositSymbol deposit',
      qr: direction.sendsZec
          ? null
          : SwapActivityDepositQrInstruction(
              railLabel: externalAsset.railLabel,
              reuseWarning: 'Do not reuse this address',
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

bool swapActivityShowsExternalDepositPage(SwapIntent intent) {
  return intent.direction == SwapDirection.externalToZec &&
      intent.status == SwapIntentStatus.awaitingExternalDeposit &&
      intent.depositClaimedAt == null &&
      SwapActivityDepositInstruction.fromIntent(intent) != null;
}

bool swapActivityShowsHardwareZecDepositPage(
  SwapIntent intent, {
  required bool intentIsHardware,
}) {
  return intentIsHardware &&
      intent.direction == SwapDirection.zecToExternal &&
      intent.status == SwapIntentStatus.awaitingDeposit &&
      !(intent.depositTxHash?.trim().isNotEmpty ?? false) &&
      SwapActivityDepositInstruction.fromIntent(intent) != null;
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
  return '${swapPreciseAmountText(sourceAsset, missingAmount)} '
      '${sourceAsset.symbol}';
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

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
