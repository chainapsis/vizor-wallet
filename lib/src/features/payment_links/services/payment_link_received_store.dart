import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/vizor_payment_link.dart';

const _storageVersion = 1;
const _fieldNotProvided = Object();

final paymentLinkReceivedStoreProvider = Provider<PaymentLinkReceivedStore>((
  ref,
) {
  return PaymentLinkReceivedStore(
    AppSecureStorePaymentLinkReceivedStorage(AppSecureStore.instance),
  );
});

enum PaymentLinkReceivedStatus { readyToClaim, receiving, received }

class PaymentLinkReceivedRecord {
  const PaymentLinkReceivedRecord({
    required this.network,
    required this.address,
    required this.amountZatoshi,
    required this.createdAt,
    required this.artworkId,
    required this.status,
    required this.claimLink,
    required this.destinationAccountUuid,
    required this.claimTxids,
    required this.updatedAt,
  });

  factory PaymentLinkReceivedRecord.fromLink(
    VizorPaymentLink link, {
    DateTime? updatedAt,
  }) {
    return PaymentLinkReceivedRecord(
      network: link.network,
      address: link.address,
      amountZatoshi: link.amountZatoshi,
      createdAt: link.createdAt.toUtc(),
      artworkId: link.presentation?.artworkId,
      status: PaymentLinkReceivedStatus.readyToClaim,
      claimLink: link,
      destinationAccountUuid: null,
      claimTxids: null,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
  }

  final String network;
  final String address;
  final BigInt amountZatoshi;
  final DateTime createdAt;
  final String? artworkId;
  final PaymentLinkReceivedStatus status;

  /// The bearer secret is retained only while the Card can still require a
  /// retry. It is removed as soon as the receiver's mined history proves the
  /// claim completed.
  final VizorPaymentLink? claimLink;
  final String? destinationAccountUuid;
  final String? claimTxids;
  final DateTime updatedAt;

  PaymentLinkReceivedRecord copyWith({
    PaymentLinkReceivedStatus? status,
    Object? claimLink = _fieldNotProvided,
    Object? destinationAccountUuid = _fieldNotProvided,
    Object? claimTxids = _fieldNotProvided,
    DateTime? updatedAt,
  }) {
    return PaymentLinkReceivedRecord(
      network: network,
      address: address,
      amountZatoshi: amountZatoshi,
      createdAt: createdAt,
      artworkId: artworkId,
      status: status ?? this.status,
      claimLink:
          identical(claimLink, _fieldNotProvided)
              ? this.claimLink
              : claimLink as VizorPaymentLink?,
      destinationAccountUuid:
          identical(destinationAccountUuid, _fieldNotProvided)
              ? this.destinationAccountUuid
              : destinationAccountUuid as String?,
      claimTxids:
          identical(claimTxids, _fieldNotProvided)
              ? this.claimTxids
              : claimTxids as String?,
      updatedAt: (updatedAt ?? this.updatedAt).toUtc(),
    );
  }
}

class PaymentLinkReceivedStoreFormatException implements Exception {
  const PaymentLinkReceivedStoreFormatException(this.message);

  final String message;

  @override
  String toString() => 'PaymentLinkReceivedStoreFormatException: $message';
}

abstract interface class PaymentLinkReceivedStorage {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

class AppSecureStorePaymentLinkReceivedStorage
    implements PaymentLinkReceivedStorage {
  const AppSecureStorePaymentLinkReceivedStorage(this._store);

  final AppSecureStore _store;

  @override
  Future<String?> read() {
    return _store.readSecretStringWithOptions(
      kPaymentLinkReceivedStorageKey,
      requireUnlockedSession: true,
    );
  }

  @override
  Future<void> write(String value) {
    return _store.writeSecretString(kPaymentLinkReceivedStorageKey, value);
  }

  @override
  Future<void> delete() {
    return _store.delete(kPaymentLinkReceivedStorageKey);
  }
}

class PaymentLinkReceivedStore {
  PaymentLinkReceivedStore(this._storage);

  final PaymentLinkReceivedStorage _storage;
  Future<void> _operationTail = Future<void>.value();

  Future<List<PaymentLinkReceivedRecord>> load() {
    return _runExclusive(_loadUnlocked);
  }

