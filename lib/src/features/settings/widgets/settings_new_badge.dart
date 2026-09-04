import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

/// The small "New" pill rendered next to a settings row label. Shared by the
/// desktop and mobile settings lists so both surfaces flag the same entry the
/// same way.
class SettingsNewBadge extends StatelessWidget {
  const SettingsNewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final brandColor = context.colors.text.brandCrimson;

    return Container(
      key: const ValueKey('settings_gift_cards_new_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: brandColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'New',
        style: AppTypography.labelLarge.copyWith(color: brandColor),
      ),
    );
  }
}
