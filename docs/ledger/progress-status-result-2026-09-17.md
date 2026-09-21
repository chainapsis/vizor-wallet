# Ledger progress feedback

## User-visible changes

- Bluetooth discovery, connection, account checking and metadata saving now use a status row with the existing animated app loader rather than a disabled primary button.
- Discovery says “Searching nearby…” before results and “Still searching nearby…” after results. Device rows remain selectable during discovery. Search again appears once discovery completes.
- Before discovering a device, the instructions say to keep Ledger nearby and unlocked rather than asking the user to select a nonexistent row.
- Known-device connection says “Connecting…”. Other-device verification says “Follow the prompts on your Ledger”, with pairing/open-app/viewing-key instructions above. That phase includes connection and approval, so it does not falsely claim the native device is already awaiting approval.
- Bluetooth permission/access checks also use the status row.
- The shared signing modal retains its existing progress block and removes redundant disabled Waiting/Finishing action buttons. Device review uses a Ledger icon and approval instructions; application processing retains animation. Cancel and failure recovery actions remain governed by their existing callbacks.

No transport, account verification, persistence, cancellation or broadcast logic changed. Mobile and macOS share the updated recovery components. Existing onboarding loaders were retained.

## Validation

- Added streamed-discovery regressions: loader visible before/after device results, selection works while discovery is active, retry becomes actionable only after completion.
- Added accessible status and reduced-motion coverage. Reused AppLoadingIcon respects MediaQuery.disableAnimations; status text remains visible.
- Existing pending-verification test now pumps bounded frames instead of waiting for an intentionally continuous animation to settle.
- Desktop Ledger/Send/payment-link/onboarding/Widgetbook selection: 395 passed, 2 skipped by lane tags.
- Mobile Ledger/Send/onboarding/voting selection: 63 passed.
- Deterministic captures: 46 desktop + 52 mobile passed, including new discovery-in-progress states, connecting and signing.
- Static analysis: no issues; diff whitespace check clean.

Screenshots: `/Users/yjh/.codex/visualizations/2026/09/17/01a0ae34-f63b-7be1-9d5f-3ad7e6563299/ledger-progress/index.html`.

Screenshots are static frames; animation is verified by widget tests. No physical Ledger/native Bluetooth run was performed.
