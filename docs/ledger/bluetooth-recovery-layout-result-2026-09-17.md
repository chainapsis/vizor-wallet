# Ledger Bluetooth recovery layout — 2026-09-17

Implemented the approved platform-specific recovery layout on top of the permission-recovery work (`0cdb070d5`).

## Result

- macOS signing recovery shows a compact, equal-width Bluetooth / USB selector for accounts whose device supports both transports. Selecting a transport persists that explicit preference but does not connect or sign. Opening recovery leaves automatic selection unchanged.
- iOS and Android show Bluetooth recovery without a transport selector.
- Access recovery uses a title, explanation, and one full-width primary action: Allow access, Open settings, Check again, Reconnect, or Close, according to current access state. The close control stays in the header.
- Returning from Settings refreshes access only. The user explicitly reconnects or restarts discovery after access is restored.
- Denying a permission request leads to Settings instead of an endlessly repeated permission request.
- Onboarding uses the same single-action recovery content. Mobile hides stale discovery rows during access recovery. The macOS Bluetooth onboarding dialog remains inside the already-selected Bluetooth flow; the dual-transport selector belongs to signing recovery with known account/device metadata.
- Saved or broadcast transaction recovery retains its transaction-specific actions; it does not turn into a device reconnect prompt.

## Review and validation

Repeated implementation / review corrected unequal intrinsic-width transport controls and a narrow recovery button. Final controls are grouped with equal transport widths and a full-width primary action. No remaining actionable findings were identified in the final review.

- Desktop focused regression suite: 330 passed, 1 skipped.
- Mobile regression suite with mobile tokens: 55 passed.
- Dedicated recovery tests: 13 passed, including platform visibility, transport persistence, manual retry, duplicate request suppression, lifecycle refresh and stale request handling.
- Flutter analysis: no issues.
- Deterministic captures: 18 desktop and 26 mobile, light and dark themes, including the actual USB-selection transition.
- Physical Ledger connections and real operating-system permission dialogs were not exercised in this task. Native permission implementations were unchanged.

Capture gallery is an external review artifact under the current task's visualization directory (`ledger-layout/index.html`); screenshots are not production assets.
