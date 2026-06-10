import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';

class OnboardingWelcomeBackdrop extends StatelessWidget {
  const OnboardingWelcomeBackdrop({
    super.key,
    this.fit = BoxFit.fill,
    this.alignment = Alignment.center,
  });

  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = isDark
        ? 'assets/illustrations/welcome_bg_dark.png'
        : 'assets/illustrations/welcome_bg_light.png';
    return Image.asset(asset, fit: fit, alignment: alignment);
  }
}

const _vizorWordmarkFrameWidth = 140.0;
const _vizorWordmarkFrameHeight = 52.83;
const _vizorWordmarkArtworkWidth = 127.748;
const _vizorWordmarkArtworkHeight = 36.758;

class VizorWordmark extends StatelessWidget {
  /// Figma frame is 140×52.83; the centered SVG artwork is 127.748×36.758.
  const VizorWordmark({
    super.key,
    this.width = _vizorWordmarkFrameWidth,
    this.height = _vizorWordmarkFrameHeight,
    this.color,
  });

  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/vizor_logo.svg',
          width: width * _vizorWordmarkArtworkWidth / _vizorWordmarkFrameWidth,
          height:
              height * _vizorWordmarkArtworkHeight / _vizorWordmarkFrameHeight,
          colorFilter: ColorFilter.mode(
            color ?? colors.text.accent,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
