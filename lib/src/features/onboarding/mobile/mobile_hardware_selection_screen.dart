import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import '../../ledger/ledger_capability.dart';
import 'mobile_onboarding_selection.dart';

class MobileHardwareSelectionScreen extends ConsumerWidget {
  const MobileHardwareSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showLedger =
        ref.watch(ledgerStaticCapabilityProvider).supported &&
        ledgerSupportsBluetooth(ref.watch(ledgerTargetPlatformProvider));
    return MobileOnboardingSelectionPage(
      scrollKey: const ValueKey('mobile_hardware_selection_scroll'),
      title: 'Connect\nHardware Wallet',
      subtitle: 'Select your hardware device.',
      cards: [
        MobileOnboardingSelectionCard(
          key: const ValueKey('mobile_welcome_keystone'),
          iconName: AppIcons.keystone,
          title: 'Connect Keystone',
          description: 'Import from Keystone wallet',
          onPressed: () => context.push('/onboarding/keystone'),
        ),
        if (showLedger)
          MobileOnboardingSelectionCard(
            key: const ValueKey('mobile_welcome_ledger'),
            iconName: AppIcons.ledger,
            title: 'Connect Ledger',
            description: 'Import from Ledger wallet',
            onPressed: () => context.push('/onboarding/ledger'),
          ),
      ],
    );
  }
}
