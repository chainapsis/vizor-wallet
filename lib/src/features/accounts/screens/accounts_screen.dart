import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/account_provider.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountProvider);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddAccountSheet(context),
          ),
        ],
      ),
      body: accountState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: state.accounts.length,
          itemBuilder: (context, index) {
            final account = state.accounts[index];
            final isActive = account.uuid == state.activeAccountUuid;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isActive
                    ? colors.primary
                    : colors.surfaceContainerHigh,
                child: Text(
                  account.name.isNotEmpty ? account.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: isActive ? colors.onPrimary : colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(
                account.name,
                style: text.titleMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              trailing: isActive
                  ? Icon(Icons.check_circle, color: colors.primary)
                  : null,
              onTap: () async {
                if (!isActive) {
                  await ref.read(accountProvider.notifier).switchAccount(account.uuid);
                }
                if (context.mounted) context.pop();
              },
              onLongPress: () => _showRenameDialog(context, ref, account),
            );
          },
        ),
      ),
    );
  }

  void _showAddAccountSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create New Wallet'),
              subtitle: const Text('Generate a new mnemonic'),
              onTap: () {
                Navigator.pop(context);
                context.push('/create');
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Import Wallet'),
              subtitle: const Text('From existing mnemonic'),
              onTap: () {
                Navigator.pop(context);
                context.push('/import');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, AccountInfo account) {
    final controller = TextEditingController(text: account.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Account'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Account Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                ref.read(accountProvider.notifier).renameAccount(account.uuid, newName);
              }
              Navigator.pop(context);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose;
  }
}
