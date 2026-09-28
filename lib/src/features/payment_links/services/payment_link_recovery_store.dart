import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/vizor_payment_link.dart';
import '../models/gift_card_usage.dart';
import 'payment_link_lifecycle_revision.dart';
import 'payment_link_batch_limits.dart';

const _storageVersion = 1;
// Envelope flag: every draft in this payload was written by a build that marks
// the broadcast boundary. Older builds ignore it and drop it on rewrite.
const _submissionMarkersKey = 'submissionMarkersRecorded';
const _fundingMetadataWriteAttempts = 2;

final paymentLinkRecoveryStoreProvider = Provider<PaymentLinkRecoveryStore>((
  ref,
) {
  return PaymentLinkRecoveryStore(
    AppSecureStorePaymentLinkRecoveryStorage(AppSecureStore.instance),
    onRecordsChanged: () {
      ref.read(paymentLinkLifecycleRevisionProvider.notifier).bump();
    },
  );
});

enum PaymentLinkRecoveryState { draft, funded, shared }

/// Removal confirmation copy for funded gift card links that were never
/// shared; removal proceeds, so the user must copy them first. A null [count]
/// means the check failed or has not finished.
String? unsharedGiftCardRemovalWarning(
  int? count, {
  required bool walletReset,
}) {
  if (count == null) {
    final action = walletReset ? 'resetting Vizor' : 'removing this account';
    return "Couldn't check for unshared gift card links. "
        'Copy any links you still need before $action.';
  }
  if (count <= 0) return null;
  final subject = walletReset ? 'Resetting Vizor' : 'Removing this account';
  if (count == 1) {
    return '1 funded gift card link has not been shared. '
        '$subject loses it. Copy the link first.';
  }
  return '$count funded gift card links have not been shared. '
      '$subject loses them. Copy the links first.';
}

const _fieldNotProvided = Object();

class PaymentLinkRecoveryRecord {
  const PaymentLinkRecoveryRecord({
    required this.link,
    required this.sourceAccountUuid,
    required this.state,
    required this.updatedAt,
    this.fundingTxids,
    this.preparedExpiryHeight,
    this.submittedAtHeight,
    this.fundedAt,
    this.usage = const GiftCardUsage(),
    required this.claimFeeReserveZatoshi,
    this.batchId,
    this.batchIndex,
    this.batchCount,
  });

  final GiftCardUsage usage;
  final VizorPaymentLink link;
  final String sourceAccountUuid;
  final PaymentLinkRecoveryState state;
  final DateTime updatedAt;
  final String? fundingTxids;
  final int? preparedExpiryHeight;

  /// The chain height the wallet knew when a funding broadcast started.
  ///
  /// Every funding path — software, Keystone and Ledger — writes it before the
  /// broadcast boundary is crossed, so a broadcast whose result never came
  /// back still leaves a durable trace, and a draft without it provably never
  /// reached the network. `0` means the height was unknown at submission time.
  final int? submittedAtHeight;

  /// When the funding transaction id was first recorded.
  ///
  /// Set once by [PaymentLinkRecoveryStore.markFunded]; later state changes,
  /// such as marking the card shared, leave it unchanged. Null for records
  /// written before this field existed.
  final DateTime? fundedAt;

  /// Amount actually reserved for claiming when this card was funded.
  final BigInt claimFeeReserveZatoshi;

  /// Present together for cards funded by one desktop batch transaction.
  final String? batchId;
  final int? batchIndex;
  final int? batchCount;

  /// True while the wallet knows a funding broadcast started but never learned
  /// its transaction id.
  ///
  /// Such a draft may hold funds, so it is neither removable as inert nor
  /// matchable by transaction id; the reconciler settles it by scanning the
  /// link's own wallet.
  bool get isAmbiguousSubmission =>
      state == PaymentLinkRecoveryState.draft &&
      (fundingTxids?.trim().isEmpty ?? true) &&
      submittedAtHeight != null;

  /// A draft that never reached the broadcast boundary: no transaction, no
  /// submission marker. Provably unfunded, so recovery may drop it once it is
  /// old enough not to be a creation still in progress.
  bool get isInertDraft =>
      state == PaymentLinkRecoveryState.draft &&
      (fundingTxids?.trim().isEmpty ?? true) &&
      preparedExpiryHeight == null &&
      submittedAtHeight == null;

  /// Funded and not yet shared, or a draft whose broadcast boundary was
  /// crossed. A draft that never reached it — even one carrying a prepared
  /// hardware txid — holds nothing and does not block deleting its account.
  bool get mayHoldUnsharedFunds =>
      state == PaymentLinkRecoveryState.funded ||
      (state == PaymentLinkRecoveryState.draft && submittedAtHeight != null);

  PaymentLinkRecoveryRecord copyWith({
    required PaymentLinkRecoveryState state,
    required DateTime updatedAt,
    Object? fundingTxids = _fieldNotProvided,
    Object? preparedExpiryHeight = _fieldNotProvided,
    Object? submittedAtHeight = _fieldNotProvided,
    Object? fundedAt = _fieldNotProvided,
    GiftCardUsage? usage,
  }) {
    return PaymentLinkRecoveryRecord(
      link: link,
      usage: usage ?? this.usage,
      claimFeeReserveZatoshi: claimFeeReserveZatoshi,
      batchId: batchId,
      batchIndex: batchIndex,
      batchCount: batchCount,
      sourceAccountUuid: sourceAccountUuid,
      state: state,
      updatedAt: updatedAt,
      fundingTxids: identical(fundingTxids, _fieldNotProvided)
          ? this.fundingTxids
          : fundingTxids as String?,
      preparedExpiryHeight: identical(preparedExpiryHeight, _fieldNotProvided)
          ? this.preparedExpiryHeight
          : preparedExpiryHeight as int?,
      submittedAtHeight: identical(submittedAtHeight, _fieldNotProvided)
          ? this.submittedAtHeight
          : submittedAtHeight as int?,
      fundedAt: identical(fundedAt, _fieldNotProvided)
          ? this.fundedAt
          : fundedAt as DateTime?,
    );
  }
}

