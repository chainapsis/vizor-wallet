import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../migration/providers/ironwood_migration_announcement_provider.dart';
import '../services/account_balance_breakdown.dart';

/// The active account's [AccountBalanceBreakdown], under the pool selection
/// Home's balance card uses.
final activeAccountBalanceBreakdownProvider = Provider<AccountBalanceBreakdown>(
  (ref) {
    final accountUuid = ref.watch(
      accountProvider.select((value) => value.value?.activeAccountUuid),
    );
    final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    return AccountBalanceBreakdown.of(
      sync,
      ironwoodOnly:
          ref.watch(ironwoodHomeBalancePresentationProvider) ==
          IronwoodHomeBalancePresentationMode.ironwoodOnly,
    );
  },
);
