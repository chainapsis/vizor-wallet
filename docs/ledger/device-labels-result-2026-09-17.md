# Ledger device labels

Use a shared presentation-only label in Bluetooth selection/recovery, mobile onboarding picker and selected-device summary, and macOS onboarding list/connecting/ready states.

Examples: `Ledger Nano X · F52C`, `Ledger Flex · A37E`. Known model aliases are normalized; matching model/name pairs appear once. Unknown models retain the advertised name (`Ledger · F52C`); Apple's ambiguous Flex/Stax model remains ambiguous. Unicode names remain intact. Connection IDs and account verification are unchanged.

Mobile onboarding combines the previously separate name/model text into one wrapping label, retaining the row, icon and selection behavior. macOS onboarding rows can grow with long content. Existing different-connection hints remain unchanged.

Review caught and corrected duplicate suppression that could hide a name when the native fallback used that same name as an unknown model.

Validation:
- Desktop Ledger/onboarding/Widgetbook suite: 317 passed, 2 skipped (before two additional Unicode label cases).
- Final label cases: 17 passed, including long/custom/unknown/ambiguous/Unicode labels.
- Mobile Ledger/onboarding selected lane: 35 passed.
- Deterministic capture tests: 42 desktop and 48 mobile passed. Inspected the updated shared picker in both form factors. Light/dark captures are available in the gallery below.
- Flutter analysis: no issues.
- Two review passes; no outstanding finding.

Screenshots: `/Users/yjh/.codex/visualizations/2026/09/17/01a0ae34-f63b-7be1-9d5f-3ad7e6563299/ledger-device-labels/index.html`.

Capture model assignments are fixtures, not inferred identities for the devices in the user's screenshot. No physical-device test was performed; native discovery and signing were not modified.