class PaymentLinkRecoveryStoreFormatException implements Exception {
  const PaymentLinkRecoveryStoreFormatException(this.message);

  final String message;

  @override
  String toString() => 'PaymentLinkRecoveryStoreFormatException: $message';
}

abstract interface class PaymentLinkRecoveryStorage {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

class AppSecureStorePaymentLinkRecoveryStorage
    implements PaymentLinkRecoveryStorage {
  const AppSecureStorePaymentLinkRecoveryStorage(this._store);

  final AppSecureStore _store;

  @override
  Future<String?> read() {
    return _store.readSecretStringWithOptions(
      kPaymentLinkRecoveryStorageKey,
      requireUnlockedSession: true,
    );
  }

  @override
  Future<void> write(String value) {
    return _store.writeSecretString(kPaymentLinkRecoveryStorageKey, value);
  }

  @override
  Future<void> delete() {
    return _store.delete(kPaymentLinkRecoveryStorageKey);
  }
}

class PaymentLinkRecoveryStore {
  PaymentLinkRecoveryStore(this._storage, {void Function()? onRecordsChanged})
    : _onRecordsChanged = onRecordsChanged;

  final PaymentLinkRecoveryStorage _storage;
  final void Function()? _onRecordsChanged;
  Future<void> _operationTail = Future<void>.value();

  Future<List<PaymentLinkRecoveryRecord>> load() {
    return _runExclusive(_loadUnlocked);
  }

  Future<int> countUnsharedFundedForAccount(String sourceAccountUuid) async {
    if (sourceAccountUuid.isEmpty) return 0;
    return countUnsharedFundedPaymentLinks(
      await load(),
      sourceAccountUuid: sourceAccountUuid,
    );
  }

  Future<PaymentLinkRecoveryRecord> saveDraft({
    required VizorPaymentLink link,
    required String sourceAccountUuid,
    required BigInt claimFeeReserveZatoshi,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      if (sourceAccountUuid.isEmpty) {
        throw ArgumentError.value(
          sourceAccountUuid,
          'sourceAccountUuid',
          'Payment link source account is required.',
        );
      }
      final records = await _loadUnlocked();
      final existing = _findByAddress(records, link.address);
      if (existing != null &&
          existing.state != PaymentLinkRecoveryState.draft) {
        throw StateError(
          'Payment link recovery cannot replace a funded record with a draft.',
        );
      }
      final record = PaymentLinkRecoveryRecord(
        link: link,
        sourceAccountUuid: sourceAccountUuid,
        claimFeeReserveZatoshi: claimFeeReserveZatoshi,
        state: PaymentLinkRecoveryState.draft,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      );
      await _writeRecords(_replaceByAddress(records, record));
      return record;
    });
  }

  /// A single secure-store write makes every bearer secret recoverable before
  /// the shared funding transaction can cross its broadcast boundary.
  Future<List<PaymentLinkRecoveryRecord>> saveBatchDrafts({
    required String batchId,
    required List<VizorPaymentLink> links,
    required String sourceAccountUuid,
    required BigInt claimFeeReserveZatoshi,
  }) => _runExclusive(() async {
    if (batchId.isEmpty ||
        sourceAccountUuid.isEmpty ||
        links.length < kPaymentLinkBatchMinCount ||
        links.length > kPaymentLinkBatchMaxCount ||
        links.map((link) => link.address).toSet().length != links.length ||
        links.any(
          (link) =>
              link.network != links.first.network ||
              link.amountZatoshi != links.first.amountZatoshi,
        )) {
      throw ArgumentError('Invalid Gift Card batch draft.');
    }
    final records = await _loadUnlocked();
    if (records.any(
      (record) =>
          record.batchId == batchId ||
          links.any((link) => link.address == record.link.address),
    )) {
      throw StateError('Gift Card batch identity already exists.');
    }
    final now = DateTime.now().toUtc();
    final drafts = [
      for (var index = 0; index < links.length; index++)
        PaymentLinkRecoveryRecord(
          link: links[index],
          sourceAccountUuid: sourceAccountUuid,
          state: PaymentLinkRecoveryState.draft,
          updatedAt: now,
          claimFeeReserveZatoshi: claimFeeReserveZatoshi,
          batchId: batchId,
          batchIndex: index + 1,
          batchCount: links.length,
        ),
    ];
    await _writeRecords([...records, ...drafts]);
    return drafts;
  });

  Future<void> markBatchSubmissionStarted({
    required String batchId,
    required int chainHeight,
  }) {
    if (chainHeight < 0) throw ArgumentError.value(chainHeight);
    return _updateBatch(
      batchId,
      done: (record) =>
          record.state == PaymentLinkRecoveryState.draft &&
          record.submittedAtHeight != null,
      invalid: (record) =>
          record.state != PaymentLinkRecoveryState.draft ||
          record.submittedAtHeight != null,
      error: 'Gift Card batch has already crossed submission.',
      update: (record, now) => record.copyWith(
        state: PaymentLinkRecoveryState.draft,
        updatedAt: now,
        submittedAtHeight: chainHeight,
      ),
    );
  }

