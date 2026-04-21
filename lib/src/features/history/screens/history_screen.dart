import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
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

  Future<void> _loadTransactions() async {
    try {
      final dbPath = await getWalletDbPath();
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (accountUuid == null) return;
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

  String _formatZec(int zatoshi) {
    final zec = zatoshi.abs() / 100000000;
    final sign = zatoshi >= 0 ? '+' : '-';
    return '$sign${zec.toStringAsFixed(8)} ZEC';
  }

  String _formatDate(int timestamp) {
    if (timestamp == 0) return 'Pending';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTransactionTile(BuildContext context, rust_sync.TransactionInfo tx) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isIncoming = tx.accountBalanceDelta.toInt() >= 0;
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
      title = isIncoming ? 'Receive Expired' : 'Send Expired';
      status = 'Transaction expired';
      amountColor = colors.outline;
    } else if (isPending) {
      icon = Icons.schedule;
      iconColor = colors.secondary;
      title = isIncoming ? 'Receiving...' : 'Sending...';
      status = 'Waiting for confirmation';
      amountColor = colors.outline;
    } else {
      icon = isIncoming ? Icons.arrow_downward : Icons.arrow_upward;
      iconColor = isIncoming ? colors.tertiary : colors.secondary;
      title = isIncoming ? 'Received' : 'Sent';
      status = 'Block ${tx.minedHeight} \u2022 ${_formatDate(tx.blockTime.toInt())}';
      amountColor = isIncoming ? colors.tertiary : colors.onSurface;
    }

    return ListTile(
      leading: isPending
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
            )
          : Icon(icon, color: iconColor),
      title: Text(title, style: text.titleSmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status, style: text.bodySmall?.copyWith(color: colors.outline)),
          if (tx.fee > BigInt.zero)
            Text(
              'Fee: ${(tx.fee.toInt() / 100000000).toStringAsFixed(5)} ZEC',
              style: text.labelSmall?.copyWith(color: colors.outline),
            ),
        ],
      ),
      trailing: Text(
        _formatZec(tx.accountBalanceDelta.toInt()),
        style: text.titleSmall?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
          decoration: isExpired ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _isLoading = true);
              _loadTransactions();
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
