import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_lifecycle_revision.dart';

const _storageVersion = 1;
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

class PaymentLinkUnsharedGiftCardsException implements Exception {
  const PaymentLinkUnsharedGiftCardsException({
    required this.sourceAccountUuid,
    required this.count,
  });

  final String sourceAccountUuid;
  final int count;

  @override
  String toString() =>
      'Copy your unshared Gift Card links before deleting this account.';
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
  });

  final VizorPaymentLink link;
  final String sourceAccountUuid;
  final PaymentLinkRecoveryState state;
  final DateTime updatedAt;
  final String? fundingTxids;
  final int? preparedExpiryHeight;

  /// The chain height the wallet knew when a software funding broadcast
  /// started.
  ///
  /// It is written before the broadcast boundary is crossed, so a broadcast
  /// whose result never came back — an FFI or channel failure after the
  /// transaction reached the network — still leaves a durable trace to
  /// reconcile. `0` means the height was unknown at submission time.
  final int? submittedAtHeight;

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

  PaymentLinkRecoveryRecord copyWith({
    required PaymentLinkRecoveryState state,
    required DateTime updatedAt,
    Object? fundingTxids = _fieldNotProvided,
    Object? preparedExpiryHeight = _fieldNotProvided,
    Object? submittedAtHeight = _fieldNotProvided,
  }) {
    return PaymentLinkRecoveryRecord(
      link: link,
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
        state: PaymentLinkRecoveryState.draft,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      );
      await _writeRecords(_replaceByAddress(records, record));
      return record;
    });
  }

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
      final updated = existing.copyWith(
        state: PaymentLinkRecoveryState.funded,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        fundingTxids: submittedTxid,
        preparedExpiryHeight: null,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  /// Records that a software funding broadcast is about to be handed to the
  /// network, before its transaction id can be known.
  ///
  /// The software path only learns its transaction id from the broadcast
  /// result, so a failure that loses that result would otherwise leave an inert
  /// draft that recovery cannot tell apart from one that never funded. Writing
  /// the submission height first turns that case into an ambiguous submission
  /// the reconciler can settle against the link's own wallet.
  ///
  /// Idempotent: an already-recorded height is the earlier, safer one and is
  /// kept. A draft that already carries a transaction id, or a record past
  /// `draft`, needs no marker and is returned unchanged.
  Future<PaymentLinkRecoveryRecord> markSubmissionStarted({
    required String address,
    required int chainHeight,
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
      final existing = _findRequired(records, address);
      if (existing.state != PaymentLinkRecoveryState.draft) return existing;
      if (existing.fundingTxids?.trim().isNotEmpty ?? false) return existing;
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
        return existing;
      }
      final updated = existing.copyWith(
        state: PaymentLinkRecoveryState.draft,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        fundingTxids: submittedTxids,
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
      if (existing.state != PaymentLinkRecoveryState.draft) {
        throw StateError(
          'Only an unbroadcast payment link draft can be removed.',
        );
      }
      await _writeRecords(
        records.where((record) => record.link.address != address).toList(),
      );
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
      return [for (final item in items) _recordFromJson(item)];
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
    required Future<T> Function(Future<void> Function() markSubmissionStarted)
    createTransaction,
    required Future<int> Function() currentChainHeight,
    required String Function(T result) fundingTxids,
  }) async {
    await _store.saveDraft(link: link, sourceAccountUuid: sourceAccountUuid);
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
  }) async {
    final txids = fundingTxids(transaction);
    // Earliest durable trace of a broadcast the software path can produce. If
    // the promotion below never lands and the in-app retry never runs, the
    // draft still carries its funding transaction, so recovery can finish the
    // job on a later launch instead of leaving funded ZEC behind an
    // unreachable link.
    try {
      await _store.markSubmitted(address: address, fundingTxids: txids);
    } catch (_) {
      // The promotion below reports the durable-write failure to the caller.
    }
    Object? recoveryError;
    StackTrace? recoveryStackTrace;
    for (var attempt = 0; attempt < _fundingMetadataWriteAttempts; attempt++) {
      try {
        await _store.markFunded(address: address, fundingTxids: txids);
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
    'link': record.link.toUri().toString(),
    'sourceAccountUuid': record.sourceAccountUuid,
    'state': record.state.name,
    'fundingTxids': record.fundingTxids,
    'preparedExpiryHeight': record.preparedExpiryHeight,
    'submittedAtHeight': record.submittedAtHeight,
    'updatedAt': record.updatedAt.toUtc().toIso8601String(),
  };
}

PaymentLinkRecoveryRecord _recordFromJson(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record must be a JSON object.',
    );
  }
  final linkRaw = value['link'];
  final sourceAccountUuid = value['sourceAccountUuid'];
  final stateRaw = value['state'];
  final fundingTxids = value['fundingTxids'];
  final preparedExpiryHeight = value['preparedExpiryHeight'];
  final submittedAtHeight = value['submittedAtHeight'];
  final updatedAtRaw = value['updatedAt'];
  if (linkRaw is! String ||
      sourceAccountUuid is! String ||
      sourceAccountUuid.isEmpty ||
      stateRaw is! String ||
      (fundingTxids != null && fundingTxids is! String) ||
      (preparedExpiryHeight != null &&
          (preparedExpiryHeight is! int || preparedExpiryHeight <= 0)) ||
      (submittedAtHeight != null &&
          (submittedAtHeight is! int || submittedAtHeight < 0)) ||
      updatedAtRaw is! String) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record fields are invalid.',
    );
  }
  final updatedAt = DateTime.tryParse(updatedAtRaw);
  if (updatedAt == null) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record timestamp is invalid.',
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

  return PaymentLinkRecoveryRecord(
    link: VizorPaymentLink.parse(linkRaw),
    sourceAccountUuid: sourceAccountUuid,
    state: state,
    fundingTxids: fundingTxids,
    preparedExpiryHeight: preparedExpiryHeight as int?,
    submittedAtHeight: submittedAtHeight as int?,
    updatedAt: updatedAt.toUtc(),
  );
}

int countUnsharedFundedPaymentLinks(
  Iterable<PaymentLinkRecoveryRecord> records, {
  required String sourceAccountUuid,
}) {
  if (sourceAccountUuid.isEmpty) return 0;
  return records
      .where(
        (record) =>
            record.sourceAccountUuid == sourceAccountUuid &&
            (record.state == PaymentLinkRecoveryState.funded ||
                (record.state == PaymentLinkRecoveryState.draft &&
                    (record.fundingTxids?.trim().isNotEmpty ?? false)) ||
                // An ambiguous submission has no transaction id to check, and
                // its broadcast may well have landed. Blocking the delete is
                // the conservative answer.
                record.isAmbiguousSubmission),
      )
      .length;
}
