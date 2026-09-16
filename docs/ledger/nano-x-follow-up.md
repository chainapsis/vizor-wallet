# Nano X physical-device investigation — deferred

Recorded 2026-09-16 at the user's request. Resume when the user has a Ledger Nano X.
Do not treat the signing-phase UI improvement as a fix for this device failure.

## Reported symptoms

- Mobile + Bluetooth signing pauses for more than 30 seconds.
- Nano X buttons become sluggish, then the screen turns off and on in a reboot
  (user explicitly distinguished this from returning to the Zcash dashboard or PIN lock).
- The original conversation also reported battery trouble, automatic locking,
  and failed Try again recovery until restarting Vizor. Desktop was reported working,
  but identical transaction/device/version conditions have not been established.
- Phone OS, Ledger OS, installed Zcash app version, transaction shape, and failing
  command are still unknown. No physical-device reproduction has been performed.

## Findings and limits

- Vizor's iOS/Android handlers await each APDU response before sending the next;
  there is no observed unbounded pipeline of transaction APDUs into the device.
- BLE fragments inside one APDU are distinct from APDU-level backpressure.
  The pinned iOS SDK uses write-without-response where available; its flow control
  remains a physical BLE investigation candidate, not a demonstrated cause.
- Current serializer sends the protocol's compact fields, not the whole proof.
  Host-side repeated PCZT parsing does not mean repeated device transactions.
- Device verification (commitment/nullifier/output decryption) contributes to
  APDU round-trip time. It cannot be labeled purely radio transfer time.
- Upstream has concrete Nano X stack/SE-resource/heap fixes, but these are already
  present in source commit `22dc38537f9a84b31b938e3ca95434595ef378d3`, also referenced
  by tag `nanox_2.7.1_3.9.3_sdk_v26.6.1`. Current Vizor requires Zcash >= 3.9.3.
  Historical app exits do not prove the cause of the reported full-device reboot.
- The current device implementation caches the spending key but rebuilds FVK /
  decipher keys per action. Reuse is a device-app optimization candidate, subject
  to memory, key lifetime, and correctness checks; not an established crash cause.

## Resume plan

1. Record phone OS, Vizor build, Ledger OS/Zcash versions, power source and lock settings.
2. Record host preparation duration, command index/type/length, action/input/output
   counts, APDU start/response timestamps, last successful response and disconnect.
   Do not log raw transaction payloads, viewing keys or note secrets.
3. Identify whether the stall is at key derivation, final action metadata verification,
   final review, or after approval. Correlate the physical screen and button behavior.
4. Compare the same Nano X and same unsigned command sequence over USB and BLE;
   separately compare battery-powered BLE with charger-powered BLE. Stop before
   broadcast or use controlled fixtures; do not replay live sends to benchmark.
5. Vary action count/output count with deterministic fixtures. Investigate stack,
   heap, SE resources and responsiveness in an instrumented device build if needed.
6. Separately verify recovery from disconnect/reboot: iOS can retain an outstanding
   SDK exchange until its callback drains, blocking subsequent attempts.

## Upstream evidence

