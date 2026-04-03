import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;

const _saplingSpendHash = 'a15ab54c2888880e53c823a3063820c728444126';
const _saplingOutputHash = '0ebc5a1ef3653948e1c46cf7a16071eac4b7e352';
const _saplingParamBaseUrl = 'https://download.z.cash/downloads/';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  bool _isSending = false;
  String? _error;
  String _addressType = '';

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _validateAddress() async {
    final addr = _addressController.text.trim();
    if (addr.isEmpty) {
      setState(() => _addressType = '');
      return;
    }
    try {
      final result = await rust_sync.validateAddress(address: addr);
      setState(() => _addressType = result.isValid ? result.addressType : 'invalid');
    } catch (_) {
      setState(() => _addressType = 'invalid');
    }
  }

  BigInt _getSpendableBalance() {
    final syncState = ref.read(syncProvider).valueOrNull;
    return syncState?.totalBalance ?? BigInt.zero;
  }

  String _formatZec(BigInt zatoshi) {
    final zec = zatoshi.toDouble() / 100000000;
    return zec.toStringAsFixed(8);
  }

  Future<void> _send() async {
    setState(() { _isSending = true; _error = null; });

    try {
      final address = _addressController.text.trim();
      final amountZec = double.tryParse(_amountController.text.trim()) ?? 0;
      final amountZatoshi = (amountZec * 100000000).round();

      if (amountZatoshi <= 0) {
        setState(() { _error = 'Invalid amount'; _isSending = false; });
        return;
      }

      // Check balance before proposing
      final spendable = _getSpendableBalance();
      if (BigInt.from(amountZatoshi) > spendable) {
        setState(() {
          _error = 'Insufficient balance. Available: ${_formatZec(spendable)} ZEC';
          _isSending = false;
        });
        return;
      }

      final memo = _memoController.text.trim();
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';

      // Step 1: Propose transfer
      log('Send: proposing transfer');
      final proposal = await rust_sync.proposeSend(
        dbPath: dbPath,
        network: 'main',
        toAddress: address,
        amountZatoshi: BigInt.from(amountZatoshi),
        memo: memo.isNotEmpty ? memo : null,
      );

      log('Send: proposal_id=${proposal.proposalId}, needs_sapling=${proposal.needsSaplingParams}, fee=${proposal.feeZatoshi}');

      // Step 2: Show confirmation with fee
      if (!mounted) return;
      final confirmed = await _showConfirmationDialog(
        address: address,
        amountZatoshi: BigInt.from(amountZatoshi),
        feeZatoshi: proposal.feeZatoshi,
        memo: memo.isNotEmpty ? memo : null,
      );
      if (!confirmed) {
        setState(() => _isSending = false);
        return;
      }

      // Step 3: Check Sapling params if needed
      final paramsDir = '${dir.path}${Platform.pathSeparator}sapling_params';
      final spendPath = '$paramsDir${Platform.pathSeparator}sapling-spend.params';
      final outputPath = '$paramsDir${Platform.pathSeparator}sapling-output.params';

      if (proposal.needsSaplingParams) {
        final spendExists = File(spendPath).existsSync();
        final outputExists = File(outputPath).existsSync();

        if (!spendExists || !outputExists) {
          if (!mounted) return;
          final downloadConfirmed = await _showSaplingParamsDialog();
          if (!downloadConfirmed) {
            setState(() => _isSending = false);
            return;
          }

          await Directory(paramsDir).create(recursive: true);
          if (!spendExists) {
            log('Send: downloading sapling-spend.params (~47MB)');
            setState(() => _error = 'Downloading sapling-spend.params...');
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-spend.params',
              spendPath,
              _saplingSpendHash,
            );
          }
          if (!outputExists) {
            log('Send: downloading sapling-output.params (~3.5MB)');
            setState(() => _error = 'Downloading sapling-output.params...');
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-output.params',
              outputPath,
              _saplingOutputHash,
            );
          }
          setState(() => _error = null);
        }
      }

      // Step 4: Get seed and execute proposal
      const storage = FlutterSecureStorage();
      final mnemonic = await storage.read(key: 'zcash_wallet_mnemonic');
      if (mnemonic == null) {
        setState(() { _error = 'Mnemonic not found in secure storage'; _isSending = false; });
        return;
      }

      final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);

      log('Send: executing proposal ${proposal.proposalId}');
      final txidResult = await rust_sync.executeProposal(
        dbPath: dbPath,
        lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
        proposalId: proposal.proposalId,
        seed: seedBytes,
        spendParamsPath: proposal.needsSaplingParams ? spendPath : null,
        outputParamsPath: proposal.needsSaplingParams ? outputPath : null,
      );

      log('Send: success, txids=$txidResult');

      // Show success and navigate back to home
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaction sent successfully'),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      log('Send: ERROR: $e');
      setState(() { _error = e.toString(); _isSending = false; });
    }
  }

  Future<bool> _showConfirmationDialog({
    required String address,
    required BigInt amountZatoshi,
    required BigInt feeZatoshi,
    String? memo,
  }) async {
    final theme = Theme.of(context);
    final totalZatoshi = amountZatoshi + feeZatoshi;

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To', style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 4),
            Text(
              '${address.substring(0, 16)}...${address.substring(address.length - 8)}',
              style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            _buildConfirmRow(theme, 'Amount', '${_formatZec(amountZatoshi)} ZEC'),
            const SizedBox(height: 8),
            _buildConfirmRow(theme, 'Fee', '${_formatZec(feeZatoshi)} ZEC'),
            Divider(height: 24, color: theme.colorScheme.outlineVariant),
            _buildConfirmRow(theme, 'Total', '${_formatZec(totalZatoshi)} ZEC',
              bold: true),
            if (memo != null && memo.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Memo', style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
              const SizedBox(height: 4),
              Text(memo, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm & Send'),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _buildConfirmRow(ThemeData theme, String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        )),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        )),
      ],
    );
  }

  Future<bool> _showSaplingParamsDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Required'),
        content: const Text(
          'This transaction uses Sapling shielded notes, which require '
          'proving parameters (~50MB) to generate zero-knowledge proofs.\n\n'
          'This is a one-time download. Network data charges may apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _downloadAndVerify(String url, String destPath, String expectedSha1) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final tempPath = '${destPath}_tmp';
      final file = File(tempPath);
      final sink = file.openWrite();
      await response.pipe(sink);

      // Verify SHA-1
      final bytes = await File(tempPath).readAsBytes();
      final digest = sha1.convert(bytes);
      if (digest.toString() != expectedSha1) {
        await File(tempPath).delete();
        throw Exception('SHA-1 mismatch: expected $expectedSha1, got $digest');
      }

      // Atomic rename
      await File(tempPath).rename(destPath);
      log('Send: downloaded and verified $destPath');
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final syncState = ref.watch(syncProvider).valueOrNull;
    final spendable = syncState?.totalBalance ?? BigInt.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('Send ZEC')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Available balance
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Available Balance',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      )),
                    const SizedBox(height: 4),
                    Text('${_formatZec(spendable)} ZEC',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Recipient Address',
                  suffixIcon: _addressType.isNotEmpty
                      ? Icon(
                          _addressType == 'invalid' ? Icons.error : Icons.check_circle,
                          color: _addressType == 'invalid'
                              ? colors.error
                              : colors.tertiary,
                        )
                      : null,
                ),
                onChanged: (_) => _validateAddress(),
                maxLines: 2,
              ),
              if (_addressType.isNotEmpty && _addressType != 'invalid')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Address type: $_addressType',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      )),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Amount (ZEC)',
                  hintText: '0.00000000',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _memoController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Memo (optional)',
                  helperText: _addressType == 'transparent'
                      ? 'Memo not available for transparent addresses'
                      : 'Only available for shielded addresses',
                  helperStyle: _addressType == 'transparent'
                      ? TextStyle(color: colors.error)
                      : null,
                ),
                maxLines: 2,
                enabled: _addressType != 'transparent',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: TextStyle(
                    color: colors.onErrorContainer,
                  )),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSending || _addressType == 'invalid' || _addressType.isEmpty
                      ? null
                      : _send,
                  child: _isSending
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
