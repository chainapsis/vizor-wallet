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
