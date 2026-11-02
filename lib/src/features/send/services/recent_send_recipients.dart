import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../../../providers/account_models.dart';

/// An address the account sent ZEC to from the Send flow on this device,
/// shown under "Recents" in the mobile Send recipient step.
class SendRecentRecipient {
  const SendRecentRecipient({required this.address, required this.isShielded});

  final String address;
  final bool isShielded;
}

const kSendRecentRecipientLimit = 5;

// Headroom for the active account's own addresses, hidden when read.
const _storedRecipientLimit = 20;

const _storageKey = 'zcash_send_recent_recipients_v1';
const _storageVersion = 1;

String _storageKeyFor(String accountUuid) => '$_storageKey:$accountUuid';

/// Recipients the Send flow records after a completed broadcast, newest
/// first and one row per address.
///
/// Only that flow writes here, so swap, Pay and Gift Card one-time addresses
/// never become recents. Account removal deletes an account's list and a
/// wallet reset clears the whole store.
abstract interface class SendRecentRecipientStore {
  Future<List<SendRecentRecipient>> load({required String accountUuid});

  Future<void> record({
    required String accountUuid,
    required SendRecentRecipient recipient,
  });

  Future<void> deleteForAccount({required String accountUuid});
}

final sendRecentRecipientStoreProvider = Provider<SendRecentRecipientStore>(
  (ref) => AppSecureStoreSendRecentRecipientStore(AppSecureStore.instance),
);

class SendRecentRecipientsRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state++;
  }
}

final sendRecentRecipientsRevisionProvider =
    NotifierProvider<SendRecentRecipientsRevisionNotifier, int>(
      SendRecentRecipientsRevisionNotifier.new,
    );

/// Stored recent recipients of [accountUuid], newest first. Show them through
/// [visibleSendRecentRecipients].
final recentSendRecipientsProvider = FutureProvider.autoDispose
    .family<List<SendRecentRecipient>, String>((ref, accountUuid) {
      ref.watch(sendRecentRecipientsRevisionProvider);
      return ref
          .read(sendRecentRecipientStoreProvider)
          .load(accountUuid: accountUuid);
    });

/// The first [kSendRecentRecipientLimit] of [stored] that are not addresses
/// of [accountUuid] itself.
///
/// [ownAccounts] is applied when it arrives rather than awaited, since
/// looking up every account's addresses would hold back the whole list.
List<SendRecentRecipient> visibleSendRecentRecipients({
  required List<SendRecentRecipient> stored,
  required String accountUuid,
  required Map<String, AccountInfo> ownAccounts,
}) => stored
    .where((recent) => ownAccounts[recent.address]?.uuid != accountUuid)
    .take(kSendRecentRecipientLimit)
    .toList(growable: false);

class AppSecureStoreSendRecentRecipientStore
    implements SendRecentRecipientStore {
  AppSecureStoreSendRecentRecipientStore(this._storage);

  final AppSecureStore _storage;

  // Serializes read-modify-write so concurrent records do not drop a row.
  Future<void> _pending = Future.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<List<SendRecentRecipient>> load({required String accountUuid}) =>
      _serialized(() async => (await _read(accountUuid)) ?? const []);

  @override
  Future<void> record({
    required String accountUuid,
    required SendRecentRecipient recipient,
  }) => _serialized(() async {
    final address = recipient.address.trim();
    if (address.isEmpty) return;
    final current = await _read(accountUuid);
    // A newer version's list is left for that version to read.
    if (current == null) return;
    final next = [
      SendRecentRecipient(address: address, isShielded: recipient.isShielded),
      for (final existing in current)
        if (existing.address != address) existing,
    ].take(_storedRecipientLimit);
    await _storage.writeString(
      _storageKeyFor(accountUuid),
      jsonEncode({
        'version': _storageVersion,
        'recipients': [
          for (final recent in next)
            {'address': recent.address, 'shielded': recent.isShielded},
        ],
      }),
    );
  });

  @override
  Future<void> deleteForAccount({required String accountUuid}) =>
      _serialized(() => _storage.delete(_storageKeyFor(accountUuid)));

  /// The stored list, empty when absent or unreadable, or null when a newer
  /// version wrote it.
  Future<List<SendRecentRecipient>?> _read(String accountUuid) async {
    final raw = await _storage.readString(_storageKeyFor(accountUuid));
    if (raw == null || raw.trim().isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map) return const [];
    final version = decoded['version'];
    if (version is int && version > _storageVersion) return null;
    final items = decoded['recipients'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item case {
          'address': final String address,
          'shielded': final bool shielded,
        } when address.trim().isNotEmpty)
          SendRecentRecipient(address: address.trim(), isShielded: shielded),
    ];
  }
}

@visibleForTesting
String sendRecentRecipientStorageKeyForTest(String accountUuid) =>
    _storageKeyFor(accountUuid);
