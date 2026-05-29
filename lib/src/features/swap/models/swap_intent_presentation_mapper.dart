import 'swap_models.dart';

SwapIntent _swapIntentFromRecord(SwapIntentRecord record, {DateTime? now}) {
  final timestamp = now ?? DateTime.now().toUtc();
  final status = _resolveDepositDeadlineStatus(
    providerStatus: record.status,
    deadline: record.depositDeadline,
    hasDepositEvidence:
        _hasText(record.depositTxHash) || _hasText(record.originChainTxHash),
    now: timestamp,
  );
  final nextAction = _nextActionForRestoredStatus(status, record);
  return SwapIntent(
    id: record.id,
    pair: record.pairText,
    sellAmount: record.sellAmountText,
    receiveEstimate: record.receiveEstimateText,
    provider: record.providerLabel,
    status: status,
    nextAction: nextAction,
    sellAmountBaseUnits: record.sellAmountBaseUnits,
    direction: record.direction,
    externalAsset: record.externalAsset,
    depositAddress: record.depositAddress,
    depositMemo: record.depositMemo,
    depositTxHash: record.depositTxHash,
    providerQuoteId: record.providerQuoteId,
    swapFeeText: record.swapFeeText,
    totalFeesText: record.totalFeesText,
    realisedSlippageText: record.realisedSlippageText,
    slippageToleranceText: record.slippageToleranceText,
    minimumReceiveText: record.minimumReceiveText,
    providerStatusRaw: record.providerStatusRaw,
    nearIntentHash: record.nearIntentHash,
    originChainTxHash: record.originChainTxHash,
    destinationChainTxHash: record.destinationChainTxHash,
    providerRefundInfo: record.providerRefundInfo,
    fiatValueBasis: record.fiatValueBasis,
    lastStatusCheckedAt: record.lastStatusCheckedAt,
    statusError: record.statusError,
    broadcastNotice: record.broadcastNotice,
    oneClickRecipient: record.oneClickRecipient,
    oneClickRefundTo: record.oneClickRefundTo,
    depositDeadline: record.depositDeadline,
    accountUuid: record.accountUuid,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    completedAt:
        record.completedAt ??
        (status.isTerminal && record.status != status ? timestamp : null),
  );
}

List<SwapIntent> swapIntentsFromRecords(
  Iterable<SwapIntentRecord> records, {
  DateTime? now,
}) {
  return [
    for (final record in records) _swapIntentFromRecord(record, now: now),
  ];
}

SwapIntentRecord swapIntentRecordForPersistence(
  SwapIntent intent, {
  required String accountUuid,
}) {
  return SwapIntentRecord.fromIntent(intent.copyWith(accountUuid: accountUuid));
}

SwapIntent swapIntentFromSnapshot({
  required SwapIntentSnapshot snapshot,
  required SwapQuote quote,
  required SwapAddressPlan addressPlan,
  required String accountUuid,
  required DateTime now,
}) {
  final depositDeadline =
      snapshot.depositInstruction.deadline ?? quote.depositInstruction.deadline;
  final status = _resolveDepositDeadlineStatus(
    providerStatus: snapshot.status,
    deadline: depositDeadline,
    hasDepositEvidence: _hasText(snapshot.originChainTxHash),
    now: now,
  );
  final nextAction = _nextActionForResolvedStatus(status, snapshot);
  final record = SwapIntentRecord(
    id: snapshot.id,
    providerLabel: snapshot.providerLabel,
    pairText: snapshot.pairText,
    sellAmountText: snapshot.sellAmountText,
    receiveEstimateText: snapshot.receiveEstimateText,
    status: status,
    nextAction: nextAction,
    sellAmountBaseUnits:
        snapshot.sellAmountBaseUnits ?? quote.sellAmountBaseUnits,
    direction: quote.direction,
    externalAsset: quote.externalAsset,
    depositAddress: quote.depositInstruction.address,
    depositMemo: quote.depositInstruction.memo,
    providerQuoteId: quote.providerQuoteId,
    swapFeeText: snapshot.swapFeeText ?? quote.feeLabel,
    totalFeesText: snapshot.totalFeesText ?? quote.totalFeesText,
    realisedSlippageText: snapshot.realisedSlippageText,
    slippageToleranceText:
        snapshot.slippageToleranceText ?? quote.slippageToleranceText,
    minimumReceiveText: snapshot.minimumReceiveText ?? quote.minimumReceiveText,
    providerStatusRaw: snapshot.providerStatusRaw,
    nearIntentHash: snapshot.nearIntentHash,
    originChainTxHash: snapshot.originChainTxHash,
    destinationChainTxHash: snapshot.destinationChainTxHash,
    providerRefundInfo: snapshot.providerRefundInfo ?? quote.providerRefundInfo,
    fiatValueBasis: snapshot.fiatValueBasis ?? quote.fiatValueBasis,
    oneClickRecipient: addressPlan.oneClickRecipient,
    oneClickRefundTo: addressPlan.oneClickRefundTo,
    depositDeadline: depositDeadline,
    accountUuid: accountUuid,
    createdAt: now,
    updatedAt: now,
    completedAt: status.isTerminal ? now : null,
  );
  return _swapIntentFromRecord(record);
}

SwapIntent swapIntentWithBroadcastNotice(
  SwapIntent intent, {
  required String notice,
  DateTime? updatedAt,
}) {
  return _swapIntentFromRecord(
    SwapIntentRecord.fromIntent(intent).copyWith(
      statusError: notice,
      broadcastNotice: notice,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    ),
  );
}

