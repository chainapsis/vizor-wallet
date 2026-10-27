import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../providers/sync_provider.dart';
import '../../migration/providers/ironwood_migration_announcement_provider.dart';

/// What a swap or payment that sends ZEC can spend ([spendable]), and what an
/// ordinary one could ([ordinary]).
typedef SwapFundingBalance = ({BigInt spendable, BigInt ordinary});

/// [SwapFundingBalance] for an account. A swap with a one-time refund address
/// is funded from Ironwood notes only, so its change can carry the refund
/// memo; any other swap can spend
/// [ironwoodMigrationAwareDisplaySpendableProvider].
final swapFundingBalanceProvider = Provider.autoDispose
    .family<SwapFundingBalance, ({String? accountUuid, bool oneTimeRefund})>((
      ref,
      key,
    ) {
      final ordinary = ref.watch(
        ironwoodMigrationAwareDisplaySpendableProvider(key.accountUuid),
      );
      if (!key.oneTimeRefund) return (spendable: ordinary, ordinary: ordinary);
      final ironwood = ref.watch(
        syncProvider.select(
          (value) => (value.value ?? SyncState())
              .scopedToAccount(key.accountUuid)
              .displayIronwoodBalance,
        ),
      );
      return (spendable: ironwood, ordinary: ordinary);
    });

/// Why ZEC that `exceeds` the balance can't fund this swap, when only its
/// Ironwood-only funding is short and an ordinary swap would have had enough.
/// Null otherwise, where "Not enough ZEC" says it. [maskAmount] hides the
/// balance in privacy mode.
String? swapIronwoodOnlyShortfallMessage(
  SwapFundingBalance balance,
  bool Function(BigInt available) exceeds, {
  required bool payment,
  String Function(String amount)? maskAmount,
}) {
  if (!exceeds(balance.spendable) || exceeds(balance.ordinary)) return null;
  final amount = ZecAmount.fromZatoshi(
    balance.spendable,
  ).pretty(denomStyle: ZecDenomStyle.upper).toString();
  final shown = (maskAmount?.call(amount) ?? amount).replaceAll(' ', ' ');
  final subject = payment ? 'Private payments' : 'Private swaps';
  return '$subject use Ironwood ZEC only. You have $shown there.';
}
