import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/desktop_sidebar_spacing.dart';
import 'package:zcash_wallet/src/core/theme/app_spacing.dart';

void main() {
  group('mainSidebarTopPadding', () {
    test('keeps the macOS window-controls reserve in regular height', () {
      expect(
        mainSidebarTopPadding(compact: false, platform: TargetPlatform.macOS),
        40,
      );
    });

    test('keeps the compact macOS top padding', () {
      expect(
        mainSidebarTopPadding(compact: true, platform: TargetPlatform.macOS),
        AppSpacing.s,
      );
    });

    test('matches side padding on Windows and Linux', () {
      expect(
        mainSidebarTopPadding(compact: false, platform: TargetPlatform.windows),
        AppSpacing.sm,
      );
      expect(
        mainSidebarTopPadding(compact: true, platform: TargetPlatform.linux),
        AppSpacing.sm,
      );
    });
  });

  group('onboardingSidebarTopOffset', () {
    test('keeps the macOS window-controls reserve', () {
      expect(onboardingSidebarTopOffset(platform: TargetPlatform.macOS), 40);
    });

    test('uses the sidebar content padding on Windows and Linux', () {
      expect(onboardingSidebarTopOffset(platform: TargetPlatform.windows), 0);
      expect(onboardingSidebarTopOffset(platform: TargetPlatform.linux), 0);
    });
  });
}
