import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_lifecycle_revision.dart';

const _storageVersion = 1;
const _fieldNotProvided = Object();

final paymentLinkReceivedStoreProvider = Provider<PaymentLinkReceivedStore>((
  ref,
) {
  return PaymentLinkReceivedStore(
    AppSecureStorePaymentLinkReceivedStorage(AppSecureStore.instance),
    countMirror: AppSecureStorePaymentLinkClaimCountMirror(
      AppSecureStore.instance,
    ),
    onRecordsChanged: () {
      ref.read(paymentLinkLifecycleRevisionProvider.notifier).bump();
    },
  );
});

final paymentLinkReceivingCountProvider = FutureProvider.family<int, String>((
  ref,
  destinationAccountUuid,
) {
  ref.watch(paymentLinkLifecycleRevisionProvider);
  return ref
      .watch(paymentLinkReceivedStoreProvider)
      .countReceivingForAccount(destinationAccountUuid);
});

/// Gift Card claims that are mid-flight across every account.
///
/// A wallet reset drains claims instead of refusing them, so a claim that
/// finishes during the drain settles into a wallet that is about to be wiped.
/// The reset and uninstall confirmations read this to warn about that window
/// before the user commits; a non-zero count means funds are still moving.
final paymentLinkClaimsInFlightProvider = FutureProvider<int>((ref) {
  ref.watch(paymentLinkLifecycleRevisionProvider);
  return ref.watch(paymentLinkReceivedStoreProvider).countClaimsInFlight();
});

enum PaymentLinkReceivedStatus { readyToClaim, submitting, receiving, received }

/// Availability is separate from the lifetime of our submitted transaction.
enum PaymentLinkAvailability {
  unchecked,
  available,
  noBalance,
  claimedElsewhere,
  checking,
  rejected,
  failed,
}

class PaymentLinkInFlightClaimsException implements Exception {
  const PaymentLinkInFlightClaimsException({
    required this.destinationAccountUuid,
    required this.count,
  });

  final String destinationAccountUuid;
  final int count;

