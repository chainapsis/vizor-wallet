import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/wallet_paths.dart';
import '../../rust/api/sync.dart' as rust_sync;
import 'gift_card_activity_index.dart';
import 'activity_row_mapper.dart';
import '../payment_links/services/payment_link_transaction_matching.dart';
import 'swap_activity_row_mapper.dart';

const activityPageSize = 20;

/// The same ordering used by the feed, without constructing row widgets.
class ActivityPageOrder {
  const ActivityPageOrder(
    this.timestamp,
    this.missingTimePending,
    this.order, [
    this.id,
  ]);
  final String? id;
  final DateTime? timestamp;
  final bool missingTimePending;
  final int order;
}

int compareActivityPageOrder(ActivityPageOrder a, ActivityPageOrder b) {
  if (a.missingTimePending != b.missingTimePending) {
    return a.missingTimePending ? -1 : 1;
  }
  final time = a.timestamp == null
      ? (b.timestamp == null ? 0 : 1)
      : (b.timestamp == null ? -1 : b.timestamp!.compareTo(a.timestamp!));
  return time != 0 ? time : a.order.compareTo(b.order);
}

DateTime? _time(BigInt block, BigInt created) {
  final seconds = block > BigInt.zero ? block : created;
  return seconds > BigInt.zero
      ? DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000)
      : null;
}

/// Projects business rows too: hidden swap legs and multi-leg claims must
/// not consume the visible page quota.
List<ActivityPageOrder> activityPageOrders({
  required List<rust_sync.TransactionInfo> transactions,
  required GiftCardActivityIndex gifts,
  required List<SwapActivityRowItem> swaps,
  required bool mobile,
  Map<String, int>? sourceOrders,
}) {
  final absorbed = matchSwapActivityLegAbsorption(
    swapItems: swaps,
    transactions: transactions,
  );
  final result = <ActivityPageOrder>[];
  var order = 0;
  final now = DateTime.now();
  for (final tx in gifts.withPendingClaims(transactions)) {
    if (absorbed.absorbs(tx)) continue;
    final timestamp =
        gifts.metadataFor(tx)?.activityTimestamp ??
        _time(tx.blockTime, tx.createdTime);
    final pending =
        timestamp == null &&
        tx.minedHeight == BigInt.zero &&
        !tx.expiredUnmined;
    result.add(
      ActivityPageOrder(
        mobile && pending ? now : timestamp,
        !mobile && pending,
        sourceOrders?[tx.txidHex] ?? ((sourceOrders?.length ?? 0) + order++),
        gifts.metadataFor(tx)?.stableId ?? activityStableTransactionId(tx),
      ),
    );
  }
  for (final swap in swaps) {
    result.add(
      ActivityPageOrder(
        swap.activityTimestamp,
        false,
        (sourceOrders?.length ?? 0) + transactions.length + order++,
        'swap:${swap.intentId}',
      ),
    );
  }
  return result..sort(compareActivityPageOrder);
}

abstract class ActivityHistorySource {
  Future<rust_sync.ActivityHistoryIndex> index();
  Future<rust_sync.ActivityHistoryRows> rows(
    String snapshot,
    List<String> txids,
  );
}

/// Tests can replace native history without bypassing the screen's metadata
/// loading and deferred-recovery path.
final activityHistorySourceFactoryProvider =
    Provider<ActivityHistorySource Function(String, String)>(
      (ref) => LocalActivityHistorySource.new,
    );

class LocalActivityHistorySource implements ActivityHistorySource {
  LocalActivityHistorySource(this.accountUuid, this.network);
  final String accountUuid;
  final String network;
  String? _dbPath;

  Future<String> _path() async => _dbPath ??= await _existingPath();
  Future<String> _existingPath() async {
    final path = await getExistingWalletDbPath();
    if (path == null) throw StateError('Wallet no longer exists');
    return path;
  }

