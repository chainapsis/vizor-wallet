# iOS keyboard dismiss control

`MobileKeyboardToolbar` publishes whether the focused Flutter input and its
keyboard inset permit a dismiss control. `KeyboardToolbarHandler` owns the
native glass button, positioned above `UIKeyboardLayoutGuide`. Flutter owns
focus and text; pressing the button ends native editing and unfocuses Flutter.

## Visibility contract

A Flutter `visible: true` request is permission, not proof of an onscreen
keyboard. Swift also requires a finite, nonempty keyboard guide intersecting
the host view, extending above its bottom safe area, and reaching its bottom
edge. The guide collapses to the bottom safe area for an absent or undocked
keyboard. In those states the custom control stays hidden. This preserves the
existing docked-keyboard scope of Flutter's bottom-inset check.

Native hide notifications and Done immediately hide the control. They preserve
or clear the Flutter request as appropriate: an ordinary keyboard replacement
can restore the last request, while Done clears it. Subsequent show/frame
notifications still require actual host geometry before displaying anything.
Non-local or different-screen show/frame notifications cannot restore it.

A hidden, noninteractive layout probe follows the guide's top edge. Guide or
window-size changes coalesce a visibility check on the main queue, without a
new Flutter request, polling timer, or per-frame channel messages. A missing
foreground host also hides an existing control. Disposing the handler removes
its observers, probe and button.

This matters on iPhone Duo: fold/unfold changes can update Flutter focus/insets
and UIKit keyboard geometry on different frames. A cached show request must
never leave a standalone checkmark at the bottom of a keyboardless screen.

## Verification

Run the mobile bridge/focus regressions with the mobile token define:

```bash
fvm flutter test test/core/widgets/mobile/mobile_keyboard_toolbar_test.dart \
  test/core/widgets/sync_keep_awake_privacy_lock_host_test.dart \
  --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile
```

`KeyboardToolbarHandlerTests` checks stale requests, empty/offscreen/floating
geometry, geometry-only changes, keyboard replacement, foreign notifications,
Done, and host availability. Native tests run on a dedicated simulator through
the Runner scheme; the actual app's test data must not be reused.

The existing `mobile-native-tab-bar` deterministic scenario includes the same
keyboard host and permits focus in its account-edit sheet. Use its name field
to check showing, dismissing, reopening, cancelling and folding with a keyboard
present. It contains no wallet, storage, Rust or network startup. Run it on Duo
and a conventional iPhone using the command in `docs/ios-native-tab-bar.md`.

References: [Apple keyboard layout guide](https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide),
[undocked guide behavior](https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide/followsundockedkeyboard).

On 2026-11-15, the two stale-request regressions failed before the change.
Afterward, all 11 keyboard-toolbar tests and 45 native tab-bar regressions
passed on the dedicated Duo simulator. The 56 mobile Flutter keyboard/privacy
regressions and full Flutter analysis also passed. The actual Runner fixture
was checked on iOS 27.2 Duo and iOS 26.5 iPhone 17 Pro: the native check dismissed
the Duo keyboard, reopening and folding preserved usable controls, closing the
input sheet left no checkmark, and changing keyboard languages on the regular
iPhone preserved the control until keyboard dismissal.

The exact production sequence behind the reported screenshot was not
conclusively reproduced. The native/Flutter timing mismatch was observed during
Duo unfolding; the regressions directly cover the keyboardless visibility
invariant that the old implementation violated.
