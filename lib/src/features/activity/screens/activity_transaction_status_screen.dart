import 'dart:async';

import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:flutter/services.dart';
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
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../send/widgets/transaction_receipt_view.dart';
import '../activity_row_mapper.dart';

class ActivityTransactionStatusArgs {
  const ActivityTransactionStatusArgs({
    required this.txidHex,
    this.initialTransaction,
  });

  final String txidHex;
  final rust_sync.TransactionInfo? initialTransaction;
}

class ActivityTransactionStatusScreen extends ConsumerStatefulWidget {
  const ActivityTransactionStatusScreen({super.key, required this.args});

  final ActivityTransactionStatusArgs args;

  @override
  ConsumerState<ActivityTransactionStatusScreen> createState() =>
      _ActivityTransactionStatusScreenState();
}

class _ActivityTransactionStatusScreenState
    extends ConsumerState<ActivityTransactionStatusScreen> {
  rust_sync.TransactionInfo? _transaction;
  bool _isLoading = false;
  String? _error;
  String? _activeAccountUuid;

  @override
  void initState() {
    super.initState();
    _transaction = widget.args.initialTransaction;
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_loadTransaction(showLoading: _transaction == null));
    });
  }

  Future<void> _loadTransaction({bool showLoading = false}) async {
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
        _isLoading = false;
        _error = 'No active account.';
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

      final tx = _findTransaction(txs, widget.args.txidHex);
      setState(() {
        if (tx != null) {
          _transaction = tx;
          _error = null;
        } else {
          _error = _transaction == null
              ? 'Transaction could not be loaded.'
              : 'Latest transaction status could not be refreshed.';
        }
        _isLoading = false;
      });
    } catch (e, st) {
      log('ActivityTransactionStatus: transaction load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = _transaction == null
            ? 'Transaction could not be loaded.'
            : 'Latest transaction status could not be refreshed.';
        _isLoading = false;
      });
    }
  }

  rust_sync.TransactionInfo? _findTransaction(
    Iterable<rust_sync.TransactionInfo> transactions,
    String txidHex,
  ) {
    final normalized = txidHex.toLowerCase();
    for (final tx in transactions) {
      if (tx.txidHex.toLowerCase() == normalized) return tx;
    }
    return null;
  }

  String _recentTxSignature(SyncState? sync) {
    final txid = widget.args.txidHex.toLowerCase();
    for (final tx in sync?.recentTransactions ?? const []) {
      if (tx.txidHex.toLowerCase() == txid) {
        return [
          tx.txidHex,
          tx.minedHeight,
          tx.expiredUnmined,
          tx.txKind,
          tx.displayAmount,
        ].join(':');
      }
    }
    return '';
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/activity');
    }
  }

  Future<void> _copyTransactionHash() async {
    await Clipboard.setData(ClipboardData(text: widget.args.txidHex));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Transaction hash copied')));
  }

  TransactionReceiptPhase _phaseFor(rust_sync.TransactionInfo? tx) {
    if (tx == null) {
      return _isLoading
          ? TransactionReceiptPhase.loading
          : TransactionReceiptPhase.failed;
    }
    if (tx.expiredUnmined) return TransactionReceiptPhase.failed;
    if (tx.minedHeight == BigInt.zero) return TransactionReceiptPhase.pending;
    return TransactionReceiptPhase.succeeded;
  }

  String _amountText(rust_sync.TransactionInfo? tx) {
    if (tx == null) return '--';
    if (tx.displayAmount == BigInt.zero) return '--';
    return formatActivityZec(tx.displayAmount);
  }

  String _dateText(rust_sync.TransactionInfo? tx) {
    if (tx == null) return '--';
    final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
    if (seconds <= BigInt.zero) return '--';
    return _formatDate(
      DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000),
    );
  }

  String _feeText(rust_sync.TransactionInfo? tx) {
    if (tx == null || tx.fee <= BigInt.zero) return '--';
    return '${_formatZec(tx.fee)} ZEC';
  }

  String _formatZec(BigInt zatoshi) {
    final whole = zatoshi ~/ BigInt.from(100000000);
    var fraction = (zatoshi % BigInt.from(100000000)).toString().padLeft(
      8,
      '0',
    );
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? '$whole' : '$whole.$fraction';
  }

  String _formatDate(DateTime value) {
    const months = <String>[
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
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${months[local.month]} ${local.day}, ${local.year} $hh:$mm';
  }

  List<String> _splitTxid(String txid) {
    if (txid.length <= 32) return [txid];
    return [txid.substring(0, 32), txid.substring(32)];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      final nextUuid = next.value?.activeAccountUuid;
      if (nextUuid != _activeAccountUuid) {
        unawaited(_loadTransaction(showLoading: _transaction == null));
      }
    });
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      final prevSig = _recentTxSignature(previous?.value);
      final nextSig = _recentTxSignature(next.value);
      if (prevSig != nextSig) {
        unawaited(_loadTransaction());
      }
    });

    final tx = _transaction;
    final colors = context.colors;
    final txidLines = _splitTxid(widget.args.txidHex);
    final error = tx?.expiredUnmined == true
        ? 'Transaction expired before it was mined.'
        : _error;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(child: TransactionReceiptIllustration()),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    TransactionReceiptBackRow(onTap: _goBack),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 255),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TransactionReceiptView(
                            phase: _phaseFor(tx),
                            amountText: _amountText(tx),
                            primaryBlock: TransactionReceiptBlockData(
                              title: 'Transaction Hash',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final line in txidLines)
                                    Text(
                                      line,
                                      style: AppTypography.codeSmall.copyWith(
                                        color: colors.text.accent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            dateText: _dateText(tx),
                            feeText: _feeText(tx),
                            error: error,
                            onCopyTxid: _copyTransactionHash,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
