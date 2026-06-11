import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../app_icon.dart';
import '../app_profile_picture.dart';

/// [AppProfilePicture] with the Keystone hardware badge from the mobile
/// frames (`User Keystone Badge`, 20 px): a dark rounded square pinned
/// to the avatar's bottom-right corner with a surface-colored ring.
class MobileAccountAvatar extends StatelessWidget {
  const MobileAccountAvatar({
    required this.profilePictureId,
    required this.size,
    this.isHardware = false,
    this.badgeRingColor,
    super.key,
  });

  final String profilePictureId;
  final AppProfilePictureSize size;
  final bool isHardware;

  /// Ring color around the badge — pass the surface the avatar sits on.
  /// Defaults to the card/sheet ground surface.
  final Color? badgeRingColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: size.dimension,
      height: size.dimension,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppProfilePicture(profilePictureId: profilePictureId, size: size),
          if (isHardware)
            Positioned(
              right: -4,
              bottom: -2,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.background.inverse,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: badgeRingColor ?? colors.background.ground,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.keystone,
                    size: 12,
                    color: colors.icon.inverse,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
