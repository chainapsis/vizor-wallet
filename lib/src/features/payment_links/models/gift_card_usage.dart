/// Sender observation is independent of funding/sharing and receiver claims.
enum GiftCardUsageStatus { unknown, unused, spendDetected, used }

enum GiftCardUsageReason {
  missingFundingInfo,
  fundingNotObserved,
  scanIncomplete,
  amountMismatch,
  awaitingConfirmation,
}

class GiftCardUsage {
  const GiftCardUsage({
    this.status = GiftCardUsageStatus.unknown,
    this.reason,
    this.accountUuid,
    this.checkedAt,
    this.verifiedHeight = 0,
    this.spentHeight = 0,
    this.spendingTxids = const [],
    this.cleanupPending = false,
    this.cleaned = false,
  });

  final GiftCardUsageStatus status;
  final GiftCardUsageReason? reason;
  final String? accountUuid;
  final DateTime? checkedAt;
  final int verifiedHeight;
  final int spentHeight;
  final List<String> spendingTxids;
  final bool cleanupPending;
  final bool cleaned;

  String get label => switch (status) {
    GiftCardUsageStatus.unknown =>
      reason == GiftCardUsageReason.awaitingConfirmation
          ? 'Confirming'
          : 'Unverified',
    GiftCardUsageStatus.unused => 'Unused',
    GiftCardUsageStatus.spendDetected => 'Use detected',
    GiftCardUsageStatus.used => 'Used',
  };

  String? get explanation => status != GiftCardUsageStatus.unknown
      ? null
      : switch (reason) {
          GiftCardUsageReason.awaitingConfirmation =>
            'Your link is ready to share. Usage tracking will begin once the funding transaction is confirmed.',
          GiftCardUsageReason.missingFundingInfo =>
            'The saved funding information is incomplete, so usage could not be verified.',
          GiftCardUsageReason.fundingNotObserved =>
            'The funding transaction could not yet be verified in the tracking history.',
          GiftCardUsageReason.scanIncomplete =>
            'The tracking history has not yet reached the funding transaction.',
          GiftCardUsageReason.amountMismatch =>
            'The observed funding amount does not match the expected card funding.',
          null =>
            'There is not enough information yet to verify whether this card has been used.',
        };

  GiftCardUsage withAccount(String uuid) => GiftCardUsage(
    status: status,
    reason: reason,
    accountUuid: uuid,
    checkedAt: checkedAt,
    verifiedHeight: verifiedHeight,
    spentHeight: spentHeight,
    spendingTxids: spendingTxids,
    cleanupPending: cleanupPending,
  );

  GiftCardUsage afterCleanup() => GiftCardUsage(
    status: status,
    reason: reason,
    checkedAt: checkedAt,
    verifiedHeight: verifiedHeight,
    spentHeight: spentHeight,
    spendingTxids: spendingTxids,
    cleaned: true,
  );

  Map<String, Object?> toJson() => {
    'status': status.name,
    'reason': reason?.name,
    'accountUuid': accountUuid,
    'checkedAt': checkedAt?.toUtc().toIso8601String(),
    'verifiedHeight': verifiedHeight,
    'spentHeight': spentHeight,
    'spendingTxids': spendingTxids,
    'cleanupPending': cleanupPending,
    'cleaned': cleaned,
  };

  static GiftCardUsage fromJson(Object? value) {
    if (value == null) return const GiftCardUsage();
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Gift Card usage record');
    }
    final status = GiftCardUsageStatus.values.byName(value['status'] as String);
    final reason = value['reason'] == null
        ? null
        : GiftCardUsageReason.values.byName(value['reason'] as String);
    final account = value['accountUuid'] as String?;
    final checked = value['checkedAt'] == null
        ? null
        : DateTime.parse(value['checkedAt'] as String).toUtc();
    final height = value['verifiedHeight'] as int;
    final spent = value['spentHeight'] as int;
    final ids = (value['spendingTxids'] as List).cast<String>();
    final cleanup = value['cleanupPending'] as bool;
    final cleaned = value['cleaned'] as bool;
    if ((reason != null && status != GiftCardUsageStatus.unknown) ||
        height < 0 ||
        spent < 0 ||
        (account != null && account.isEmpty) ||
        ids.any((id) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) ||
        ((cleanup || cleaned) && status != GiftCardUsageStatus.used) ||
        (cleanup && (cleaned || account == null)) ||
        (cleaned && account != null) ||
        (status == GiftCardUsageStatus.used &&
            (spent == 0 ||
                height < spent + 5 ||
                ids.isEmpty ||
                checked == null))) {
      throw const FormatException('Inconsistent Gift Card usage record');
    }
    return GiftCardUsage(
      status: status,
      reason: reason,
      accountUuid: account,
      checkedAt: checked,
      verifiedHeight: height,
      spentHeight: spent,
      spendingTxids: List.unmodifiable(ids),
      cleanupPending: cleanup,
      cleaned: cleaned,
    );
  }
}