  Future<void> markBatchPrepared({
    required String batchId,
    required String fundingTxid,
    required int expiryHeight,
  }) {
    if (fundingTxid.trim().isEmpty || expiryHeight <= 0) {
      throw ArgumentError('Invalid prepared Gift Card batch.');
    }
    return _updateBatch(
      batchId,
      invalid: (record) =>
          record.state != PaymentLinkRecoveryState.draft ||
          record.submittedAtHeight != null ||
          !_sameFundingTxid(record.fundingTxids, fundingTxid) ||
          (record.preparedExpiryHeight != null &&
              record.preparedExpiryHeight != expiryHeight),
      error: 'Gift Card batch preparation state is inconsistent.',
      update: (record, now) => record.copyWith(
        state: PaymentLinkRecoveryState.draft,
        updatedAt: now,
        fundingTxids: fundingTxid,
        preparedExpiryHeight: expiryHeight,
      ),
    );
  }

  /// Records the shared funding txid on every member. Repeating it, or
  /// calling it after the batch was already promoted, is a no-op.
  Future<void> markBatchSubmitted({
    required String batchId,
    required String fundingTxids,
  }) {
    if (fundingTxids.trim().isEmpty) throw ArgumentError.value(fundingTxids);
    return _updateBatch(
      batchId,
      done: (record) =>
          record.fundingTxids != null &&
          _sameFundingTxid(record.fundingTxids, fundingTxids) &&
          (record.state != PaymentLinkRecoveryState.draft ||
              record.submittedAtHeight != null),
      invalid: _cannotTakeBatchFunding(fundingTxids),
      error: 'Gift Card batch submission state is inconsistent.',
      update: (record, now) => record.copyWith(
        state: PaymentLinkRecoveryState.draft,
        updatedAt: now,
        fundingTxids: fundingTxids,
      ),
    );
  }

  /// Promotes every member at once. Already-funded members with the same
  /// txid make this a no-op, so a lost write can simply be retried.
  Future<void> markBatchFunded({
    required String batchId,
    required String fundingTxids,
  }) {
    if (fundingTxids.trim().isEmpty) throw ArgumentError.value(fundingTxids);
    return _updateBatch(
      batchId,
      done: (record) =>
          record.state != PaymentLinkRecoveryState.draft &&
          _sameFundingTxid(record.fundingTxids, fundingTxids),
      invalid: _cannotTakeBatchFunding(fundingTxids),
      error: 'Gift Card batch funding state is inconsistent.',
      update: (record, now) => record.copyWith(
        state: PaymentLinkRecoveryState.funded,
        updatedAt: now,
        fundingTxids: fundingTxids,
        preparedExpiryHeight: null,
        fundedAt: record.fundedAt ?? now,
      ),
    );
  }

  Future<void> removeUnsubmittedBatch(String batchId) => _removeBatch(
    batchId,
    retained: (record) => !record.isInertDraft,
    error: 'A submitted Gift Card batch cannot be removed.',
  );

  Future<void> removeUnbroadcastBatch(String batchId) => _removeBatch(
    batchId,
    retained: (record) =>
        record.state != PaymentLinkRecoveryState.draft ||
        record.submittedAtHeight != null,
    error: 'A broadcast Gift Card batch cannot be removed.',
  );

  /// Caller must have a definitive rejection or expiry from the signed
  /// outbox. An uncertain network result must retain every bearer secret.
  Future<void> removeTerminalBatch(String batchId) => _removeBatch(
    batchId,
    retained: (record) => record.state != PaymentLinkRecoveryState.draft,
    error: 'A funded Gift Card batch cannot be removed.',
  );

  /// Rewrites every member of [batchId] in one secure-store write, unless all
  /// of them are already [done].
  Future<void> _updateBatch(
    String batchId, {
    required bool Function(PaymentLinkRecoveryRecord record) invalid,
    required String error,
    required PaymentLinkRecoveryRecord Function(
      PaymentLinkRecoveryRecord record,
      DateTime now,
    )
    update,
    bool Function(PaymentLinkRecoveryRecord record)? done,
  }) => _runExclusive(() async {
    final records = await _loadUnlocked();
    final members = _requireBatchMembers(records, batchId);
    if (done != null && members.every(done)) return;
    if (members.any(invalid)) throw StateError(error);
    final now = DateTime.now().toUtc();
    await _writeRecords([
      for (final record in records)
        record.batchId == batchId ? update(record, now) : record,
    ]);
  });

  /// Removes a whole batch unless any member must be [retained]. A batch that
  /// is already gone counts as removed.
  Future<void> _removeBatch(
    String batchId, {
    required bool Function(PaymentLinkRecoveryRecord record) retained,
    required String error,
  }) => _runExclusive(() async {
    final records = await _loadUnlocked();
    if (!records.any((record) => record.batchId == batchId)) return;
    final members = _requireBatchMembers(records, batchId);
    if (members.any(retained)) throw StateError(error);
    await _writeRecords(
      records.where((record) => record.batchId != batchId).toList(),
    );
  });

