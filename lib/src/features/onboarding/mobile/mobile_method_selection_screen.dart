import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      title: 'Import Account\nto Vizor',
      subtitle: 'Select the method you want.',
      cards: [
        MobileOnboardingSelectionCard(
          key: const ValueKey('mobile_import_passphrase'),
          iconName: AppIcons.key,
          title: 'Import secret passphrase',
          description: 'Vizor, ZODL, or any other wallet',
          onPressed: () => context.pushOnboarding('/import'),
        ),
        MobileOnboardingSelectionCard(
          key: const ValueKey('mobile_welcome_link_desktop'),
          iconName: AppIcons.monitor,
          title: 'Link Vizor Desktop',
          description: 'Scan & connect to Vizor Desktop',
          onPressed: () => context.pushOnboarding('/onboarding/link-desktop'),
        ),
        MobileOnboardingSelectionCard(
          key: const ValueKey('mobile_import_hardware'),
          iconName: AppIcons.usb,
          title: 'Connect hardware wallet',
          description: showLedger
              ? 'Ledger or Keystone wallet'
              : 'Keystone wallet',
          onPressed: () => context.pushOnboarding('/onboarding/hardware'),
        ),
      ],
    );
  }
}
