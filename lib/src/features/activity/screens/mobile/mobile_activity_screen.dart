import '../../../../core/layout/mobile/mobile_navigation_scope.dart';
import 'dart:async';

import '../../activity_history_pager.dart';
import '../../activity_scroll_anchor.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/config/swap_feature_config.dart';
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/enhance_pir_provider.dart';
import '../../../../providers/privacy_mode_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/pending_activity_evidence_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../activity_feed_sections.dart';
import '../../activity_eta_provider.dart';
import '../../activity_row_mapper.dart';
import '../../gift_card_activity_index.dart';
import '../../../swap/models/swap_activity_navigation.dart';
import '../../../swap/widgets/swap_activity_status_auto_refresh.dart';
import '../../swap_activity_row_items_provider.dart';
import '../../swap_activity_row_mapper.dart';
import '../../widgets/activity_feed.dart';
import '../../widgets/deferred_gift_card_recovery.dart';
import 'mobile_transaction_status_screen.dart';

/// Loads the full transaction history for one account; injectable so
/// widget tests can avoid the Rust FFI.
typedef MobileActivityHistoryLoader =
    Future<List<rust_sync.TransactionInfo>> Function(String accountUuid);

/// Mobile activity tab — Figma `ACTIVITY` frames (4486:51925): the full
/// date-grouped feed, reusing the shared section builder and row
/// mappers with the desktop activity screen.
class MobileActivityScreen extends ConsumerStatefulWidget {
  const MobileActivityScreen({
    this.historyLoader,
    this.historySource,
    super.key,
  });

  final MobileActivityHistoryLoader? historyLoader;
  final ActivityHistorySource? historySource;

  @override
  ConsumerState<MobileActivityScreen> createState() =>
      _MobileActivityScreenState();
}

