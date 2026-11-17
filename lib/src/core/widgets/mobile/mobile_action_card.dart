import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../app_icon.dart';
import 'mobile_surface_card.dart';

/// A tappable card that starts an action: an icon in a round badge coloured
/// like the primary button, a title and a short description. Stack them with [AppSpacing.s] between for
/// a sheet of choices, such as the mobile Home Receive sheet.
///
/// The card owns no haptics or navigation; [onTap] does.
class MobileActionCard extends StatelessWidget {
  const MobileActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  /// An [AppIcons] name, drawn in the badge.
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const _badgeSize = 36.0;
  static const _iconSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      // One item for screen readers: the title, then the description.
      container: true,
      button: true,
      label: '$title\n$subtitle',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // The mobile surface of the settings groups, with its soft lift.
        child: MobileSurfaceCard(
          cornerRadius: AppRadii.large,
          child: Row(
            children: [
              Container(
                width: _badgeSize,
                height: _badgeSize,
                alignment: Alignment.center,
                // The primary button's colours: dark in light theme, light in
                // dark theme.
                decoration: BoxDecoration(
                  color: colors.button.primary.bg,
                  shape: BoxShape.circle,
                ),
                child: AppIcon(
                  icon,
                  size: _iconSize,
                  color: colors.button.primary.label,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
