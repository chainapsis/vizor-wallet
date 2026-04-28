import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../activity_row_mapper.dart';
import '../models/activity_row_data.dart';
import '../widgets/activity_table.dart';
import 'activity_transaction_status_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  static const _activityRowsPerPage = 6;
  static const _firstPageTransactionCount = _activityRowsPerPage - 1;

  final ScrollController _scrollController = ScrollController();
  List<rust_sync.TransactionInfo>? _transactions;
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  String? _activeAccountUuid;
  bool _isHovered = false;
  bool _canScroll = false;

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

    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        if (resetPage) {
          _currentPage = 1;
          _transactions = null;
        }
      });
    }

    if (accountUuid == null) {
      if (!mounted) return;
      setState(() {
        _transactions = const [];
        _isLoading = false;
        _error = null;
        _currentPage = 1;
      });
      return;
    }

    try {
      final dbPath = await getWalletDbPath();
      final txs = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: ZcashNetwork.mainnet.name,
        accountUuid: accountUuid,
      );
      if (!mounted) return;
      if (accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
        return;
      }
      setState(() {
        _transactions = txs;
        _isLoading = false;
        _error = null;
        if (resetPage) _currentPage = 1;
      });
    } catch (e, st) {
      log('Activity: transaction load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
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

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _openTransactionStatus(rust_sync.TransactionInfo transaction) {
    context.push(
      '/activity/tx/${transaction.txidHex}',
      extra: ActivityTransactionStatusArgs(
        txidHex: transaction.txidHex,
        initialTransaction: transaction,
      ),
    );
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

    final sync = ref.watch(syncProvider).value ?? SyncState();
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final transactions = _transactions ?? sync.recentTransactions;
    final transactionsAfterFirstPage = math.max(
      0,
      transactions.length - _firstPageTransactionCount,
    );
    final totalPages =
        1 + (transactionsAfterFirstPage / _activityRowsPerPage).ceil();
    final currentPage = math.min(math.max(_currentPage, 1), totalPages);
    final firstTxIndex = currentPage == 1
        ? 0
        : _firstPageTransactionCount +
              ((currentPage - 2) * _activityRowsPerPage);
    final transactionCount = currentPage == 1
        ? _firstPageTransactionCount
        : _activityRowsPerPage;
    final pageTransactions = transactions
        .skip(firstTxIndex)
        .take(transactionCount);
    final rows = accountUuid == null
        ? const <ActivityRowData>[]
        : [
            if (currentPage == 1)
              buildSyncActivityRow(
                context: context,
                sync: sync,
                onRetrySync: () => ref.read(syncProvider.notifier).startSync(),
              ),
            ...pageTransactions.map(
              (tx) => buildTransactionActivityRow(
                context: context,
                transaction: tx,
                onTap: () => _openTransactionStatus(tx),
              ),
            ),
          ];

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: _ActivityPane(
                        rows: rows,
                        isLoading:
                            _isLoading &&
                            _transactions == null &&
                            sync.recentTransactions.isEmpty,
                        errorText: _transactions == null ? _error : null,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        onPageChanged: _setPage,
                        onBack: _goBack,
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
    required this.onBack,
  });

  final List<ActivityRowData> rows;
  final bool isLoading;
  final String? errorText;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActivityBackRow(onTap: onBack),
        const SizedBox(height: AppSpacing.s),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: ActivityTable(
            rows: rows,
            isLoading: isLoading,
            errorText: errorText,
            showPagination: true,
            currentPage: currentPage,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
      ],
    );
  }
}

class _ActivityBackRow extends StatelessWidget {
  const _ActivityBackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 60),
            child: SizedBox(
              height: 32,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.chevronBackward,
                    size: 16,
                    color: colors.icon.accent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Back',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
