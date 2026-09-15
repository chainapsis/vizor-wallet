import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_button.dart';
import '../ledger_capability.dart';

/// Null where there is no supported Bluetooth-settings shortcut.
final ledgerBluetoothSettingsOpenerProvider =
    Provider<Future<bool> Function()?>((ref) {
      return switch (ref.watch(ledgerTargetPlatformProvider)) {
        TargetPlatform.macOS => () => launchUrl(
          Uri.parse('x-apple.systempreferences:com.apple.BluetoothSettings'),
        ),
        TargetPlatform.windows => () => launchUrl(
          Uri.parse('ms-settings:bluetooth'),
        ),
        TargetPlatform.android =>
          () async =>
              await const MethodChannel(
                'com.zcash.wallet/ledger_mobile',
              ).invokeMethod<bool>('openBluetoothSettings') ??
              false,
        _ => null,
      };
    });

class LedgerBluetoothSettingsButton extends ConsumerWidget {
  const LedgerBluetoothSettingsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(ledgerBluetoothSettingsOpenerProvider);
    if (open == null) return const SizedBox.shrink();
    return AppButton(
      expand: true,
      constrainContent: true,
      variant: AppButtonVariant.ghost,
      onPressed: () async {
        var opened = false;
        try {
          opened = await open();
        } catch (_) {
          // Keep the recovery screen available if the OS refuses the shortcut.
        }
        if (!opened && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Open Bluetooth settings on your device to continue.',
              ),
            ),
          );
        }
      },
      child: const Text('Open Bluetooth settings'),
    );
  }
}
