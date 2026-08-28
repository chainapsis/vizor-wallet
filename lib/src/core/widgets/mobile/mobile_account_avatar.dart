import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../../providers/account_models.dart';
import '../app_icon.dart';
import '../app_profile_picture.dart';

/// [AppProfilePicture] with a vendor-specific hardware signer badge.
class MobileAccountAvatar extends StatelessWidget {
  const MobileAccountAvatar({
    required this.profilePictureId,
    required this.size,
    this.hardwareSignerKind,
    this.badgeRingColor,
    this.badgeBorderWidth = 2,
    this.badgeRight = -4,
    this.badgeBottom = -2,
    super.key,
  });

  final String profilePictureId;
  final AppProfilePictureSize size;
  final HardwareSignerKind? hardwareSignerKind;

  /// Ring color around the badge — pass the surface the avatar sits on.
  /// Defaults to the card/sheet ground surface.
  final Color? badgeRingColor;

  final double badgeBorderWidth;
  final double badgeRight;
  final double badgeBottom;

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
          if (hardwareSignerKind case final signerKind?)
            Positioned(
              right: badgeRight,
              bottom: badgeBottom,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.background.inverse,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: badgeRingColor ?? colors.background.ground,
                    width: badgeBorderWidth,
                  ),
                ),
                child: Center(
                  child: AppIcon(
                    signerKind == HardwareSignerKind.keystone
                        ? AppIcons.keystone
                        : AppIcons.ledger,
                    key: ValueKey('hardware_signer_badge_${signerKind.name}'),
                    size: signerKind == HardwareSignerKind.ledger ? 16 : 12,
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
