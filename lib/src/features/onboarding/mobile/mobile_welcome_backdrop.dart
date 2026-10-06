import 'package:flutter/widgets.dart';

import '../shared/welcome_video_backdrop.dart';

const kMobileWelcomeVideoAsset = 'assets/animations/mobile_welcome.mp4';
const kMobileWelcomePosterAsset =
    'assets/illustrations/mobile_welcome_poster.webp';

class MobileWelcomeBackdrop extends StatelessWidget {
  const MobileWelcomeBackdrop({this.animate = true, super.key});

  final bool animate;

  @override
  Widget build(BuildContext context) => WelcomeVideoBackdrop(
    videoAsset: kMobileWelcomeVideoAsset,
    posterAsset: kMobileWelcomePosterAsset,
    animate: animate,
  );
}