  Future<PaymentLinkRecoveryRecord> markFunded({
    required String address,
    required String fundingTxids,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      if (fundingTxids.trim().isEmpty) {
        throw ArgumentError.value(
          fundingTxids,
          'fundingTxids',
          'A funded payment link requires a transaction id.',
        );
      }
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (existing.state != PaymentLinkRecoveryState.draft &&
          existing.state != PaymentLinkRecoveryState.funded) {
        throw StateError('Payment link funding state cannot move backwards.');
      }
      final preparedTxid = existing.fundingTxids?.trim();
      final submittedTxid = fundingTxids.trim();
      if (existing.state == PaymentLinkRecoveryState.draft &&
          preparedTxid != null &&
          preparedTxid.isNotEmpty &&
          preparedTxid.toLowerCase() != submittedTxid.toLowerCase()) {
        throw StateError(
          'Payment link funding result does not match the prepared transaction.',
        );
      }
      final timestamp = (updatedAt ?? DateTime.now()).toUtc();
      final updated = existing.copyWith(
        state: PaymentLinkRecoveryState.funded,
        updatedAt: timestamp,
        fundingTxids: submittedTxid,
        preparedExpiryHeight: null,
        fundedAt: existing.fundedAt ?? timestamp,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  /// Records that a funding broadcast is about to be handed to the network.
  ///
  /// The software path only learns its transaction id from the broadcast
  /// result, so a failure that loses that result would otherwise leave an inert
  /// draft that recovery cannot tell apart from one that never funded. Writing
  /// the submission height first turns that case into an ambiguous submission
  /// the reconciler can settle against the link's own wallet. Hardware drafts
  /// already carry their prepared txid; the marker is what separates one that
  /// reached the network from one abandoned before signing.
  ///
  /// Idempotent: an already-recorded height is the earlier, safer one and is
  /// kept. A record past `draft` needs no marker and is returned unchanged.
  Future<PaymentLinkRecoveryRecord> markSubmissionStarted({
    required String address,
    required int chainHeight,
    DateTime? updatedAt,
  }) async {
    return (await _markSubmissionStarted(
      address: address,
      chainHeight: chainHeight,
      updatedAt: updatedAt,
      requireRecord: true,
    ))!;
  }

  /// [markSubmissionStarted] for a Ledger outbox broadcast, which may outlive
  /// a draft the reconciler already removed as expired; Rust settles that
  /// operation itself. Returns null when [address] has no record.
  Future<PaymentLinkRecoveryRecord?> markSubmissionStartedIfPresent({
    required String address,
    required int chainHeight,
  }) {
    return _markSubmissionStarted(
      address: address,
      chainHeight: chainHeight,
      requireRecord: false,
    );
  }

  Future<PaymentLinkRecoveryRecord?> _markSubmissionStarted({
    required String address,
    required int chainHeight,
    required bool requireRecord,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      if (chainHeight < 0) {
        throw ArgumentError.value(
          chainHeight,
          'chainHeight',
          'A submitted payment link requires a non-negative chain height.',
        );
      }
      final records = await _loadUnlocked();
      final existing = requireRecord
          ? _findRequired(records, address)
          : _findByAddress(records, address);
      if (existing == null) return null;
      if (existing.state != PaymentLinkRecoveryState.draft) return existing;
      if (existing.submittedAtHeight != null) return existing;
      final updated = existing.copyWith(
        state: PaymentLinkRecoveryState.draft,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        submittedAtHeight: chainHeight,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  /// Records the broadcast transaction id on a draft without promoting it to
  /// [PaymentLinkRecoveryState.funded].
  ///
  /// The software funding path only learns its transaction id when the
  /// broadcast returns, so unlike the hardware path it has nothing to write
  /// through [markPrepared] beforehand. Writing the id separately from the
  /// promotion means a [markFunded] that fails still leaves the reconciler a
  /// transaction to match against the chain, and leaves
  /// [countUnsharedFundedPaymentLinks] counting the row — otherwise a draft
  /// whose funding really was broadcast reads as inert and its Card link
  /// becomes unreachable.
  ///
  /// No expiry height is recorded, because the software path never sees one.
  /// The reconciler therefore promotes such a draft when its transaction is
  /// mined but never expires it.
  ///
  /// A recorded broadcast txid proves the broadcast boundary was crossed, so
  /// a missing submission marker is filled in with an unknown height.
  Future<PaymentLinkRecoveryRecord> markSubmitted({
    required String address,
    required String fundingTxids,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      final submittedTxids = fundingTxids.trim();
      if (submittedTxids.isEmpty) {
        throw ArgumentError.value(
          fundingTxids,
          'fundingTxids',
          'A submitted payment link requires a transaction id.',
        );
      }
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      // Nothing to add once the record has moved past `draft`; the promotion
      // that follows owns those states.
      if (existing.state != PaymentLinkRecoveryState.draft) return existing;
      final existingTxids = existing.fundingTxids?.trim();
      if (existingTxids != null && existingTxids.isNotEmpty) {
        if (existingTxids.toLowerCase() != submittedTxids.toLowerCase()) {
          throw StateError(
            'Payment link funding was prepared with a different transaction.',
          );
        }
        if (existing.submittedAtHeight != null) return existing;
      }
      final updated = existing.copyWith(
        state: PaymentLinkRecoveryState.draft,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        fundingTxids: (existingTxids?.isNotEmpty ?? false)
            ? existingTxids
            : submittedTxids,
        submittedAtHeight: existing.submittedAtHeight ?? 0,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<PaymentLinkRecoveryRecord> markPrepared({
    required String address,
    required String fundingTxid,
    required int expiryHeight,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      final normalizedTxid = fundingTxid.trim();
      if (normalizedTxid.isEmpty) {
        throw ArgumentError.value(
          fundingTxid,
          'fundingTxid',
          'A prepared payment link requires a transaction id.',
        );
      }
      if (expiryHeight <= 0) {
        throw ArgumentError.value(
          expiryHeight,
          'expiryHeight',
          'A prepared payment link requires a positive expiry height.',
        );
      }
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (existing.state != PaymentLinkRecoveryState.draft) {
        throw StateError('Only a draft payment link can be prepared.');
      }
      final existingTxid = existing.fundingTxids?.trim();
      if (existingTxid != null &&
          existingTxid.isNotEmpty &&
          existingTxid.toLowerCase() != normalizedTxid.toLowerCase()) {
        throw StateError(
          'Payment link funding was prepared with a different transaction.',
        );
      }
      final existingExpiryHeight = existing.preparedExpiryHeight;
      if (existingExpiryHeight != null &&
          existingExpiryHeight != expiryHeight) {
        throw StateError(
          'Payment link funding was prepared with a different expiry height.',
        );
      }
      final updated = existing.copyWith(
        state: PaymentLinkRecoveryState.draft,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        fundingTxids: normalizedTxid,
        preparedExpiryHeight: expiryHeight,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<PaymentLinkRecoveryRecord> markShared({
    required String address,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (existing.state != PaymentLinkRecoveryState.funded &&
          existing.state != PaymentLinkRecoveryState.shared) {
        throw StateError('Only a funded payment link can be marked shared.');
      }
      final updated = existing.copyWith(
        state: PaymentLinkRecoveryState.shared,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<void> removeUnsubmittedDraft({required String address}) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findByAddress(records, address);
      if (existing == null) return;
      if (existing.state != PaymentLinkRecoveryState.draft ||
          (existing.fundingTxids?.trim().isNotEmpty ?? false) ||
          existing.preparedExpiryHeight != null ||
          // A broadcast started for this draft and its result was never seen,
          // so it may hold funds even without a transaction id.
          existing.submittedAtHeight != null) {
        throw StateError(
          'Only an unsubmitted payment link draft can be removed.',
        );
      }
      await _writeRecords(
        records.where((record) => record.link.address != address).toList(),
      );
    });
  }

  Future<void> removeUnbroadcastDraft({required String address}) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findByAddress(records, address);
      if (existing == null) return;
      if (existing.state != PaymentLinkRecoveryState.draft ||
          existing.isAmbiguousSubmission) {
        throw StateError(
          'Only an unbroadcast payment link draft can be removed.',
        );
      }
      await _writeRecords(
        records.where((record) => record.link.address != address).toList(),
      );
    });
  }

  /// Removes a prepared hardware draft whose flow ended before its broadcast
  /// boundary. Checked under the store lock, so a marker written after the
  /// caller's read keeps the draft.
  Future<void> removeUnsubmittedPreparedDraft({required String address}) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findByAddress(records, address);
      if (existing == null) return;
      if (existing.state != PaymentLinkRecoveryState.draft ||
          (existing.fundingTxids?.trim().isEmpty ?? true) ||
          existing.submittedAtHeight != null) {
        throw StateError(
          'Only an unsubmitted prepared payment link draft can be removed.',
        );
      }
      await _writeRecords(
        records.where((record) => record.link.address != address).toList(),
      );
    });
  }

  /// Drops [sourceAccountUuid]'s drafts that never crossed the broadcast
  /// boundary. Called once the account itself is gone: they can no longer be
  /// funded, and the reconciler cannot query a deleted account's history.
  Future<int> removeUnsubmittedDraftsForAccount(String sourceAccountUuid) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final kept = records
          .where(
            (record) =>
                record.sourceAccountUuid != sourceAccountUuid ||
                record.state != PaymentLinkRecoveryState.draft ||
                record.mayHoldUnsharedFunds,
          )
          .toList();
      final removed = records.length - kept.length;
      if (removed > 0) await _writeRecords(kept);
      return removed;
    });
  }

  Future<void> removeUnsharedExpiredFunding({
    required String address,
    required String fundingTxids,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findByAddress(records, address);
      if (existing == null) return;
      if (existing.state != PaymentLinkRecoveryState.funded ||
          existing.fundingTxids?.trim().toLowerCase() !=
              fundingTxids.trim().toLowerCase()) {
        throw StateError(
          'Only the matching unshared expired funding can be removed.',
        );
      }
      await _writeRecords(
        records.where((record) => record.link.address != address).toList(),
      );
    });
  }

  /// Compare identity and funding before applying an asynchronous observation.
  /// Preserve independent funding/share changes made while the scan ran.
  Future<bool> updateUsage({
    required PaymentLinkRecoveryRecord expected,
    required GiftCardUsage usage,
  }) async => (await updateUsages([
    (expected: expected, usage: usage),
  ])).contains(expected.link.address);

  /// [updateUsage] for many cards in one secure-store write, so a scan of a
  /// large group does not rewrite every record once per card. Returns the
  /// addresses that were saved.
  Future<Set<String>> updateUsages(
    List<({PaymentLinkRecoveryRecord expected, GiftCardUsage usage})> updates,
  ) => _runExclusive(() async {
    if (updates.isEmpty) return const <String>{};
    var records = await _loadUnlocked();
    final saved = <String>{};
    for (final (:expected, :usage) in updates) {
      final current = _findByAddress(records, expected.link.address);
      if (current == null ||
          !current.link.hasSameCanonicalPayload(expected.link) ||
          current.fundingTxids != expected.fundingTxids ||
          jsonEncode(current.usage.toJson()) !=
              jsonEncode(expected.usage.toJson())) {
        continue;
      }
      // Apply the same validation to writes and reads.
      GiftCardUsage.fromJson(usage.toJson());
      records = _replaceByAddress(
        records,
        current.copyWith(
          state: current.state,
          updatedAt: current.updatedAt,
          usage: usage,
        ),
      );
      saved.add(expected.link.address);
    }
    if (saved.isNotEmpty) await _writeRecords(records);
    return saved;
  });

  Future<List<PaymentLinkRecoveryRecord>> _loadUnlocked() async {
    final raw = await _storage.read();
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const PaymentLinkRecoveryStoreFormatException(
          'Recovery payload must be a JSON object.',
        );
      }
      if (decoded['version'] != _storageVersion) {
        throw const PaymentLinkRecoveryStoreFormatException(
          'Recovery payload version is not supported.',
        );
      }
      final items = decoded['records'];
      if (items is! List) {
        throw const PaymentLinkRecoveryStoreFormatException(
          'Recovery payload records are missing.',
        );
      }
      final records = [for (final item in items) _recordFromJson(item)];
      if (decoded[_submissionMarkersKey] == true) return records;
      return [
        for (final record in records) _withLegacySubmissionMarker(record),
      ];
    } on PaymentLinkRecoveryStoreFormatException {
      rethrow;
    } catch (error) {
      throw PaymentLinkRecoveryStoreFormatException(
        'Recovery payload could not be decoded: $error',
      );
    }
  }

