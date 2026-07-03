import '../../../core/layout/app_form_factor.dart';
import '../../address_book/models/address_book_contact.dart';
import '../domain/near_intents_explorer.dart';
import 'swap_address_formatting.dart';
import 'swap_detail_tooltips.dart';
import 'swap_fiat_value_formatting.dart';
import 'swap_models.dart';
import 'swap_status_presentation.dart';
import 'swap_token_amount_formatting.dart';
import 'package:intl/intl.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/formatting/date_format.dart' show intlSafeLocale;

class SwapActivityAccountDetail {
  const SwapActivityAccountDetail({required this.name, this.profilePictureId});

  final String name;
  final String? profilePictureId;
}

class _SwapActivityAddressBookLabels {
  _SwapActivityAddressBookLabels(Iterable<AddressBookContact> contacts)
    : _contacts = contacts.toList(growable: false);

  final List<AddressBookContact> _contacts;

  String? labelFor({required SwapAsset? asset, required String address}) {
    if (asset == null) return null;
    final network = AddressBookNetwork.tryFromChainTicker(asset.chainTicker);
    if (network == null) return null;

    final target = _normalizedAddress(network, address);
    if (target.isEmpty) return null;
    for (final contact in _contacts) {
      if (contact.network != network) continue;
      if (_normalizedAddress(network, contact.address) != target) continue;
      final label = contact.label.trim();
      return label.isEmpty ? null : label;
    }
    return null;
  }
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
  required AppLocalizations l10n,
  SwapActivityAccountDetail? accountDetail,
  Iterable<AddressBookContact> addressBookContacts = const [],
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
  );
  final receiveFiatText = _swapActivityFiatTextForAsset(
    intent: intent,
    side: _SwapActivityAmountSide.receive,
    amountText: intent.receiveEstimate,
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
      receiveDetailText = l10n.swapToAddressOnChain(
        compactSwapAddress(recipientAddress),
        receiveAsset.chainLabel,
      );
      receiveDetailCopyText = recipientAddress;
    }
  } else {
    if (refundAddress != null && refundAddress.isNotEmpty) {
      payDetailText = l10n.swapRefundToAddress(
        compactSwapAddress(refundAddress),
      );
      payDetailCopyText = refundAddress;
    }
  }

  return SwapActivityStatusPresentation(
    title: _swapActivityStatusTitle(intent, l10n),
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
    statusLabel: intent.status.label(l10n),
    badgeKind: _swapActivityStatusBadgeKind(intent.status),
    progressIndex: _swapActivityStatusProgressIndex(intent),
    steps: _swapActivityProgressSteps(intent, l10n),
    details: _swapActivityStatusDetails(
      intent,
      addressBookContacts: addressBookContacts,
      l10n: l10n,
    ),
    showTabs: !intent.status.isTerminal,
  );
}

