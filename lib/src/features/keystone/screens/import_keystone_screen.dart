import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/keystone_transport.dart';
import '../../../services/qr_scanner.dart';

class ImportKeystoneScreen extends ConsumerStatefulWidget {
  const ImportKeystoneScreen({super.key});

  @override
  ConsumerState<ImportKeystoneScreen> createState() => _ImportKeystoneScreenState();
}

class _ImportKeystoneScreenState extends ConsumerState<ImportKeystoneScreen> {
  List<rust_keystone.KeystoneAccountInfo>? _accounts;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _connectAndGetAccounts());
  }

  Future<void> _connectAndGetAccounts() async {
    if (!QrScanner.isAvailable) {
      setState(() { _error = 'QR scanning not available on this platform'; _isLoading = false; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final qrTransport = QrKeystoneTransport();
      final accounts = await qrTransport.getAccountsWithContext(context);

      if (!mounted) return;
      setState(() { _accounts = accounts; _isLoading = false; });
    } catch (e) {
      log('ImportKeystone: error: $e');
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _importAccount(rust_keystone.KeystoneAccountInfo info) async {
    setState(() { _isLoading = true; _error = null; });

    try {
      await ref.read(accountProvider.notifier).importKeystoneAccount(
        name: info.name,
        ufvk: info.ufvk,
        seedFingerprint: info.seedFingerprint.toList(),
        zip32Index: info.index,
      );

      if (!mounted) return;
      // Navigate to home — sync will auto-start via accountProvider listener
      context.go('/home');
    } catch (e) {
      log('ImportKeystone: import error: $e');
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Keystone')),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting to Keystone...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: colors.error, size: 48),
                        const SizedBox(height: 16),
                        Text('Connection Failed', style: text.titleLarge),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(color: colors.outline)),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _connectAndGetAccounts,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _accounts != null
                  ? _buildAccountList()
                  : const SizedBox.shrink(),
    );
  }

  Widget _buildAccountList() {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (_accounts!.isEmpty) {
      return Center(
        child: Text('No accounts found on device', style: text.bodyLarge),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('Select an account to import',
              style: text.titleMedium?.copyWith(color: colors.outline)),
        ),
        for (final account in _accounts!)
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: Text(account.name),
              subtitle: Text(
                '${account.ufvk.substring(0, 20)}...',
                style: text.bodySmall?.copyWith(color: colors.outline),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _importAccount(account),
            ),
          ),
      ],
    );
  }
}
