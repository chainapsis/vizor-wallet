# Ledger saved connection indicator

Implemented on 2026-09-17, based on `d5b869851436a7f81a243e17d7187ef338ed0e0d`.

## Behavior

- Bluetooth recovery discovery shows “Different from saved connection” below a device name when its discovery ID differs from a nonempty saved ID. Matching or missing saved IDs have no badge.
- Selection remains available without another confirmation dialog. Discovery IDs are connection hints, not hardware serial numbers or proof of account ownership.
- Every selected device, including one with the saved ID, exports the account viewing key for the existing ZIP 32 account index. The full UFVK and index must match before saving connection metadata.
- Successful replacement reports “This Ledger matches your account. Your saved connection has been updated.” only after persistence succeeds. Matching or previously missing IDs use the existing success message.
- Account mismatch and storage failure do not report success or replace saved metadata. Signing resumes only through the existing Continue signing action.
- macOS retains its Bluetooth/USB selector; mobile retains the Bluetooth-only recovery presentation. No native transport code changed.

## Validation and review

- Focused recovery suite: 28 passed on desktop and 28 with mobile tokens, including the saved/same/missing ID × match/mismatch/storage-failure matrix.
- Desktop Ledger/onboarding/send/payment-link regression selection: 358 passed, 1 skipped.
- Broader mobile Ledger/send/onboarding selection: 341 passed, 3 failed. All three failures also reproduce with the entire change reverted to the base tree: onboarding progress expects 4 rather than 5 steps, and two birthday calendar tests overflow horizontally by 11 pixels. These unrelated existing failures are outside this change.
- Flutter analyze: no issues. Diff whitespace check passed.
- Deterministic Flutter captures: 30 desktop + 38 mobile, covering both themes. Inspected device lists, replacement success, and account mismatch screens.
- Reviewed discovery-only identification, account verification before persistence, provider refresh after saving, cancellation/session guards, and all callers of the changed service return value. No actionable findings remained.

## Evidence and limits

Screenshots and gallery are under `/Users/yjh/.codex/visualizations/2026/09/17/01a0ae34-f63b-7be1-9d5f-3ad7e6563299/ledger-device-indicator/`.

Tests use deterministic transport fixtures. Physical Ledger replacement, OS pairing prompts, and real iOS/Android/macOS Bluetooth behavior were not exercised in this task.
