import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/vizor_payment_link.dart';

const _storageVersion = 1;

final paymentLinkRecoveryStoreProvider = Provider<PaymentLinkRecoveryStore>((
  ref,
) {
  return PaymentLinkRecoveryStore(
    AppSecureStorePaymentLinkRecoveryStorage(AppSecureStore.instance),
  );
});

enum PaymentLinkRecoveryState { draft, funded, shared }

const _fieldNotProvided = Object();

class PaymentLinkRecoveryRecord {
  const PaymentLinkRecoveryRecord({
    required this.link,
    required this.sourceAccountUuid,
    required this.state,
    required this.updatedAt,
    this.fundingTxids,
    this.archivedAt,
  });

  final VizorPaymentLink link;
  final String sourceAccountUuid;
  final PaymentLinkRecoveryState state;
  final DateTime updatedAt;
  final String? fundingTxids;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  PaymentLinkRecoveryRecord copyWith({
    required PaymentLinkRecoveryState state,
    required DateTime updatedAt,
    String? fundingTxids,
    Object? archivedAt = _fieldNotProvided,
  }) {
    return PaymentLinkRecoveryRecord(
      link: link,
      sourceAccountUuid: sourceAccountUuid,
      state: state,
      updatedAt: updatedAt,
      fundingTxids: fundingTxids ?? this.fundingTxids,
      archivedAt: identical(archivedAt, _fieldNotProvided)
          ? this.archivedAt
          : archivedAt as DateTime?,
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
  PaymentLinkRecoveryStore(this._storage);

  final PaymentLinkRecoveryStorage _storage;
  Future<void> _operationTail = Future<void>.value();

  Future<List<PaymentLinkRecoveryRecord>> load() {
    return _runExclusive(_loadUnlocked);
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
      final updated = existing.copyWith(
        state: PaymentLinkRecoveryState.funded,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        fundingTxids: fundingTxids.trim(),
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

  Future<PaymentLinkRecoveryRecord> setArchived({
    required String address,
    required bool archived,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      final now = (updatedAt ?? DateTime.now()).toUtc();
      final updated = existing.copyWith(
        state: existing.state,
        updatedAt: now,
        archivedAt: archived ? now : null,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
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
      return;
    }
    await _storage.write(
      jsonEncode({
        'version': _storageVersion,
        'records': [for (final record in records) _recordToJson(record)],
      }),
    );
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

class PaymentLinkFundingRecovery {
  const PaymentLinkFundingRecovery(this._store);

  final PaymentLinkRecoveryStore _store;

  Future<T> fund<T>({
    required VizorPaymentLink link,
    required String sourceAccountUuid,
    required Future<T> Function() createTransaction,
    required String Function(T result) fundingTxids,
  }) async {
    await _store.saveDraft(link: link, sourceAccountUuid: sourceAccountUuid);
    final result = await createTransaction();
    await _store.markFunded(
      address: link.address,
      fundingTxids: fundingTxids(result),
    );
    return result;
  }
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
    'link': record.link.encode(),
    'sourceAccountUuid': record.sourceAccountUuid,
    'state': record.state.name,
    'fundingTxids': record.fundingTxids,
    'archivedAt': record.archivedAt?.toUtc().toIso8601String(),
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
  final archivedAtRaw = value['archivedAt'];
  final updatedAtRaw = value['updatedAt'];
  if (linkRaw is! String ||
      sourceAccountUuid is! String ||
      sourceAccountUuid.isEmpty ||
      stateRaw is! String ||
      (fundingTxids != null && fundingTxids is! String) ||
      (archivedAtRaw != null && archivedAtRaw is! String) ||
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
  final archivedAt = archivedAtRaw == null
      ? null
      : DateTime.tryParse(archivedAtRaw);
  if (archivedAtRaw != null && archivedAt == null) {
    throw const PaymentLinkRecoveryStoreFormatException(
      'Recovery record archive timestamp is invalid.',
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

  return PaymentLinkRecoveryRecord(
    link: VizorPaymentLink.decode(linkRaw),
    sourceAccountUuid: sourceAccountUuid,
    state: state,
    fundingTxids: fundingTxids as String?,
    archivedAt: archivedAt?.toUtc(),
    updatedAt: updatedAt.toUtc(),
  );
}
