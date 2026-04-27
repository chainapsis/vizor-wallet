import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';

class OnboardingWelcomeBackdrop extends StatelessWidget {
  const OnboardingWelcomeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = isDark
        ? 'assets/illustrations/welcome_bg_dark.png'
        : 'assets/illustrations/welcome_bg_light.png';
    return Image.asset(asset, fit: BoxFit.fill);
  }
}

class VizorWordmark extends StatelessWidget {
  const VizorWordmark({super.key, this.width = 74, this.height = 37});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/vizor_logo.svg',
          width: width * 62 / 74,
          colorFilter: ColorFilter.mode(colors.text.accent, BlendMode.srcIn),
        ),
      ),
    );
  }
}
