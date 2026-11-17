import 'package:flutter/widgets.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mobile/mobile_section.dart';
import 'mobile_tor_control.dart';
import 'mobile_private_queries_control.dart';
export 'mobile_tor_control.dart' show MobilePrivacyToggle;

/// Mobile Tor control.
///
/// Deliberately not the desktop [NetworkPrivacyControl]: that widget's copy is
/// mostly about desktop software updates, which mobile gets from the app
/// stores, and its toggle geometry belongs to a settings page rather than a
/// grouped card. The state machine behind both is the same provider.
class MobileNetworkPrivacyCard extends StatelessWidget {
  const MobileNetworkPrivacyCard({super.key});

  @override
  Widget build(BuildContext context) {
    // Titled above its card like the Settings list groups.
    return MobileSection(
      title: context.l10n.settingsPrivacyTitle,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MobileTorControl(),
          MobilePrivateQueriesControl(divided: true),
        ],
      ),
    );
  }
}
