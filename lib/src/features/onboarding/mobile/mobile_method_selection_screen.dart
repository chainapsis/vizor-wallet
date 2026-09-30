import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import 'mobile_onboarding_selection.dart';

/// Import choices reached from Welcome's Import wallet action.
class MobileMethodSelectionScreen extends StatelessWidget {
  const MobileMethodSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) => MobileOnboardingSelectionPage(
    scrollKey: const ValueKey('mobile_method_selection_scroll'),
    title: 'Import Account\nto Vizor',
    subtitle: 'Select the method you want.',
    cards: [
      MobileOnboardingSelectionCard(
        key: const ValueKey('mobile_import_passphrase'),
        iconName: AppIcons.key,
        title: 'Import secret passphrase',
        description: 'Vizor, ZODL, or any other wallet',
        onPressed: () => context.push('/import'),
      ),
      MobileOnboardingSelectionCard(
        key: const ValueKey('mobile_welcome_link_desktop'),
        iconName: AppIcons.monitor,
        title: 'Link Vizor Desktop',
        description: 'Scan & connect to Vizor Desktop',
        onPressed: () => context.push('/onboarding/link-desktop'),
      ),
      MobileOnboardingSelectionCard(
        key: const ValueKey('mobile_import_hardware'),
        iconName: AppIcons.usb,
        title: 'Connect hardware wallet',
        description: 'Ledger or Keystone wallet',
        onPressed: () => context.push('/onboarding/hardware'),
      ),
    ],
  );
}
