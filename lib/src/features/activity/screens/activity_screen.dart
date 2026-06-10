import 'dart:async';
import 'dart:math' as math;

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
  final ScrollController _scrollController = ScrollController();
  List<rust_sync.TransactionInfo>? _transactions;
  String? _transactionsAccountUuid;
  bool _isLoading = true;
  String? _error;
  String? _activeAccountUuid;
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
      if (!mounted) return;
      if (accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
        return;
      }
      setState(() {
        _transactions = txs;
        _transactionsAccountUuid = accountUuid;
        _isLoading = false;
        _error = null;
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
    final sections = _activityFeedSections(entries);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
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
              child: Stack(
                children: [
                  const Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    height: 48,
                    child: AppPaneToolbar(backLinkMinWidth: 60),
                  ),
                  Positioned(
                    left: 0,
                    top: 48,
                    right: 0,
                    bottom: 0,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        key: const ValueKey('activity_screen_scroll_view'),
                        controller: _scrollController,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight.isFinite
                                ? constraints.maxHeight - 48
                                : 0,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: 420,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.sm,
                                ),
                                child: ActivityFeed(
                                  sections: sections,
                                  rowKeyPrefix: 'activity_screen',
                                  isLoading:
                                      _isLoading &&
                                      !canRenderTransactions &&
                                      sections.isEmpty,
                                  errorText:
                                      sections.isEmpty &&
                                          loadedTransactions == null
                                      ? _error
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isDesktopLayoutPlatform)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 18,
                      child: _ActivityScreenScrollbar(
                        controller: _scrollController,
                        visible: _canScroll,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActivityScreenScrollbar extends StatelessWidget {
  const _ActivityScreenScrollbar({
    required this.controller,
    required this.visible,
  });

  static const _thumbWidth = 6.0;
  static const _thumbTopInset = 14.8212890625;
  static const _thumbHeightFactor = 337.178955078125 / 704;

  final ScrollController controller;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: const ValueKey('activity_screen_scrollbar'),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              if (!visible ||
                  !controller.hasClients ||
                  !controller.position.hasContentDimensions ||
                  controller.position.maxScrollExtent <= 0) {
                return const SizedBox.shrink();
              }

              final height = constraints.maxHeight;
              final thumbHeight = height * _thumbHeightFactor;
              final maxTop = math.max(_thumbTopInset, height - thumbHeight);
              final trackScrollExtent = maxTop - _thumbTopInset;
              final scrollFraction =
                  (controller.offset / controller.position.maxScrollExtent)
                      .clamp(0.0, 1.0)
                      .toDouble();
              final top = _thumbTopInset + (trackScrollExtent * scrollFraction);

              return Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    height: thumbHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) =>
                          _handleThumbDragUpdate(details, trackScrollExtent),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Center(
                          child: DecoratedBox(
                            key: const ValueKey('activity_screen_scroll_thumb'),
                            decoration: BoxDecoration(
                              color: context.colors.background.overlay,
                              borderRadius: BorderRadius.circular(
                                AppRadii.full,
                              ),
                            ),
                            child: const SizedBox(
                              width: _thumbWidth,
                              height: double.infinity,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _handleThumbDragUpdate(
    DragUpdateDetails details,
    double trackScrollExtent,
  ) {
    if (!controller.hasClients || trackScrollExtent <= 0) return;
    final position = controller.position;
    final scrollDelta =
        details.delta.dy / trackScrollExtent * position.maxScrollExtent;
    final nextOffset = (controller.offset + scrollDelta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    controller.jumpTo(nextOffset);
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

List<ActivityFeedSectionData> _activityFeedSections(
  List<_ActivityEntry> entries,
) {
  final sections = <ActivityFeedSectionData>[];
  List<ActivityRowData>? currentRows;
  String? currentTitle;

  for (final entry in entries) {
    final title = _activitySectionTitle(entry.timestamp);
    if (title != currentTitle) {
      currentTitle = title;
      currentRows = <ActivityRowData>[];
      sections.add(ActivityFeedSectionData(title: title, rows: currentRows));
    }
    currentRows!.add(entry.row);
  }

  return sections;
}

String _activitySectionTitle(DateTime? timestamp) {
  if (timestamp == null) return 'Earlier';

  final local = timestamp.toLocal();
  final now = DateTime.now();
  final weekStart = _startOfWeek(now);
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
