import 'package:flutter/widgets.dart';

import '../profile_pictures.dart';
import '../theme/app_theme.dart';

enum AppProfilePictureSize {
  medium(24),
  large(32),
  navLarge(40),
  xLarge(56),
  xxLarge(72);

  const AppProfilePictureSize(this.dimension);

  final double dimension;

  double get radius => dimension / 2;
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

    return Container(
      width: size.dimension,
      height: size.dimension,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        shape: BoxShape.circle,
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