- [Nano X finalization stack fix](https://github.com/LedgerHQ/app-zcash/commit/a557a72ead64e0a68811c8567a16242085af662e)
- [Stack headroom and slow Sinsemilla implementation](https://github.com/LedgerHQ/app-zcash/commit/8bf62cfbd33aa88a31766873d61e64cde3b01de1)
- [Reuse spending key to avoid SE exhaustion](https://github.com/LedgerHQ/app-zcash/commit/e6712555bed6b664326f8cf294b8ba3c3979f314)
- [Separate action and review memory budgets](https://github.com/LedgerHQ/app-zcash/commit/12542bb41bcc307057b4613b60ed70cc6b76bf7f)

Related UI analysis: [Signing phase guidance](signing-phase-guidance.md).

## Debug instrumentation and Android reproduction

The investigation branch adds debug-only `[LedgerTrace]` metadata:

- Dart: UI stage/round, attempt generation, readiness/version, validation,
  wallet-path lookup, connection, APDU-plan command count/byte total, review-busy
  retries and signature finalization. UTC timestamps distinguish host preparation
  from the native exchange. UI lines can repeat on rebuild; they are not attempts.
- Android/Apple BLE: monotonic timestamps, batch request ID, command sequence,
  CLA/INS/P1/P2, byte count, response status word, elapsed round-trip time, and
  cancellation/connection results. Native diagnostics are also forwarded to Dart.
- USB debug Rust builds: APDU header, sizes, status word and round-trip timing.
  Rust logs follow the platform logger, not the Flutter console on Apple platforms.

No new logs contain account UUIDs, device identifiers, addresses, amounts, memo
text, keys, raw commands/responses, signatures or exception messages. Sizes and
counts still reveal transaction shape. Logging is off in release builds. Logging
may affect timing, so failure to reproduce with diagnostics is not proof of a fix.
No timeout, automatic retry, device polling, or APDU ordering changes are added.

Android procedure (real phone, not an emulator):

1. Enable USB debugging on the phone, connect it to this Mac and accept the phone's
   debugging prompt. Find its ID with `~/Library/Android/sdk/platform-tools/adb devices`.
2. From the repository root, start `scripts/capture-ledger-android.sh DEVICE_ID` in
   one terminal. It prints its output path, includes phone model/OS, and captures
   only `[LedgerTrace]` lines. It does not clear system logs or overwrite a file.
3. In another terminal run
   `fvm flutter run -d DEVICE_ID --dart-define=VIZOR_FORM_FACTOR=mobile`.
   Use the debug build; a store/release build does not emit these diagnostics.
4. Unlock Nano X, open Zcash and reproduce the same Bluetooth signing flow. Start
   with the original power condition. If review appears normally, reject on the
   Ledger rather than approving/broadcasting merely to test the pre-review stall.
5. If it reboots, note the approximate time, app stage, last device screen,
   responsiveness and whether the phone reports disconnection. Keep capture
   running for 10–15 seconds. If possible, retry once after unlocking/reopening
   Zcash (without restarting Vizor), then stop capture with Ctrl-C.
6. Send the capture file plus Ledger OS/Zcash versions, whether Nano X was on
   battery or charging, and what happened on retry. After the first trace is
   analyzed, compare the same request under external power/USB as appropriate.

Interpretation: `apdu_start` without its matching `apdu_end`/`apdu_error` means the
host is still waiting on that exchange; it does **not** by itself distinguish
radio failure, device computation, or power failure. `review_boundary` precedes
both final validation and device approval. Metadata alone cannot prove heap or
stack exhaustion, which may require an instrumented device-app build.

## App-query recovery (2026-09-16)

The supplied Android trace stopped at `currentApp` / `GetAppAndVersionCommand`,
before the signing APDU plan. It does not establish a device reboot or a Zcash
verification-memory failure. Stax working is useful comparison evidence, but
installed OS/app versions and connection-start logs are still needed.

App-name/version queries now have a 10-second deadline on Android and Apple.
Opening-app approval and transaction review do not use this short deadline.
Timeout/cancellation invalidates the old request and retires its native session;
new requests remain excluded until teardown completes. Android also quarantines
failed disconnects across Activity recreation. Apple uses the pinned BLE 1.0.1
source in `third_party/ledger_ble_transport`, patched to abort the physical link
and resolve a pending exchange on disconnect. A late response cannot publish a
cancelled result. Dart clears cancelled connection metadata and resets native
state before reconnecting. SDK raw APDU logging is disabled.

Physical-device verification still required:

1. With Zcash open, repeat the Android flow and capture `[LedgerTrace]` output.
   A stalled app query should leave preparation after about 10 seconds.
2. After disconnect cleanup, retry without restarting Vizor. A fresh connection
   should reach `app_query_end` and then the signing plan, or return a concrete
   connection error. Signing commands are never automatically replayed.
3. Repeat on iOS, including turning the Ledger off during the query, cancelling,
   reconnecting, and leaving an actual approval prompt open longer than 10 seconds.
4. Compare Nano X and Stax with phone, app/OS versions, and transaction held fixed.

If the OS never confirms physical disconnect, exclusion intentionally remains:
we must not overlap a replacement request with an unretired connection. That is a
separate OS/transport recovery failure, not permission to release the slot early.
