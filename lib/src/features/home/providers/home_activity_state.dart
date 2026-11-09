import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/sync_provider.dart';

enum HomeActivityState { rows, loading, unavailable, empty }

/// Loading belongs to the account's local reads, independently of its balance
/// or network sync. Existing rows and retained source values stay visible.
HomeActivityState homeActivityState({
  required String? accountUuid,
  required SyncState sync,
  required bool hasRows,
  required List<AsyncValue<Object?>> localSources,
}) {
  if (hasRows) return HomeActivityState.rows;
  if (accountUuid == null) return HomeActivityState.empty;
  if (sync.hasRecentTransactionsError ||
      localSources.any((source) => source.hasError && !source.hasValue)) {
    return HomeActivityState.unavailable;
  }
  if (!sync.hasRecentTransactionsData ||
      localSources.any((source) => source.isLoading && !source.hasValue)) {
    return HomeActivityState.loading;
  }
  return HomeActivityState.empty;
}
