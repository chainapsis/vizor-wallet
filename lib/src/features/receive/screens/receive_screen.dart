import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../main.dart' show log;
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  String? _currentAddress;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    final wallet = ref.read(walletProvider).value;
    _currentAddress = wallet?.unifiedAddress;
  }

  Future<void> _generateNewAddress() async {
    setState(() => _isGenerating = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
      final newAddr = await rust_sync.getNextAvailableAddress(
        dbPath: dbPath,
        network: 'main',
      );
      log('Receive: new diversified address generated');
      setState(() {
        _currentAddress = newAddr;
        _isGenerating = false;
      });
    } catch (e) {
      log('Receive: ERROR generating address: $e');
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = _currentAddress ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Receive ZEC')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              if (address.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: 'zcash:$address',
                    version: QrVersions.auto,
                    size: 240,
                  ),
                ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shielded Address',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text(
                        address,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: address));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Address copied')),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isGenerating ? null : _generateNewAddress,
                              icon: _isGenerating
                                  ? const SizedBox(height: 16, width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.refresh, size: 16),
                              label: const Text('New Address'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Each new address is a diversified address derived from the same key. '
                'They all receive to the same wallet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