  Future<PaymentLinkReceivedRecord> saveReady(
    VizorPaymentLink link, {
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findByAddress(records, link.address);
      if (existing?.status == PaymentLinkReceivedStatus.received) {
        return existing!;
      }
      final record = PaymentLinkReceivedRecord(
        network: link.network,
        address: link.address,
        amountZatoshi: link.amountZatoshi,
        createdAt: link.createdAt.toUtc(),
        artworkId: link.presentation?.artworkId,
        status: existing?.status ?? PaymentLinkReceivedStatus.readyToClaim,
        claimLink: link,
        destinationAccountUuid: existing?.destinationAccountUuid,
        claimTxids: existing?.claimTxids,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      );
      await _writeRecords(_replaceByAddress(records, record));
      return record;
    });
  }

  Future<PaymentLinkReceivedRecord> markReceiving({
    required String address,
    required String destinationAccountUuid,
    required String claimTxids,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      if (destinationAccountUuid.trim().isEmpty) {
        throw ArgumentError.value(
          destinationAccountUuid,
          'destinationAccountUuid',
          'A receiving payment link requires a destination account.',
        );
      }
      if (claimTxids.trim().isEmpty) {
        throw ArgumentError.value(
          claimTxids,
          'claimTxids',
          'A receiving payment link requires a claim transaction id.',
        );
      }
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (existing.status == PaymentLinkReceivedStatus.received) {
        return existing;
      }
      final updated = PaymentLinkReceivedRecord(
        network: existing.network,
        address: existing.address,
        amountZatoshi: existing.amountZatoshi,
        createdAt: existing.createdAt,
        artworkId: existing.artworkId,
        status: PaymentLinkReceivedStatus.receiving,
        claimLink: existing.claimLink,
        destinationAccountUuid: destinationAccountUuid.trim(),
        claimTxids: claimTxids.trim(),
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<PaymentLinkReceivedRecord> markReceived({
    required String address,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      final updated = PaymentLinkReceivedRecord(
        network: existing.network,
        address: existing.address,
        amountZatoshi: existing.amountZatoshi,
        createdAt: existing.createdAt,
        artworkId: existing.artworkId,
        status: PaymentLinkReceivedStatus.received,
        claimLink: null,
        destinationAccountUuid: existing.destinationAccountUuid,
        claimTxids: existing.claimTxids,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<PaymentLinkReceivedRecord> markReadyToClaim({
    required String address,
    DateTime? updatedAt,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (existing.claimLink == null) {
        throw StateError(
          'A received payment link without its secret cannot be retried.',
        );
      }
      final updated = PaymentLinkReceivedRecord(
        network: existing.network,
        address: existing.address,
        amountZatoshi: existing.amountZatoshi,
        createdAt: existing.createdAt,
        artworkId: existing.artworkId,
        status: PaymentLinkReceivedStatus.readyToClaim,
        claimLink: existing.claimLink,
        destinationAccountUuid: null,
        claimTxids: null,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<List<PaymentLinkReceivedRecord>> _loadUnlocked() async {
    final raw = await _storage.read();
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const PaymentLinkReceivedStoreFormatException(
          'Received-card payload must be a JSON object.',
        );
      }
      if (decoded['version'] != _storageVersion) {
        throw const PaymentLinkReceivedStoreFormatException(
          'Received-card payload version is not supported.',
        );
      }
      final items = decoded['records'];
      if (items is! List) {
        throw const PaymentLinkReceivedStoreFormatException(
          'Received-card records are missing.',
        );
      }
      return [for (final item in items) _recordFromJson(item)];
    } on PaymentLinkReceivedStoreFormatException {
      rethrow;
    } catch (error) {
      throw PaymentLinkReceivedStoreFormatException(
        'Received-card payload could not be decoded: $error',
      );
    }
  }

  Future<void> _writeRecords(List<PaymentLinkReceivedRecord> records) async {
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

PaymentLinkReceivedRecord? _findByAddress(
  List<PaymentLinkReceivedRecord> records,
  String address,
) {
  for (final record in records) {
    if (record.address == address) return record;
  }
  return null;
}

PaymentLinkReceivedRecord _findRequired(
  List<PaymentLinkReceivedRecord> records,
  String address,
) {
  final record = _findByAddress(records, address);
  if (record == null) {
    throw StateError('Received payment link record was not found.');
  }
  return record;
}

List<PaymentLinkReceivedRecord> _replaceByAddress(
  List<PaymentLinkReceivedRecord> records,
  PaymentLinkReceivedRecord replacement,
) {
  final replaced = <PaymentLinkReceivedRecord>[];
  var didReplace = false;
  for (final record in records) {
    if (record.address == replacement.address) {
      replaced.add(replacement);
      didReplace = true;
    } else {
      replaced.add(record);
    }
  }
  if (!didReplace) replaced.add(replacement);
  return replaced;
}

Map<String, Object?> _recordToJson(PaymentLinkReceivedRecord record) {
  return {
    'network': record.network,
    'address': record.address,
    'amountZatoshi': record.amountZatoshi.toString(),
    'createdAt': record.createdAt.toUtc().toIso8601String(),
    'artworkId': record.artworkId,
    'status': record.status.name,
    'claimLink': record.claimLink?.encode(),
    'destinationAccountUuid': record.destinationAccountUuid,
    'claimTxids': record.claimTxids,
    'updatedAt': record.updatedAt.toUtc().toIso8601String(),
  };
}

PaymentLinkReceivedRecord _recordFromJson(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card record must be a JSON object.',
    );
  }
  final network = value['network'];
  final address = value['address'];
  final amountRaw = value['amountZatoshi'];
  final createdAtRaw = value['createdAt'];
  final artworkId = value['artworkId'];
  final statusRaw = value['status'];
  final claimLinkRaw = value['claimLink'];
  final destinationAccountUuid = value['destinationAccountUuid'];
  final claimTxids = value['claimTxids'];
  final updatedAtRaw = value['updatedAt'];
  if (network is! String ||
      network.isEmpty ||
      address is! String ||
      address.isEmpty ||
      amountRaw is! String ||
      createdAtRaw is! String ||
      (artworkId != null && artworkId is! String) ||
      statusRaw is! String ||
      (claimLinkRaw != null && claimLinkRaw is! String) ||
      (destinationAccountUuid != null && destinationAccountUuid is! String) ||
      (claimTxids != null && claimTxids is! String) ||
      updatedAtRaw is! String) {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card record fields are invalid.',
    );
  }
  final amountZatoshi = BigInt.tryParse(amountRaw);
  final createdAt = DateTime.tryParse(createdAtRaw);
  final updatedAt = DateTime.tryParse(updatedAtRaw);
  if (amountZatoshi == null ||
      amountZatoshi <= BigInt.zero ||
      createdAt == null ||
      updatedAt == null) {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card amount or timestamp is invalid.',
    );
  }
  late final PaymentLinkReceivedStatus status;
  try {
    status = PaymentLinkReceivedStatus.values.byName(statusRaw);
  } on ArgumentError {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card status is invalid.',
    );
  }
  final claimLink =
      claimLinkRaw == null ? null : VizorPaymentLink.decode(claimLinkRaw);
  if (claimLink != null &&
      (claimLink.network != network ||
          claimLink.address != address ||
          claimLink.amountZatoshi != amountZatoshi)) {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card link metadata does not match its record.',
    );
  }
  if (status != PaymentLinkReceivedStatus.received && claimLink == null) {
    throw const PaymentLinkReceivedStoreFormatException(
      'An unfinished received Card must retain its claim link.',
    );
  }
  if (status == PaymentLinkReceivedStatus.received && claimLink != null) {
    throw const PaymentLinkReceivedStoreFormatException(
      'A received Card must not retain its claim link.',
    );
  }
  if (status == PaymentLinkReceivedStatus.receiving &&
      ((destinationAccountUuid as String?)?.trim().isEmpty ?? true)) {
    throw const PaymentLinkReceivedStoreFormatException(
      'A receiving Card must retain its destination account.',
    );
  }
  if (status == PaymentLinkReceivedStatus.receiving &&
      ((claimTxids as String?)?.trim().isEmpty ?? true)) {
    throw const PaymentLinkReceivedStoreFormatException(
      'A receiving Card must retain its claim transaction id.',
    );
  }

  return PaymentLinkReceivedRecord(
    network: network,
    address: address,
    amountZatoshi: amountZatoshi,
    createdAt: createdAt.toUtc(),
    artworkId: artworkId as String?,
    status: status,
    claimLink: claimLink,
    destinationAccountUuid: destinationAccountUuid as String?,
    claimTxids: claimTxids as String?,
    updatedAt: updatedAt.toUtc(),
  );
}