  Future<void> _writeRecords(List<PaymentLinkRecoveryRecord> records) async {
    if (records.isEmpty) {
      await _storage.delete();
      _onRecordsChanged?.call();
      return;
    }
    await _storage.write(
      jsonEncode({
        'version': _storageVersion,
        _submissionMarkersKey: true,
        'records': [for (final record in records) _recordToJson(record)],
      }),
    );
    _onRecordsChanged?.call();
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

class PaymentLinkFundingRecoveryResult<T> {
  const PaymentLinkFundingRecoveryResult({
    required this.transaction,
    this.recoveryError,
    this.recoveryStackTrace,
  });

  final T transaction;
  final Object? recoveryError;
  final StackTrace? recoveryStackTrace;

  bool get fundingMetadataSaved => recoveryError == null;
}

class PaymentLinkFundingRecovery {
  const PaymentLinkFundingRecovery(this._store);

  final PaymentLinkRecoveryStore _store;

  /// Persists the bearer secret, then runs [createTransaction] to fund it.
  ///
  /// [createTransaction] receives a `markSubmissionStarted` callback it must
  /// await immediately before the broadcast boundary. The ordering is what
  /// makes recovery possible:
  ///
  /// 1. `saveDraft` — the bearer secret exists before anything can be spent to
  ///    it.
  /// 2. `markSubmissionStarted` — a durable trace of a broadcast that is about
  ///    to happen, written while the transaction id is still unknown.
  /// 3. the broadcast, then `complete` — the transaction id, then the
  ///    promotion to funded.
  ///
  /// A failure before step 2 is definitive: nothing was sent, so the draft is
  /// removed as inert. A failure after it — including one that loses the
  /// broadcast result itself — still propagates to the caller, but leaves an
  /// ambiguous submission the reconciler can settle against the link's own
  /// wallet instead of an inert draft it would ignore.
  Future<PaymentLinkFundingRecoveryResult<T>> fund<T>({
    required VizorPaymentLink link,
    required String sourceAccountUuid,
    required BigInt claimFeeReserveZatoshi,
    required Future<T> Function(Future<void> Function() markSubmissionStarted)
    createTransaction,
    required Future<int> Function() currentChainHeight,
    required String Function(T result) fundingTxids,
  }) async {
    await _store.saveDraft(
      link: link,
      sourceAccountUuid: sourceAccountUuid,
      claimFeeReserveZatoshi: claimFeeReserveZatoshi,
    );
    late final T result;
    try {
      result = await createTransaction(() async {
        await _store.markSubmissionStarted(
          address: link.address,
          chainHeight: await currentChainHeight(),
        );
      });
    } on PaymentLinkFundingNotSubmittedException catch (failure) {
      await _store.removeUnsubmittedDraft(address: link.address);
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    return complete(
      transaction: result,
      address: link.address,
      fundingTxids: fundingTxids,
    );
  }

  Future<PaymentLinkFundingRecoveryResult<T>> complete<T>({
    required T transaction,
    required String address,
    required String Function(T result) fundingTxids,
  }) {
    final txids = fundingTxids(transaction);
    return _complete(
      transaction,
      markSubmitted: () =>
          _store.markSubmitted(address: address, fundingTxids: txids),
      markFunded: () =>
          _store.markFunded(address: address, fundingTxids: txids),
    );
  }

  /// [complete] for a batch whose members share one funding transaction.
  Future<PaymentLinkFundingRecoveryResult<T>> completeBatch<T>({
    required T transaction,
    required String batchId,
    required String fundingTxids,
  }) => _complete(
    transaction,
    markSubmitted: () =>
        _store.markBatchSubmitted(batchId: batchId, fundingTxids: fundingTxids),
    markFunded: () =>
        _store.markBatchFunded(batchId: batchId, fundingTxids: fundingTxids),
  );

  Future<PaymentLinkFundingRecoveryResult<T>> _complete<T>(
    T transaction, {
    required Future<void> Function() markSubmitted,
    required Future<void> Function() markFunded,
  }) async {
    // Earliest durable trace of a broadcast the software path can produce. If
    // the promotion below never lands and the in-app retry never runs, the
    // draft still carries its funding transaction, so recovery can finish the
    // job on a later launch instead of leaving funded ZEC behind an
    // unreachable link.
    try {
      await markSubmitted();
    } catch (_) {
      // The promotion below reports the durable-write failure to the caller.
    }
    Object? recoveryError;
    StackTrace? recoveryStackTrace;
    for (var attempt = 0; attempt < _fundingMetadataWriteAttempts; attempt++) {
      try {
        await markFunded();
        return PaymentLinkFundingRecoveryResult(transaction: transaction);
      } catch (error, stackTrace) {
        recoveryError = error;
        recoveryStackTrace = stackTrace;
      }
    }
    return PaymentLinkFundingRecoveryResult(
      transaction: transaction,
      recoveryError: recoveryError,
      recoveryStackTrace: recoveryStackTrace,
    );
  }
}

class PaymentLinkFundingNotSubmittedException implements Exception {
  const PaymentLinkFundingNotSubmittedException(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

PaymentLinkRecoveryRecord? _findByAddress(
  List<PaymentLinkRecoveryRecord> records,
  String address,
) {
  for (final record in records) {
    if (record.link.address == address) return record;
  }
  return null;
}

/// Older builds could broadcast a draft's funding without writing the marker,
/// so a legacy draft carrying a txid is treated as submitted at an unknown
/// height.
PaymentLinkRecoveryRecord _withLegacySubmissionMarker(
  PaymentLinkRecoveryRecord record,
) {
  if (record.state != PaymentLinkRecoveryState.draft ||
      record.submittedAtHeight != null ||
      (record.fundingTxids?.trim().isEmpty ?? true)) {
    return record;
  }
  return record.copyWith(
    state: record.state,
    updatedAt: record.updatedAt,
    submittedAtHeight: 0,
  );
}

PaymentLinkRecoveryRecord _findRequired(
  List<PaymentLinkRecoveryRecord> records,
  String address,
) {
  final record = _findByAddress(records, address);
  if (record == null) {
    throw StateError('Payment link recovery record was not found.');
  }
  return record;
}

List<PaymentLinkRecoveryRecord> _replaceByAddress(
  List<PaymentLinkRecoveryRecord> records,
  PaymentLinkRecoveryRecord replacement,
) {
  final replaced = <PaymentLinkRecoveryRecord>[];
  var didReplace = false;
  for (final record in records) {
    if (record.link.address == replacement.link.address) {
      replaced.add(replacement);
      didReplace = true;
    } else {
      replaced.add(record);
    }
  }
  if (!didReplace) replaced.add(replacement);
  return replaced;
}

Map<String, Object?> _recordToJson(PaymentLinkRecoveryRecord record) {
  return {
    'usage': record.usage.toJson(),
    'link': record.link.toRecoveryUri().toString(),
    'address': record.link.address,
    'createdAt': record.link.createdAt.toUtc().toIso8601String(),
    'sourceAccountUuid': record.sourceAccountUuid,
    'state': record.state.name,
    'fundingTxids': record.fundingTxids,
    'preparedExpiryHeight': record.preparedExpiryHeight,
    'submittedAtHeight': record.submittedAtHeight,
    'fundedAt': record.fundedAt?.toUtc().toIso8601String(),
    'claimFeeReserveZatoshi': record.claimFeeReserveZatoshi.toString(),
    'updatedAt': record.updatedAt.toUtc().toIso8601String(),
    if (record.batchId != null) 'batchId': record.batchId,
    if (record.batchIndex != null) 'batchIndex': record.batchIndex,
    if (record.batchCount != null) 'batchCount': record.batchCount,
  };
}

PaymentLinkRecoveryRecord _recordFromJson(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record must be a JSON object.',
    );
  }
  final reserveRaw = value['claimFeeReserveZatoshi'];
  final reserve = reserveRaw is String ? BigInt.tryParse(reserveRaw) : null;
  // Gift Cards are unreleased: require the creation-time reserve rather than
  // infer it from a previous schema or the current fee policy.
  if (reserve == null || reserve < BigInt.zero) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Invalid claim fee reserve.',
    );
  }
  final linkRaw = value['link'];
  final address = value['address'];
  final createdAtRaw = value['createdAt'];
  final sourceAccountUuid = value['sourceAccountUuid'];
  final stateRaw = value['state'];
  final fundingTxids = value['fundingTxids'];
  final preparedExpiryHeight = value['preparedExpiryHeight'];
  final submittedAtHeight = value['submittedAtHeight'];
  final updatedAtRaw = value['updatedAt'];
  final batchId = value['batchId'];
  final batchIndex = value['batchIndex'];
  final batchCount = value['batchCount'];
  final fundedAtRaw = value['fundedAt'];
  if (linkRaw is! String ||
      (address != null && (address is! String || address.isEmpty)) ||
      (createdAtRaw != null && createdAtRaw is! String) ||
      sourceAccountUuid is! String ||
      sourceAccountUuid.isEmpty ||
      stateRaw is! String ||
      (fundingTxids != null && fundingTxids is! String) ||
      (preparedExpiryHeight != null &&
          (preparedExpiryHeight is! int || preparedExpiryHeight <= 0)) ||
      (submittedAtHeight != null &&
          (submittedAtHeight is! int || submittedAtHeight < 0)) ||
      (fundedAtRaw != null && fundedAtRaw is! String) ||
      updatedAtRaw is! String) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record fields are invalid.',
    );
  }
  if ((batchId != null || batchIndex != null || batchCount != null) &&
      (batchId is! String ||
          batchId.isEmpty ||
          batchIndex is! int ||
          batchCount is! int ||
          batchCount < kPaymentLinkBatchMinCount ||
          batchCount > kPaymentLinkBatchMaxCount ||
          batchIndex < 1 ||
          batchIndex > batchCount)) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Gift Card batch metadata is invalid.',
    );
  }
  final updatedAt = DateTime.tryParse(updatedAtRaw);
  final createdAt = createdAtRaw == null
      ? null
      : DateTime.tryParse(createdAtRaw as String);
  if (updatedAt == null) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record timestamp is invalid.',
    );
  }
  final fundedAt = fundedAtRaw == null
      ? null
      : DateTime.tryParse(fundedAtRaw as String);
  if (fundedAtRaw != null && fundedAt == null) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record funding timestamp is invalid.',
    );
  }
  if (createdAtRaw != null && createdAt == null) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record creation timestamp is invalid.',
    );
  }
  late final PaymentLinkRecoveryState state;
  try {
    state = PaymentLinkRecoveryState.values.byName(stateRaw);
  } on ArgumentError {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record state is invalid.',
    );
  }

  // A draft may carry a funding transaction without an expiry height: the
  // hardware path records both through `markPrepared`, while the software path
  // learns its transaction id only when the broadcast returns and never sees an
  // expiry height. An expiry height without a transaction is still incomplete —
  // there would be nothing to reconcile it against.
  final hasPreparedTxid =
      state == PaymentLinkRecoveryState.draft &&
      (fundingTxids as String?)?.trim().isNotEmpty == true;
  if (preparedExpiryHeight != null && !hasPreparedTxid) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Prepared recovery metadata is incomplete.',
    );
  }

  final parsedLink = VizorPaymentLink.parse(linkRaw);
  final addressMismatch =
      parsedLink.knownAddress != null &&
      address != null &&
      parsedLink.knownAddress != address;
  final createdAtMismatch =
      parsedLink.knownCreatedAt != null &&
      createdAt != null &&
      parsedLink.knownCreatedAt != createdAt;
  if (addressMismatch || createdAtMismatch) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record link metadata does not match its record.',
    );
  }
  final resolvedAddress = (address as String?) ?? parsedLink.knownAddress;
  final resolvedCreatedAt = createdAt ?? parsedLink.knownCreatedAt;
  if (resolvedAddress == null || resolvedCreatedAt == null) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record link metadata is missing.',
    );
  }

  return PaymentLinkRecoveryRecord(
    link: parsedLink.withResolvedMetadata(
      address: resolvedAddress,
      createdAt: resolvedCreatedAt,
    ),
    usage: GiftCardUsage.fromJson(value['usage']),
    claimFeeReserveZatoshi: reserve,
    sourceAccountUuid: sourceAccountUuid,
    state: state,
    fundingTxids: fundingTxids,
    preparedExpiryHeight: preparedExpiryHeight as int?,
    submittedAtHeight: submittedAtHeight as int?,
    fundedAt: fundedAt?.toUtc(),
    updatedAt: updatedAt.toUtc(),
    batchId: batchId as String?,
    batchIndex: batchIndex as int?,
    batchCount: batchCount as int?,
  );
}

