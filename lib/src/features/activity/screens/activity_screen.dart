import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/swap_feature_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_decorative_divider.dart';
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
import '../widgets/activity_table.dart';
import 'activity_transaction_status_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  static const _activityRowsPerPage = 6;
  // Figma frame keeps a 32px Back row plus a 616px Activity panel.
  static const double _activityPaneMinHeight = 648;
  static const double _activityTitleBlockHeight =
      AppBackLink.height +
      (AppSpacing.s * 2) +
      44 +
      AppSpacing.sm +
      16 +
      AppSpacing.sm;

  final ScrollController _scrollController = ScrollController();
  List<rust_sync.TransactionInfo>? _transactions;
  String? _transactionsAccountUuid;
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  String? _activeAccountUuid;
  bool _isHovered = false;
  bool _canScroll = false;
  Timer? _swapActivityRefreshTimer;
  String? _swapActivityRefreshAccountUuid;

  @override
  void initState() {
    super.initState();
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _loadTransactions(showLoading: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      _syncSwapActivityStatusRefresh();
      _updateCanScroll();
    });
  }

  @override
  void didUpdateWidget(covariant ActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCanScroll();
    });
  }

  @override
  void dispose() {
    _swapActivityRefreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions({
    bool showLoading = false,
    bool resetPage = false,
  }) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _activeAccountUuid = accountUuid;

    if ((showLoading || resetPage) && mounted) {
      setState(() {
        if (showLoading) {
          _isLoading = true;
          _error = null;
        }
        if (resetPage) {
          _currentPage = 1;
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
        _currentPage = 1;
      });
      return;
    }

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final txs = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: endpoint.walletNetworkName,
        accountUuid: accountUuid,
      );
      if (!mounted) return;
      if (accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
        return;
      }
      setState(() {
        _transactions = txs;
        _transactionsAccountUuid = accountUuid;
        _isLoading = false;
        _error = null;
        if (resetPage) _currentPage = 1;
      });
    } catch (e, st) {
      log('Activity: transaction load failed: $e\n$st');
      if (!mounted) return;
      if (accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
        return;
      }
      setState(() {
        _transactionsAccountUuid = accountUuid;
        _error = 'Activity could not be loaded.';
        _isLoading = false;
      });
    }
  }

  void _updateCanScroll() {
    if (!_scrollController.hasClients) return;
    final canScroll = _scrollController.position.maxScrollExtent > 0;
    if (canScroll == _canScroll) return;
    setState(() {
      _canScroll = canScroll;
    });
  }

  void _setPage(int page) {
    if (page == _currentPage) return;
    setState(() {
      _currentPage = page;
    });
    if (_scrollController.hasClients) {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _openTransactionStatus(rust_sync.TransactionInfo transaction) {
    unawaited(_pushTransactionStatus(transaction));
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
        network: endpoint.walletNetworkName,
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
        unawaited(_loadTransactions(showLoading: true, resetPage: true));
        _syncSwapActivityStatusRefresh();
      }
    });
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      final prevSig = _recentSignature(previous?.value);
      final nextSig = _recentSignature(next.value);
      if (prevSig != nextSig) {
        unawaited(_loadTransactions(resetPage: true));
      }
    });

    final syncState = ref.watch(syncProvider).value;
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final sync = (syncState ?? SyncState()).scopedToAccount(accountUuid);
    final hasSyncForActiveAccount =
        syncState?.hasDataForAccount(accountUuid) ?? false;
    final loadedTransactions = _transactionsAccountUuid == accountUuid
        ? _transactions
        : null;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final transactions =
        loadedTransactions ??
        (hasSyncForActiveAccount
            ? sync.recentTransactions
            : const <rust_sync.TransactionInfo>[]);
    final canRenderTransactions =
        accountUuid != null &&
        (loadedTransactions != null || hasSyncForActiveAccount);
    final swapFeatureEnabled = ref.watch(swapFeatureEnabledProvider);
    final swapItems = accountUuid == null || !swapFeatureEnabled
        ? const <SwapActivityRowItem>[]
        : ref.watch(swapActivityRowItemsProvider(accountUuid)).value ??
              const <SwapActivityRowItem>[];
    final entries = <_ActivityEntry>[
      if (canRenderTransactions)
        for (final tx in transactions)
          _ActivityEntry(
            timestamp: _transactionActivityTimestamp(tx),
            row: buildTransactionActivityRow(
              context: context,
              transaction: tx,
              privacyModeEnabled: privacyModeEnabled,
              onTap: () => _openTransactionStatus(tx),
            ),
          ),
      for (final item in swapItems)
        _ActivityEntry(
          timestamp: item.activityTimestamp,
          row: buildSwapActivityRow(
            context: context,
            item: item,
            privacyModeEnabled: privacyModeEnabled,
            onTap: () => _openSwapStatus(item.intentId),
          ),
        ),
    ]..sort(_compareActivityEntries);
    final entriesAfterFirstPage = math.max(
      0,
      entries.length - _activityRowsPerPage,
    );
    final totalPages =
        1 + (entriesAfterFirstPage / _activityRowsPerPage).ceil();
    final currentPage = math.min(math.max(_currentPage, 1), totalPages);
    final firstEntryIndex = currentPage == 1
        ? 0
        : _activityRowsPerPage + ((currentPage - 2) * _activityRowsPerPage);
    final rows = entries
        .skip(firstEntryIndex)
        .take(_activityRowsPerPage)
        .map((entry) => entry.row)
        .toList(growable: false);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final paneHeight = _activityPaneHeight(
              viewportHeight: constraints.maxHeight - AppSpacing.md,
              rows: rows,
              showPagination: totalPages > 1,
            );
            return NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _updateCanScroll();
                });
                return false;
              },
              child: MouseRegion(
                onEnter: (_) {
                  if (!_isHovered) {
                    setState(() {
                      _isHovered = true;
                    });
                  }
                },
                onExit: (_) {
                  if (_isHovered) {
                    setState(() {
                      _isHovered = false;
                    });
                  }
                },
                child: Scrollbar(
                  key: const ValueKey('activity_screen_scrollbar'),
                  controller: _scrollController,
                  thumbVisibility:
                      isDesktopLayoutPlatform && _isHovered && _canScroll,
                  child: SingleChildScrollView(
                    key: const ValueKey('activity_screen_scroll_view'),
                    controller: _scrollController,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        0,
                      ),
                      child: SizedBox(
                        height: paneHeight,
                        child: _ActivityPane(
                          rows: rows,
                          isLoading:
                              _isLoading &&
                              !canRenderTransactions &&
                              rows.isEmpty,
                          errorText: rows.isEmpty && loadedTransactions == null
                              ? _error
                              : null,
                          currentPage: currentPage,
                          totalPages: totalPages,
                          onPageChanged: _setPage,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double _activityPaneHeight({
    required double viewportHeight,
    required List<ActivityRowData> rows,
    required bool showPagination,
  }) {
    return math.max(
      math.max(viewportHeight, _activityPaneMinHeight),
      _activityTitleBlockHeight +
          estimateActivityTableContentHeight(
            rows: rows,
            showPagination: showPagination,
          ),
    );
  }
}

class _ActivityPane extends StatelessWidget {
  const _ActivityPane({
    required this.rows,
    required this.isLoading,
    required this.errorText,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  final List<ActivityRowData> rows;
  final bool isLoading;
  final String? errorText;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: AppRouteBackLink(minWidth: 60),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.s,
              bottom: AppSpacing.s,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(
                    'Activity',
                    style: AppTypography.displaySmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Center(child: AppDecorativeDivider(width: 256)),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: ActivityTable(
                      rows: rows,
                      rowKeyPrefix: 'activity_screen',
                      isLoading: isLoading,
                      errorText: errorText,
                      showPagination: true,
                      pinPaginationToBottom: true,
                      currentPage: currentPage,
                      totalPages: totalPages,
                      onPageChanged: onPageChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityEntry {
  const _ActivityEntry({required this.timestamp, required this.row});

  final DateTime? timestamp;
  final ActivityRowData row;
}

int _compareActivityEntries(_ActivityEntry a, _ActivityEntry b) {
  final aTime = a.timestamp;
  final bTime = b.timestamp;
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
