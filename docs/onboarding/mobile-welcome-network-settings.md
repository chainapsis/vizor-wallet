# Mobile Welcome network settings

## Scope

The initial walletless Welcome opens a network settings sheet from its cog.
Additional-account Welcome does not expose it. Tor and the custom lightwalletd
endpoint use the existing settings providers and persistent preferences.

Welcome retains its video, copy and CTA positions. Connection status stays
inside the sheet. Private queries, endpoint presets and latency sweeps remain
in Settings.

## Tor and dismissal

- Off or connected: close, outside tap, drag and Back can dismiss.
- Connecting: every dismissal path is blocked. Turning Tor off cancels the
  attempt through the existing provider; direct-route switching finishes
  before dismissal becomes available.
- Switching to direct: Tor controls and dismissal are temporarily disabled.
- Failed with the Tor route retained: retry or explicitly turn Tor off. Never
  silently downgrade to a direct connection. A failed disable must still
  describe the retained Tor route accurately.
- Failed with a usable direct route: show the setting/save failure honestly;
  dismissal remains available. Saved preferences may still enable Tor on the
  next launch.
- Tor success does not close the sheet: the endpoint can be edited next.

Dismissal is locked before the first await of a toggle, not only after the
provider publishes Connecting. Cancellation supersedes the earlier operation;
its late completion cannot clear the newer operation's hold.

The sheet route observes the same dismissal control for barrier, drag and
PopScope. It waits for its exit transition before releasing the Gift-link hold.
Other sheet callers keep their existing presentation defaults.

## Custom endpoint

Edits are an unsaved local draft. Ordinary dismissal discards the draft without
changing an already-applied Tor choice.

Update validates the URL and build policy, verifies the chain through the
selected route, then persists. Verification has a 30-second total Rust deadline
including channel establishment; the existing 10-second response deadline
remains. A Dart timeout around a still-running save is not used.

During verification/save, input, Tor controls and all dismissal paths are
blocked. Verification, wrong-network and storage errors retain the draft.
Current changes only after persistence succeeds; persistence failures can leave
partially written storage, so retry completes the setting rather than promising
an atomic rollback. Success closes the sheet and shows `Endpoint updated`.

No wallet sync starts before an account exists. Existing Settings still restarts
sync after endpoint updates.

## Startup and incoming links

Persisted Tor can reconnect on startup. If walletless Welcome is entered while
Tor is connecting or failed with a retained Tor route, the same sheet opens
once. No unsaved URL draft or keyboard is restored.

Gift intake retains an incoming link while this sheet is open, including while
its transport is already ready. Welcome CTAs and the walletless `/gift` push
also check readiness immediately before navigation. After the sheet's exit,
intake is drained with the current route and unlock state rechecked. ZIP-321's
existing rejection during Welcome/onboarding is unchanged.

## Review surfaces

Widgetbook: `Screens / Onboarding / Mobile welcome network settings`.
Tor controls reuse the production widget. RPC pending/error fixtures reuse the
production content layout without storage or network calls.

Capture scenarios start with `mobile-welcome-network-`: `off`, `connecting`,
`connected`, `switching`, `failed`, `save-failed`, `rpc-checking`,
`rpc-wrong-network`, and `rpc-save-failed`.

Mobile tests require `--dart-define=VIZOR_FORM_FACTOR=mobile` and the project's
mobile test lane. Platform route tests cover Android and iOS dismissal paths;
physical-device networking and native IME gestures require device verification.

The live iOS Simulator integration test in
`integration_test/mobile_welcome_network_settings_test.dart` exercises real Tor
cancellation, native keyboard focus and RPC verification on a fresh install.
It also checks that no wallet, sync or new wallet DB is created. It does not
cover full Tor bootstrap success or Android device networking.

Run it against a dedicated fresh-install test device:

```bash
fvm flutter test --tags mobile --run-skipped \
  --dart-define=VIZOR_FORM_FACTOR=mobile \
  integration_test/mobile_welcome_network_settings_test.dart -d <device-id>
```
