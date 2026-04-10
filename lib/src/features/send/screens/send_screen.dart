import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../services/keystone_transport.dart';

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
  String? _amountError; // null = no error, empty string = silent invalid (empty/dot)
  int _validateSeq = 0;

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
    } catch (e) {
      log('Send: address validation error: $e');
      setState(() => _addressType = 'error');
    }
  }

  BigInt _getSpendableBalance() {
    final syncState = ref.read(syncProvider).value;
    return syncState?.spendableBalance ?? BigInt.zero;
  }

  Future<void> _validateAmount() async {
    final seq = ++_validateSeq;
    final text = _amountController.text.trim();

    // Empty or just "." — silently invalid (no error shown, button disabled)
    if (text.isEmpty || text == '.') {
      setState(() => _amountError = '');
      return;
    }

    final zatoshi = _parseZecToZatoshi(text);
    if (zatoshi == null || zatoshi <= 0) {
      setState(() => _amountError = 'Invalid amount');
      return;
    }

    // Quick balance pre-check
    final spendable = _getSpendableBalance();
    if (BigInt.from(zatoshi) > spendable) {
      setState(() => _amountError = 'Insufficient balance');
      return;
    }

    // Need valid address to estimate fee
    final address = _addressController.text.trim();
    if (address.isEmpty || _addressType == 'invalid' || _addressType == 'error' || _addressType.isEmpty) {
      setState(() => _amountError = null);
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
      final memo = _memoController.text.trim();
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (accountUuid == null) { setState(() => _amountError = null); return; }
      final fee = await rust_sync.estimateFee(
        dbPath: dbPath,
        network: 'main',
        accountUuid: accountUuid,
        toAddress: address,
        amountZatoshi: BigInt.from(zatoshi),
        memo: memo.isNotEmpty ? memo : null,
      );

      // Stale check — new input arrived while awaiting
      if (seq != _validateSeq) return;

      final totalNeeded = BigInt.from(zatoshi) + fee;
      if (totalNeeded > spendable) {
        final feeZec = _formatZec(fee);
        setState(() => _amountError = 'Insufficient balance (fee: $feeZec ZEC)');
      } else {
        setState(() => _amountError = null);
      }
    } catch (e) {
      if (seq != _validateSeq) return;
      final msg = e.toString();
      if (msg.contains('InsufficientFunds') || msg.contains('insufficient')) {
        setState(() => _amountError = 'Insufficient balance including fee');
      } else {
        log('Send: fee estimation failed (non-blocking): $e');
        setState(() => _amountError = null);
      }
    }
  }

  bool get _isAmountValid => _amountError == null;

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('insufficientfunds') || lower.contains('insufficient')) {
      return 'Insufficient balance to cover amount and fee.';
    }
    if (lower.contains('grpc connect failed') || lower.contains('connection refused') || lower.contains('dns error') || lower.contains('tls error')) {
      return 'Network error. Please check your connection and try again.';
    }
    // Partial broadcast must be checked before generic "broadcast rejected"
    if (lower.contains('broadcast failed after') && lower.contains('txs sent')) {
      return 'Some transactions were broadcast but not all. '
             'Please check your transaction history before retrying.';
    }
    if (lower.contains('broadcast rejected')) {
      return 'Transaction was rejected by the network. Please try again.';
    }
    if (lower.contains('proposal not found')) {
      return 'Transaction expired. Please try again.';
    }
    return 'Send failed. Please try again.';
  }

  String _formatZec(BigInt zatoshi) {
    final abs = zatoshi.abs();
    final whole = abs ~/ BigInt.from(100000000);
    final frac = (abs % BigInt.from(100000000)).toString().padLeft(8, '0');
    final sign = zatoshi < BigInt.zero ? '-' : '';
    return '$sign$whole.$frac';
  }

  /// Parse a ZEC string to zatoshi without floating-point.
  /// Handles: "1.5", ".01", "100", "0.00000001"
  int? _parseZecToZatoshi(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('.')) s = '0$s';

    final parts = s.split('.');
    if (parts.length > 2) return null;

    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
    if (whole == null || whole < 0) return null;

    String frac = parts.length > 1 ? parts[1] : '';
    if (frac.length > 8) frac = frac.substring(0, 8);
    frac = frac.padRight(8, '0');

    final fracInt = int.tryParse(frac);
    if (fracInt == null) return null;

    return whole * 100000000 + fracInt;
  }

  Future<void> _send() async {
    setState(() { _isSending = true; _error = null; });

    try {
      final address = _addressController.text.trim();
      final amountZatoshi = _parseZecToZatoshi(_amountController.text.trim());

      if (amountZatoshi == null || amountZatoshi <= 0) {
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
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (accountUuid == null) {
        setState(() { _error = 'No active account'; _isSending = false; });
        return;
      }
      final proposal = await rust_sync.proposeSend(
        dbPath: dbPath,
        network: 'main',
        accountUuid: accountUuid,
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

      // Step 4: Sign and execute
      final isHardware = ref.read(accountProvider.notifier).isActiveAccountHardware;

      String txidResult;
      if (isHardware) {
        // Hardware wallet (Keystone): three-PCZT flow (matches zcash-android-wallet-sdk)
        //   1. createPcztFromProposal → base PCZT
        //   2. clone → addProofsToPczt → pcztWithProofs (local Orchard proofs)
        //   3. clone → redactPcztForSigner → send to Keystone → pcztWithSignatures
        //   4. extractAndBroadcastPczt(pcztWithProofs, pcztWithSignatures) → combines + broadcasts
        log('Send: creating PCZT from proposal ${proposal.proposalId}');
        final pcztBytes = await rust_sync.createPcztFromProposal(
          dbPath: dbPath,
          network: ZcashNetwork.mainnet.name,
          proposalId: proposal.proposalId,
        );

        log('Send: adding proofs to PCZT locally (sapling=${proposal.needsSaplingParams})');
        // Hand Sapling params paths to Rust only when the proposal actually
        // needs them. They were downloaded above in the `needsSaplingParams`
        // block, so the files are already on disk by the time we get here.
        final pcztWithProofs = await rust_sync.addProofsToPczt(
          pcztBytes: pcztBytes,
          spendParamsPath: proposal.needsSaplingParams ? spendPath : null,
          outputParamsPath: proposal.needsSaplingParams ? outputPath : null,
        );

        log('Send: redacting PCZT for hardware signer');
        final redactedPczt = await rust_sync.redactPcztForSigner(pcztBytes: pcztBytes);

        // Select transport and sign
        if (!mounted) return;
        final transport = await KeystoneTransport.select(context);
        if (transport == null || !mounted) {
          setState(() { _isSending = false; });
          return;
        }

        log('Send: signing PCZT via ${transport.name}');
        final pcztWithSignatures = await transport.signPczt(context, redactedPczt);

        // Combine, extract, and broadcast
        log('Send: combining PCZTs and broadcasting');
        txidResult = await rust_sync.extractAndBroadcastPczt(
          dbPath: dbPath,
          lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
          network: ZcashNetwork.mainnet.name,
          pcztWithProofsBytes: pcztWithProofs,
          pcztWithSignaturesBytes: pcztWithSignatures,
        );
      } else {
        // Software wallet: mnemonic-based signing
        final mnemonic = await ref.read(accountProvider.notifier).getActiveMnemonic();
        if (mnemonic == null) {
          setState(() { _error = 'Mnemonic not found for active account'; _isSending = false; });
          return;
        }

        final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);

        log('Send: executing proposal ${proposal.proposalId}');
        txidResult = await rust_sync.executeProposal(
          dbPath: dbPath,
          lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
          proposalId: proposal.proposalId,
          seed: seedBytes,
          spendParamsPath: proposal.needsSaplingParams ? spendPath : null,
          outputParamsPath: proposal.needsSaplingParams ? outputPath : null,
        );
      }

      log('Send: success, txids=$txidResult');

      // === Send confirmed at this point — all below is non-critical ===

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('Send: refreshAfterSend failed (non-critical): $e');
      }

      if (Platform.isIOS) {
        try {
          const channel = MethodChannel('com.zcash.wallet/background_sync');
          final available = await channel.invokeMethod<bool>('isAvailable') ?? false;
          if (available) {
            await channel.invokeMethod('startTxTracking');
            log('Send: iOS TX tracking started');
          }
        } catch (e) {
          log('Send: iOS TX tracking failed (non-critical): $e');
        }
      }

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
      setState(() { _error = _friendlyError(e.toString()); _isSending = false; });
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
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode} for $url');
      }
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
    final syncState = ref.watch(syncProvider).value;
    final spendable = syncState?.spendableBalance ?? BigInt.zero;
    final pending = syncState?.pendingBalance ?? BigInt.zero;

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
                    if (pending > BigInt.zero) ...[
                      const SizedBox(height: 4),
                      Text('+ ${_formatZec(pending)} ZEC pending confirmations',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        )),
                    ],
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
                          (_addressType == 'invalid' || _addressType == 'error')
                              ? Icons.error : Icons.check_circle,
                          color: (_addressType == 'invalid' || _addressType == 'error')
                              ? colors.error
                              : colors.tertiary,
                        )
                      : null,
                ),
                onChanged: (_) => _validateAddress(),
                maxLines: 2,
              ),
              if (_addressType == 'error')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Address validation failed. Please try again.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.error,
                      )),
                ),
              if (_addressType.isNotEmpty && _addressType != 'invalid' && _addressType != 'error')
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
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  _ZecAmountFormatter(),
                ],
                onChanged: (_) => _validateAmount(),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Amount (ZEC)',
                  hintText: '0.00000000',
                  errorText: _amountError != null && _amountError!.isNotEmpty
                      ? _amountError
                      : null,
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
                  onPressed: _isSending || _addressType == 'invalid' || _addressType == 'error' || _addressType.isEmpty || !_isAmountValid
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

/// Enforces: one decimal point max, up to 8 fractional digits.
class _ZecAmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Allow empty
    if (text.isEmpty) return newValue;

    // Only one decimal point
    if ('.'.allMatches(text).length > 1) return oldValue;

    // Limit fractional digits to 8
    final dotIndex = text.indexOf('.');
    if (dotIndex != -1 && text.length - dotIndex - 1 > 8) return oldValue;

    return newValue;
  }
}
