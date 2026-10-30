import 'package:flutter/widgets.dart';

import '../profile_pictures.dart';

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

    return SizedBox(
      width: size.dimension,
      height: size.dimension,
      child: ClipOval(
        child: Image.asset(
          option.assetPath,
          width: size.dimension,
          height: size.dimension,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
