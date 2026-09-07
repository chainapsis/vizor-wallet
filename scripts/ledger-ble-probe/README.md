# Ledger-shaped virtual BLE probe

This directory contains a raw Android GATT probe and an official Ledger DMK
probe. Neither provides Vizor, Ledger firmware, RF, or Speculos E2E coverage.
No seed, wallet, or network transaction is used. The raw peripheral accepts
test bytes; `sdk_peripheral.py` implements single-frame Ledger APDU transport
and synthetic responses. Do not use either to validate signatures.

## Run

Use a disposable/read-only AVD. The tested environment was macOS, Android
Emulator 35.4.9, Android 36 arm64, and Bumble 0.0.234.

1. Start the emulator with `-read-only -no-snapshot-save -no-window
   -packet-streamer-endpoint default`. Do not run against a physical device.
2. Start exactly one peripheral:
   `uv run --with bumble==0.0.234 --with grpcio --with protobuf python scripts/ledger-ble-probe/peripheral.py`.
3. Create an output directory with `mktemp -d /tmp/vizor-ble-probe.XXXXXX`.
4. Run `zsh scripts/ledger-ble-probe/run-android.sh emulator-5554 OUTPUT_DIRECTORY`.
   This installs/replaces **only** `app.vizor.bleprobe`, grants its BLE permissions,
   enables guest Bluetooth, and waits for a terminal test result. It exits
   nonzero for a failure or missing result. Reuse the output directory for its
   temporary signing key when reinstalling. Override `ANDROID_SDK_ROOT` and
   `PROBE_JAVA_HOME` as needed. Build tools/platform 36 are required.

The emulator and peripheral are left running for diagnosis. The scripts do not
kill processes, wipe AVD data, modify Vizor storage, or access physical radios.
The test app is direct-boot aware because the available AVD snapshot started
with Android user 0 in RUNNING_LOCKED; no device credentials were bypassed.

## Observed results, 2026-09-07 KST

The initial run passed discovery, service/notification setup, write/notification
exchange, a 1510 ms delayed reply, disconnect while a no-response command was
pending, and a fresh exchange after reconnecting.

The extended run **failed**, as intended to detect unsafe assumptions:

- 16:12:00.976: new exchange after the first reconnect passed.
- 16:12:01.489: disconnect callback arrived while another delayed reply was pending.
- 16:12:01.491: the replacement GATT client reported connected.
- 16:12:02.487: the old `02 90 00` reply arrived after the replacement client had
  completed its `01 90 00` exchange; the test reported `FAIL unexpected
  notification stage=6`.

The peripheral still recognized the original connection object and emitted the
delayed notification. This suggests Android retained the underlying BLE link
while replacing the application's GATT client. It is not proof that an old
packet crossed a genuinely new link, nor proof of a Vizor/DMK bug.

**Design consequence:** a GATT disconnect callback alone is not evidence that
all old application responses were drained. Test the actual Ledger transport's
framing, subscriber lifetime, cancellation, and reconnect behavior before
enabling signing retries. The 3-second UFVK guard is not tested here and is not
a substitute for request/session isolation.

## Apple transport source check

Vizor pins `LedgerHQ/hw-transport-ios-ble` 1.0.1 at
`4df8fff21c1738a1dff4d2ee19175dd3263d6c5f`. In `BleTransport.swift`,
`disconnect(completion:)` queues the disconnect completion while `isExchanging`
is true; it does not immediately interrupt a pending exchange. The async
`exchange` uses a checked continuation. Therefore a proposed recovery path
must not assume `disconnect()` forcibly aborts a stuck exchange.

This is source evidence, **not an iOS runtime test**. Native iOS SDK injection,
Vizor integration, multi-frame APDUs, and a Speculos bridge remain open.

## Official Android SDK probe

The separate `dmk` application uses the unmodified Maven dependency
`io.github.ledgerhq:device-management-kit:0.0.4`, matching Vizor's Android pin.
It uses the emulator Bluetooth stack, not a mocked SDK transport.

With the read-only emulator running and guest Bluetooth enabled:

1. Start `uv run --with bumble==0.0.234 --with grpcio --with protobuf python scripts/ledger-ble-probe/sdk_peripheral.py`.
   The peer advertises `DMKProbe` and exits automatically after 180 seconds.
