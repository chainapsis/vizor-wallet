import 'package:flutter/widgets.dart';

import '../shared/welcome_art_assets.dart';
import '../shared/welcome_video_backdrop.dart';

const kMobileWelcomeVideoAsset = 'assets/animations/mobile_welcome.mp4';
const kMobileWelcomePosterAsset =
    'assets/illustrations/mobile_welcome_poster.webp';

class MobileWelcomeBackdrop extends StatelessWidget {
  const MobileWelcomeBackdrop({
    this.animate = true,
    this.landscape = false,
    super.key,
  });

  final bool animate;
  final bool landscape;

  @override
  Widget build(BuildContext context) => WelcomeVideoBackdrop(
    // A source change must replace the native controller, not just its poster.
    key: ValueKey(landscape),
    videoAsset: landscape
        ? kLandscapeWelcomeVideoAsset
        : kMobileWelcomeVideoAsset,
    posterAsset: landscape
        ? kLandscapeWelcomePosterAsset
        : kMobileWelcomePosterAsset,
    animate: animate,
  );
}
