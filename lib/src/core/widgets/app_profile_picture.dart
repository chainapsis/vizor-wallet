import 'package:flutter/widgets.dart';

import '../profile_pictures.dart';
import '../theme/app_theme.dart';

enum AppProfilePictureSize {
  medium(24, AppRadii.xSmall),
  large(32, AppRadii.small),
  xLarge(56, AppRadii.medium);

  const AppProfilePictureSize(this.dimension, this.radius);

  final double dimension;
  final double radius;
}

class AppProfilePicture extends StatelessWidget {
  const AppProfilePicture({
    super.key,
    required this.profilePictureId,
    this.size = AppProfilePictureSize.medium,
  });

  final String profilePictureId;
  final AppProfilePictureSize size;

  @override
  Widget build(BuildContext context) {
    final option = resolveProfilePictureOption(profilePictureId);
    final isZns = isZnsProfilePictureId(profilePictureId);

    return Container(
      width: size.dimension,
      height: size.dimension,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isZns ? const Color(0xFFD4A843) : context.colors.background.raised,
        borderRadius: BorderRadius.circular(size.radius),
      ),
      child: Image.asset(
        option.assetPath,
        width: size.dimension,
        height: size.dimension,
        fit: BoxFit.cover,
      ),
    );
  }
}
