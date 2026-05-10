import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../rust/wallet/keystone.dart' show KeystoneAccountInfo;
import '../../../services/keystone_transport.dart';
import '../../../services/qr_scanner.dart';
import '../../onboarding/shared/onboarding_flow_args.dart';

class ImportKeystoneScreen extends ConsumerStatefulWidget {
  const ImportKeystoneScreen({super.key});

  @override
  ConsumerState<ImportKeystoneScreen> createState() =>
      _ImportKeystoneScreenState();
}

enum _KeystoneLoadingPhase { idle, connecting, stoppingSync, importing }

class _ImportKeystoneScreenState extends ConsumerState<ImportKeystoneScreen> {
  List<KeystoneAccountInfo>? _accounts;
  _KeystoneLoadingPhase _loadingPhase = _KeystoneLoadingPhase.idle;
  String? _error;

  bool get _isLoading => _loadingPhase != _KeystoneLoadingPhase.idle;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _connectAndGetAccounts());
  }

  Future<void> _connectAndGetAccounts() async {
    if (!QrScanner.isAvailable) {
      setState(() {
        _error =
            'Keystone import uses camera QR scanning only. Connect a camera and try again. '
            'If a monitor webcam cannot focus on the QR code, increase the distance, '
            'improve lighting, or use a mobile device.';
        _loadingPhase = _KeystoneLoadingPhase.idle;
      });
      return;
    }

    setState(() {
      _loadingPhase = _KeystoneLoadingPhase.connecting;
      _error = null;
    });

    try {
      final qrTransport = QrKeystoneTransport();
      final accounts = await qrTransport.getAccounts(context);

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loadingPhase = _KeystoneLoadingPhase.idle;
      });
    } catch (e) {
      log('ImportKeystone: error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingPhase = _KeystoneLoadingPhase.idle;
      });
    }
  }

  Future<void> _importAccount(KeystoneAccountInfo info) async {
    setState(() {
      _loadingPhase = _KeystoneLoadingPhase.importing;
      _error = null;
    });

    try {
      final security = ref.read(appSecurityProvider);
      if (!security.isPasswordConfigured) {
        if (!mounted) return;
        context.go(
          '/import-keystone/set-password',
          extra: SetPasswordScreenArgs.importKeystone(
            name: info.name,
            ufvk: info.ufvk,
            seedFingerprint: info.seedFingerprint.toList(),
            zip32Index: info.index,
          ),
        );
        return;
      }

      await runWithSyncPausedForAccountMutation(
        ref,
        () => ref
            .read(accountProvider.notifier)
            .importKeystoneAccount(
              name: info.name,
              ufvk: info.ufvk,
              seedFingerprint: info.seedFingerprint.toList(),
              zip32Index: info.index,
            ),
        onStoppingSync: () {
          if (!mounted) return;
          setState(() {
            _loadingPhase = _KeystoneLoadingPhase.stoppingSync;
          });
        },
        onSyncPaused: () {
          if (!mounted) return;
          setState(() {
            _loadingPhase = _KeystoneLoadingPhase.importing;
          });
        },
      );

      if (!mounted) return;
      // Navigate to home — sync will auto-start via accountProvider listener
      context.go('/home');
    } catch (e) {
      log('ImportKeystone: import error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingPhase = _KeystoneLoadingPhase.idle;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final loadingText = switch (_loadingPhase) {
      _KeystoneLoadingPhase.connecting => 'Connecting to Keystone...',
      _KeystoneLoadingPhase.stoppingSync => 'Stop syncing...',
      _KeystoneLoadingPhase.importing => 'Importing...',
      _KeystoneLoadingPhase.idle => '',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Keystone')),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(loadingText),
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
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: colors.outline),
                    ),
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
          child: Text(
            'Select an account to import',
            style: text.titleMedium?.copyWith(color: colors.outline),
          ),
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
