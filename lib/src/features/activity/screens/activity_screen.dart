import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/swap_feature_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../swap/models/swap_activity_navigation.dart';
import '../../swap/providers/swap_activity_tracker.dart';
import '../activity_row_mapper.dart';
import '../models/activity_row_data.dart';
import '../swap_activity_row_items_provider.dart';
import '../swap_activity_row_mapper.dart';
import '../widgets/activity_feed.dart';
import 'activity_transaction_status_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  List<rust_sync.TransactionInfo>? _transactions;
  String? _transactionsAccountUuid;
  bool _isLoading = true;
  String? _error;
  String? _activeAccountUuid;
  int _transactionLoadGeneration = 0;
  bool _pendingTransactionRefresh = false;
  Timer? _swapActivityRefreshTimer;
  String? _swapActivityRefreshAccountUuid;

  @override
  void initState() {
    super.initState();
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _loadTransactions(showLoading: true, clearExisting: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      _syncSwapActivityStatusRefresh();
    });
  }

  @override
  void dispose() {
    _swapActivityRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTransactions({
    bool showLoading = false,
    bool clearExisting = false,
  }) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final generation = ++_transactionLoadGeneration;
    _pendingTransactionRefresh = false;
    _activeAccountUuid = accountUuid;

    if ((showLoading || clearExisting) && mounted) {
      setState(() {
        if (showLoading) {
          _isLoading = true;
          _error = null;
        }
        if (clearExisting) {
          _transactions = null;
          _transactionsAccountUuid = accountUuid;
        }
      });
    }

    if (accountUuid == null) {
      if (!mounted) return;
      setState(() {
        _transactions = const [];
        _transactionsAccountUuid = null;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final txs = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
      );
      if (!_isCurrentTransactionLoad(generation, accountUuid)) {
        return;
      }
      setState(() {
        _transactions = txs;
        _transactionsAccountUuid = accountUuid;
        _isLoading = false;
        _error = null;
      });
      _runPendingTransactionRefreshIfNeeded(generation, accountUuid);
    } catch (e, st) {
      log('Activity: transaction load failed: $e\n$st');
      if (!_isCurrentTransactionLoad(generation, accountUuid)) {
        return;
      }
      final hasExistingTransactions =
          _transactionsAccountUuid == accountUuid && _transactions != null;
      if (hasExistingTransactions && !clearExisting) return;
      setState(() {
        _transactionsAccountUuid = accountUuid;
        _error = 'Activity could not be loaded.';
        _isLoading = false;
      });
      _runPendingTransactionRefreshIfNeeded(generation, accountUuid);
    }
  }

  bool _isCurrentTransactionLoad(int generation, String? accountUuid) {
    return mounted &&
        generation == _transactionLoadGeneration &&
        accountUuid == ref.read(accountProvider).value?.activeAccountUuid;
  }

  void _runPendingTransactionRefreshIfNeeded(
    int generation,
    String accountUuid,
  ) {
    if (!_pendingTransactionRefresh) return;
    if (!_isCurrentTransactionLoad(generation, accountUuid)) return;
    _pendingTransactionRefresh = false;
    unawaited(_loadTransactions());
  }

  void _refreshTransactionsAfterSyncChange() {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    final hasLoadedTransactions =
        _transactionsAccountUuid == accountUuid && _transactions != null;
    if (hasLoadedTransactions) {
      unawaited(_loadTransactions());
      return;
    }
    if (_isLoading) {
      _pendingTransactionRefresh = true;
      return;
    }
    unawaited(_loadTransactions(showLoading: true, clearExisting: true));
  }

  void _openTransactionStatus(rust_sync.TransactionInfo transaction) {
    unawaited(_pushTransactionStatus(transaction));
  }

  String? _absorbedReceiveAmountText(rust_sync.TransactionInfo? transaction) {
    if (transaction == null) return null;
    final amount = transaction.displayAmount;
    if (amount == BigInt.zero) return null;
    return ZecAmount.fromZatoshi(amount).signedActivity.toString();
  }

  void _openSwapStatus(String intentId) {
    context.push(
      swapActivityDetailUri(
        intentId: intentId,
        returnTarget: SwapActivityReturnTarget.activity,
      ).toString(),
    );
  }

  void _syncSwapActivityStatusRefresh() {
    if (!ref.read(swapFeatureEnabledProvider)) {
      _swapActivityRefreshTimer?.cancel();
      _swapActivityRefreshAccountUuid = null;
      return;
    }
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == _swapActivityRefreshAccountUuid &&
        _swapActivityRefreshTimer?.isActive == true) {
      return;
    }
    _swapActivityRefreshTimer?.cancel();
    _swapActivityRefreshAccountUuid = accountUuid;
    if (accountUuid == null || accountUuid.trim().isEmpty) return;

    unawaited(_refreshSwapActivityStatus(accountUuid));
    _swapActivityRefreshTimer = Timer.periodic(
      swapActivityStatusRefreshInterval,
      (_) => unawaited(_refreshSwapActivityStatus(accountUuid)),
    );
  }

  Future<void> _refreshSwapActivityStatus(
    String accountUuid, {
    bool force = false,
  }) {
    return ref
        .read(swapActivityStatusRefresherProvider)
        .refreshOpenActivities(accountUuid: accountUuid, force: force);
  }

  Future<void> _pushTransactionStatus(
    rust_sync.TransactionInfo transaction,
  ) async {
    final detail = await _loadTransactionDetail(transaction);
    if (!mounted) return;
    context.push(
      Uri(
        path: '/activity/tx/${transaction.txidHex}',
        queryParameters: {'kind': transaction.txKind},
      ).toString(),
      extra: ActivityTransactionStatusArgs(
        txidHex: transaction.txidHex,
        txKind: transaction.txKind,
        initialTransaction: transaction,
        initialDetail: detail,
      ),
    );
  }

  Future<rust_sync.TransactionDetail?> _loadTransactionDetail(
    rust_sync.TransactionInfo transaction,
  ) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return null;

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      if (!mounted ||
          accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
        return null;
      }
      return rust_sync.getTransactionDetail(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        txidHex: transaction.txidHex,
        txKind: transaction.txKind,
      );
    } catch (e, st) {
      log('Activity: transaction detail load failed: $e\n$st');
      return null;
    }
  }

  String _recentSignature(SyncState? sync) {
    return sync?.recentTransactions
            .map(
              (tx) =>
                  '${tx.txidHex}:${tx.minedHeight}:${tx.expiredUnmined}:${tx.txKind}:${tx.displayAmount}',
            )
            .join('|') ??
        '';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      final nextUuid = next.value?.activeAccountUuid;
      if (nextUuid != _activeAccountUuid) {
        unawaited(_loadTransactions(showLoading: true, clearExisting: true));
        _syncSwapActivityStatusRefresh();
      }
    });
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      final prevSig = _recentSignature(previous?.value);
      final nextSig = _recentSignature(next.value);
      if (prevSig != nextSig) {
        _refreshTransactionsAfterSyncChange();
      }
    });

    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final loadedTransactions = _transactionsAccountUuid == accountUuid
        ? _transactions
        : null;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final transactions =
        loadedTransactions ?? const <rust_sync.TransactionInfo>[];
    final canRenderTransactions =
        accountUuid != null && loadedTransactions != null;
    final swapFeatureEnabled = ref.watch(swapFeatureEnabledProvider);
    final swapItems = accountUuid == null || !swapFeatureEnabled
        ? const <SwapActivityRowItem>[]
        : ref.watch(swapActivityRowItemsProvider(accountUuid)).value ??
              const <SwapActivityRowItem>[];
    // Absorb swap-leg transactions into their swap rows: the matched ZEC
    // payout feeds the tappable 'Received ZEC' sub row, and our own ZEC
    // deposit broadcast is suppressed as a duplicate of the swap row itself.
    final absorption = canRenderTransactions
        ? matchSwapActivityLegAbsorption(
            swapItems: swapItems,
            transactions: transactions,
          )
        : SwapActivityLegAbsorption.empty;
    final swapReceiveTxByIntent = absorption.receiveTxByIntent;

    final entries = <_ActivityEntry>[];
    var sourceOrder = 0;
    if (canRenderTransactions) {
      for (final tx in transactions) {
        if (absorption.absorbs(tx)) continue;
        entries.add(
          _ActivityEntry(
            sortKey: activitySortKeyForTransaction(
              tx,
              sourceOrder: sourceOrder++,
            ),
            row: buildTransactionActivityRow(
              context: context,
              transaction: tx,
              privacyModeEnabled: privacyModeEnabled,
              onTap: () => _openTransactionStatus(tx),
            ),
          ),
        );
      }
    }
    for (final item in swapItems) {
      entries.add(
        _ActivityEntry(
          sortKey: activitySortKeyForSwapItem(item, sourceOrder: sourceOrder++),
          row: buildSwapActivityRow(
            context: context,
            item: item,
            privacyModeEnabled: privacyModeEnabled,
            onTap: () => _openSwapStatus(item.intentId),
            receivedAmountText: _absorbedReceiveAmountText(
              swapReceiveTxByIntent[item.intentId],
            ),
            onReceivedLegTap: switch (swapReceiveTxByIntent[item.intentId]) {
              null => null,
              final tx => () => _openTransactionStatus(tx),
            },
          ),
        ),
      );
    }
    entries.sort(_compareActivityEntries);
    final sections = _activityFeedSections(entries);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: AppPaneSliverScrollScaffold(
          toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          slivers: [
            ActivityFeedSliver(
              sections: sections,
              rowKeyPrefix: 'activity_screen',
              isLoading:
                  _isLoading && !canRenderTransactions && sections.isEmpty,
              errorText: sections.isEmpty && loadedTransactions == null
                  ? _error
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityEntry {
  const _ActivityEntry({required this.sortKey, required this.row});

  final ActivityEntrySortKey sortKey;
  final ActivityRowData row;
}

int _compareActivityEntries(_ActivityEntry a, _ActivityEntry b) {
  return compareActivityEntrySortKeys(a.sortKey, b.sortKey);
}

@visibleForTesting
class ActivityEntrySortKey {
  const ActivityEntrySortKey({
    required this.timestamp,
    required this.isPendingTransaction,
    required this.sourceOrder,
  });

  final DateTime? timestamp;
  final bool isPendingTransaction;
  final int sourceOrder;
}

@visibleForTesting
ActivityEntrySortKey activitySortKeyForTransaction(
  rust_sync.TransactionInfo tx, {
  required int sourceOrder,
}) {
  return ActivityEntrySortKey(
    timestamp: _transactionActivityTimestamp(tx),
    isPendingTransaction: isPendingActivityTransaction(tx),
    sourceOrder: sourceOrder,
  );
}

@visibleForTesting
ActivityEntrySortKey activitySortKeyForSwapItem(
  SwapActivityRowItem item, {
  required int sourceOrder,
}) {
  return ActivityEntrySortKey(
    timestamp: item.activityTimestamp,
    isPendingTransaction: false,
    sourceOrder: sourceOrder,
  );
}

@visibleForTesting
bool isPendingActivityTransaction(rust_sync.TransactionInfo tx) {
  return tx.minedHeight == BigInt.zero && !tx.expiredUnmined;
}

@visibleForTesting
int compareActivityEntrySortKeys(
  ActivityEntrySortKey a,
  ActivityEntrySortKey b,
) {
  final aMissingTimestampPending =
      a.isPendingTransaction && a.timestamp == null;
  final bMissingTimestampPending =
      b.isPendingTransaction && b.timestamp == null;
  if (aMissingTimestampPending != bMissingTimestampPending) {
    return aMissingTimestampPending ? -1 : 1;
  }
  final aTime = a.timestamp;
  final bTime = b.timestamp;
  final timeComparison = _compareActivityTimestamps(aTime, bTime);
  if (timeComparison != 0) return timeComparison;
  return a.sourceOrder.compareTo(b.sourceOrder);
}

int _compareActivityTimestamps(DateTime? aTime, DateTime? bTime) {
  if (aTime == null && bTime == null) return 0;
  if (aTime == null) return 1;
  if (bTime == null) return -1;
  return bTime.compareTo(aTime);
}

DateTime? _transactionActivityTimestamp(rust_sync.TransactionInfo tx) {
  final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
  if (seconds <= BigInt.zero) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
}

List<ActivityFeedSectionData> _activityFeedSections(
  List<_ActivityEntry> entries,
) {
  final sections = <ActivityFeedSectionData>[];
  List<ActivityRowData>? currentRows;
  String? currentTitle;

  for (final entry in entries) {
    final title = activitySectionTitleForSortKey(entry.sortKey);
    if (title != currentTitle) {
      currentTitle = title;
      currentRows = <ActivityRowData>[];
      sections.add(ActivityFeedSectionData(title: title, rows: currentRows));
    }
    currentRows!.add(entry.row);
  }

  return sections;
}

@visibleForTesting
String activitySectionTitleForSortKey(
  ActivityEntrySortKey sortKey, {
  DateTime? now,
}) {
  if (sortKey.isPendingTransaction && sortKey.timestamp == null) {
    return 'This week';
  }
  return activitySectionTitleForTimestamp(sortKey.timestamp, now: now);
}

@visibleForTesting
String activitySectionTitleForTimestamp(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) return 'Earlier';

  final local = timestamp.toLocal();
  final reference = now ?? DateTime.now();
  final weekStart = _startOfWeek(reference);
  final nextWeekStart = weekStart.add(const Duration(days: 7));
  if (!local.isBefore(weekStart) && local.isBefore(nextWeekStart)) {
    return 'This week';
  }

  return '${_monthName(local.month)} ${local.year}';
}

DateTime _startOfWeek(DateTime date) {
  final localDate = DateTime(date.year, date.month, date.day);
  return localDate.subtract(Duration(days: date.weekday - DateTime.monday));
}

String _monthName(int month) {
  const months = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return months[month];
}