  @override
  String toString() =>
      'Wait for incoming gift cards to finish before deleting this account.';
}

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
    this.message,
    this.fiatSnapshot,
    this.claimSubmittedAt,
    this.claimDestinationPool,
    this.availability = PaymentLinkAvailability.unchecked,
    this.archived = false,
    this.claimPriorTxids = const [],
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
      message: link.presentation?.message,
      fiatSnapshot: link.presentation?.fiatSnapshot,
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
  final String? message;
  final PaymentLinkFiatSnapshot? fiatSnapshot;
  final PaymentLinkReceivedStatus status;

  /// The bearer secret is retained only while the Card can still require a
  /// retry. Receipt display completes at one confirmation; the secret remains
  /// until six verified confirmations so a shallow reorg can still recover.
  final VizorPaymentLink? claimLink;
  final String? destinationAccountUuid;

  /// Comma-separated protocol/storage-order IDs, matching TransactionInfo.
  /// Broadcast IDs are converted before saving; recovery history is already
  /// in this order. This unreleased contract has no byte-order fallback.
  final String? claimTxids;
  final DateTime updatedAt;

  /// Stable user-visible claim time; reconciliation only updates [updatedAt].
  /// Null only before submission. Gift Cards are unreleased, so old records
  /// without this timestamp are rejected instead of using reconciliation time.
  final DateTime? claimSubmittedAt;

  /// Pool of the claim output addressed to the destination account.
  final String? claimDestinationPool;
  final PaymentLinkAvailability availability;
  final bool archived;

  /// Local transactions that predate this attempt, excluded from recovery.
  /// Null means an older record has no baseline; [] is a known empty baseline.
  final List<String>? claimPriorTxids;

  bool get canArchive =>
      !isClaimInFlight &&
      (availability == PaymentLinkAvailability.noBalance ||
          availability == PaymentLinkAvailability.claimedElsewhere ||
          availability == PaymentLinkAvailability.failed);

  bool get isClaimInFlight =>
      status == PaymentLinkReceivedStatus.submitting ||
      status == PaymentLinkReceivedStatus.receiving;

  /// Completed receipts can still need background reorg recovery and cleanup.
  bool get needsClaimRecovery =>
      isClaimInFlight ||
      claimLink != null && status == PaymentLinkReceivedStatus.received;

  bool get needsClaimMetadataRecovery =>
      status == PaymentLinkReceivedStatus.submitting;

  PaymentLinkReceivedRecord copyWith({
    PaymentLinkReceivedStatus? status,
    Object? claimLink = _fieldNotProvided,
    Object? destinationAccountUuid = _fieldNotProvided,
    Object? claimTxids = _fieldNotProvided,
    DateTime? updatedAt,
    DateTime? claimSubmittedAt,
    String? claimDestinationPool,
    PaymentLinkAvailability? availability,
    bool? archived,
    Object? claimPriorTxids = _fieldNotProvided,
  }) {
    return PaymentLinkReceivedRecord(
      network: network,
      address: address,
      amountZatoshi: amountZatoshi,
      createdAt: createdAt,
      artworkId: artworkId,
      message: message,
      fiatSnapshot: fiatSnapshot,
      status: status ?? this.status,
      claimLink: identical(claimLink, _fieldNotProvided)
          ? this.claimLink
          : claimLink as VizorPaymentLink?,
      destinationAccountUuid:
          identical(destinationAccountUuid, _fieldNotProvided)
          ? this.destinationAccountUuid
          : destinationAccountUuid as String?,
      claimTxids: identical(claimTxids, _fieldNotProvided)
          ? this.claimTxids
          : claimTxids as String?,
      updatedAt: (updatedAt ?? this.updatedAt).toUtc(),
      claimSubmittedAt: claimSubmittedAt ?? this.claimSubmittedAt,
      claimDestinationPool: claimDestinationPool ?? this.claimDestinationPool,
      availability: availability ?? this.availability,
      archived: archived ?? this.archived,
      claimPriorTxids: identical(claimPriorTxids, _fieldNotProvided)
          ? this.claimPriorTxids
          : claimPriorTxids as List<String>?,
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

/// Locked-readable copy of the in-flight claim count. The records are a
/// secret the locked app cannot read, but the reset screens exist only while
/// locked and need this one number.
abstract interface class PaymentLinkClaimCountMirror {
  Future<int?> read();

  Future<void> write(int count);
}

class AppSecureStorePaymentLinkClaimCountMirror
    implements PaymentLinkClaimCountMirror {
  const AppSecureStorePaymentLinkClaimCountMirror(this._store);

  final AppSecureStore _store;

  @override
  Future<int?> read() async {
    final raw = await _store.readPlain(kPaymentLinkClaimsInFlightCountKey);
    return raw == null ? null : int.tryParse(raw);
  }

  @override
  Future<void> write(int count) {
    return _store.writePlain(kPaymentLinkClaimsInFlightCountKey, '$count');
  }
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
  PaymentLinkReceivedStore(
    this._storage, {
    PaymentLinkClaimCountMirror? countMirror,
    void Function()? onRecordsChanged,
  }) : _countMirror = countMirror,
       _onRecordsChanged = onRecordsChanged;

  final PaymentLinkClaimCountMirror? _countMirror;

  final PaymentLinkReceivedStorage _storage;
  final void Function()? _onRecordsChanged;
  Future<void> _operationTail = Future<void>.value();

  Future<List<PaymentLinkReceivedRecord>> load() {
    return _runExclusive(_loadUnlocked);
  }

  Future<PaymentLinkReceivedRecord?> find(String address) {
    return _runExclusive(() async {
      return _findByAddress(await _loadUnlocked(), address);
    });
  }

  /// Claims that have been submitted but not yet observed as received, across
  /// every destination account. Receipt completes at one confirmation; retained
  /// reorg recovery must not extend the account-removal or reset guard.
  /// Includes records whose destination account
  /// is not yet written, which [countReceivingForAccount] cannot see.
  Future<int> countClaimsInFlight() {
    return _runExclusive(() async {
      final raw = await _storage.read();
      // Locked: the secret payload reads as null; the plain mirror answers.
      if (raw == null) return await _countMirror?.read() ?? 0;
      return _decodeRecords(raw).where((r) => r.isClaimInFlight).length;
    });
  }

  Future<int> countReceivingForAccount(String destinationAccountUuid) async {
    if (destinationAccountUuid.isEmpty) return 0;
    final records = await load();
    return records
        .where(
          (record) =>
              record.isClaimInFlight &&
              record.destinationAccountUuid == destinationAccountUuid,
        )
        .length;
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
        message: link.presentation?.message,
        fiatSnapshot: link.presentation?.fiatSnapshot,
        status: existing?.status ?? PaymentLinkReceivedStatus.readyToClaim,
        claimLink: link,
        destinationAccountUuid: existing?.destinationAccountUuid,
        claimTxids: existing?.claimTxids,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        claimSubmittedAt: existing?.claimSubmittedAt,
        claimDestinationPool: existing?.claimDestinationPool,
        availability:
            existing?.availability ?? PaymentLinkAvailability.unchecked,
        archived: existing?.archived ?? false,
        claimPriorTxids: existing == null ? const [] : existing.claimPriorTxids,
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
    DateTime? claimSubmittedAt,
    String? claimDestinationPool,
    PaymentLinkReceivedRecord? expected,
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
      if (expected != null &&
          (existing.status != expected.status ||
              existing.claimTxids != expected.claimTxids ||
              existing.claimSubmittedAt != expected.claimSubmittedAt ||
              existing.destinationAccountUuid !=
                  expected.destinationAccountUuid)) {
        return existing;
      }

      if (existing.status == PaymentLinkReceivedStatus.received &&
          existing.claimLink == null) {
        return existing;
      }
      final submissionTime = claimSubmittedAt ?? existing.claimSubmittedAt;
      if (submissionTime == null) {
        throw StateError(
          'A receiving Card requires its claim submission time.',
        );
      }
      final updated = PaymentLinkReceivedRecord(
        network: existing.network,
        address: existing.address,
        amountZatoshi: existing.amountZatoshi,
        createdAt: existing.createdAt,
        artworkId: existing.artworkId,
        message: existing.message,
        fiatSnapshot: existing.fiatSnapshot,
        status: PaymentLinkReceivedStatus.receiving,
        claimLink: existing.claimLink,
        destinationAccountUuid: destinationAccountUuid.trim(),
        claimTxids: claimTxids.trim(),
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        claimSubmittedAt: submissionTime.toUtc(),
        claimDestinationPool:
            claimDestinationPool ?? existing.claimDestinationPool,
        availability: PaymentLinkAvailability.available,
        archived: existing.archived,
        claimPriorTxids: existing.claimPriorTxids,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<PaymentLinkReceivedRecord> markClaimStarted({
    required String address,
    required String destinationAccountUuid,
    DateTime? updatedAt,
    List<String> priorTxids = const [],
  }) {
    return _runExclusive(() async {
      final normalizedAccountUuid = destinationAccountUuid.trim();
      if (normalizedAccountUuid.isEmpty) {
        throw ArgumentError.value(
          destinationAccountUuid,
          'destinationAccountUuid',
          'A started payment link claim requires a destination account.',
        );
      }
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (existing.status == PaymentLinkReceivedStatus.received) {
        return existing;
      }
      if (existing.status != PaymentLinkReceivedStatus.readyToClaim ||
          existing.claimLink == null) {
        throw StateError('Only a ready Gift Card claim can be started.');
      }
      final submissionTime = (updatedAt ?? DateTime.now()).toUtc();
      final updated = existing.copyWith(
        status: PaymentLinkReceivedStatus.submitting,
        availability: PaymentLinkAvailability.checking,
        archived: false,
        claimPriorTxids: List<String>.unmodifiable(priorTxids),
        destinationAccountUuid: normalizedAccountUuid,
        claimTxids: null,
        updatedAt: submissionTime,
        claimSubmittedAt: submissionTime,
        claimDestinationPool: null,
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
        message: existing.message,
        fiatSnapshot: existing.fiatSnapshot,
        status: PaymentLinkReceivedStatus.received,
        claimLink: existing.claimLink,
        destinationAccountUuid: existing.destinationAccountUuid,
        claimTxids: existing.claimTxids,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        claimSubmittedAt: existing.claimSubmittedAt,
        claimDestinationPool: existing.claimDestinationPool,
        availability: existing.availability,
        archived: existing.archived,
        claimPriorTxids: existing.claimPriorTxids,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  /// Enriches claim metadata without restarting an already received claim.
  Future<PaymentLinkReceivedRecord> updateClaimDestinationPool({
    required String address,
    required String claimDestinationPool,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (existing.status != PaymentLinkReceivedStatus.receiving &&
          existing.status != PaymentLinkReceivedStatus.received) {
        throw StateError(
          'Only a submitted claim can update its destination pool.',
        );
      }
      final pool = claimDestinationPool.trim();
      if (pool.isEmpty) throw ArgumentError.value(claimDestinationPool);
      final updated = existing.copyWith(claimDestinationPool: pool);
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<PaymentLinkReceivedRecord> clearConfirmedClaimSecret({
    required String address,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (existing.status != PaymentLinkReceivedStatus.received) {
        throw StateError('Only a received Card can finish claim recovery.');
      }
      final updated = existing.copyWith(claimLink: null);
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<PaymentLinkReceivedRecord> markReadyToClaim({
    required String address,
    DateTime? updatedAt,
    PaymentLinkReceivedRecord? expected,
    PaymentLinkAvailability availability = PaymentLinkAvailability.failed,
  }) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      // A concurrent check may finish after another check settled this attempt
      // and the user started a new one. Never settle that newer attempt.
      if (expected != null &&
          (existing.status != expected.status ||
              existing.claimTxids != expected.claimTxids ||
              existing.claimSubmittedAt != expected.claimSubmittedAt ||
              existing.destinationAccountUuid !=
                  expected.destinationAccountUuid)) {
        return existing;
      }

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
        message: existing.message,
        fiatSnapshot: existing.fiatSnapshot,
        status: PaymentLinkReceivedStatus.readyToClaim,
        availability: availability,
        archived: existing.archived,
        claimLink: existing.claimLink,
        destinationAccountUuid: null,
        claimTxids: null,
        updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
        claimSubmittedAt: null,
        claimDestinationPool: null,
      );
      await _writeRecords(_replaceByAddress(records, updated));
      return updated;
    });
  }

  Future<void> setAvailability(
    String address,
    PaymentLinkAvailability availability,
  ) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findByAddress(records, address);
      if (existing == null ||
          existing.status == PaymentLinkReceivedStatus.received) {
        return;
      }
      // A preview arriving late cannot overwrite an in-flight submission.
      if (existing.isClaimInFlight &&
          availability != PaymentLinkAvailability.checking &&
          availability != PaymentLinkAvailability.rejected) {
        return;
      }
      await _writeRecords(
        _replaceByAddress(
          records,
          existing.copyWith(availability: availability),
        ),
      );
    });
  }

  Future<void> setArchived(String address, bool archived) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final existing = _findRequired(records, address);
      if (archived && !existing.canArchive) {
        throw StateError('Only inactive gift cards can be hidden.');
      }
      await _writeRecords(
        _replaceByAddress(records, existing.copyWith(archived: archived)),
      );
    });
  }

  /// Forgets a Card the caller has established can never be claimed again.
  Future<void> remove(String address) {
    return _runExclusive(() async {
      final records = await _loadUnlocked();
      final remaining = records
          .where((record) => record.address != address)
          .toList();
      if (remaining.length == records.length) return;
      await _writeRecords(remaining);
    });
  }

  Future<List<PaymentLinkReceivedRecord>> _loadUnlocked() async {
    return _decodeRecords(await _storage.read());
  }

  List<PaymentLinkReceivedRecord> _decodeRecords(String? raw) {
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
    } else {
      await _storage.write(
        jsonEncode({
          'version': _storageVersion,
          'records': [for (final record in records) _recordToJson(record)],
        }),
      );
    }
    await _countMirror?.write(
      records.where((record) => record.isClaimInFlight).length,
    );
    _onRecordsChanged?.call();
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
    'message': record.message,
    'fiat': record.fiatSnapshot?.toPayload(),
    'status': record.status.name,
    'availability': record.availability.name,
    'archived': record.archived,
    'claimPriorTxids': record.claimPriorTxids,
    'claimLink': record.claimLink?.toUri().toString(),
    'destinationAccountUuid': record.destinationAccountUuid,
    'claimTxids': record.claimTxids,
    'updatedAt': record.updatedAt.toUtc().toIso8601String(),
    'claimSubmittedAt': record.claimSubmittedAt?.toUtc().toIso8601String(),
    'claimDestinationPool': record.claimDestinationPool,
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
  final message = value['message'];
  final statusRaw = value['status'];
  final availabilityRaw = value['availability'];
  final archivedRaw = value['archived'];
  final priorTxidsRaw = value['claimPriorTxids'];
  final claimLinkRaw = value['claimLink'];
  final destinationAccountUuid = value['destinationAccountUuid'];
  final claimTxids = value['claimTxids'];
  final updatedAtRaw = value['updatedAt'];
  final claimSubmittedAtRaw = value['claimSubmittedAt'];
  final claimDestinationPool = value['claimDestinationPool'];
  if (network is! String ||
      network.isEmpty ||
      address is! String ||
      address.isEmpty ||
      amountRaw is! String ||
      createdAtRaw is! String ||
      (artworkId != null && artworkId is! String) ||
      (message != null && message is! String) ||
      statusRaw is! String ||
      (claimLinkRaw != null && claimLinkRaw is! String) ||
      (destinationAccountUuid != null && destinationAccountUuid is! String) ||
      (claimTxids != null && claimTxids is! String) ||
      updatedAtRaw is! String ||
      (claimSubmittedAtRaw != null && claimSubmittedAtRaw is! String) ||
      (claimDestinationPool != null && claimDestinationPool is! String)) {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card record fields are invalid.',
    );
  }
  final amountZatoshi = BigInt.tryParse(amountRaw);
  final createdAt = DateTime.tryParse(createdAtRaw);
  final updatedAt = DateTime.tryParse(updatedAtRaw);
  final claimSubmittedAt = claimSubmittedAtRaw == null
      ? null
      : DateTime.tryParse(claimSubmittedAtRaw);
  if (amountZatoshi == null ||
      amountZatoshi <= BigInt.zero ||
      createdAt == null ||
      updatedAt == null) {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card amount or timestamp is invalid.',
    );
  }
  if (claimSubmittedAtRaw != null && claimSubmittedAt == null) {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card claim submission timestamp is invalid.',
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
  if (status != PaymentLinkReceivedStatus.readyToClaim &&
      claimSubmittedAt == null) {
    throw const PaymentLinkReceivedStoreFormatException(
      'A submitted Card must retain its claim submission timestamp.',
    );
  }
  final claimLink = claimLinkRaw == null
      ? null
      : VizorPaymentLink.parse(claimLinkRaw);
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
  if (status == PaymentLinkReceivedStatus.submitting &&
      ((destinationAccountUuid as String?)?.trim().isEmpty ?? true)) {
    throw const PaymentLinkReceivedStoreFormatException(
      'A submitting Card must retain its destination account.',
    );
  }
  if (status == PaymentLinkReceivedStatus.submitting && claimTxids != null) {
    throw const PaymentLinkReceivedStoreFormatException(
      'A submitting Card cannot retain claim transaction ids.',
    );
  }
  if (status == PaymentLinkReceivedStatus.readyToClaim &&
      (destinationAccountUuid != null || claimTxids != null)) {
    throw const PaymentLinkReceivedStoreFormatException(
      'A ready Card cannot retain in-flight claim metadata.',
    );
  }

  // Missing or null new fields are supported for older development records.
  // Present but malformed values still fail the entire read rather than
  // silently changing a claim's recovery or visibility semantics.
  if ((availabilityRaw != null && availabilityRaw is! String) ||
      (archivedRaw != null && archivedRaw is! bool) ||
      (priorTxidsRaw != null &&
          (priorTxidsRaw is! List ||
              priorTxidsRaw.any((id) => id is! String)))) {
    throw const PaymentLinkReceivedStoreFormatException(
      'Received-card outcome fields are invalid.',
    );
  }
  final availability = availabilityRaw == null
      ? switch (status) {
          PaymentLinkReceivedStatus.readyToClaim =>
            PaymentLinkAvailability.unchecked,
          PaymentLinkReceivedStatus.submitting =>
            PaymentLinkAvailability.checking,
          PaymentLinkReceivedStatus.receiving ||
          PaymentLinkReceivedStatus.received =>
            PaymentLinkAvailability.available,
        }
      : PaymentLinkAvailability.values.byName(availabilityRaw as String);

  return PaymentLinkReceivedRecord(
    network: network,
    address: address,
    amountZatoshi: amountZatoshi,
    createdAt: createdAt.toUtc(),
    artworkId: artworkId as String?,
    message: message as String?,
    fiatSnapshot: PaymentLinkFiatSnapshot.fromPayload(value['fiat']),
    status: status,
    availability: availability,
    archived: (archivedRaw as bool?) ?? false,
    claimPriorTxids: priorTxidsRaw == null
        ? null
        : List<String>.unmodifiable((priorTxidsRaw as List).cast<String>()),
    claimLink: claimLink,
    destinationAccountUuid: destinationAccountUuid as String?,
    claimTxids: claimTxids as String?,
    updatedAt: updatedAt.toUtc(),
    claimSubmittedAt: claimSubmittedAt?.toUtc(),
    claimDestinationPool: claimDestinationPool as String?,
  );
}
