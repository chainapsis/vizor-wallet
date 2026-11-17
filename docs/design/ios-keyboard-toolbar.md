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

References: [Apple keyboard layout guide](https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide),
[undocked guide behavior](https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide/followsundockedkeyboard).
