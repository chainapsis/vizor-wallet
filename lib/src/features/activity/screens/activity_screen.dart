import 'dart:async';

import '../activity_history_pager.dart';
import '../activity_scroll_anchor.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/swap_feature_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/pending_activity_evidence_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../swap/models/swap_activity_navigation.dart';
import '../../swap/providers/swap_activity_tracker.dart';
import '../activity_eta_provider.dart';
import '../activity_row_mapper.dart';
import '../gift_card_activity_index.dart';
import '../models/activity_row_data.dart';
import '../swap_activity_row_items_provider.dart';
import '../swap_activity_row_mapper.dart';
import '../widgets/activity_feed.dart';
import '../widgets/deferred_gift_card_recovery.dart';
import 'activity_transaction_status_screen.dart';

/// Loads the full transaction history for one account; injectable so
/// widget tests can avoid the Rust FFI.
typedef ActivityHistoryLoader =
    Future<List<rust_sync.TransactionInfo>> Function(String accountUuid);

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({this.historyLoader, this.historySource, super.key});

  final ActivityHistoryLoader? historyLoader;
  final ActivityHistorySource? historySource;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  List<rust_sync.TransactionInfo>? _transactions;
  String? _transactionsAccountUuid;
  (int?, int?, DateTime?)? _transactionsSnapshot;
  bool _hasFreshTransactionHistory = false;
  bool _isLoading = true;
  String? _error;
  String? _activeAccountUuid;
  Timer? _swapActivityRefreshTimer;
  String? _swapActivityRefreshAccountUuid;
  ActivityHistoryPager? _pager;
  String? _pagerNetwork;
  final _scrollAnchor = ActivityScrollAnchor(topInset: 48);

  GiftCardActivityIndex _gifts() {
    final uuid = _activeAccountUuid;
    return uuid == null
        ? GiftCardActivityIndex.empty
        : ref.read(giftCardActivityIndexProvider(uuid)).value ??
              GiftCardActivityIndex.empty;
  }

  List<SwapActivityRowItem> _swaps() {
    final uuid = _activeAccountUuid;
    if (!ref.read(swapFeatureEnabledProvider)) return const [];
    return uuid == null
        ? const []
        : ref.read(swapActivityRowItemsProvider(uuid)).value ?? const [];
  }

  @override
  void initState() {
    super.initState();
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _scrollAnchor.controller.addListener(_loadNearEnd);
    unawaited(_loadTransactions(showLoading: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      _syncSwapActivityStatusRefresh();
    });
  }

  void _loadNearEnd() {
    final pager = _pager;
    if (!_scrollAnchor.controller.hasClients ||
        pager == null ||
        pager.isLoading ||
        !pager.hasMore ||
        pager.error != null) {
      return;
    }
    if (_scrollAnchor.controller.position.extentAfter < 300) {
      unawaited(pager.load(more: true));
    }
  }

  void _publishPage() {
    if (!mounted) return;
    final pager = _pager!;
    final restoreAnchor = _scrollAnchor.capture();
    setState(() {
      _transactions = pager.transactions;
      _transactionsAccountUuid = _activeAccountUuid;
      _hasFreshTransactionHistory = pager.fresh;
      if (!pager.isLoading && pager.fresh) {
        _transactionsSnapshot = activityHistorySnapshot(
          ref.read(syncProvider).value,
        );
      }
      _isLoading = pager.transactions == null && pager.isLoading;
      _error = pager.error == null ? null : 'Activity could not be loaded.';
    });
    restoreAnchor();
    if (!pager.isLoading && pager.error == null && pager.transactions != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadNearEnd();
      });
    }
  }

  Future<void> _loadTransactions({bool showLoading = false}) async {
    final uuid = ref.read(accountProvider).value?.activeAccountUuid;
    final network = ref.read(rpcEndpointProvider).networkName;
    if (uuid != _activeAccountUuid ||
        network != _pagerNetwork ||
        _pager == null) {
      _pager?.removeListener(_publishPage);
      _pager?.dispose();
      _pager = null;
      _activeAccountUuid = uuid;
      _pagerNetwork = network;
      _transactions = null;
      _hasFreshTransactionHistory = false;
      if (uuid != null) {
        final loader = widget.historyLoader;
        _pager = ActivityHistoryPager(
          source:
              widget.historySource ??
              (loader == null
                  ? ref.read(activityHistorySourceFactoryProvider)(
                      uuid,
                      network,
                    )
                  : FixtureActivityHistorySource(() => loader(uuid))),
          gifts: _gifts,
          swaps: _swaps,
          mobile: false,
        )..addListener(_publishPage);
      }
      if (_scrollAnchor.controller.hasClients) {
        _scrollAnchor.controller.jumpTo(0);
      }
    }
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    final pager = _pager;
    if (pager == null) {
      if (mounted) {
        setState(() {
          _transactions = const [];
          _isLoading = false;
        });
      }
      return;
    }
    // Local business metadata determines sorting, grouping and hidden legs.
    // Existing test fixtures provide their metadata synchronously.
    if (widget.historyLoader == null && widget.historySource == null) {
      try {
        await ref.read(giftCardActivityIndexProvider(uuid!).future);
      } catch (_) {}
      if (!mounted || !identical(pager, _pager)) return;
      if (ref.read(swapFeatureEnabledProvider)) {
        try {
          await ref.read(swapActivityRowItemsProvider(uuid!).future);
        } catch (_) {}
        if (!mounted || !identical(pager, _pager)) return;
      }
    }
    await pager.load(refresh: true);
  }

  void _refreshTransactionsAfterSyncChange() {
    unawaited(_loadTransactions());
  }

  @override
  void dispose() {
    _swapActivityRefreshTimer?.cancel();
    _pager?.removeListener(_publishPage);
    _pager?.dispose();
    _scrollAnchor.dispose();
    super.dispose();
  }

  void _openTransactionStatus(
    rust_sync.TransactionInfo transaction, {
    GiftCardActivityMetadata? giftCard,
  }) {
    _pushTransactionStatus(transaction, giftCard: giftCard);
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

  void _pushTransactionStatus(
    rust_sync.TransactionInfo transaction, {
    GiftCardActivityMetadata? giftCard,
  }) {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    context.push(
      Uri(
        path: '/activity/tx/${transaction.txidHex}',
        queryParameters: {'kind': transaction.txKind},
      ).toString(),
      extra: ActivityTransactionStatusArgs(
        txidHex: transaction.txidHex,
        txKind: transaction.txKind,
        initialTransaction: transaction,
        sourceAccountUuid: accountUuid,
        giftCard: giftCard,
      ),
    );
  }

  String _recentSignature(SyncState? sync) {
    final recent = activityHistoryStatusSignature(
      sync?.recentTransactions ?? const [],
    );
    return '${sync?.lastSyncCompletedAt}|$recent';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(swapFeatureEnabledProvider, (_, _) {
      _syncSwapActivityStatusRefresh();
    });
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      final nextUuid = next.value?.activeAccountUuid;
      if (nextUuid != _activeAccountUuid) {
        unawaited(_loadTransactions(showLoading: true));
        _syncSwapActivityStatusRefresh();
      }
    });
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      final prevSig = _recentSignature(previous?.value);
      final nextSig = _recentSignature(next.value);
      // Enhancement can change older rows outside the ten recent transactions.
      final syncCompleted =
          next.value?.isSyncComplete == true &&
          previous?.value?.isSyncComplete != true;
      if (prevSig != nextSig || syncCompleted) {
        _refreshTransactionsAfterSyncChange();
      }
    });

    // Recovery and detail updates can change rows outside recent history.
    ref.listen<int>(syncFollowupProvider, (_, _) {
      _refreshTransactionsAfterSyncChange();
    });

    ref.listen(rpcEndpointProvider, (_, next) {
      if (next.networkName != _pagerNetwork) {
        unawaited(_loadTransactions(showLoading: true));
      }
    });
    final swapFeatureEnabled = ref.watch(swapFeatureEnabledProvider);
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    if (accountUuid != null) {
      ref.listen(giftCardActivityIndexProvider(accountUuid), (_, next) {
        if (next.hasValue && !next.isLoading) unawaited(_pager?.load());
      });
      if (swapFeatureEnabled) {
        ref.listen(swapActivityRowItemsProvider(accountUuid), (_, next) {
          if (next.hasValue && !next.isLoading) unawaited(_pager?.load());
        });
      }
    }
    final giftCardActivityIndex = accountUuid == null
        ? GiftCardActivityIndex.empty
        : ref.watch(giftCardActivityIndexProvider(accountUuid)).value ??
              GiftCardActivityIndex.empty;
    final loadedTransactions = _transactionsAccountUuid == accountUuid
        ? _transactions
        : null;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final transactions =
        loadedTransactions ?? const <rust_sync.TransactionInfo>[];
    final canRenderTransactions =
        accountUuid != null && loadedTransactions != null;
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
    if (accountUuid != null) {
      for (final tx in giftCardActivityIndex.withPendingClaims(transactions)) {
        if (absorption.absorbs(tx)) continue;
        final giftCard = giftCardActivityIndex.metadataFor(
          tx,
          transactions: transactions,
        );
        entries.add(
          _ActivityEntry(
            sortKey: activitySortKeyForTransaction(
              tx,
              sourceOrder: sourceOrder++,
              giftCard: giftCard,
            ),
            row: buildTransactionActivityRow(
              context: context,
              transaction: tx,
              privateQueriesEnabled: ref.watch(enhancePirProvider),
              showPendingEstimate: !ref
                  .watch(activityEtaExcludedTxidsProvider)
                  .contains(activityTxidKey(tx.txidHex)),
              pendingLabel:
                  (_hasFreshTransactionHistory &&
                          _transactionsSnapshot ==
                              activityHistorySnapshot(
                                ref.watch(syncProvider).value,
                              )
                      ? activityEtaLabelFor(
                          transaction: tx,
                          labels: ref.watch(activityEtaLabelsProvider),
                          giftCard: giftCard,
                        )
                      : null) ??
                  ref.watch(activityPendingFallbackLabelProvider),
              giftCardKind: giftCard?.kind,
              giftCardAmountZatoshi: giftCard?.amountZatoshi,
              giftCardBatchCount: giftCard?.batchCount,
              giftCardClaimInFlight: giftCard?.isClaimInFlight ?? false,
              giftCardStableId: giftCard?.stableId,
              giftCardActivityTimestamp: giftCard?.activityTimestamp,
              giftCardDisplayPool: giftCard?.displayPool,
              privacyModeEnabled: privacyModeEnabled,
              onTap: () => _openTransactionStatus(tx, giftCard: giftCard),
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
    final sections = _activityFeedSections(
      entries.take(_pager?.visibleCount ?? activityPageSize).toList(),
    );

    final content = AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: AppPaneSliverScrollScaffold(
          controller: _scrollAnchor.controller,
          toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          slivers: [
            ActivityFeedSliver(
              sections: sections,
              rowKeyPrefix: 'activity_screen',
              scrollAnchor: _scrollAnchor,
              isLoadingMore:
                  _pager?.isLoading == true && loadedTransactions != null,
              loadMoreError:
                  loadedTransactions != null && _pager?.error != null,
              onRetry: () => _pager?.retry(),
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
    return DeferredGiftCardRecovery(
      accountUuid: accountUuid,
      sessionKey: _pager,
      ready: loadedTransactions != null && _pager?.error == null,
      child: content,
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
  GiftCardActivityMetadata? giftCard,
}) {
  return ActivityEntrySortKey(
    timestamp: giftCard?.activityTimestamp ?? _transactionActivityTimestamp(tx),
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
