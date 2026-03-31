import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../main.dart' show log;
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
  String? _txid;
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

  Future<void> _send() async {
    setState(() { _isSending = true; _error = null; _txid = null; });

    try {
      final address = _addressController.text.trim();
      final amountZec = double.tryParse(_amountController.text.trim()) ?? 0;
      final amountZatoshi = (amountZec * 100000000).round();
      final memo = _memoController.text.trim();

      if (amountZatoshi <= 0) {
        setState(() { _error = 'Invalid amount'; _isSending = false; });
        return;
      }

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

      // Step 2: Check Sapling params if needed
      final paramsDir = '${dir.path}${Platform.pathSeparator}sapling_params';
      final spendPath = '$paramsDir${Platform.pathSeparator}sapling-spend.params';
      final outputPath = '$paramsDir${Platform.pathSeparator}sapling-output.params';

      if (proposal.needsSaplingParams) {
        final spendExists = File(spendPath).existsSync();
        final outputExists = File(outputPath).existsSync();

        if (!spendExists || !outputExists) {
          // Show confirmation dialog
          if (!mounted) return;
          final confirmed = await _showSaplingParamsDialog();
          if (!confirmed) {
            setState(() => _isSending = false);
            return;
          }

          // Download params
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

      // Step 3: Get seed and execute proposal
      const storage = FlutterSecureStorage();
      final mnemonic = await storage.read(key: 'zcash_wallet_mnemonic');
      if (mnemonic == null) {
        setState(() { _error = 'Mnemonic not found in secure storage'; _isSending = false; });
        return;
      }

      // Derive seed bytes from mnemonic
      final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);

      log('Send: executing proposal ${proposal.proposalId}');
      final txidResult = await rust_sync.executeProposal(
        dbPath: dbPath,
        proposalId: proposal.proposalId,
        seed: seedBytes,
        spendParamsPath: proposal.needsSaplingParams ? spendPath : null,
        outputParamsPath: proposal.needsSaplingParams ? outputPath : null,
      );

      log('Send: success, txids=$txidResult');
      setState(() {
        _txid = txidResult;
        _isSending = false;
      });
    } catch (e) {
      log('Send: ERROR: $e');
      setState(() { _error = e.toString(); _isSending = false; });
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Send ZEC')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Recipient Address',
                  suffixIcon: _addressType.isNotEmpty
                      ? Icon(
                          _addressType == 'invalid' ? Icons.error : Icons.check_circle,
                          color: _addressType == 'invalid' ? Colors.red : Colors.green,
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
                      style: Theme.of(context).textTheme.labelSmall),
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
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Memo (optional)',
                  helperText: 'Only available for shielded addresses',
                ),
                maxLines: 2,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  )),
                ),
              ],
              if (_txid != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Transaction sent!', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('TxID: $_txid', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                    ],
                  ),
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