2. Run `zsh scripts/ledger-ble-probe/run-dmk.sh emulator-5554`.
   It builds with the repository Gradle wrapper and installs/replaces only
   `app.vizor.dmkprobe`. It exits nonzero on a failed assertion or missing result.

### Observed SDK results, 2026-09-07 KST

Discovery as Nano X, connection, notification subscription, MTU handshake,
`GetAppAndVersion`, a normal framed APDU, and a 1.5-second delayed APDU passed.
The reported `Zcash 3.9.3` is synthetic peripheral data, not firmware execution.

Cancellation/reconnect exposed two distinct boundaries:

- `disconnectDevice()` returned before removal of the SDK session. Immediate
  reconnect reported `Device already connected`.
- Waiting until `observeConnectedDevices()` no longer contained the peer
  allowed reconnect, but the new `e0 f3 00 00 00` request received the cancelled
  `e0 f2 00 00 00` request's delayed `02 90 00`, instead of `03 90 00`.
  The assertion failed twice, at 16:20:30.878 and 16:20:56.265.

The caller cancelled after 300 ms; the old response was scheduled for 1.5 s
and the replacement response for 2.5 s. The peer only delivers through the
same still-live underlying connection object. This models a retained BLE link
with delayed application work, not delivery across a proven physical disconnect.

The SDK source associates incoming response frames with the currently pending
command. Its public disconnect call requests asynchronous closure. Together
these explain why caller cancellation and session-list removal alone did not
prevent misbinding in this fixture. This is not evidence that real Ledger
firmware emits this sequence, that Vizor accepts an invalid signature, or that
the three-second UFVK guard fails. Those paths were not exercised.

Before enabling automatic retries, replay this fault at Vizor's actual handler
boundary and verify response validation and cleanup. Do not infer safe retries
from the successful normal-path tests.

Official SDK source archive:
https://repo.maven.apache.org/maven2/io/github/ledgerhq/device-management-kit-android/0.0.4/device-management-kit-android-0.0.4-sources.jar

## Production Android handler replay

`HandlerProbe` compiles the current, unchanged production
`android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt` through a
Gradle copy task. Test-only Flutter channel interfaces invoke its public
`handle()` entry point and capture results. There is no Flutter engine, channel
codec, Dart signing gate, Rust finalizer, or product UI in this APK.

Run against the same SDK peripheral:
`zsh scripts/ledger-ble-probe/run-dmk.sh emulator-5554 HandlerProbe 100`.
The optional final argument controls the experimental disconnect-to-reconnect
delay in milliseconds; it does not modify any product delay.

At production HEAD `92850b6df70ff6432f10b1814ce6a592b2397580`:

- 16:28:56 KST: discovery, connection, normal APDU passed.
- 16:28:57.996: the cancelled callback had exactly one completion, but the
  replacement request returned `[[2, 144, 0]]` instead of `[[3, 144, 0]]`.
  Handler generation fencing does not detect an SDK response already bound
  to the new operation. This is a failing regression probe, not a passing E2E.
- A 4000 ms reconnect-delay control dropped the old response at the peripheral,
  but crashed at 16:29:49.812 inside official SDK
  `AndroidBluetoothDeviceConnection.kt:81`: `getName(...) must not be null`.
  The same SDK exception occurred on the initial run's first connection.
  Adding a 500 ms discovery-to-connect delay allowed the next first connection;
  it is a fixture timing control, not a confirmed fix. Recovery remains failed.
- Existing focused Dart BLE service and signing-gate tests passed: 16 tests.
  They do not exercise this native SDK fault.

The current Dart `kLedgerMobileSigningStatusCooldown` and Rust
`SIGNING_STATUS_COOLDOWN` are both four seconds, not three. The Dart gate wraps
the signing stream, sets a cooldown on failure, and cancels queued generations.
This harness bypasses that gate, so the fast reconnect failure is not proof
that the full UI signing path ignores its cooldown. No three-second UFVK
recovery guard was found in the inspected Android handler or Dart BLE service.

Static tracing shows raw responses pass next to Rust finalizers, which check
response count, empty packet acknowledgements, signature length and PCZT
signature validity. The synthetic one-byte payload would not qualify as a
64-byte shielded signature. This turn did not execute cryptographic finalization
or broadcast, and does not establish signature-validation bypass.

Next boundary: reproduce SDK reconnect/name handling with refreshed discovery,
then drive the real Dart signing gate and finalizer through the native transport.
Do not enable automatic signing replay based on a timer alone.

