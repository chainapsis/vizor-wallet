import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/tor_settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torEnabled = ref.watch(torSettingsProvider);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader(context, 'Privacy'),
          SwitchListTile(
            title: const Text('Route through Tor'),
            subtitle: Text(
              'Hides your wallet\'s IP address from the lightwalletd '
              'server. First connection is slower while the Tor '
              'circuit bootstraps. Toggling forces the current sync '
              'to restart.',
              style: text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            value: torEnabled,
            onChanged: (value) {
              ref.read(torSettingsProvider.notifier).setEnabled(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: text.labelSmall?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