  @override
  Future<rust_sync.ActivityHistoryIndex> index() async =>
      rust_sync.getActivityHistoryIndex(
        dbPath: await _path(),
        network: network,
        accountUuid: accountUuid,
      );

  @override
  Future<rust_sync.ActivityHistoryRows> rows(
    String snapshot,
    List<String> txids,
  ) async => rust_sync.getActivityHistoryRows(
    dbPath: await _path(),
    network: network,
    accountUuid: accountUuid,
    snapshotId: snapshot,
    txidHexes: txids,
  );
}

/// Adapter for existing deterministic screen fixtures. Production always uses
/// the bounded native source above.
class FixtureActivityHistorySource implements ActivityHistorySource {
  FixtureActivityHistorySource(this.load);
  final Future<List<rust_sync.TransactionInfo>> Function() load;
  List<rust_sync.TransactionInfo> _rows = [];
  int _version = 0;

  @override
  Future<rust_sync.ActivityHistoryIndex> index() async {
    _rows = await load();
    final seen = <String>{};
    return rust_sync.ActivityHistoryIndex(
      snapshotId: '${++_version}',
      summaries: [
        for (final tx in _rows)
          if (seen.add(tx.txidHex))
            rust_sync.ActivityHistorySummary(
              txidHex: tx.txidHex,
              minedHeight: tx.minedHeight,
              expiredUnmined: tx.expiredUnmined,
              blockTime: tx.blockTime,
              createdTime: tx.createdTime,
              sourceOrder: seen.length - 1,
            ),
      ],
    );
  }

  @override
  Future<rust_sync.ActivityHistoryRows> rows(
    String snapshot,
    List<String> txids,
  ) async => rust_sync.ActivityHistoryRows(
    stale: snapshot != '$_version',
    transactions: _rows.where((tx) => txids.contains(tx.txidHex)).toList(),
  );
}

/// Owns one account/network session. A refresh builds a replacement offscreen;
/// the published list stays intact until a complete, ordered page is ready.
class ActivityHistoryPager extends ChangeNotifier {
  ActivityHistoryPager({
    required this.source,
    required this.gifts,
    required this.swaps,
    required this.mobile,
  });
  final ActivityHistorySource source;
  final GiftCardActivityIndex Function() gifts;
  final List<SwapActivityRowItem> Function() swaps;
  final bool mobile;
  List<rust_sync.TransactionInfo>? transactions;
  int visibleCount = activityPageSize;
  bool isLoading = false;
  bool hasMore = true;
  Object? error;
  bool fresh = false;
  bool _disposed = false;
  bool _failedMore = false;
  bool _failedRefresh = false;
  bool _refreshPending = false;
  bool _reprojectPending = false;
  String? _candidateSnapshot;
  GiftCardActivityIndex? _candidateGifts;
  List<SwapActivityRowItem>? _candidateSwaps;
  List<rust_sync.ActivityHistorySummary>? _candidates;
  rust_sync.ActivityHistoryIndex? _index;
  Map<String, List<rust_sync.TransactionInfo>> _loaded = {};

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> retry() => load(refresh: _failedRefresh, more: _failedMore);