String _swapActivityStatusTitle(SwapIntent intent, AppLocalizations l10n) {
  return switch (intent.status) {
    SwapIntentStatus.complete => l10n.swapTitleCompleted,
    SwapIntentStatus.incompleteDeposit => l10n.swapStatusIncompleteDeposit,
    SwapIntentStatus.failed || SwapIntentStatus.refunded => l10n.swapTitleFailed,
    _ => l10n.swapTitleInProgress,
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

List<SwapStatusStepData> _swapActivityProgressSteps(
  SwapIntent intent,
  AppLocalizations l10n,
) {
  final sourceSymbol = swapActivityPairSymbol(intent.pair, 0);
  final receiveSymbol = swapActivityPairSymbol(intent.pair, 1);
  final sourceVerb = intent.direction == SwapDirection.zecToExternal
      ? l10n.swapVerbSending
      : l10n.swapVerbDepositing;
  final sourceDone = intent.direction == SwapDirection.zecToExternal
      ? l10n.swapSymbolSent(sourceSymbol)
      : l10n.swapSymbolDeposited(sourceSymbol);
  final deliveryTitle = intent.direction == SwapDirection.zecToExternal
      ? l10n.swapDeliverSymbol(receiveSymbol)
      : l10n.swapSendSymbol(receiveSymbol);

  final lastCheckedLabel =
      _swapActivityLastRelativeStatusCheckedLabel(
        intent.lastStatusCheckedAt,
        l10n,
      ) ??
      l10n.swapLastCheckJustNow;

  return [
    SwapStatusStepData(
      title: sourceSymbol,
      state: SwapStatusStepState.pending,
      completeTitle: sourceDone,
      activeTitle: '$sourceVerb $sourceSymbol...',
      pendingTitle: intent.direction == SwapDirection.zecToExternal
          ? l10n.swapSendSymbol(sourceSymbol)
          : l10n.swapDepositSymbol(sourceSymbol),
      lastCheckedLabel: lastCheckedLabel,
      description: l10n.swapStepSourceDesc,
    ),
    SwapStatusStepData(
      title: l10n.swapStepDepositConfirmation,
      state: SwapStatusStepState.pending,
      activeTitle: l10n.swapStepDepositConfirmationActive,
      lastCheckedLabel: lastCheckedLabel,
      description: l10n.swapStepConfirmingDesc,
    ),
    SwapStatusStepData(
      title: l10n.swapStepSwapTitle,
      state: SwapStatusStepState.pending,
      activeTitle: l10n.swapStepSwapActive,
      lastCheckedLabel: lastCheckedLabel,
      description: l10n.swapStepSwapDesc,
    ),
    SwapStatusStepData(
      title: deliveryTitle,
      state: SwapStatusStepState.pending,
      activeTitle: '$deliveryTitle...',
      lastCheckedLabel: lastCheckedLabel,
      description: l10n.swapStepDeliveryDesc,
    ),
  ];
}

List<SwapStatusDetailRowData> _swapActivityStatusDetails(
  SwapIntent intent, {
  required Iterable<AddressBookContact> addressBookContacts,
  required AppLocalizations l10n,
}) {
  final sourceSymbol = swapActivityPairSymbol(intent.pair, 0);
  final receiveSymbol = swapActivityPairSymbol(intent.pair, 1);
  final sourceAsset = swapActivitySellAsset(intent);
  final receiveAsset = swapActivityReceiveAsset(intent);
  final addressBookLabels = _SwapActivityAddressBookLabels(addressBookContacts);
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
          l10n: l10n,
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
      l10n,
    );
    final explorerUri = nearIntentsExplorerUri(
      nearIntentHash: intent.nearIntentHash,
      depositTxHash: depositTxHash,
      depositAddress: depositAddress,
    );
    return [
      if (!failed)
        SwapStatusDetailRowData(
          label: l10n.swapRealizedSlippageLabel,
          kind: SwapStatusDetailRowKind.realizedSlippage,
          value: intent.realisedSlippageText ?? l10n.swapNotReported,
        ),
      if (timestamp != null)
        SwapStatusDetailRowData(
          label: l10n.swapTimestampLabel,
          kind: SwapStatusDetailRowKind.timestamp,
          value: timestamp,
        ),
      if (depositTxHash != null && depositTxHash.isNotEmpty)
        SwapStatusDetailRowData(
          label: l10n.swapDepositTxLabel(sourceSymbol),
          kind: SwapStatusDetailRowKind.depositTx,
          value: compactSwapAddress(depositTxHash),
          copyable: true,
          copyText: depositTxHash,
          scaleValueToFit: true,
          linkUri: explorerUri,
        ),
      if (failed && refundAddress != null && refundAddress.isNotEmpty)
        ..._addressDetailRows(
          label: l10n.swapRefundedToLabel(sourceSymbol),
          kind: SwapStatusDetailRowKind.refundAddress,
          address: refundAddress,
          asset: sourceAsset,
          addressBookLabels: addressBookLabels,
        ),
      ?txIdRow,
      SwapStatusDetailRowData(
        label: l10n.swapTotalFeesLabel,
        kind: SwapStatusDetailRowKind.totalFees,
        value:
            intent.totalFeesText ??
            intent.swapFeeText ??
            intent.providerRefundInfo?.refundFeeText ??
            l10n.swapIncluded,
        help: true,
        helpTooltip: swapTotalFeesTooltip(l10n),
      ),
    ];
  }

  if (intent.status == SwapIntentStatus.incompleteDeposit) {
    return _swapActivityIncompleteDepositDetails(
      intent,
      l10n: l10n,
      sourceSymbol: sourceSymbol,
      receiveSymbol: receiveSymbol,
      depositAddress: depositAddress,
      depositMemo: intent.depositMemo?.trim(),
      refundAddress: refundAddress,
      recipientAddress: recipientAddress,
      depositTxHash: depositTxHash,
      sendsZec: sendsZec,
      addressBookLabels: addressBookLabels,
    );
  }

  // In-flight surfaces date the swap by when it was started; updatedAt
  // changes on every poll and would make the row jitter.
  final timestamp = _swapActivityTimestampLabel(intent.createdAt, l10n);
  final depositMemo = intent.depositMemo?.trim();
  return [
    if (sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapRecipientLabel(receiveSymbol),
        kind: SwapStatusDetailRowKind.recipient,
        address: recipientAddress,
        asset: receiveAsset,
        addressBookLabels: addressBookLabels,
      ),
    if (!sendsZec && refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapRefundAddressLabel(sourceSymbol),
        kind: SwapStatusDetailRowKind.refundAddress,
        address: refundAddress,
        asset: sourceAsset,
        addressBookLabels: addressBookLabels,
      ),
    if (depositAddress != null && depositAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapDepositToLabel(sourceSymbol),
        kind: SwapStatusDetailRowKind.depositAddress,
        address: depositAddress,
        asset: sourceAsset,
        addressBookLabels: addressBookLabels,
      ),
    // externalToZec deposits the user sends manually: keep a required memo
    // reachable after the optimistic claim hides the deposit page (memo/tag
    // deposits cannot complete without it).
    if (!sendsZec && depositMemo != null && depositMemo.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapMemoLabel,
        kind: SwapStatusDetailRowKind.memo,
        value: depositMemo,
        copyable: true,
        copyText: depositMemo,
      ),
    SwapStatusDetailRowData(
      label: l10n.swapSlippageToleranceLabel,
      kind: SwapStatusDetailRowKind.slippageTolerance,
      value: intent.slippageToleranceText ?? l10n.swapConfiguredQuote,
    ),
    SwapStatusDetailRowData(
      label: l10n.swapGuaranteedMinimumLabel,
      kind: SwapStatusDetailRowKind.guaranteedMinimum,
      value: intent.minimumReceiveText ?? intent.receiveEstimate,
      help: true,
      helpTooltip: swapMinimumReceiveTooltip(l10n, receiveSymbol),
    ),
    if (timestamp != null)
      SwapStatusDetailRowData(
        label: l10n.swapTimestampLabel,
        kind: SwapStatusDetailRowKind.timestamp,
        value: timestamp,
      ),
    ?txIdRow,
    if (sendsZec && refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapRefundAddressLabel(sourceSymbol),
        kind: SwapStatusDetailRowKind.refundAddress,
        address: refundAddress,
        asset: sourceAsset,
        addressBookLabels: addressBookLabels,
      ),
    if (!sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapRecipientLabel(receiveSymbol),
        kind: SwapStatusDetailRowKind.recipient,
        address: recipientAddress,
        asset: receiveAsset,
        addressBookLabels: addressBookLabels,
      ),
    if (depositTxHash != null && depositTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapDepositTxLabel(sourceSymbol),
        kind: SwapStatusDetailRowKind.depositTx,
        value: compactSwapAddress(depositTxHash),
        copyable: true,
        copyText: depositTxHash,
        scaleValueToFit: true,
      ),
    if (destinationChainTxHash != null && destinationChainTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapDeliveryTxLabel(receiveSymbol),
        kind: SwapStatusDetailRowKind.deliveryTx,
        value: compactSwapAddress(destinationChainTxHash),
        copyable: true,
        copyText: destinationChainTxHash,
        scaleValueToFit: true,
      ),
    SwapStatusDetailRowData(
      label: l10n.swapFeeLabel,
      kind: SwapStatusDetailRowKind.swapFee,
      value: intent.swapFeeText ?? l10n.swapIncludedInRate,
      help: true,
      helpTooltip: swapFeeTooltip(l10n),
    ),
  ];
}

