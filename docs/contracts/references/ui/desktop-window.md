# Desktop window bootstrap

Use when changing native window creation, showing, sizing, or appearance.

Implementation: [app.dart](../../../../lib/app.dart): `initializeZcashWalletRuntime`, `runZcashWalletApp`; [app_layout.dart](../../../../lib/src/core/layout/app_layout.dart); [MainFlutterWindow.swift](../../../../macos/Runner/MainFlutterWindow.swift).

- `window_manager` owns desktop sizing and lifecycle; `desktop_window_bootstrap`
  owns native appearance. Create the OS window before initializing its visuals.
  The current runtime requests `DesktopWindowVisualStyle.opaque`.

- `runZcashWalletApp` shows Windows after the first Flutter frame; other desktop
  platforms show during initialization. Preserve that order, not a universal
  show-before-`runApp` rule.

- Native/bootstrap code owns appearance. Exposing a translucent native region
  requires a transparent Flutter background; opaque fills cover it. The current
  opaque shell need not become translucent.

## Verification

Verify native-window changes on the real window surface. General checks: [CONTRIBUTING](../../../../CONTRIBUTING.md#testing).
