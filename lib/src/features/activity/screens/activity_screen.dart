import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
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
import '../activity_row_mapper.dart';
import '../models/activity_row_data.dart';
import '../widgets/activity_table.dart';
import '../widgets/memos_tab.dart';
import 'activity_transaction_status_screen.dart';

enum _ActivityTab { all, memos }

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  static const _activityRowsPerPage = 6;
  static const _firstPageTransactionCount = _activityRowsPerPage - 1;
  // Figma frame keeps a 32px Back row plus a 616px Activity panel.
  static const double _activityPaneMinHeight = 648;

  final ScrollController _scrollController = ScrollController();
  List<rust_sync.TransactionInfo>? _transactions;
  String? _transactionsAccountUuid;
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  String? _activeAccountUuid;
  bool _isHovered = false;
  bool _canScroll = false;
  _ActivityTab _selectedTab = _ActivityTab.all;

  @override
  void initState() {
    super.initState();
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _loadTransactions(showLoading: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
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
        network: endpoint.networkName,
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
        unawaited(_loadTransactions(showLoading: true, resetPage: true));
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
    final firstPageTransactionCount = hasSyncForActiveAccount
        ? _firstPageTransactionCount
        : _activityRowsPerPage;
    final transactionsAfterFirstPage = math.max(
      0,
      transactions.length - firstPageTransactionCount,
    );
    final totalPages =
        1 + (transactionsAfterFirstPage / _activityRowsPerPage).ceil();
    final currentPage = math.min(math.max(_currentPage, 1), totalPages);
    final firstTxIndex = currentPage == 1
        ? 0
        : firstPageTransactionCount +
              ((currentPage - 2) * _activityRowsPerPage);
    final transactionCount = currentPage == 1
        ? firstPageTransactionCount
        : _activityRowsPerPage;
    final pageTransactions = transactions
        .skip(firstTxIndex)
        .take(transactionCount);
    final canRenderRows =
        accountUuid != null &&
        (loadedTransactions != null || hasSyncForActiveAccount);
    final rows = !canRenderRows
        ? const <ActivityRowData>[]
        : [
            if (currentPage == 1 && hasSyncForActiveAccount)
              buildSyncActivityRow(
                context: context,
                sync: sync,
                privacyModeEnabled: privacyModeEnabled,
                onRetrySync: () => ref.read(syncProvider.notifier).startSync(),
              ),
            ...pageTransactions.map(
              (tx) => buildTransactionActivityRow(
                context: context,
                transaction: tx,
                privacyModeEnabled: privacyModeEnabled,
                onTap: () => _openTransactionStatus(tx),
              ),
            ),
          ];

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
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
                  controller: _scrollController,
                  thumbVisibility:
                      isDesktopLayoutPlatform && _isHovered && _canScroll,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: SizedBox(
                      height: math.max(
                        constraints.maxHeight,
                        _activityPaneMinHeight,
                      ),
                      child: _ActivityPane(
                        rows: rows,
                        isLoading: _isLoading && !canRenderRows,
                        errorText: loadedTransactions == null ? _error : null,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        onPageChanged: _setPage,
                        selectedTab: _selectedTab,
                        onTabChanged: (tab) =>
                            setState(() => _selectedTab = tab),
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
}

class _ActivityPane extends StatelessWidget {
  const _ActivityPane({
    required this.rows,
    required this.isLoading,
    required this.errorText,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    required this.selectedTab,
    required this.onTabChanged,
  });

  final List<ActivityRowData> rows;
  final bool isLoading;
  final String? errorText;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final _ActivityTab selectedTab;
  final ValueChanged<_ActivityTab> onTabChanged;

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
                Center(
                  child: _ActivitySegmentedControl(
                    selected: selectedTab,
                    onChanged: onTabChanged,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: selectedTab == _ActivityTab.all
                        ? ActivityTable(
                            rows: rows,
                            rowKeyPrefix: 'activity_screen',
                            isLoading: isLoading,
                            errorText: errorText,
                            showPagination: true,
                            pinPaginationToBottom: true,
                            currentPage: currentPage,
                            totalPages: totalPages,
                            onPageChanged: onPageChanged,
                          )
                        : const MemosTab(),
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

class _ActivitySegmentedControl extends StatelessWidget {
  const _ActivitySegmentedControl({
    required this.selected,
    required this.onChanged,
  });

  final _ActivityTab selected;
  final ValueChanged<_ActivityTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SegmentButton(
          key: const ValueKey('activity_tab_all'),
          label: 'All',
          isSelected: selected == _ActivityTab.all,
          onTap: () => onChanged(_ActivityTab.all),
          colors: colors,
          isFirst: true,
        ),
        _SegmentButton(
          key: const ValueKey('activity_tab_memos'),
          label: 'Memos',
          isSelected: selected == _ActivityTab.memos,
          onTap: () => onChanged(_ActivityTab.memos),
          colors: colors,
          isLast: true,
        ),
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final AppColors colors;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.horizontal(
      left: isFirst ? const Radius.circular(AppRadii.small) : Radius.zero,
      right: isLast ? const Radius.circular(AppRadii.small) : Radius.zero,
    );
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.background.neutralSubtleOpacity
                : colors.background.neutralSubtleOpacity.withValues(alpha: 0.4),
            borderRadius: radius,
            border: Border.all(color: colors.border.subtle),
          ),
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected ? colors.text.accent : colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}
