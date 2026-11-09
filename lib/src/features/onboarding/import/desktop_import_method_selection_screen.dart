import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
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
      title: context.l10n.onboardingImportMethodTitle,
      subtitle: context.l10n.onboardingImportMethodSubtitle,
      footerLabel: context.l10n.commonCancel,
      onFooterPressed: onCancel ?? () => context.go(cancelRoute),
      cards: [
        DesktopMethodSelectionCard(
          key: const ValueKey('desktop_import_secret_passphrase_card'),
          iconName: AppIcons.key,
          title: context.l10n.onboardingImportSecretPassphrase,
          description:
              context.l10n.onboardingImportSecretPassphraseDescriptionDesktop,
          onPressed: () => context.go(secretPassphraseRoute),
        ),
        DesktopMethodSelectionCard(
          key: const ValueKey('desktop_import_hardware_card'),
          iconName: AppIcons.usb,
          title: context.l10n.onboardingConnectHardwareWallet,
          description: ref.watch(ledgerStaticCapabilityProvider).supported
              ? context.l10n.onboardingHardwareLedgerOrKeystone
              : context.l10n.onboardingHardwareKeystoneOnly,
          onPressed: () => context.go(hardwareRoute),
        ),
      ],
    );
  }
}
