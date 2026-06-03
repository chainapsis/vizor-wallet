import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/app_navigation_source.dart';

void main() {
  TargetPlatform? previousTargetPlatform;

  setUp(() {
    previousTargetPlatform = debugDefaultTargetPlatformOverride;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = previousTargetPlatform;
  });

  test('uses mobile sidebar transition for sidebar navigation on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(
      shouldUseMobileSidebarTransition(AppNavigationSource.mainSidebar),
      isTrue,
    );
  });

  test('does not use mobile sidebar transition on desktop platforms', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    expect(
      shouldUseMobileSidebarTransition(AppNavigationSource.mainSidebar),
      isFalse,
    );
  });

  test('does not use mobile sidebar transition without sidebar source', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(shouldUseMobileSidebarTransition(null), isFalse);
  });
}