class _MobileActivityScreenState extends ConsumerState<MobileActivityScreen> {
  List<rust_sync.TransactionInfo>? _transactions;
  String? _transactionsAccountUuid;
  (int?, int?, DateTime?)? _transactionsSnapshot;
  bool _hasFreshTransactionHistory = false;
  bool _isLoading = true;
  String? _error;
  String? _activeAccountUuid;
  ActivityHistoryPager? _pager;
  String? _pagerNetwork;
  final _scrollAnchor = ActivityScrollAnchor(topInset: 0);

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
      _error = pager.error == null
          ? null
          : "Couldn't load activity. Try again in a moment.";
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
          mobile: true,
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
    _pager?.removeListener(_publishPage);
    _pager?.dispose();
    _scrollAnchor.dispose();
    super.dispose();
  }

  void _openTransactionStatus(
    BuildContext context,
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
      extra: MobileTransactionStatusArgs(
        txidHex: transaction.txidHex,
        txKind: transaction.txKind,
        initialTransaction: transaction,
        sourceAccountUuid: accountUuid,
        giftCard: giftCard,
      ),
    );
  }

  ActivityEntry _transactionEntry(
    BuildContext context,
    rust_sync.TransactionInfo transaction,
    GiftCardActivityMetadata? giftCard, {
    required bool privacyModeEnabled,
    required DateTime activityNow,
  }) {
    return ActivityEntry(
      timestamp:
          giftCard?.activityTimestamp ??
          transactionActivityTimestamp(transaction, now: activityNow),
      row: buildTransactionActivityRow(
        context: context,
        transaction: transaction,
        privateQueriesEnabled: ref.watch(enhancePirProvider),
        showPendingEstimate: !ref
            .watch(activityEtaExcludedTxidsProvider)
            .contains(activityTxidKey(transaction.txidHex)),
        pendingLabel:
            (_hasFreshTransactionHistory &&
                    _transactionsSnapshot ==
                        activityHistorySnapshot(ref.watch(syncProvider).value)
                ? activityEtaLabelFor(
                    transaction: transaction,
                    labels: ref.watch(activityEtaLabelsProvider),
                    giftCard: giftCard,
                  )
                : null) ??
            ref.watch(activityPendingFallbackLabelProvider),
        giftCardKind: giftCard?.kind,
        giftCardAmountZatoshi: giftCard?.amountZatoshi,
        giftCardClaimInFlight: giftCard?.isClaimInFlight ?? false,
        giftCardStableId: giftCard?.stableId,
        giftCardActivityTimestamp: giftCard?.activityTimestamp,
        giftCardDisplayPool: giftCard?.displayPool,
        privacyModeEnabled: privacyModeEnabled,
        onTap: () =>
            _openTransactionStatus(context, transaction, giftCard: giftCard),
      ),
    );
  }

  void _openLoadedTransactionStatus(
    BuildContext context,
    rust_sync.TransactionInfo transaction,
  ) {
    context.push(
      Uri(
        path: '/activity/tx/${transaction.txidHex}',
        queryParameters: {'kind': transaction.txKind},
      ).toString(),
      extra: MobileTransactionStatusArgs(
        txidHex: transaction.txidHex,
        txKind: transaction.txKind,
        initialTransaction: transaction,
        sourceAccountUuid: ref.read(accountProvider).value?.activeAccountUuid,
      ),
    );
  }

  String? _absorbedReceiveAmountText(rust_sync.TransactionInfo? transaction) {
    if (transaction == null) return null;
    final amount = transaction.displayAmount;
    if (amount == BigInt.zero) return null;
    return ZecAmount.fromZatoshi(amount).signedActivity.toString();
  }

  String _recentSignature(SyncState? sync) {
    final recent = activityHistoryStatusSignature(
      sync?.recentTransactions ?? const [],
    );
    return '${sync?.lastSyncCompletedAt}|$recent';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      final nextUuid = next.value?.activeAccountUuid;
      if (nextUuid != _activeAccountUuid) {
        unawaited(_loadTransactions(showLoading: true));
      }
    });
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      // Enhancement can change older rows outside the ten recent transactions.
      final syncCompleted =
          next.value?.isSyncComplete == true &&
          previous?.value?.isSyncComplete != true;
      if (_recentSignature(previous?.value) != _recentSignature(next.value) ||
          syncCompleted) {
        _refreshTransactionsAfterSyncChange();
      }
    });

    // Recovery and detail updates can change rows outside recent history.
    ref.listen<int>(syncFollowupProvider, (_, _) {
      unawaited(_loadTransactions());
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
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final loadedTransactions = _transactionsAccountUuid == accountUuid
        ? _transactions
        : null;
    final swapItems = accountUuid == null || !swapFeatureEnabled
        ? const <SwapActivityRowItem>[]
        : ref.watch(swapActivityRowItemsProvider(accountUuid)).value ??
              const <SwapActivityRowItem>[];
    final transactions =
        loadedTransactions ?? const <rust_sync.TransactionInfo>[];
    final absorption = loadedTransactions == null
        ? SwapActivityLegAbsorption.empty
        : matchSwapActivityLegAbsorption(
            swapItems: swapItems,
            transactions: transactions,
          );
    final swapReceiveTxByIntent = absorption.receiveTxByIntent;

    final activityNow = DateTime.now();
    final entries = <ActivityEntry>[
      for (final tx in giftCardActivityIndex.withPendingClaims(transactions))
        if (!absorption.absorbs(tx))
          _transactionEntry(
            context,
            tx,
            giftCardActivityIndex.metadataFor(tx, transactions: transactions),
            privacyModeEnabled: privacyModeEnabled,
            activityNow: activityNow,
          ),
      for (final item in swapItems)
        ActivityEntry(
          timestamp: item.activityTimestamp,
          row: buildSwapActivityRow(
            context: context,
            item: item,
            privacyModeEnabled: privacyModeEnabled,
            // Swap intents need their detail surface reachable — deposit
            // signing and claiming happen there.
            onTap: () => context.push(
              swapActivityDetailUri(
                intentId: item.intentId,
                returnTarget: SwapActivityReturnTarget.activity,
              ).toString(),
            ),
            receivedAmountText: _absorbedReceiveAmountText(
              swapReceiveTxByIntent[item.intentId],
            ),
            onReceivedLegTap: switch (swapReceiveTxByIntent[item.intentId]) {
              null => null,
              final tx => () => _openLoadedTransactionStatus(context, tx),
            },
          ),
        ),
    ];
    final sections = buildActivityFeedSections(
      entries,
      limit: _pager?.visibleCount ?? activityPageSize,
    );

    final content = SwapActivityStatusAutoRefresh(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            MobileTopNav.back(title: 'Activity'),
            Expanded(
              child: CustomScrollView(
                controller: _scrollAnchor.controller,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xxs,
                      AppSpacing.s,
                      AppSpacing.xxs,
                      MobileNavigationScope.bottomClearanceOf(
                        context,
                        kMobileTabBarHeight + AppSpacing.lg,
                      ),
                    ),
                    sliver: ActivityFeedSliver(
                      key: const ValueKey('mobile_activity_feed'),
                      sections: sections,
                      showHeader: false,
                      cardWidth: null,
                      rowKeyPrefix: 'mobile_activity',
                      scrollAnchor: _scrollAnchor,
                      isLoadingMore:
                          _pager?.isLoading == true &&
                          loadedTransactions != null,
                      loadMoreError:
                          loadedTransactions != null && _pager?.error != null,
                      onRetry: () => _pager?.retry(),
                      isLoading:
                          _isLoading &&
                          loadedTransactions == null &&
                          sections.isEmpty,
                      errorText: sections.isEmpty && loadedTransactions == null
                          ? _error
                          : null,
                    ),
                  ),
                ],
              ),
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