## Rediscovery and real Dart gate follow-up

The native-only replay with a 4000 ms delay and fresh discovery passed at
16:33:19 KST. Run it with
`zsh scripts/ledger-ble-probe/run-dmk.sh emulator-5554 HandlerProbe 4000 true`.
This does not establish that rediscovery reliably fixes the SDK name exception.

`BridgeProbe` exposes the unchanged handler through a loopback-only newline-JSON
socket for 180 seconds. The host Flutter test runs the production
`MethodChannelLedgerMobileBleService` and `LedgerMobileSigningStatusGate`, using
the test messenger solely to forward calls through adb. Responses still travel
through the official DMK and Android Bluetooth stack. The socket replaces the
Flutter-engine/native channel; it does not replace BLE with mocked responses.

After building the probe APK and starting the SDK peripheral:

1. Install only `app.vizor.dmkprobe` using the APK described above.
2. Run `adb -s emulator-5554 forward tcp:18765 tcp:18765`.
3. Run `adb -s emulator-5554 shell am start -n app.vizor.dmkprobe/.BridgeProbe`.
4. Run `VIZOR_NATIVE_BLE_PROBE=1 fvm flutter test --no-pub test/features/ledger/ledger_native_ble_probe_test.dart --reporter expanded`.

Do not start another bridge while the previous activity's server is running.
The bridge accepts only discovery, connect, disconnect, synthetic APDU exchange,
and cancellation operations. No wallet credentials or external network endpoint
are involved. The test is opt-in and registers no tests in the normal test lane.

Two real-Dart-gate attempts were made:

- First attempt failed during SDK connection with `getName(...) must not be
  null` at 16:35:12.308. Dart observed the bridge socket closing. This is a
  runtime failure, not a test assertion to suppress.
- The same-condition retry passed: initial connection and normal exchange,
  cancellation, disconnect, the real gate's 3998 ms remaining cooldown,
  fresh discovery/reconnection, and the expected `03 90 00` replacement reply.
  The test completed in 13 seconds. The gate's default remains 4 seconds;
  the stopwatch starts after cancellation cleanup has already consumed a few ms.

The new test passes static analysis; the probe APK builds. This proves one
successful recovery through the real Dart gate, not robust recovery across
all timings. The earlier SDK crash remains unresolved. Firmware, RF, iOS,
Rust finalization, UI navigation, and transaction broadcast remain outside
this test. Product code and delay constants were not changed.

Next diagnosis should isolate why Android's `BluetoothDevice.name` is null
after successful SDK transport readiness, including the emulator/peripheral
identity behavior. Do not ship a timing-only or rediscovery-only fix based on
the single passing retry.

## Device-name diagnosis, 2026-09-07 KST

`HandlerProbe` now samples the virtual peer's Android `BluetoothDevice.name`
every 25 ms for two seconds around each connection. This is observation only;
it does not replace the name, block connection on it, or modify the SDK.

Three native replays in this round gave one crash and two passes:

- 16:39:38.678: rediscovery completed, then the SDK crashed at the same
  `AndroidBluetoothDeviceConnection.kt:81` null-name check.
- 16:40:08.023: both connections and the fresh reply passed with name sampling.
- 16:40:29.618: the cached name changed from `DMKProbe` to `null` after the
  first connection had succeeded and cancellation/disconnect had been requested.
  At 16:40:35.113 rediscovery had restored `DMKProbe`; recovery passed at
  16:40:38.356. The address remained `F0:F1:F2:F3:F4:F8`.

The fixture supplies a complete local name in advertising. Bumble's enabled
default GAP service also exposes `GenericAccessService(self.name)`, initialized
from `config.name = 'DMKProbe'`. A missing name in the fixture configuration is
therefore not the explanation. The exact Android cache invalidation mechanism
and its frequency on real phones/devices are still unverified. Sampling itself
can affect timing; two passing sampled runs are not a reliability guarantee.

Confirmed SDK contract violation: `parseScanResult` rejects a null name, but
`connect()` reads `device.name` again after asynchronous transport readiness
and passes it to a non-null constructor. Its catches cover timeout and JVM
`Error`, not `NullPointerException` (an `Exception`). Therefore an allowed
nullable Android API result escapes the SDK and crashes the unguarded handler
coroutine. Android documents `getName()` as a cached lookup that can return null:
https://developer.android.com/reference/android/bluetooth/BluetoothDevice#getName()

