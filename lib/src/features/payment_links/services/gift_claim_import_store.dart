import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/vizor_payment_link.dart';

final giftClaimImportStoreProvider = Provider((ref) => GiftClaimImportStore());

class GiftClaimImportHandoff {
  const GiftClaimImportHandoff({
    required this.link,
    required this.accountUuidsBeforeSetup,
  });

  final VizorPaymentLink link;
  final Set<String> accountUuidsBeforeSetup;

  Set<String> importedAccountUuids(Iterable<String> currentAccountUuids) =>
      currentAccountUuids
          .where((uuid) => !accountUuidsBeforeSetup.contains(uuid))
          .toSet();

  String? recipientAccountUuid({
    required Iterable<String> currentAccountUuids,
  }) {
    // An active account is only a UI default, not consent to receive a gift.
    final added = importedAccountUuids(currentAccountUuids);
    return added.length == 1 ? added.single : null;
  }
}

/// Before a wallet password exists, the bearer link is protected by the OS
/// secure store. After import it moves to the password-encrypted Received store.
/// Keep this journal until that destination binding has been durably saved.
abstract interface class GiftClaimImportStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class _SecureImportStorage implements GiftClaimImportStorage {
  @override
  Future<String?> read() =>
      AppSecureStore.instance.readPlain(kGiftClaimImportHandoffStorageKey);
  @override
  Future<void> write(String value) => AppSecureStore.instance.writePlain(
    kGiftClaimImportHandoffStorageKey,
    value,
  );
  @override
  Future<void> delete() =>
      AppSecureStore.instance.delete(kGiftClaimImportHandoffStorageKey);
}

class GiftClaimImportStore {
  GiftClaimImportStore({GiftClaimImportStorage? storage})
    : _storage = storage ?? _SecureImportStorage();

  final GiftClaimImportStorage _storage;
  Future<void> _tail = Future<void>.value();
  bool hasLiveHandoff = false;
  bool _loaded = false;
  GiftClaimImportHandoff? _cached;

  bool hasLiveHandoffFor(VizorPaymentLink link) =>
      hasLiveHandoff && _cached?.link.hasSameCanonicalPayload(link) == true;

  Future<T> _exclusive<T>(Future<T> Function() run) {
    final result = _tail.then((_) => run());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> save(GiftClaimImportHandoff handoff) => _exclusive(() async {
    await _storage.write(
      jsonEncode({
        'link': handoff.link.toUri().toString(),
        'address': handoff.link.address,
        'createdAt': handoff.link.createdAt.toUtc().toIso8601String(),
        'isCreatedAtProvisional': handoff.link.isCreatedAtProvisional,
        'accountsBeforeSetup': handoff.accountUuidsBeforeSetup.toList(),
      }),
    );
    // The live caller owns the existing inspection. Restart recovery may scan
    // again; normal setup must not race it and perform an additional scan.
    _loaded = true;
    _cached = handoff;
    hasLiveHandoff = true;
  });

  Future<GiftClaimImportHandoff?> load() => _exclusive(_load);

  Future<GiftClaimImportHandoff?> _load() async {
    if (_loaded) return _cached;
    final raw = await _storage.read();
    if (raw == null) {
      _loaded = true;
      return null;
    }
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final handoff = GiftClaimImportHandoff(
        link: VizorPaymentLink.parse(value['link'] as String)
            .withResolvedMetadata(
              address: value['address'] as String,
              createdAt: DateTime.parse(value['createdAt'] as String),
              isCreatedAtProvisional: value['isCreatedAtProvisional'] as bool,
            ),
        accountUuidsBeforeSetup: Set.unmodifiable(
          (value['accountsBeforeSetup'] as List).cast<String>(),
        ),
      );
      _cached = handoff;
      _loaded = true;
      return handoff;
    } catch (_) {
      // Recovery logs the exception. Never echo a malformed bearer payload.
      throw const FormatException('Invalid stored gift import handoff.');
    }
  }

  Future<void> clear(GiftClaimImportHandoff handoff) => _exclusive(() async {
    final saved = await _load();
    if (saved == null || !saved.link.hasSameCanonicalPayload(handoff.link)) {
      return;
    }
    await _storage.delete();
    _cached = null;
    _loaded = true;
    hasLiveHandoff = false;
  });

  /// Cancellation and transfer share the same queue. A recovery that loaded a
  /// handoff before removal must recheck it before recreating the Received card.
  Future<void> transferToReceived(
    GiftClaimImportHandoff expected,
    Future<bool> Function() saveReceived,
  ) => _exclusive(() async {
    final saved = await _load();
    if (hasLiveHandoff ||
        saved == null ||
        !saved.link.hasSameCanonicalPayload(expected.link)) {
      return;
    }
    if (!await saveReceived()) return;
    await _storage.delete();
    _cached = null;
    _loaded = true;
  });

  Future<void> clearForAddress(String address) => _exclusive(() async {
    GiftClaimImportHandoff? saved;
    try {
      saved = await _load();
    } on FormatException {
      // An unreadable journal cannot resurrect this card; retain it separately.
      return;
    }
    if (saved?.link.address != address) return;
    await _storage.delete();
    _cached = null;
    _loaded = true;
    hasLiveHandoff = false;
  });

  void releaseLiveHandoff() => hasLiveHandoff = false;

  void resetMemory() {
    _cached = null;
    _loaded = false;
    hasLiveHandoff = false;
  }
}
