import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/app_icon.dart';
import '../../ledger/ledger_capability.dart';
import 'desktop_import_navigation.dart';
import 'desktop_method_selection.dart';

class DesktopHardwareSelectionScreen extends ConsumerWidget {
  const DesktopHardwareSelectionScreen({
    this.backRoute = '/import/method',
    this.deviceBackRoute = '/import/hardware',
    super.key,
  });

  final String backRoute;
  final String deviceBackRoute;

  String _deviceLocation(String destination) {
    final origin = Uri.parse(deviceBackRoute);
    return preserveDesktopImportEntry(
      origin.replace(
        queryParameters: {
          ...origin.queryParameters,
          'entry': 'hardware-method',
        },
      ),
      destination,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showLedger = ref.watch(ledgerStaticCapabilityProvider).supported;

    return DesktopMethodSelectionScaffold(
      title: context.l10n.onboardingConnectHardwareTitle,
      subtitle: context.l10n.onboardingConnectHardwareSubtitleDesktop,
      footerLabel: context.l10n.commonBack,
      onFooterPressed: () => context.go(backRoute),
      cards: [
        DesktopMethodSelectionCard(
          key: const ValueKey('desktop_hardware_keystone_card'),
          iconName: AppIcons.keystone,
          title: context.l10n.onboardingConnectKeystone,
          description: context.l10n.onboardingImportFromKeystone,
          onPressed: () => context.go(_deviceLocation('/onboarding/keystone')),
        ),
        if (showLedger)
          DesktopMethodSelectionCard(
            key: const ValueKey('desktop_hardware_ledger_card'),
            iconName: AppIcons.ledger,
            title: context.l10n.onboardingConnectLedger,
            description: context.l10n.onboardingImportFromLedger,
            onPressed: () => context.go(_deviceLocation('/onboarding/ledger')),
          ),
      ],
    );
  }
}
