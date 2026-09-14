# Mobile bottom insets

Use when changing sheet/tab-bar padding, keyboard insets, or iOS/Android bottom geometry.

Implementation: [app_mobile_shell.dart](../../../../lib/src/core/layout/mobile/app_mobile_shell.dart), [mobile_tab_history.dart](../../../../lib/src/core/navigation/mobile_tab_history.dart), [mobile_bottom_safe_area.dart](../../../../lib/src/core/layout/mobile/mobile_bottom_safe_area.dart).

- Sheet bodies and the floating tab bar use `MobileBottomSafeArea`.
  `bottomPadding` is the actual padding below the last control. On iOS, at least
  `kIosHomeIndicatorClearance` (16) suppresses the extra bottom inset; Android
  always honors its navigation-bar inset. Keyboard `viewInsets` stay separate;
  tests override `defaultTargetPlatform`.

- The mobile tab bar has a 16px bottom gap on iOS and 12px plus the inset on
  Android. Keep the wrapper argument aligned when changing a padding token.

## Verification

[Mobile bottom inset tests](../../../../test/core/layout/mobile/mobile_bottom_safe_area_test.dart).
