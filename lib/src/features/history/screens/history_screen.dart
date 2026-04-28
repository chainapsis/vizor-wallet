import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<rust_sync.TransactionInfo>? _transactions;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final dbPath = await getWalletDbPath();
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (accountUuid == null) {
        if (mounted) {
          setState(() {
            _transactions = const [];
            _isLoading = false;
          });
        }
        return;
      }
      final txs = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: 'main',
        accountUuid: accountUuid,
      );
      if (mounted) {
        setState(() {
          _transactions = txs;
          _isLoading = false;
        });
      }
    } catch (e) {
      log('History: ERROR: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatZec(BigInt zatoshi, {String? sign}) {
    final abs = zatoshi.abs();
    final whole = abs ~/ BigInt.from(100000000);
    final frac = (abs % BigInt.from(100000000)).toString().padLeft(8, '0');
    final prefix = sign ?? '';
    return '$prefix$whole.$frac ZEC';
  }

  String _formatDate(BigInt timestamp) {
    if (timestamp == BigInt.zero) return 'Pending';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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

  String _titleForTx(rust_sync.TransactionInfo tx) {
    final base = switch (tx.txKind) {
      'received' => 'Received',
      'sent' => 'Sent',
      'shielded' => 'Shielded',
      'internal' => 'Internal',
      _ => 'Transaction',
    };
    if (!tx.expiredUnmined) return base;
    return '$base Failed';
  }

  String? _poolLabel(rust_sync.TransactionInfo tx) {
    if (tx.txKind != 'received' && tx.txKind != 'sent') return null;
    return switch (tx.displayPool) {
      'transparent' => 'Transparent',
      'shielded' => 'Shielded',
      'mixed' => 'Mixed',
      _ => null,
    };
  }

  String _amountForTx(rust_sync.TransactionInfo tx) {
    if (tx.displayAmount == BigInt.zero) return '--';
    return switch (tx.txKind) {
      'received' => _formatZec(tx.displayAmount, sign: '+'),
      'sent' => _formatZec(tx.displayAmount, sign: '-'),
      'shielded' => _formatZec(tx.displayAmount),
      'internal' => _formatZec(tx.displayAmount),
      _ => _formatZec(tx.displayAmount),
    };
  }

  BigInt _timestampForTx(rust_sync.TransactionInfo tx) {
    return tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
  }

  Widget _buildTransactionTile(
    BuildContext context,
    rust_sync.TransactionInfo tx,
  ) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isIncoming = tx.txKind == 'received';
    final isSent = tx.txKind == 'sent';
    final isShielded = tx.txKind == 'shielded';
    final isPending = tx.minedHeight == BigInt.zero && !tx.expiredUnmined;
    final isExpired = tx.expiredUnmined;

    final IconData icon;
    final Color iconColor;
    final String title;
    final String status;
    final Color amountColor;

    if (isExpired) {
      icon = Icons.cancel_outlined;
      iconColor = colors.error;
      title = _titleForTx(tx);
      status = 'Failed';
      amountColor = colors.outline;
    } else if (isPending) {
      icon = Icons.schedule;
      iconColor = colors.secondary;
      title = _titleForTx(tx);
      status = 'In progress';
      amountColor = colors.outline;
    } else {
      icon = isShielded
          ? Icons.shield_outlined
          : isIncoming
          ? Icons.arrow_downward
          : Icons.arrow_upward;
      iconColor = isIncoming ? colors.tertiary : colors.secondary;
      title = _titleForTx(tx);
      status = 'Block ${tx.minedHeight} • ${_formatDate(_timestampForTx(tx))}';
      amountColor = isIncoming ? colors.tertiary : colors.onSurface;
    }

    final poolLabel = _poolLabel(tx);

    return ListTile(
      leading: isPending
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: iconColor,
              ),
            )
          : Icon(icon, color: iconColor),
      title: Text(title, style: text.titleSmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poolLabel == null ? status : '$poolLabel • $status',
            style: text.bodySmall?.copyWith(color: colors.outline),
          ),
        ],
      ),
      trailing: Text(
        _amountForTx(tx),
        style: text.titleSmall?.copyWith(
          color: isSent ? colors.onSurface : amountColor,
          fontWeight: FontWeight.w600,
          decoration: isExpired ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      final prevSig = _recentSignature(previous?.value);
      final nextSig = _recentSignature(next.value);
      if (prevSig != nextSig && nextSig.isNotEmpty) {
        unawaited(_loadTransactions());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        actions: [
          IconButton(
            onPressed: () {
              unawaited(_loadTransactions(showLoading: true));
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _transactions == null || _transactions!.isEmpty
          ? const Center(child: Text('No transactions yet'))
          : ListView.builder(
              itemCount: _transactions!.length,
              itemBuilder: (context, index) =>
                  _buildTransactionTile(context, _transactions![index]),
            ),
    );
  }
}
