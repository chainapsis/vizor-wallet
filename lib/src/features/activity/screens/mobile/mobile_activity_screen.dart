import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/navigation/mobile_tab_history.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/privacy_mode_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../activity_feed_sections.dart';
import '../../activity_row_mapper.dart';
import '../../../swap/models/swap_activity_navigation.dart';
import '../../../swap/widgets/swap_activity_status_auto_refresh.dart';
import '../../swap_activity_row_items_provider.dart';
import '../../swap_activity_row_mapper.dart';
import '../../widgets/activity_feed.dart';
import 'mobile_transaction_status_screen.dart';

/// Loads the full transaction history for one account; injectable so
/// widget tests can avoid the Rust FFI.
typedef MobileActivityHistoryLoader =
    Future<List<rust_sync.TransactionInfo>> Function(String accountUuid);

/// Mobile activity tab — Figma `ACTIVITY` frames (4486:51925): the full
/// date-grouped feed, reusing the shared section builder and row
/// mappers with the desktop activity screen.
class MobileActivityScreen extends ConsumerStatefulWidget {
  const MobileActivityScreen({this.historyLoader, super.key});

  final MobileActivityHistoryLoader? historyLoader;

  @override
  ConsumerState<MobileActivityScreen> createState() =>
      _MobileActivityScreenState();
}

class _MobileActivityScreenState extends ConsumerState<MobileActivityScreen> {
  List<rust_sync.TransactionInfo>? _transactions;
  String? _transactionsAccountUuid;
  bool _isLoading = true;
  String? _error;
  String? _activeAccountUuid;

  @override
  void initState() {
    super.initState();
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    unawaited(_loadTransactions(showLoading: true));
  }

  Future<List<rust_sync.TransactionInfo>> _loadHistory(
    String accountUuid,
  ) async {
    final loader = widget.historyLoader;
    if (loader != null) return loader(accountUuid);
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    return rust_sync.getTransactionHistory(
      dbPath: dbPath,
      network: endpoint.walletNetworkName,
      accountUuid: accountUuid,
    );
  }

  Future<void> _loadTransactions({bool showLoading = false}) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _activeAccountUuid = accountUuid;

    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
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
      final txs = await _loadHistory(accountUuid);
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
      log('MobileActivity: transaction load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = "Couldn't load activity. Try again in a moment.";
      });
    }
  }

  void _openTransactionStatus(
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
      ),
    );
  }

  String _recentSignature(SyncState? sync) {
    return sync?.recentTransactions
            .map(
              (tx) =>
                  '${tx.txidHex}:${tx.minedHeight}:${tx.expiredUnmined}:'
                  '${tx.txKind}:${tx.displayAmount}',
            )
            .join('|') ??
        '';
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
      if (_recentSignature(previous?.value) != _recentSignature(next.value)) {
        unawaited(_loadTransactions());
      }
    });

    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final loadedTransactions = _transactionsAccountUuid == accountUuid
        ? _transactions
        : null;
    final swapItems = accountUuid == null
        ? const <SwapActivityRowItem>[]
        : ref.watch(swapActivityRowItemsProvider(accountUuid)).value ??
              const <SwapActivityRowItem>[];

    final entries = <ActivityEntry>[
      if (loadedTransactions != null)
        for (final tx in loadedTransactions)
          ActivityEntry(
            timestamp: transactionActivityTimestamp(tx),
            row: buildTransactionActivityRow(
              context: context,
              transaction: tx,
              privacyModeEnabled: privacyModeEnabled,
              onTap: () => _openTransactionStatus(context, tx),
            ),
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
          ),
        ),
    ];
    final sections = buildActivityFeedSections(entries);

    return SwapActivityStatusAutoRefresh(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Activity',
              onBack: () => context.go(
                resolveMobileBackPath(ref, currentPath: '/activity'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxs,
                  AppSpacing.s,
                  AppSpacing.xxs,
                  kMobileTabBarHeight + AppSpacing.lg,
                ),
                children: [
                  ActivityFeed(
                    key: const ValueKey('mobile_activity_feed'),
                    sections: sections,
                    showHeader: false,
                    cardWidth: null,
                    rowKeyPrefix: 'mobile_activity',
                    isLoading:
                        _isLoading &&
                        loadedTransactions == null &&
                        sections.isEmpty,
                    errorText: sections.isEmpty && loadedTransactions == null
                        ? _error
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