  Future<void> load({bool refresh = false, bool more = false}) async {
    if (_disposed) return;
    if (isLoading) {
      _refreshPending |= refresh;
      _reprojectPending |= !more && !refresh;
      return;
    }
    if (more && !hasMore) return;
    isLoading = true;
    error = null;
    notifyListeners();
    final requestedTarget = visibleCount + (more ? activityPageSize : 0);
    try {
      // A moving DB or an LRU eviction invalidates only this in-flight page.
      // Bound retries so continuous sync cannot create a busy retry loop.
      for (var attempt = 0; attempt < 3; attempt++) {
        var checkedSnapshot = refresh || _index == null || attempt > 0;
        final index = checkedSnapshot ? await source.index() : _index!;
        if (_disposed) return;
        final loaded = index.snapshotId == _index?.snapshotId
            ? Map<String, List<rust_sync.TransactionInfo>>.of(_loaded)
            : <String, List<rust_sync.TransactionInfo>>{};
        final giftIndex = gifts();
        final swapItems = swaps();
        final retainedIds = activityPageOrders(
          transactions: transactions ?? const [],
          gifts: giftIndex,
          swaps: swapItems,
          mobile: mobile,
        ).take(visibleCount).map((r) => r.id).toSet();
        final retainedTxids = {
          for (final tx in transactions ?? const <rust_sync.TransactionInfo>[])
            if (retainedIds.contains(
              giftIndex.metadataFor(tx)?.stableId ??
                  activityStableTransactionId(tx),
            ))
              tx.txidHex,
        };
        var target = requestedTarget;
        final giftTimes = <String, DateTime>{
          for (final e in giftIndex.redeemedMetadataByTxid.entries)
            if (e.value.activityTimestamp != null)
              paymentLinkTransactionKey(e.key): e.value.activityTimestamp!,
        };
        for (final swap in swapItems) {
          for (final txid in [
            swap.receiveWalletTxidHex,
            swap.depositWalletTxidHex,
          ]) {
            final time = swap.activityTimestamp;
            if (txid != null &&
                time != null &&
                (giftTimes[paymentLinkTransactionKey(txid)] == null ||
                    time.isAfter(
                      giftTimes[paymentLinkTransactionKey(txid)]!,
                    ))) {
              giftTimes[paymentLinkTransactionKey(txid)] = time;
            }
          }
        }
        final sourceOrders = {
          for (final s in index.summaries) s.txidHex: s.sourceOrder,
        };
        if (_candidateSnapshot != index.snapshotId ||
            !identical(_candidateGifts, giftIndex) ||
            !identical(_candidateSwaps, swapItems)) {
          final input = (summaries: index.summaries, times: giftTimes);
          _candidates = index.summaries.length >= 1000
              ? await compute(_sortActivityCandidates, input)
              : _sortActivityCandidates(input);
          if (_disposed) return;
          _candidateSnapshot = index.snapshotId;
          _candidateGifts = giftIndex;
          _candidateSwaps = swapItems;
        }
        final candidates = _candidates!;
        var stale = false;
        List<rust_sync.TransactionInfo> ordered() => [
          for (final summary in index.summaries)
            ...loaded[summary.txidHex] ?? const <rust_sync.TransactionInfo>[],
        ];
        while (true) {
          final current = ordered();
          final orders = activityPageOrders(
            transactions: current,
            gifts: giftIndex,
            swaps: swapItems,
            mobile: mobile,
            sourceOrders: sourceOrders,
          );
          for (var i = 0; i < orders.length; i++) {
            if (retainedIds.contains(orders[i].id) && i >= target) {
              target = i + 1;
            }
          }
          final unread = candidates.where(
            (s) => !loaded.containsKey(s.txidHex),
          );
          final first = unread.firstOrNull;
          final loadedKeys = loaded.keys.map(paymentLinkTransactionKey).toSet();
          final requiredKeys = <String>{};
          for (final metadata in giftIndex.redeemedMetadataByTxid.values) {
            final keys = metadata.claimTxids
                .map(paymentLinkTransactionKey)
                .toSet();
            if (keys.any(loadedKeys.contains)) requiredKeys.addAll(keys);
          }
          final required = unread.where(
            (s) =>
                retainedTxids.contains(s.txidHex) ||
                requiredKeys.contains(paymentLinkTransactionKey(s.txidHex)),
          );
          final needsClaimLeg = required.isNotEmpty;
          // Candidate bounds use the latest possible business timestamp. A
          // split/hidden transaction cannot push an unseen newer row behind
          // this page's cutoff. Native source order breaks timestamp ties.
          if (first == null ||
              (!needsClaimLeg &&
                  orders.length >= target &&
                  _beforeCutoff(
                        _activitySummaryBound(first, giftTimes),
                        orders[target - 1],
                      ) ==
                      false)) {
            if (!checkedSnapshot) {
              // A split-row buffer can fill the next visible page without
              // loading more receipts. Validate its token with an empty read;
              // this reads no summaries or details.
              final check = await source.rows(index.snapshotId, const []);
              if (_disposed) return;
              if (check.stale) {
                stale = true;
                break;
              }
              checkedSnapshot = true;
            }
            _index = index;
            _loaded = loaded;
            transactions = current;
            visibleCount = target;
            hasMore = first != null || orders.length > target;
            fresh = !_refreshPending && !_reprojectPending;
            break;
          }
          final batch = (needsClaimLeg ? required : unread)
              .take(activityPageSize)
              .map((s) => s.txidHex)
              .toList();
          final page = await source.rows(index.snapshotId, batch);
          checkedSnapshot = true;
          if (_disposed) return;
          if (page.stale) {
            stale = true;
            break;
          }
          for (final txid in batch) {
            loaded[txid] = [];
          }
          for (final row in page.transactions) {
            loaded[row.txidHex]?.add(row);
          }
          await Future<void>.delayed(Duration.zero);
        }
        if (!stale) return;
      }
      throw StateError('Activity changed while loading. Try again.');
    } catch (e) {
      if (!_disposed) {
        error = e;
        _failedMore = more;
        _failedRefresh = refresh;
        fresh = false;
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
        if (_refreshPending || _reprojectPending) {
          final refresh = _refreshPending;
          _refreshPending = false;
          _reprojectPending = false;
          await load(refresh: refresh);
        }
      }
    }
  }