Preferred repair candidate is SDK-level handling of the nullable display name
using the already captured discovery name, while retaining the address/session
as identity. App-level containment must also close failed connection state and
return a typed failure; catching the exception without cleanup is not recovery.
Neither repair was applied in this diagnosis round. No upstream issue was
posted and no SDK fork or product dependency was changed.

## Android connection exception containment

The production handler now catches exceptions from connection setup, requests
DMK disconnect for the exact attempted uid/connectivity (using the discovery
metadata to construct the public disconnect argument), removes the stale
discovery entry, and returns a typed error. Cleanup has a five-second bound and
is attempted even during cancellation. If cleanup itself fails, the message
explicitly asks for a Bluetooth reconnect rather than reporting successful
cleanup. Cancellation is rethrown after the channel result is completed.

This uses the unmodified SDK 0.0.4. It does not repair the SDK's null-name
assumption, prove completion of physical disconnection, or enable automatic
signing replay. The SDK disconnect method requests asynchronous closure.

Validation on 2026-09-07 KST:
- At 16:43:11 the null-name condition returned to the probe instead of killing
  its process; the original success-only assertion failed, as expected.
- The updated probe can explicitly simulate up to three user connection
  attempts, requiring the expected typed error before rediscovery. This is
  test behavior, not a product auto-retry policy.
- Native normal/cancel/reconnect scenarios passed at 16:43:53, 16:44:20 and
  16:44:45. These runs did not trigger the exception, so exception-to-success
  recovery in the same process remains unverified.
- The focused Dart BLE and signing-gate suite passed all 16 tests. The modified
  production Kotlin handler compiled in the probe APK. A full wallet build,
  UI rendering, real-device test and cryptographic signing were not run.

Name polling is now opt-in through the test activity's `traceNames=true` intent
extra, because additional cache reads may affect the race being measured.

## Recovery gating and no operation replay

Android now serializes connect/disconnect transitions. Disconnect waits up to
five seconds for both Android's GATT connection list and the SDK's public
session list to exclude the peer. A timeout retains the pending cleanup target
and blocks APDUs; a later connection must first complete that cleanup. This is
stronger than waiting for `disconnectDevice()` to return, but does not prove
every SDK internal callback has drained or establish real-firmware coverage.

The Dart connection service now switches transports only before the supplied
operation starts. Once entered, an operation error is rethrown without invoking
another transport. This applies in both USB-to-Bluetooth and Bluetooth-to-USB
directions. Typed readiness connection failures still permit preparation-stage
fallback; rejection/lock/version errors do not.

Native validation at 16:50:32 KST observed an APDU being rejected while cleanup
was pending. With only 100 ms additional probe delay after disconnect, fresh
discovery, reconnect, and the correct new response passed at 16:50:38.818.
The 4000 ms control also passed at 16:50:12.488. The product signing cooldown
remains four seconds; the 100 ms parameter is only a test perturbation.

This round changes recovery behavior, not UI layout. Dedicated recovery-screen
states, timeout fault injection, SDK internal-map removal races, iOS behavior,
and post-exception recovery in the same process still need separate validation.

References:
- https://google.github.io/bumble/platforms/android.html
- https://github.com/LedgerHQ/hw-transport-ios-ble/tree/4df8fff21c1738a1dff4d2ee19175dd3263d6c5f

## Common recovery controller replay, 2026-09-07 KST

The host bridge test now uses `LedgerConnectionRecoveryController` for fresh
discovery/connection. Two simultaneous recovery calls share one future and
one native preparation. Only a subsequent explicit test action enters the real
signing gate and sends the replacement APDU. The replay passed after the
17:23 KST fixture start: cleanup, rediscovery, duplicate suppression, and the
expected `03 90 00` response, with 4251 ms elapsed since cancellation completed.
The test passed including final disconnection (11 seconds total).

The production cooldown is **four seconds**, unchanged. This replay does not
exercise `LedgerConnectionService.reconnect`, actual widget navigation, app
readiness, or cryptographic signing; it joins the shared controller, real Dart
gate and real native transport using a test preparation callback. Service and
widget tests separately cover explicit retry, failure presentation, disposal,
and preventing automatic operation replay. Native timeout/SDK-exception fault
recovery and iOS runtime coverage remain unverified in this round.
