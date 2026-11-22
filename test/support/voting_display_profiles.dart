import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_layout.dart';

import 'widget_test_viewport.dart';

/// Logical app viewport and Flutter backing scale. Desktop device entries model
/// example windows; OS chrome, macOS final display scaling, and camera optics
/// are outside a widget capture. Insets are representative portrait safe areas.
class VotingDisplayProfile {
  const VotingDisplayProfile(
    this.name,
    this.size,
    this.ratio, {
    this.top = 0,
    this.bottom = 0,
  });
  final String name;
  final Size size;
  final double ratio;
  final double top;
  final double bottom;

  Future<void> apply(WidgetTester tester) async {
    await setWidgetTestViewport(tester, size, devicePixelRatio: ratio);
    final padding = FakeViewPadding(top: top * ratio, bottom: bottom * ratio);
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }
}

final desktopVotingProfiles = [
  for (final ratio in [1.0, 1.25, 2.0])
    VotingDisplayProfile(
      'Desktop minimum at ${ratio}x',
      AppLayoutMode.large.minimumSize,
      ratio,
    ),
  const VotingDisplayProfile('13-inch MacBook Air', Size(1280, 832), 2),
  const VotingDisplayProfile('15-inch MacBook Air', Size(1440, 932), 2),
  const VotingDisplayProfile('14-inch MacBook Pro', Size(1512, 982), 2),
  const VotingDisplayProfile('16-inch MacBook Pro', Size(1728, 1117), 2),
  const VotingDisplayProfile('1366 by 768 laptop', Size(1366, 768), 1),
  const VotingDisplayProfile(
    '1080p Windows laptop at 125%',
    Size(1536, 864),
    1.25,
  ),
];

const mobileVotingProfiles = [
  VotingDisplayProfile(
    'iPhone SE (3rd generation)',
    Size(375, 667),
    2,
    top: 20,
  ),
  VotingDisplayProfile('iPhone 16e', Size(390, 844), 3, top: 47, bottom: 34),
  VotingDisplayProfile('iPhone 16', Size(393, 852), 3, top: 59, bottom: 34),
  VotingDisplayProfile(
    'iPhone 16 Pro / 17',
    Size(402, 874),
    3,
    top: 62,
    bottom: 34,
  ),
  VotingDisplayProfile(
    'iPhone 16 Pro Max',
    Size(440, 956),
    3,
    top: 62,
    bottom: 34,
  ),
  VotingDisplayProfile(
    'Galaxy A06 at 2x',
    Size(360, 800),
    2,
    top: 24,
    bottom: 24,
  ),
  VotingDisplayProfile(
    'Galaxy A16 5G at 3x',
    Size(360, 780),
    3,
    top: 24,
    bottom: 24,
  ),
];