SwapStatusDetailRowData? _swapActivityTxIdRow({
  required SwapIntent intent,
  required String? depositTxHash,
  required String? depositAddress,
  required AppLocalizations l10n,
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
    label: l10n.swapTxIdLabel,
    kind: SwapStatusDetailRowKind.txId,
    value: compactSwapAddress(txId),
    linkUri: linkUri,
  );
}

List<SwapStatusDetailRowData> _swapActivityIncompleteDepositDetails(
  SwapIntent intent, {
  required AppLocalizations l10n,
  required String sourceSymbol,
  required String receiveSymbol,
  required String? depositAddress,
  required String? depositMemo,
  required String? refundAddress,
  required String? recipientAddress,
  required String? depositTxHash,
  required bool sendsZec,
  required _SwapActivityAddressBookLabels addressBookLabels,
}) {
  final sourceAsset = swapActivitySellAsset(intent);
  final receiveAsset = swapActivityReceiveAsset(intent);
  final providerInfo = intent.providerRefundInfo;
  final missingDepositText = sourceAsset == null
      ? null
      : _swapActivityMissingDepositText(intent, sourceAsset);
  final deadlineText = _swapActivityTimestampLabel(
    intent.depositDeadline,
    l10n,
  );

  return [
    if (missingDepositText != null)
      SwapStatusDetailRowData(
        label: l10n.swapMissingDepositLabel,
        kind: SwapStatusDetailRowKind.missingDeposit,
        value: missingDepositText,
      ),
    if (depositMemo != null && depositMemo.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapMemoLabel,
        kind: SwapStatusDetailRowKind.memo,
        value: depositMemo,
        copyable: true,
        copyText: depositMemo,
      ),
    if (depositAddress != null && depositAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapDepositToLabel(sourceSymbol),
        kind: SwapStatusDetailRowKind.depositAddress,
        address: depositAddress,
        asset: sourceAsset,
        addressBookLabels: addressBookLabels,
      ),
    SwapStatusDetailRowData(
      label: l10n.swapRequiredDepositLabel,
      kind: SwapStatusDetailRowKind.requiredDeposit,
      value: intent.sellAmount,
    ),
    if (providerInfo?.depositedAmountText != null)
      SwapStatusDetailRowData(
        label: l10n.swapDetectedDepositLabel,
        kind: SwapStatusDetailRowKind.detectedDeposit,
        value: providerInfo!.depositedAmountText!,
      ),
    if (deadlineText != null)
      SwapStatusDetailRowData(
        label: l10n.swapDepositDeadlineRowLabel,
        kind: SwapStatusDetailRowKind.depositDeadline,
        value: deadlineText,
      ),
    if (providerInfo?.refundFeeText != null)
      SwapStatusDetailRowData(
        label: l10n.swapRefundFeeLabel,
        kind: SwapStatusDetailRowKind.refundFee,
        value: providerInfo!.refundFeeText!,
      ),
    if (refundAddress != null && refundAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapRefundAddressLabel(sourceSymbol),
        kind: SwapStatusDetailRowKind.refundAddress,
        address: refundAddress,
        asset: sourceAsset,
        addressBookLabels: addressBookLabels,
      ),
    if (!sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      ..._addressDetailRows(
        label: l10n.swapRecipientLabel(receiveSymbol),
        kind: SwapStatusDetailRowKind.recipient,
        address: recipientAddress,
        asset: receiveAsset,
        addressBookLabels: addressBookLabels,
      ),
    if (depositTxHash != null && depositTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: l10n.swapDepositTxLabel(sourceSymbol),
        kind: SwapStatusDetailRowKind.depositTx,
        value: compactSwapAddress(depositTxHash),
        copyable: true,
        copyText: depositTxHash,
        scaleValueToFit: true,
      ),
  ];
}

List<SwapStatusDetailRowData> _addressDetailRows({
  required String label,
  required String address,
  required SwapAsset? asset,
  required _SwapActivityAddressBookLabels addressBookLabels,
  required SwapStatusDetailRowKind kind,
}) {
  final addressBookLabel = addressBookLabels.labelFor(
    asset: asset,
    address: address,
  );
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
      scaleValueToFit: true,
      kind: kind,
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

String? swapDepositDeadlineLabel(
  SwapIntent intent,
  AppLocalizations l10n,
) {
  final deadline = intent.depositDeadline;
  if (deadline == null) return null;
  final remaining = deadline.difference(DateTime.now());
  if (remaining.isNegative) return '00:00';
  if (remaining.inHours >= 1) {
    final hours = (remaining.inSeconds / Duration.secondsPerHour).ceil();
    return l10n.swapHoursShort(hours);
  }
  if (remaining.inMinutes >= 15) {
    return l10n.swapMinutesShort(remaining.inMinutes);
  }
  final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String? _swapActivityLastRelativeStatusCheckedLabel(
  DateTime? checkedAt,
  AppLocalizations l10n,
) {
  if (checkedAt == null) return null;
  final elapsed = DateTime.now().difference(checkedAt.toLocal());
  if (elapsed.inMinutes <= 0) return l10n.swapLastCheckJustNow;
  return l10n.swapLastCheckMinutesAgo(elapsed.inMinutes);
}

String? _swapActivityTimestampLabel(
  DateTime? timestamp,
  AppLocalizations l10n,
) {
  if (timestamp == null) return null;
  final local = timestamp.toLocal();
  return DateFormat(
    'MMM d, y HH:mm',
    intlSafeLocale(l10n.localeName),
  ).format(local);
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

  static SwapActivityDepositInstruction? fromIntent(
    SwapIntent intent,
    AppLocalizations l10n,
  ) {
    final direction = intent.direction;
    final externalAsset = intent.externalAsset;
    final depositAddress = intent.depositAddress;
    if (direction == null || externalAsset == null || depositAddress == null) {
      return null;
    }

    final depositSymbol = direction.fromSymbol(externalAsset);
    final depositAddressLabel = direction.sendsZec
        ? l10n.swapDepositLabelShort(depositSymbol)
        : l10n.swapSourceDepositLabel(depositSymbol);

    return SwapActivityDepositInstruction(
      sendLabel: direction.sendsZec
          ? l10n.swapSendSymbol(depositSymbol)
          : l10n.swapSendFromSourceChain(depositSymbol),
      depositSymbol: depositSymbol,
      depositAddressLabel: depositAddressLabel,
      address: depositAddress,
      memo: intent.depositMemo,
      txHashLabel: l10n.swapDepositTxHashLabel(depositSymbol),
      txHashHint: l10n.swapDepositTxHashHint(depositSymbol),
      submitLabel: l10n.swapSubmitDeposit(depositSymbol),
      qr: direction.sendsZec
          ? null
          : SwapActivityDepositQrInstruction(
              railLabel: externalAsset.railLabel,
              reuseWarning: l10n.swapDoNotReuseAddress,
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

bool _hasDepositInstruction(SwapIntent intent) {
  return intent.direction != null &&
      intent.externalAsset != null &&
      intent.depositAddress != null;
}

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

String? _swapActivityMissingDepositText(
  SwapIntent intent,
  SwapAsset sourceAsset,
) {
  final requiredAmount = _numericAmount(intent.sellAmount);
  final depositedAmount = _numericAmount(
    intent.providerRefundInfo?.depositedAmountText ?? '',
  );
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

String _normalizedAddress(AddressBookNetwork network, String address) {
  final trimmed = address.trim();
  return _addressBookNetworkIgnoresCase(network)
      ? trimmed.toLowerCase()
      : trimmed;
}

bool _addressBookNetworkIgnoresCase(AddressBookNetwork network) {
  return switch (network) {
    AddressBookNetwork.ethereum ||
    AddressBookNetwork.base ||
    AddressBookNetwork.arbitrum ||
    AddressBookNetwork.binanceSmartChain ||
    AddressBookNetwork.optimism ||
    AddressBookNetwork.avalanche ||
    AddressBookNetwork.gnosis ||
    AddressBookNetwork.polygon ||
    AddressBookNetwork.xLayer ||
    AddressBookNetwork.plasma ||
    AddressBookNetwork.abstractChain ||
    AddressBookNetwork.bera ||
    AddressBookNetwork.monad ||
    AddressBookNetwork.scroll ||
    AddressBookNetwork.near => true,
    _ => false,
  };
}

double? _numericAmount(String amountText) {
  final raw = amountText.split(RegExp(r'\s+')).first.replaceAll(',', '').trim();
  final amount = double.tryParse(raw);
  return amount == null || !amount.isFinite ? null : amount;
}

