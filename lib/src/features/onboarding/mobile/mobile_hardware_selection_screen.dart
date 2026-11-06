import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import 'mobile_onboarding_progress_scope.dart';

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
      title: context.l10n.onboardingConnectHardwareTitle,
      subtitle: context.l10n.onboardingConnectHardwareSubtitleMobile,
      cards: [
        MobileOnboardingSelectionCard(
          key: const ValueKey('mobile_welcome_keystone'),
          iconName: AppIcons.keystone,
          title: context.l10n.onboardingConnectKeystone,
          description: context.l10n.onboardingImportFromKeystone,
          onPressed: () => context.pushOnboarding('/onboarding/keystone'),
        ),
        if (showLedger)
          MobileOnboardingSelectionCard(
            key: const ValueKey('mobile_welcome_ledger'),
            iconName: AppIcons.ledger,
            title: context.l10n.onboardingConnectLedger,
            description: context.l10n.onboardingImportFromLedger,
            onPressed: () => context.pushOnboarding('/onboarding/ledger'),
          ),
      ],
    );
  }
}
