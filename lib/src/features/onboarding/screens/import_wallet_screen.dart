import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../providers/account_provider.dart';

class ImportWalletScreen extends ConsumerStatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  ConsumerState<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends ConsumerState<ImportWalletScreen> {
  final _mnemonicController = TextEditingController();
  final _birthdayController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  bool get _isValid {
    final text = _mnemonicController.text.trim();
    final words = text.split(RegExp(r'\s+'));
    final wordCountOk = words.length == 24;
    final mnemonicValid =
        wordCountOk ? rust_wallet.validateMnemonic(mnemonic: text) : false;
    log('ImportScreen._isValid: wordCount=${words.length}, wordCountOk=$wordCountOk, mnemonicValid=$mnemonicValid');
    return wordCountOk && mnemonicValid;
  }

  Future<void> _import() async {
    log('ImportScreen._import: button pressed');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final birthdayText = _birthdayController.text.trim();
      final birthdayHeight =
          birthdayText.isNotEmpty ? int.tryParse(birthdayText) : null;
      log('ImportScreen._import: calling importWallet, birthdayHeight=$birthdayHeight');

      await ref.read(accountProvider.notifier).importAccount(
            mnemonic: _mnemonicController.text.trim(),
            birthdayHeight: birthdayHeight,
          );

      log('ImportScreen._import: importWallet completed, navigating to /home');
      if (mounted) context.go('/home');
    } catch (e, st) {
      log('ImportScreen._import: ERROR: $e\n$st');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Wallet')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your recovery phrase',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the 24 words separated by spaces.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _mnemonicController,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'word1 word2 word3 ...',
                  labelText: 'Recovery Phrase',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _birthdayController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 419200',
                  labelText: 'Birthday Height (optional)',
                  helperText:
                      'Block height when wallet was created. Speeds up sync.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isValid && !_isLoading ? _import : null,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Import'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
