import 'swap_models.dart';

SwapIntent _swapIntentFromRecord(SwapIntentRecord record, {DateTime? now}) {
  final timestamp = now ?? DateTime.now().toUtc();
  final status = _resolveDepositDeadlineStatus(
    providerStatus: record.status,
    deadline: record.depositDeadline,
    hasDepositEvidence: swapHasConfirmedDepositEvidence(
      originChainTxHash: record.originChainTxHash,
      depositTxHash: record.depositTxHash,
      broadcastStatus: record.broadcastStatus,
    ),
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
    broadcastStatus: record.broadcastStatus,
    oneClickRecipient: record.oneClickRecipient,
    oneClickRefundTo: record.oneClickRefundTo,
    depositDeadline: record.depositDeadline,
    accountUuid: record.accountUuid,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    completedAt:
        record.completedAt ??
        (status.isTerminal && record.status != status ? timestamp : null),
    depositClaimedAt: record.depositClaimedAt,
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

/// Applies the same deadline-derived status resolution as [swapIntentsFromRecords]
/// (e.g. a past-deadline awaiting deposit with no on-chain evidence becomes
/// `expired`) but returns a record, so list surfaces agree with the detail
/// panel instead of showing a stale raw status. Returns the record unchanged
/// when no resolution applies.
SwapIntentRecord resolveSwapRecordForDisplay(
  SwapIntentRecord record, {
  DateTime? now,
}) {
  final status = _resolveDepositDeadlineStatus(
    providerStatus: record.status,
    deadline: record.depositDeadline,
    hasDepositEvidence: swapHasConfirmedDepositEvidence(
      originChainTxHash: record.originChainTxHash,
      depositTxHash: record.depositTxHash,
      broadcastStatus: record.broadcastStatus,
    ),
    now: now ?? DateTime.now().toUtc(),
  );
  if (status == record.status) return record;
  return record.copyWith(
    status: status,
    nextAction: _nextActionForRestoredStatus(status, record),
  );
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
    hasDepositEvidence: swapHasConfirmedDepositEvidence(
      originChainTxHash: snapshot.originChainTxHash,
      broadcastStatus: null,
    ),
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
    // Prefer the address the provider assigned in `startSwap` (the snapshot).
    // NEAR hands back the real deposit address at quote time, but zwap's
    // atomic-swap address is only derived after the order is created + matched,
    // so it lives on the snapshot — using the quote here would show a
    // placeholder. Fall back to the quote for providers that don't set it.
    depositAddress: _hasText(snapshot.depositInstruction.address)
        ? snapshot.depositInstruction.address
        : quote.depositInstruction.address,
    depositMemo: _hasText(snapshot.depositInstruction.memo)
        ? snapshot.depositInstruction.memo
        : quote.depositInstruction.memo,
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
  String? broadcastStatus,
  DateTime? updatedAt,
}) {
  return _swapIntentFromRecord(
    SwapIntentRecord.fromIntent(intent).copyWith(
      statusError: notice,
      broadcastNotice: notice,
      broadcastStatus: broadcastStatus,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    ),
  );
}

SwapIntent swapIntentWithDepositCheckpoint(
  SwapIntent intent, {
  required String txHash,
  String? statusError,
  String? broadcastNotice,
  String? broadcastStatus,
  required bool clearStatusError,
  required bool clearBroadcastNotice,
  DateTime? updatedAt,
}) {
  return _swapIntentFromRecord(
    SwapIntentRecord.fromIntent(intent).copyWith(
      depositTxHash: txHash,
      statusError: statusError ?? broadcastNotice,
      broadcastNotice: broadcastNotice,
      broadcastStatus: broadcastStatus,
      clearStatusError: clearStatusError,
      clearBroadcastNotice: clearBroadcastNotice,
      clearBroadcastStatus: broadcastStatus == null && broadcastNotice == null,
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
    hasDepositEvidence: swapHasConfirmedDepositEvidence(
      originChainTxHash:
          _hasText(intent.originChainTxHash)
          ? intent.originChainTxHash
          : snapshot.originChainTxHash,
      depositTxHash: intent.depositTxHash,
      broadcastStatus: intent.broadcastStatus,
    ),
    now: timestamp,
  );
  final nextAction = _nextActionForResolvedStatus(status, snapshot);
  final record = SwapIntentRecord.fromIntent(intent).copyWith(
    providerLabel: snapshot.providerLabel,
    pairText: snapshot.pairText,
    // Preserve the amounts captured when the intent was created if the status
    // snapshot omits them. The zwap adapter's `_statusSnapshot` returns empty
    // `sellAmountText`/`receiveEstimateText` (it only knows the settle-side
    // fields), so overwriting unconditionally would blank the deposit screen's
    // "Amount to deposit" on the first status refresh. NEAR always repopulates
    // these, so this fallback is a no-op there.
    sellAmountText: _hasText(snapshot.sellAmountText)
        ? snapshot.sellAmountText
        : intent.sellAmount,
    receiveEstimateText: _hasText(snapshot.receiveEstimateText)
        ? snapshot.receiveEstimateText
        : intent.receiveEstimate,
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
  // Partial-deposit progress is transient (re-derived from each poll's snapshot,
  // not persisted via the record). The record-built intent always starts with
  // depositProgress == null, so this copyWith sets the fresh value or clears it
  // once the deposit is complete.
  return _swapIntentFromRecord(
    record,
  ).copyWith(depositProgress: snapshot.depositProgress);
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

