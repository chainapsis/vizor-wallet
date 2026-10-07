import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import 'desktop_method_selection.dart';
import '../../ledger/ledger_capability.dart';

class DesktopImportMethodSelectionScreen extends ConsumerWidget {
  const DesktopImportMethodSelectionScreen({
    this.cancelRoute = '/welcome',
    this.onCancel,
    this.hardwareRoute = '/import/hardware',
    this.secretPassphraseRoute = '/import?entry=import-method',
    super.key,
  });

  final String cancelRoute;
  final VoidCallback? onCancel;
  final String hardwareRoute;
  final String secretPassphraseRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DesktopMethodSelectionScaffold(
      title: 'Import Account\nto Vizor',
      subtitle: 'Select the method you want.',
      footerLabel: 'Cancel',
      onFooterPressed: onCancel ?? () => context.go(cancelRoute),
      cards: [
        DesktopMethodSelectionCard(
          key: const ValueKey('desktop_import_secret_passphrase_card'),
          iconName: AppIcons.key,
          title: 'Import secret passphrase',
          description: 'Vizor or any other Zcash wallet',
          onPressed: () => context.go(secretPassphraseRoute),
        ),
        DesktopMethodSelectionCard(
          key: const ValueKey('desktop_import_hardware_card'),
          iconName: AppIcons.usb,
          title: 'Connect hardware wallet',
          description: ref.watch(ledgerStaticCapabilityProvider).supported
              ? 'Ledger or Keystone wallet'
              : 'Keystone wallet',
          onPressed: () => context.go(hardwareRoute),
        ),
      ],
    );
  }
}
