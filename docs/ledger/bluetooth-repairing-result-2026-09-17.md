# Ledger re-pairing recovery — 2026-09-17

Implemented on top of `9bddb8e65` for existing Ledger accounts. This changes the connection-failure flow, without deleting or importing an account.

## User flow

1. Typed BLE pairing-invalid, pairing-rejected and disconnected failures offer **Find my Ledger**. An unknown connection failure is not diagnosed as a pairing reset.
2. **Did you reset pairing?** expands in place: remove the old OS pairing if listed, then return and find the Ledger. The main action remains below the disclosure. Device selection uses quiet list rows rather than stacked secondary buttons.
3. Starting discovery stops the previous scan and disconnects the old session. Selecting a discovered device requests a viewing-key export at the existing account's derivation index.
4. Vizor compares the complete exported UFVK and account index with the existing account. Device name, Bluetooth ID and model are not identity proofs. Only a matching result reaches the metadata commit.
5. On success, **Continue signing** is a separate explicit action. Settings return, discovery, selection and account verification never request transaction signatures themselves.

macOS retains the equal-width Bluetooth/USB selector for dual-transport devices. Mobile has no transport selector. Permission denial, Bluetooth off, and location restrictions reached during rediscovery use the existing single-action access recovery.

## Platform settings behavior

- Android opens `Settings.ACTION_BLUETOOTH_SETTINGS`, separate from the existing app-permission settings action. A Robolectric test checks the actual intent action.
- macOS opens System Settings; the disclosure names **System Settings > Bluetooth**. The implementation does not claim a direct Bluetooth-pane deep link.
- iOS displays manual **Settings > Bluetooth** instructions and no settings-link action for pairing. It uses no private URL scheme. The native pairing-settings method returns false on iOS.
- Existing native error classification remains unchanged: the UI can offer re-pairing after a typed disconnect without claiming that the user reset pairing.

## Safety and scope

- Connection verification shares exclusion with normal connection/signing work.
- Cancellation or a context change before commit cannot publish a verified result or replace the saved device. A recovery session remembers intermediate account switches and lock/unlock transitions, even if the original state returns before the response.
- Viewing-key approval is outside the durable-operation drain. Reading the expected key and committing verified connection metadata use short lifecycle leases so account deletion cannot race those operations. Once the verified metadata commit begins, it is allowed to finish.
- Failed discovery generations are invalidated and subscriptions cancelled; late results cannot replace the failure UI.
- Saved/broadcast swap and payment-link recovery keeps its existing transaction actions. Send, shield and immediate migration use the shared recovery surface at their device-failure boundary.
- Initial account onboarding and a dedicated replacement-device management flow are outside this task. No Rust API or signing/broadcast format changed.

## Review and validation

Review/fix cycles addressed short-window overflow with expanded help, queued discovery events after failure, visual hierarchy differences, and dependence on route disposal for account/lock cancellation. No unresolved product-code findings remain after final review.

- Desktop regression suite: 346 passed, 1 skipped.
- Mobile regression suite: 55 passed; the 16 new lane-independent recovery tests also passed with mobile design tokens.
- Flutter analysis: no issues.
- Shared Apple native handler suite: 42 passed.
- Android Ledger handler suite: 39 passed (JDK 17 / Gradle 8.14).
- Widget captures cover collapsed/expanded help, device list, verified connection and account mismatch in both themes and form factors, plus the existing access-recovery states.

The tests use scripted devices. A physical Ledger pairing reset, native OS pairing dialogs, real viewing-key approval and system-settings navigation still require device verification on iOS, Android and macOS. No physical-device success is claimed.