  bool _beforeCutoff(ActivityPageOrder candidate, ActivityPageOrder cutoff) =>
      compareActivityPageOrder(candidate, cutoff) <= 0;
}

ActivityPageOrder _activitySummaryBound(
  rust_sync.ActivityHistorySummary s,
  Map<String, DateTime> giftTimes,
) {
  var timestamp = _time(s.blockTime, s.createdTime);
  final pending =
      timestamp == null && s.minedHeight == BigInt.zero && !s.expiredUnmined;
  final giftTime = giftTimes[paymentLinkTransactionKey(s.txidHex)];
  if (giftTime != null && (timestamp == null || giftTime.isAfter(timestamp))) {
    timestamp = giftTime;
  }
  return ActivityPageOrder(timestamp, pending, s.sourceOrder);
}

typedef _ActivityCandidateInput = ({
  List<rust_sync.ActivityHistorySummary> summaries,
  Map<String, DateTime> times,
});

List<rust_sync.ActivityHistorySummary> _sortActivityCandidates(
  _ActivityCandidateInput input,
) => [...input.summaries]
  ..sort(
    (a, b) => compareActivityPageOrder(
      _activitySummaryBound(a, input.times),
      _activitySummaryBound(b, input.times),
    ),
  );

/// Targeted claim reads share native summaries/details with Home and Activity.
Future<List<rust_sync.TransactionInfo>> loadActivityClaimRows({
  required String accountUuid,
  required String network,
  required List<String> txids,
}) async {
  final source = LocalActivityHistorySource(accountUuid, network);
  for (var attempt = 0; attempt < 3; attempt++) {
    final index = await source.index();
    final keys = txids.map(paymentLinkTransactionKey).toSet();
    final matching = index.summaries
        .where((s) => keys.contains(paymentLinkTransactionKey(s.txidHex)))
        .map((s) => s.txidHex)
        .toList();
    final result = <rust_sync.TransactionInfo>[];
    var stale = false;
    for (var offset = 0; offset < matching.length; offset += activityPageSize) {
      final page = await source.rows(
        index.snapshotId,
        matching.skip(offset).take(activityPageSize).toList(),
      );
      if (page.stale) {
        stale = true;
        break;
      }
      result.addAll(page.transactions);
    }
    if (!stale) return result;
  }
  throw StateError('Activity changed while loading');
}
