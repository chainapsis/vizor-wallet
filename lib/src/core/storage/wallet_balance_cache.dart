import 'dart:convert';

import '../../rust/api/balance_cache.dart' as rust_cache;
import '../../rust/api/sync.dart' as rust_sync;

/// A previous accepted read, for display only. Restoring this never establishes
/// current spendability, sync completion, or transparent authority.
class CachedWalletBalance {
  const CachedWalletBalance(this.balance, this.savedAt);

  final rust_sync.WalletBalance balance;
  final DateTime savedAt;

  String encode() => jsonEncode({
    'version': 1,
    'savedAt': savedAt.millisecondsSinceEpoch,
    'transparentAuthority': balance.transparentAuthority.name,
    'transparentLastKnown': balance.transparentLastKnown?.toString(),
    'transparentStop': balance.transparentStop?.name,
    'transparentPrivate': balance.transparentPrivate,
    'transparent': balance.transparent.toString(),
    'sapling': balance.sapling.toString(),
    'orchard': balance.orchard.toString(),
    'ironwood': balance.ironwood.toString(),
    'transparentLocked': balance.transparentLocked.toString(),
    'saplingLocked': balance.saplingLocked.toString(),
    'orchardLocked': balance.orchardLocked.toString(),
    'ironwoodLocked': balance.ironwoodLocked.toString(),
    'transparentPending': balance.transparentPending.toString(),
    'saplingPending': balance.saplingPending.toString(),
    'orchardPending': balance.orchardPending.toString(),
    'ironwoodPending': balance.ironwoodPending.toString(),
    'changePendingConfirmation': balance.changePendingConfirmation.toString(),
    'valuePendingSpendability': balance.valuePendingSpendability.toString(),
    'uneconomicValue': balance.uneconomicValue.toString(),
    'spendable': balance.spendable.toString(),
    'locked': balance.locked.toString(),
    'total': balance.total.toString(),
  });

  static CachedWalletBalance? decode(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (data['version'] != 1) return null;
      BigInt amount(String key) {
        final value = BigInt.parse(data[key] as String);
        if (value.isNegative || value > BigInt.from(2100000000000000)) {
          throw const FormatException('Invalid cached amount');
        }
        return value;
      }

      final balance = rust_sync.WalletBalance(
        availability: rust_sync.WalletBalanceAvailability.available,
        transparentAuthority: rust_sync.TransparentBalanceAuthority.values
            .byName(data['transparentAuthority'] as String),
        transparentLastKnown: data['transparentLastKnown'] == null
            ? null
            : amount('transparentLastKnown'),
        transparentStop: data['transparentStop'] == null
            ? null
            : rust_sync.TransparentStopReason.values.byName(
                data['transparentStop'] as String,
              ),
        transparentPrivate: data['transparentPrivate'] as bool,
        transparent: amount('transparent'),
        sapling: amount('sapling'),
        orchard: amount('orchard'),
        ironwood: amount('ironwood'),
        transparentLocked: amount('transparentLocked'),
        saplingLocked: amount('saplingLocked'),
        orchardLocked: amount('orchardLocked'),
        ironwoodLocked: amount('ironwoodLocked'),
        transparentPending: amount('transparentPending'),
        saplingPending: amount('saplingPending'),
        orchardPending: amount('orchardPending'),
        ironwoodPending: amount('ironwoodPending'),
        changePendingConfirmation: amount('changePendingConfirmation'),
        valuePendingSpendability: amount('valuePendingSpendability'),
        uneconomicValue: amount('uneconomicValue'),
        spendable: amount('spendable'),
        locked: amount('locked'),
        total: amount('total'),
      );
      return CachedWalletBalance(
        balance,
        DateTime.fromMillisecondsSinceEpoch(
          data['savedAt'] as int,
          isUtc: true,
        ),
      );
    } catch (_) {
      // A cache from a future version or a damaged row must not block unlock.
      return null;
    }
  }
}

Future<CachedWalletBalance?> readCachedWalletBalance({
  required String dbPath,
  required String network,
  required String accountUuid,
}) async {
  final payload = await rust_cache.loadBalanceCache(
    dbPath: dbPath,
    network: network,
    accountUuid: accountUuid,
  );
  return payload == null ? null : CachedWalletBalance.decode(payload);
}