SwapIntent swapIntentWithDepositCheckpoint(
  SwapIntent intent, {
  required String txHash,
  String? statusError,
  String? broadcastNotice,
  required bool clearStatusError,
  required bool clearBroadcastNotice,
  DateTime? updatedAt,
}) {
  return _swapIntentFromRecord(
    SwapIntentRecord.fromIntent(intent).copyWith(
      depositTxHash: txHash,
      statusError: statusError ?? broadcastNotice,
      broadcastNotice: broadcastNotice,
      clearStatusError: clearStatusError,
      clearBroadcastNotice: clearBroadcastNotice,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    ),
  );
}

SwapIntent swapIntentWithDepositSnapshot(
  SwapIntent intent,
  SwapIntentSnapshot snapshot, {
  required String txHash,
  String? broadcastNotice,
  DateTime? updatedAt,
}) {
  final timestamp = updatedAt ?? DateTime.now().toUtc();
  final effectiveBroadcastNotice = broadcastNotice ?? intent.broadcastNotice;
  final updated = updateSwapIntentFromSnapshot(
    intent,
    snapshot,
    updatedAt: timestamp,
  );
  return _swapIntentFromRecord(
    SwapIntentRecord.fromIntent(updated).copyWith(
      depositTxHash: txHash,
      statusError: effectiveBroadcastNotice,
      broadcastNotice: effectiveBroadcastNotice,
      clearStatusError: effectiveBroadcastNotice == null,
      clearBroadcastNotice: effectiveBroadcastNotice == null,
      updatedAt: timestamp,
    ),
  );
}

SwapIntent updateSwapIntentFromSnapshot(
  SwapIntent intent,
  SwapIntentSnapshot snapshot, {
  DateTime? updatedAt,
  DateTime? lastStatusCheckedAt,
}) {
  final timestamp = updatedAt ?? DateTime.now().toUtc();
  final providerRefundInfo =
      intent.providerRefundInfo?.merge(snapshot.providerRefundInfo) ??
      snapshot.providerRefundInfo;
  final depositDeadline =
      snapshot.depositInstruction.deadline ?? intent.depositDeadline;
  final status = _resolveDepositDeadlineStatus(
    providerStatus: snapshot.status,
    deadline: depositDeadline,
    hasDepositEvidence:
        _hasText(intent.depositTxHash) ||
        _hasText(intent.originChainTxHash) ||
        _hasText(snapshot.originChainTxHash),
    now: timestamp,
  );
  final nextAction = _nextActionForResolvedStatus(status, snapshot);
  final record = SwapIntentRecord.fromIntent(intent).copyWith(
    providerLabel: snapshot.providerLabel,
    pairText: snapshot.pairText,
    sellAmountText: snapshot.sellAmountText,
    receiveEstimateText: snapshot.receiveEstimateText,
    status: status,
    nextAction: nextAction,
    sellAmountBaseUnits: snapshot.sellAmountBaseUnits,
    swapFeeText: snapshot.swapFeeText,
    totalFeesText: snapshot.totalFeesText,
    realisedSlippageText: snapshot.realisedSlippageText,
    slippageToleranceText: snapshot.slippageToleranceText,
    minimumReceiveText: snapshot.minimumReceiveText,
    providerStatusRaw: snapshot.providerStatusRaw,
    nearIntentHash: snapshot.nearIntentHash,
    originChainTxHash: snapshot.originChainTxHash,
    destinationChainTxHash: snapshot.destinationChainTxHash,
    providerRefundInfo: providerRefundInfo,
    fiatValueBasis: intent.fiatValueBasis ?? snapshot.fiatValueBasis,
    lastStatusCheckedAt: lastStatusCheckedAt,
    depositAddress:
        intent.depositAddress ?? snapshot.depositInstruction.address,
    depositMemo: intent.depositMemo ?? snapshot.depositInstruction.memo,
    depositDeadline: depositDeadline,
    updatedAt: timestamp,
    completedAt: intent.completedAt ?? (status.isTerminal ? timestamp : null),
  );
  return _swapIntentFromRecord(record);
}

SwapIntentStatus _resolveDepositDeadlineStatus({
  required SwapIntentStatus providerStatus,
  required DateTime? deadline,
  required bool hasDepositEvidence,
  required DateTime now,
}) {
  if (!_isAwaitingDepositStatus(providerStatus) ||
      deadline == null ||
      hasDepositEvidence ||
      now.toUtc().isBefore(deadline.toUtc())) {
    return providerStatus;
  }
  return SwapIntentStatus.expired;
}

bool _isAwaitingDepositStatus(SwapIntentStatus status) {
  return status == SwapIntentStatus.awaitingDeposit ||
      status == SwapIntentStatus.awaitingExternalDeposit;
}

String _nextActionForResolvedStatus(
  SwapIntentStatus status,
  SwapIntentSnapshot snapshot,
) {
  if (status == SwapIntentStatus.expired &&
      snapshot.status != SwapIntentStatus.expired) {
    return 'Start a fresh quote';
  }
  return snapshot.nextAction;
}

String _nextActionForRestoredStatus(
  SwapIntentStatus status,
  SwapIntentRecord record,
) {
  if (status == SwapIntentStatus.expired &&
      record.status != SwapIntentStatus.expired) {
    return 'Start a fresh quote';
  }
  return record.nextAction;
}

bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