bool Function(PaymentLinkRecoveryRecord record) _cannotTakeBatchFunding(
  String fundingTxids,
) =>
    (record) =>
        record.state != PaymentLinkRecoveryState.draft ||
        record.submittedAtHeight == null ||
        !_sameFundingTxid(record.fundingTxids, fundingTxids);

/// An unset saved txid accepts any; otherwise txids compare case-insensitively.
bool _sameFundingTxid(String? saved, String txid) =>
    saved == null ||
    saved.trim().isEmpty ||
    saved.trim().toLowerCase() == txid.trim().toLowerCase();

List<PaymentLinkRecoveryRecord> _requireBatchMembers(
  List<PaymentLinkRecoveryRecord> records,
  String batchId,
) {
  final members = records.where((record) => record.batchId == batchId).toList();
  if (batchId.isEmpty || !isCompletePaymentLinkBatch(members)) {
    throw StateError('Gift Card batch recovery records are incomplete.');
  }
  return members;
}

/// Whether [members] are exactly one batch: numbered 1 through N and sharing
/// the batch, source account, network, card amount and claim fee reserve.
bool isCompletePaymentLinkBatch(List<PaymentLinkRecoveryRecord> members) {
  if (members.isEmpty) return false;
  final first = members.first;
  final indices = members.map((record) => record.batchIndex).toSet();
  return first.batchId != null &&
      first.batchCount == members.length &&
      indices.length == members.length &&
      indices.containsAll([for (var i = 1; i <= members.length; i++) i]) &&
      members.every(
        (record) =>
            record.batchId == first.batchId &&
            record.batchCount == members.length &&
            record.sourceAccountUuid == first.sourceAccountUuid &&
            record.link.network == first.link.network &&
            record.link.amountZatoshi == first.link.amountZatoshi &&
            record.claimFeeReserveZatoshi == first.claimFeeReserveZatoshi,
      );
}

/// Gift Cards that block deleting [sourceAccountUuid]: see
/// [PaymentLinkRecoveryRecord.mayHoldUnsharedFunds].
int countUnsharedFundedPaymentLinks(
  Iterable<PaymentLinkRecoveryRecord> records, {
  required String sourceAccountUuid,
}) {
  if (sourceAccountUuid.isEmpty) return 0;
  return records
      .where(
        (record) =>
            record.sourceAccountUuid == sourceAccountUuid &&
            record.mayHoldUnsharedFunds,
      )
      .length;
}
