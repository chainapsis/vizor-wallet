import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../main.dart' show log;
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
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
      final txs = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: 'main',
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
                      itemBuilder: (context, index) {
                        final tx = _transactions![index];
                        final isIncoming = tx.accountBalanceDelta.toInt() >= 0;
                        final colors = Theme.of(context).colorScheme;
                        return ListTile(
                          leading: Icon(
                            isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                            color: isIncoming ? colors.tertiary : colors.error,
                          ),
                          title: Text(
                            _formatZec(tx.accountBalanceDelta.toInt()),
                            style: TextStyle(
                              color: isIncoming ? colors.tertiary : colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.expiredUnmined
                                    ? 'Expired'
                                    : tx.minedHeight.toInt() > 0
                                        ? 'Block ${tx.minedHeight}'
                                        : 'Pending',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                _formatDate(tx.blockTime.toInt()),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                          trailing: tx.fee.toInt() > 0
                              ? Text(
                                  'Fee: ${(tx.fee.toInt() / 100000000).toStringAsFixed(5)}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                )
                              : null,
                        );
                      },
                    ),
    );
  }
}
