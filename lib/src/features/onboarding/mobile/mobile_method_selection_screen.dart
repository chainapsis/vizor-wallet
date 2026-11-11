import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import 'mobile_onboarding_progress_scope.dart';

import '../../../core/widgets/app_icon.dart';
import '../../ledger/ledger_capability.dart';
import 'mobile_onboarding_selection.dart';

/// Import choices reached from Welcome's Import wallet action.
class MobileMethodSelectionScreen extends ConsumerWidget {
  const MobileMethodSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showLedger =
        ref.watch(ledgerStaticCapabilityProvider).supported &&
        ledgerSupportsBluetooth(ref.watch(ledgerTargetPlatformProvider));
    return MobileOnboardingSelectionPage(
      scrollKey: const ValueKey('mobile_method_selection_scroll'),
      title: context.l10n.onboardingImportMethodTitle,
      subtitle: context.l10n.onboardingImportMethodSubtitle,
      cards: [
        MobileOnboardingSelectionCard(
          key: const ValueKey('mobile_import_passphrase'),
          iconName: AppIcons.key,
          title: context.l10n.onboardingImportSecretPassphrase,
          description:
              context.l10n.onboardingImportSecretPassphraseDescriptionMobile,
          onPressed: () => context.pushOnboarding('/import'),
        ),
        MobileOnboardingSelectionCard(
          key: const ValueKey('mobile_welcome_link_desktop'),
          iconName: AppIcons.monitor,
          title: context.l10n.onboardingLinkVizorDesktop,
          description: context.l10n.onboardingLinkVizorDesktopDescription,
          onPressed: () => context.pushOnboarding('/onboarding/link-desktop'),
        ),
        MobileOnboardingSelectionCard(
          key: const ValueKey('mobile_import_hardware'),
          iconName: AppIcons.usb,
          title: context.l10n.onboardingConnectHardwareWallet,
          description: showLedger
              ? context.l10n.onboardingHardwareLedgerOrKeystone
              : context.l10n.onboardingHardwareKeystoneOnly,
          onPressed: () => context.pushOnboarding('/onboarding/hardware'),
        ),
      ],
    );
  }
}
